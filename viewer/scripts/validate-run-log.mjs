import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import Ajv2020 from "ajv/dist/2020.js";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(scriptDirectory, "../..");
const schemaPath = resolve(repositoryRoot, "schemas/run-log-v1.schema.json");
const defaultLogPath = resolve(repositoryRoot, "examples/sample-run-v1.jsonl");

const schema = JSON.parse(readFileSync(schemaPath, "utf8"));
const ajv = new Ajv2020({ allErrors: true, strict: true });
const validateEvent = ajv.compile(schema);

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
