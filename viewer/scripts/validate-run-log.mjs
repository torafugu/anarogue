import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import Ajv2020 from "ajv/dist/2020.js";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(scriptDirectory, "../..");
const schemaPaths = [
  resolve(repositoryRoot, "schemas/run-log-v1.schema.json"),
  resolve(repositoryRoot, "schemas/run-log-v2.schema.json"),
  resolve(repositoryRoot, "schemas/run-log-v3.schema.json"),
  resolve(repositoryRoot, "schemas/run-log-v4.schema.json"),
  resolve(repositoryRoot, "schemas/run-log-v5.schema.json"),
  resolve(repositoryRoot, "schemas/run-log-v6.schema.json"),
  resolve(repositoryRoot, "schemas/run-log-v7.schema.json"),
  resolve(repositoryRoot, "schemas/run-log-v8.schema.json"),
];
const defaultLogPath = resolve(repositoryRoot, "examples/sample-run-v1.jsonl");

const ajv = new Ajv2020({ allErrors: true, strict: true });
const validators = new Map(
  schemaPaths.map((schemaPath) => {
    const schema = JSON.parse(readFileSync(schemaPath, "utf8"));
    return [schema.properties.schema_version.const, ajv.compile(schema)];
  }),
);

const requestedPaths = process.argv.slice(2);
const logPaths = requestedPaths.length > 0
  ? requestedPaths.map((path) => resolve(process.cwd(), path))
  : [defaultLogPath];

let eventCount = 0;
let runCount = 0;

for (const logPath of logPaths) {
  const lines = readFileSync(logPath, "utf8").split(/\r?\n/);
  const runStates = new Map();

  lines.forEach((line, index) => {
    if (!line.trim()) return;
    const lineNumber = index + 1;
    let event;

    try {
      event = JSON.parse(line);
    } catch (error) {
      throw new Error(`${logPath}:${lineNumber}: invalid JSON: ${error.message}`);
    }

    const validateEvent = validators.get(event.schema_version);
    if (!validateEvent) {
      throw new Error(`${logPath}:${lineNumber}: unsupported schema_version ${event.schema_version}`);
    }
    if (!validateEvent(event)) {
      const errors = ajv.errorsText(validateEvent.errors, {
        dataVar: `${logPath}:${lineNumber}`,
        separator: "\n  ",
      });
      throw new Error(`Schema validation failed:\n  ${errors}`);
    }

    validateSemanticInvariants(event, runStates, logPath, lineNumber);
    eventCount += 1;
  });

  runCount += runStates.size;
}

console.log(
  `Run-log schema validation passed (${eventCount} events across ${runCount} runs).`,
);

function validateSemanticInvariants(event, runStates, logPath, lineNumber) {
  const location = `${logPath}:${lineNumber}`;
  const previous = runStates.get(event.run_id);

  if (previous) {
    assert(
      event.sequence > previous.sequence,
      location,
      `sequence must increase within run ${event.run_id}`,
    );
    assert(event.turn >= previous.turn, location, "turn must not decrease");
    assert(event.depth >= previous.depth, location, "depth must not decrease");
    assert(event.scenario_id === previous.scenario_id, location, "scenario_id changed within a run");
    assert(event.scenario_seed === previous.scenario_seed, location, "scenario_seed changed within a run");
    assert(event.strategy_id === previous.strategy_id, location, "strategy_id changed within a run");
  } else {
    assert(event.event === "run_start", location, "the first event of a run must be run_start");
    assert(event.sequence === 1, location, "run_start sequence must be 1");
    assert(event.turn === 0, location, "run_start turn must be 0");
    assert(event.depth === 1, location, "run_start depth must be 1");
  }

  assert(event.hp === event.player_state.hp, location, "hp must match player_state.hp");
  assert(event.gold === event.player_state.gold, location, "gold must match player_state.gold");

  if (event.event === "run_start") {
    assert(event.details.scenario_id === event.scenario_id, location, "run_start scenario_id mismatch");
    assert(event.details.scenario_seed === event.scenario_seed, location, "run_start scenario_seed mismatch");
    assert(event.details.strategy_id === event.strategy_id, location, "run_start strategy_id mismatch");
  }

  if (event.event === "floor_start") {
    assert(
      event.details.enemy_count === event.details.enemies.length,
      location,
      "floor_start enemy_count must match enemies.length",
    );
    if (event.schema_version >= 2) {
      assert(
        event.details.map_rows.length === event.details.map_size.height,
        location,
        "floor_start map_rows length must match map height",
      );
      event.details.map_rows.forEach((row) => {
        assert(
          row.length === event.details.map_size.width,
          location,
          "every floor_start map row must match map width",
        );
      });
    }
  }

  if (event.event === "decision") {
    assert(event.details.strategy_id === event.strategy_id, location, "decision strategy_id mismatch");
    assert(event.details.action_turn === event.turn + 1, location, "decision action_turn must equal turn + 1");
    assert(
      event.details.observation.enemy_count === event.details.observation.enemies.length,
      location,
      "decision enemy_count must match enemies.length",
    );
  }

  if (event.schema_version >= 8 && event.event === "run_start") {
    const p = event.details.goal_policy;
    assert(p.enemy_weight + p.item_weight + p.stairs_weight > 0, location, "all goal weights are zero");
  }
  if (event.schema_version >= 8 && event.details.observation?.goal_selection) {
    const g = event.details.observation.goal_selection;
    const total = g.distribution.reduce((n, row) => n + row.mass, 0);
    assert(new Set(g.distribution.map(row => row.kind)).size === g.distribution.length, location, "duplicate goal category in lottery");
    for (const row of g.distribution) {
      assert(row.total_mass === total, location, "goal probability denominator mismatch");
      assert(g.candidates.some(c => c.kind === row.kind && c.id === row.id && c.eligible), location, "lottery goal is not eligible");
    }
    for (const c of g.candidates) {
      const remaining = event.hp - c.estimated_damage;
      const risk = Math.floor(c.estimated_damage * 20 / Math.max(1, event.hp)) + Math.max(0, 6 - remaining) * 4;
      assert(c.risk === risk && c.utility === c.benefit - risk - c.turns - c.revisit_penalty, location, "goal utility mismatch");
      assert(!c.eligible || remaining > 0, location, "lethal goal included");
    }
    assert(g.candidates.some(c => c.kind === g.selected_kind && c.id === g.selected_id && c.eligible), location, "selected goal is not eligible");
    if (g.target_retained) {
      assert(g.draw === null && g.rng_before === g.rng_after, location, "retention consumes policy randomness");
    } else {
      assert(g.draw !== null && g.draw < total, location, "goal draw outside distribution");
      let cursor = g.draw;
      const chosen = g.distribution.find(row => { if (cursor < row.mass) return true; cursor -= row.mass; return false; });
      assert(chosen?.kind === g.selected_kind && chosen.id === g.selected_id, location, "goal draw does not match selected target");
    }
    const target = event.details.action.target;
    assert(g.selected_kind === "stairs" ? target.kind === "stairs" : target.id === g.selected_id, location, "goal / action target mismatch");
  }

  if (event.event === "floor_descend") {
    assert(event.details.to_depth === event.depth, location, "floor_descend to_depth mismatch");
    assert(event.details.hp_after === event.hp, location, "floor_descend hp_after mismatch");
  }

  if (event.schema_version >= 3) {
    assert(event.hp <= event.player_state.max_hp, location, "hp exceeds max_hp");
    if (event.event === "decision") {
      assert(JSON.stringify(event.details.observation.inventory) === JSON.stringify(event.player_state.inventory), location, "observation inventory mismatch");
    }
    if (event.event === "item_result") {
      assert(JSON.stringify(event.details.inventory) === JSON.stringify(event.player_state.inventory), location, "item result inventory mismatch");
      if (event.details.result === "item_used") {
        assert(event.details.hp_after - event.details.hp_before === event.details.healed, location, "healed amount mismatch");
        assert(event.details.hp_after === event.hp, location, "item hp_after mismatch");
      }
    }
  }

  if (event.schema_version >= 4) {
    const player = event.player_state;
    const rawAttack = player.base_attack + player.attack_bonus;
    const effectiveAttack = event.schema_version >= 6 && player.weapon_kind === "bow" ? Math.max(1, Math.floor(rawAttack / 2)) : rawAttack;
    assert(player.attack === effectiveAttack, location, "effective attack mismatch");
    assert(player.defense === player.base_defense + player.defense_bonus, location, "effective defense mismatch");
    assert(player.attack_bonus === (player.equipment.weapon?.attack_bonus ?? 0), location, "weapon bonus mismatch");
    assert(player.defense_bonus === (player.equipment.armor?.defense_bonus ?? 0), location, "armor bonus mismatch");
    assert(!player.equipment.weapon || player.equipment.weapon.type === "weapon", location, "wrong weapon slot");
    assert(!player.equipment.armor || player.equipment.armor.type === "armor", location, "wrong armor slot");
    if (typeof event.details.damage === "number") {
      assert(event.details.damage === Math.max(1, event.details.attack_power - event.details.defense_power), location, "damage formula mismatch");
    }
    if (event.details.result === "item_equipped") {
      assert(JSON.stringify(event.details.equipment) === JSON.stringify(player.equipment), location, "equipped item mismatch");
      assert(!event.details.items.some(item => item.id === event.details.item.id), location, "equipped item remains on floor");
    }
  }

  if (event.schema_version >= 5 && event.event === "decision") {
    const p = event.player_state;
    const ob = event.details.observation;
    assert(ob.level === p.level && ob.xp === p.xp, location, "growth observation differs from player");
    assert(ob.xp_to_next_level === p.level * 8 - p.xp, location, "XP threshold mismatch");
    const comparison = ob.progression;
    if (comparison) {
      const cautious = event.strategy_id === "cautious_v1";
      assert(comparison.stairs_healing === Math.min(4, p.max_hp - p.hp), location, "stairs recovery estimate mismatch");
      const stairsScore = (cautious ? 16 : 8) + comparison.stairs_healing * 2 - Math.min(comparison.stairs_steps, 8) + (event.depth === 4 ? 20 : 0);
      assert(comparison.stairs_score === stairsScore, location, "stairs score mismatch");
      for (const candidate of comparison.candidates) {
        if (candidate.rejection === "out_of_reach") continue;
        const enemy = ob.enemies.find(enemy => enemy.id === candidate.enemy_id);
        assert(Boolean(enemy), location, "unknown growth enemy");
        const xpGain = enemy.type === "archer" || (event.schema_version >= 7 && enemy.type === "brute") ? 5 : 3;
        assert(candidate.xp_gain === xpGain, location, "growth XP reward mismatch");
        let level = p.level, xp = p.xp + xpGain;
        while (xp >= level * 8) { xp -= level * 8; level += 1; }
        assert(candidate.levels_gained === level - p.level, location, "projected growth mismatch");
        assert(candidate.attack_turns === Math.ceil(enemy.hp / Math.max(1, p.attack - enemy.defense)), location, "projected attack count mismatch");
        const score = xpGain * (cautious ? 2 : 4) + candidate.levels_gained * (8 + (4 - event.depth) * 6)
          - candidate.steps * (cautious ? 2 : 1) - candidate.attack_turns - candidate.estimated_damage * (cautious ? 3 : 2) - candidate.revisit_penalty;
        assert(candidate.score === score, location, "combat score mismatch");
        const rejection = p.hp - candidate.estimated_damage <= (cautious ? 4 : 2) ? "hp_reserve"
          : cautious && enemy.type === "archer" && (event.schema_version < 6 || p.weapon_kind !== "bow") ? "mobile_target" : cautious && candidate.levels_gained === 0 ? "no_level_up" : "";
        assert(candidate.rejection === rejection && candidate.eligible === !rejection, location, "combat safety assessment mismatch");
      }
      if (comparison.selected === "combat") {
        const candidate = comparison.candidates.find(candidate => candidate.enemy_id === comparison.selected_enemy_id);
        assert(candidate?.eligible && candidate.score > comparison.stairs_score, location, "selected growth fight is not advantageous");
        assert(event.details.action.target.id === comparison.selected_enemy_id && event.details.rule_id === "hunt_for_growth", location, "selected growth target mismatch");
      } else {
        assert(comparison.selected_enemy_id === null && !comparison.target_retained, location, "stairs decision has a combat target");
        assert(event.details.action.target.kind === "stairs" && event.details.rule_id === "descend_for_progress", location, "stairs action mismatch");
      }
    }
  }

  if (event.schema_version >= 6) {
    const p = event.player_state;
    assert(p.weapon_kind === (p.equipment.weapon?.weapon_kind ?? "melee"), location, "weapon subtype mismatch");
    assert(p.attack_range === (p.weapon_kind === "bow" ? 5 : 1), location, "weapon range mismatch");
    if (event.event === "user_action" && event.details.action === "shoot") {
      const from = event.details.from, to = event.details.target;
      const distance = (from.x - to.x) ** 2 + (from.y - to.y) ** 2;
      assert(p.weapon_kind === "bow" && distance > 0 && distance <= 25, location, "shot outside bow range");
      assert(from.x === p.pos.x && from.y === p.pos.y, location, "shot origin mismatch");
    }
    if (event.event === "battle_result" && ["enemy_hit", "enemy_defeated"].includes(event.details.result) && event.details.ranged) {
      assert(p.weapon_kind === "bow", location, "player ranged hit without bow");
    }
  }

  const windups = new Map(previous?.windups ?? []);
  if (event.schema_version >= 7) {
    const enemies = event.event === "floor_start" ? event.details.enemies
      : event.event === "decision" ? event.details.observation.enemies : [];
    for (const enemy of enemies) {
      if (enemy.windup_target) {
        assert(enemy.type === "brute", location, "only Brute can wind up");
        assert(Math.abs(enemy.pos.x - enemy.windup_target.x) + Math.abs(enemy.pos.y - enemy.windup_target.y) === 1, location, "windup target must be adjacent");
      }
    }
    if (["floor_start", "floor_descend"].includes(event.event)) windups.clear();
    if (event.event === "battle_result") {
      const d = event.details;
      if (d.result === "enemy_windup") {
        assert(!windups.has(d.enemy_id), location, "Brute wound up twice without resolving its strike");
        assert(d.target.x === event.player_state.pos.x && d.target.y === event.player_state.pos.y, location, "Brute must mark Player's current tile");
        assert(d.target.x === d.windup_target.x && d.target.y === d.windup_target.y, location, "windup target mismatch");
        assert(Math.abs(d.enemy_pos.x - d.target.x) + Math.abs(d.enemy_pos.y - d.target.y) === 1, location, "Brute cannot wind up at range");
        windups.set(d.enemy_id, { target: d.target, turn: event.turn });
      } else if (d.result === "enemy_strike_missed" || (d.result === "player_hit" && d.enemy_type === "brute")) {
        const ready = windups.get(d.enemy_id);
        assert(Boolean(ready) && event.turn === ready.turn + 1, location, "Brute strike requires the previous turn's windup");
        const pos = event.player_state.pos;
        const onTarget = pos.x === ready.target.x && pos.y === ready.target.y;
        assert(d.result === "player_hit" ? onTarget : !onTarget, location, "Brute strike retargeted after its windup");
        if (d.result === "enemy_strike_missed") {
          assert(d.target.x === ready.target.x && d.target.y === ready.target.y, location, "missed strike target mismatch");
        }
        assert(d.windup_target === null, location, "resolved strike must clear the windup");
        windups.delete(d.enemy_id);
      } else if (d.result === "enemy_defeated") windups.delete(d.enemy_id);
    }
  }

  runStates.set(event.run_id, {
    windups,
    sequence: event.sequence,
    turn: event.turn,
    depth: event.depth,
    scenario_id: event.scenario_id,
    scenario_seed: event.scenario_seed,
    strategy_id: event.strategy_id,
  });
}

function assert(condition, location, message) {
  if (!condition) throw new Error(`${location}: ${message}`);
}
