use anarogue_simulation::{
    run_store::save_run, RunLogEvent, Simulation, SimulationConfig, Strategy,
};
use rusqlite::Connection;
use serde_json::Value;
use std::path::PathBuf;
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

struct Scratch(PathBuf);
impl Scratch {
    fn new() -> Self {
        let path = std::env::temp_dir().join(format!(
            "anarogue-store-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(&path).unwrap();
        Self(path)
    }
    fn db(&self) -> PathBuf {
        self.0.join("runs.sqlite3")
    }
}
impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}
fn events() -> Vec<RunLogEvent> {
    include_str!("../../examples/reference-v8/aggressive-seed-424242.jsonl")
        .lines()
        .map(|line| serde_json::from_str(line).unwrap())
        .collect()
}
fn count(path: &std::path::Path) -> u32 {
    Connection::open(path)
        .unwrap()
        .query_row("SELECT COUNT(*) FROM events", [], |row| row.get(0))
        .unwrap()
}

#[test]
fn save_append_reimport_and_conflict_preserve_history() {
    let scratch = Scratch::new();
    let events = events();
    let key = save_run(&scratch.db(), &events[..20]).unwrap();
    assert_eq!(save_run(&scratch.db(), &events[..40]).unwrap(), key);
    assert_eq!(save_run(&scratch.db(), &events[..10]).unwrap(), key);
    assert_eq!(count(&scratch.db()), 40);
    let mut conflict = events[..50].to_vec();
    conflict[5].hp += 1;
    assert!(save_run(&scratch.db(), &conflict)
        .unwrap_err()
        .contains("conflicting event"));
    assert_eq!(count(&scratch.db()), 40);
    assert_eq!(save_run(&scratch.db(), &events).unwrap(), key);
    assert_eq!(save_run(&scratch.db(), &events).unwrap(), key);
    assert_eq!(count(&scratch.db()), events.len() as u32);
    let db = Connection::open(scratch.db()).unwrap();
    let (status, score, depth): (String, u32, u32) = db
        .query_row("SELECT status,score,max_depth FROM runs", [], |r| {
            Ok((r.get(0)?, r.get(1)?, r.get(2)?))
        })
        .unwrap();
    assert_eq!((status.as_str(), score, depth), ("cleared", 20, 5));
    let mut extended = events.clone();
    let mut extra = events.last().unwrap().clone();
    extra.sequence += 1;
    extended.push(extra);
    assert!(save_run(&scratch.db(), &extended)
        .unwrap_err()
        .contains("completed"));
    assert_eq!(count(&scratch.db()), events.len() as u32);
}

#[test]
fn rejects_invalid_sequences_and_unknown_database_versions() {
    let scratch = Scratch::new();
    let events = events();
    assert!(save_run(&scratch.db(), &[]).is_err());
    assert!(save_run(&scratch.db(), &events[1..3]).is_err());
    let mut mixed = events[..3].to_vec();
    mixed[2].run_id = "another-run".into();
    assert!(save_run(&scratch.db(), &mixed).is_err());
    assert!(!scratch.db().exists());
    let db = Connection::open(scratch.db()).unwrap();
    db.pragma_update(None, "user_version", 99).unwrap();
    assert!(save_run(&scratch.db(), &events)
        .unwrap_err()
        .contains("version 99"));
    assert_eq!(
        db.pragma_query_value(None, "user_version", |row| row.get::<_, u32>(0))
            .unwrap(),
        99
    );
}

#[test]
fn repeated_same_seed_runs_have_unique_identity_and_equal_outcomes() {
    let config = SimulationConfig {
        scenario_seed: 424242,
        strategy: Strategy::AggressiveV1,
        map_width: 24,
        map_height: 18,
        max_turns: 120,
    };
    let first = Simulation::new_logged(config, "same.jsonl".into())
        .unwrap()
        .run_logged();
    let second = Simulation::new_logged(config, "same.jsonl".into())
        .unwrap()
        .run_logged();
    assert_ne!(first.events[0].run_id, second.events[0].run_id);
    assert_eq!(first.summary, second.summary);
    let scratch = Scratch::new();
    assert_ne!(
        save_run(&scratch.db(), &first.events).unwrap(),
        save_run(&scratch.db(), &second.events).unwrap()
    );
}

#[test]
fn cli_saves_without_jsonl_and_reports_errors() {
    let scratch = Scratch::new();
    let binary = env!("CARGO_BIN_EXE_anarogue-sim");
    let output = Command::new(binary)
        .args([
            "--db",
            scratch.db().to_str().unwrap(),
            "--revision",
            "test-revision",
        ])
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let summary: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(summary["final_score"], 20);
    let db = Connection::open(scratch.db()).unwrap();
    let revision: String = db
        .query_row("SELECT code_revision FROM runs", [], |r| r.get(0))
        .unwrap();
    assert_eq!(revision, "test-revision");
    let invalid = Command::new(binary)
        .args([
            "--db",
            scratch.db().to_str().unwrap(),
            "--output",
            scratch.db().to_str().unwrap(),
        ])
        .output()
        .unwrap();
    assert!(!invalid.status.success());
    assert_eq!(count(&scratch.db()), 273);
    let alias = scratch.0.join("alias.jsonl");
    std::fs::hard_link(scratch.db(), &alias).unwrap();
    let invalid = Command::new(binary)
        .args([
            "--db",
            scratch.db().to_str().unwrap(),
            "--output",
            alias.to_str().unwrap(),
        ])
        .output()
        .unwrap();
    assert!(!invalid.status.success());
    assert_eq!(count(&scratch.db()), 273);
    let sidecar = PathBuf::from(format!("{}-wal", scratch.db().display()));
    let invalid = Command::new(binary)
        .args([
            "--db",
            scratch.db().to_str().unwrap(),
            "--output",
            sidecar.to_str().unwrap(),
        ])
        .output()
        .unwrap();
    assert!(!invalid.status.success());
    assert_eq!(count(&scratch.db()), 273);
    #[cfg(unix)]
    {
        let link = scratch.0.join("database-link");
        std::os::unix::fs::symlink(scratch.db(), &link).unwrap();
        let invalid = Command::new(binary)
            .args([
                "--db",
                link.to_str().unwrap(),
                "--output",
                sidecar.to_str().unwrap(),
            ])
            .output()
            .unwrap();
        assert!(!invalid.status.success());
        assert_eq!(count(&scratch.db()), 273);
        let missing = scratch.0.join("future-db");
        let link = scratch.0.join("dangling-link");
        std::os::unix::fs::symlink(&missing, &link).unwrap();
        let invalid = Command::new(binary)
            .args([
                "--db",
                link.to_str().unwrap(),
                "--output",
                missing.to_str().unwrap(),
            ])
            .output()
            .unwrap();
        assert!(!invalid.status.success());
        assert!(!missing.exists());
    }
    let revision_only = Command::new(binary)
        .args(["--revision", "test"])
        .output()
        .unwrap();
    assert!(!revision_only.status.success());
}

#[test]
fn concurrent_writers_keep_a_single_complete_run() {
    let scratch = Scratch::new();
    let events = std::sync::Arc::new(events());
    save_run(&scratch.db(), &events[..20]).unwrap();
    let handles: Vec<_> = (0..3)
        .map(|_| {
            let path = scratch.db();
            let events = events.clone();
            std::thread::spawn(move || save_run(&path, &events).unwrap())
        })
        .collect();
    let keys: Vec<_> = handles.into_iter().map(|h| h.join().unwrap()).collect();
    assert!(keys.iter().all(|key| key == &keys[0]));
    assert_eq!(count(&scratch.db()), events.len() as u32);
}

#[test]
fn python_imported_prefix_can_be_completed_by_rust_without_duplicate_identity() {
    let scratch = Scratch::new();
    let events = events();
    let log = scratch.0.join("prefix.jsonl");
    let prefix: String = events[..20]
        .iter()
        .map(|event| format!("{}\n", serde_json::to_string(event).unwrap()))
        .collect();
    std::fs::write(&log, prefix).unwrap();
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .to_path_buf();
    let python = std::env::var("ANAROGUE_PYTHON").unwrap_or_else(|_| {
        if Command::new("python3").arg("--version").output().is_ok() {
            "python3".into()
        } else {
            "python".into()
        }
    });
    let imported = Command::new(&python)
        .arg(root.join("tools/run_store.py"))
        .args([
            "--db",
            scratch.db().to_str().unwrap(),
            "--revision",
            "python-producer",
            "import",
            log.to_str().unwrap(),
        ])
        .output()
        .expect("Python 3 is required for the Run-store interoperability test");
    assert!(
        imported.status.success(),
        "{}",
        String::from_utf8_lossy(&imported.stderr)
    );
    let db = Connection::open(scratch.db()).unwrap();
    let before: String = db
        .query_row("SELECT id FROM runs", [], |r| r.get(0))
        .unwrap();
    assert_eq!(save_run(&scratch.db(), &events).unwrap(), before);
    assert_eq!(count(&scratch.db()), events.len() as u32);
    let revision: String = db
        .query_row("SELECT code_revision FROM runs", [], |r| r.get(0))
        .unwrap();
    assert_eq!(revision, "python-producer");
    let rows: u32 = db
        .query_row("SELECT COUNT(*) FROM runs", [], |r| r.get(0))
        .unwrap();
    assert_eq!(rows, 1);
}
