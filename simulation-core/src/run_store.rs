//! SQLite persistence compatible with tools/run_store.py's v1 catalogue.
use crate::RunLogEvent;
use rusqlite::{params, Connection, OptionalExtension, TransactionBehavior};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::fs;
use std::path::Path;
use std::time::Duration;

/// Save a single logged Run atomically. Returns the catalogue's SHA-256 Run key.
/// Re-saving events is idempotent; conflicting history is never overwritten.
pub fn save_run(path: &Path, events: &[RunLogEvent]) -> Result<String, String> {
    save_run_inner(path, events)
        .map_err(|error| format!("could not save Run to {}: {error}", path.display()))
}

fn save_run_inner(path: &Path, events: &[RunLogEvent]) -> Result<String, String> {
    let first = events.first().ok_or("cannot save an empty Run")?;
    if first.event != "run_start" || first.sequence != 1 || first.run_id.is_empty() {
        return Err("Run must begin with run_start at sequence 1".into());
    }
    for (index, event) in events.iter().enumerate() {
        if event.run_id != first.run_id || event.sequence as usize != index + 1 {
            return Err("events must belong to one Run with contiguous ordered sequences".into());
        }
    }
    let payloads: Vec<String> = events
        .iter()
        .map(|event| canonical(&serde_json::to_value(event).map_err(|e| e.to_string())?))
        .collect::<Result<_, _>>()?;
    let key = format!("{:x}", Sha256::digest(payloads[0].as_bytes()));
    if let Some(parent) = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
    {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let mut db = Connection::open(path).map_err(|e| e.to_string())?;
    db.busy_timeout(Duration::from_secs(10))
        .map_err(|e| e.to_string())?;
    let version: i32 = db
        .pragma_query_value(None, "user_version", |row| row.get(0))
        .map_err(|e| e.to_string())?;
    if version != 0 && version != 1 {
        return Err(format!("unsupported Run database version {version}"));
    }
    db.pragma_update(None, "foreign_keys", true)
        .map_err(|e| e.to_string())?;
    db.execute_batch(include_str!("../../schemas/run-store-v1.sql"))
        .map_err(|e| e.to_string())?;
    let transaction = db
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(|e| e.to_string())?;
    let old: Option<(usize, String)> = transaction
        .query_row(
            "SELECT event_count,status FROM runs WHERE id=?1",
            [&key],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .optional()
        .map_err(|e| e.to_string())?;
    let existing: BTreeMap<u32, String> = {
        let mut statement = transaction
            .prepare("SELECT sequence,payload FROM events WHERE run_key=?1")
            .map_err(|e| e.to_string())?;
        let rows = statement
            .query_map([&key], |row| Ok((row.get(0)?, row.get(1)?)))
            .map_err(|e| e.to_string())?;
        rows.collect::<Result<_, _>>().map_err(|e| e.to_string())?
    };
    for (event, payload) in events.iter().zip(&payloads) {
        if existing
            .get(&event.sequence)
            .is_some_and(|old| old != payload)
        {
            return Err(format!(
                "conflicting event at sequence {}; use a new run_id",
                event.sequence
            ));
        }
    }
    if let Some((count, status)) = old {
        if events.len() <= count {
            return Ok(key); // Dropped read-only transaction leaves the old snapshot intact.
        }
        if status != "unfinished" {
            return Err("completed Runs cannot be extended".into());
        }
    }
    let summary = summarize(events);
    let policy = canonical(first.details.get("goal_policy").unwrap_or(&json!({})))?;
    let summary_json = canonical(&summary)?;
    transaction.execute(
        "INSERT INTO runs (id,run_id,started_at,strategy_id,scenario_id,scenario_seed,simulation_version,
         schema_version,code_revision,goal_policy,status,event_count,turns,max_depth,score,summary)
         VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16)
         ON CONFLICT(id) DO UPDATE SET status=excluded.status,event_count=excluded.event_count,
         turns=excluded.turns,max_depth=excluded.max_depth,score=excluded.score,
         summary=excluded.summary,updated_at=CURRENT_TIMESTAMP",
        params![key, first.run_id, first.time, first.strategy_id, first.scenario_id, first.scenario_seed,
            first.details.get("simulation_version").and_then(Value::as_u64).unwrap_or(first.schema_version.into()),
            first.schema_version, first.details.get("code_revision").and_then(Value::as_str).unwrap_or(""),
            policy, summary["status"].as_str(), events.len(), summary["turns"].as_u64(),
            summary["max_depth"].as_u64(), summary["score"].as_u64(), summary_json],
    ).map_err(|e| e.to_string())?;
    {
        let mut insert = transaction
            .prepare("INSERT INTO events (run_key,sequence,payload) VALUES (?1,?2,?3)")
            .map_err(|e| e.to_string())?;
        for (event, payload) in events.iter().zip(&payloads) {
            if !existing.contains_key(&event.sequence) {
                insert
                    .execute(params![key, event.sequence, payload])
                    .map_err(|e| e.to_string())?;
            }
        }
    }
    transaction.commit().map_err(|e| e.to_string())?;
    Ok(key)
}

// serde_json's default map is sorted recursively. Keeping payloads canonical is
// essential: Python hashes the same run_start and compares exact payload strings.
fn canonical(value: &Value) -> Result<String, String> {
    serde_json::to_string(value).map_err(|error| error.to_string())
}

fn summarize(events: &[RunLogEvent]) -> Value {
    let last = events.last().expect("validated nonempty Run");
    let player = &last.player_state;
    let mut status = "unfinished";
    let (mut kills, mut damage, mut picked, mut used, mut healed) =
        (0_u64, 0_u64, 0_u64, 0_u64, 0_u64);
    for event in events {
        let result = event
            .details
            .get("result")
            .and_then(Value::as_str)
            .unwrap_or("");
        if event.event == "battle_result" {
            status = match result {
                "player_defeated" => "defeated",
                "dungeon_cleared" => "cleared",
                "restart" => "restarted",
                _ => status,
            };
            kills += u64::from(result == "enemy_defeated");
            if result == "player_hit" {
                damage += event
                    .details
                    .get("damage")
                    .and_then(Value::as_u64)
                    .unwrap_or(0);
            }
        }
        if event.event == "item_result" {
            picked += u64::from(result == "item_picked_up");
            used += u64::from(result == "item_used");
            if result == "item_used" {
                healed += event
                    .details
                    .get("healed")
                    .and_then(Value::as_u64)
                    .unwrap_or(0);
            }
        }
    }
    json!({
        "turns": events.iter().map(|e| e.turn).max().unwrap_or(0),
        "max_depth": events.iter().map(|e| e.depth).max().unwrap_or(1),
        "score": player.get("score").and_then(Value::as_u64).unwrap_or(0),
        "level": player.get("level").and_then(Value::as_u64).unwrap_or(1),
        "xp": player.get("xp").and_then(Value::as_u64).unwrap_or(0),
        "hp": player.get("hp").and_then(Value::as_i64).unwrap_or(last.hp.into()),
        "gold": player.get("gold").and_then(Value::as_u64).unwrap_or(last.gold.into()),
        "status": status, "kills": kills, "damage_taken": damage,
        "potions_picked_up": picked, "potions_used": used, "hp_healed": healed,
    })
}
