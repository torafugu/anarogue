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
    assert(player.attack === player.base_attack + player.attack_bonus, location, "effective attack mismatch");
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
        const xpGain = enemy.type === "archer" ? 5 : 3;
        assert(candidate.xp_gain === xpGain, location, "growth XP reward mismatch");
        let level = p.level, xp = p.xp + xpGain;
        while (xp >= level * 8) { xp -= level * 8; level += 1; }
        assert(candidate.levels_gained === level - p.level, location, "projected growth mismatch");
        assert(candidate.attack_turns === Math.ceil(enemy.hp / Math.max(1, p.attack - enemy.defense)), location, "projected attack count mismatch");
        const score = xpGain * (cautious ? 2 : 4) + candidate.levels_gained * (8 + (4 - event.depth) * 6)
          - candidate.steps * (cautious ? 2 : 1) - candidate.attack_turns - candidate.estimated_damage * (cautious ? 3 : 2) - candidate.revisit_penalty;
        assert(candidate.score === score, location, "combat score mismatch");
        const rejection = p.hp - candidate.estimated_damage <= (cautious ? 4 : 2) ? "hp_reserve"
          : cautious && enemy.type === "archer" ? "mobile_target" : cautious && candidate.levels_gained === 0 ? "no_level_up" : "";
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

  runStates.set(event.run_id, {
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
