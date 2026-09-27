# Run log schema v1

AnaRogue writes one JSON object per line to
`user://simple_rogue_battle_log.jsonl`. Each line is an independent event and
conforms to [`schemas/run-log-v1.schema.json`](../schemas/run-log-v1.schema.json).

## Event envelope

Every event has the same top-level envelope:

| Field | Meaning |
| --- | --- |
| `schema_version` | Log contract version. Version 1 is represented by the integer `1`. |
| `time` | Time at which Godot wrote the event. |
| `event` | Event category, such as `decision` or `battle_result`. |
| `run_id` | Identifies one run. Enemy and decision IDs are unique within this run. |
| `sequence` | Strictly increasing event order within the run. |
| `turn` | Last completed turn when the event was written. |
| `depth` | Current dungeon depth. |
| `hp`, `gold` | Compatibility summary fields retained from the original log. |
| `player_state` | Complete player snapshot at the time of the event. |
| `details` | Event-specific payload. |

Old log lines written before this schema do not contain `schema_version` and
should be treated as legacy version 0 by readers.

## Decision events

The automatic player emits a `decision` event immediately before every action.
Its `details` object contains:

- `decision_id`: joins the decision to the following `user_action` event.
- `strategy_id`: currently `default_v1`; later this can identify a preset or DSL program.
- `rule_id`: stable name of the rule that won priority evaluation.
- `reason`: human-readable explanation intended for the log viewer.
- `action_turn`: turn that the selected action is expected to advance.
- `observation`: facts available to the strategy when it made the decision.
- `action`: selected action, direction, and target snapshot.

The current built-in rules are evaluated in this order:

1. `attack_adjacent_enemy`
2. `hunt_nearest_enemy`
3. `seek_stairs`

If pathfinding cannot reach the selected target, the corresponding
`wait_no_path_to_enemy` or `wait_no_path_to_stairs` rule is recorded instead.

The rule identifiers are deliberately independent from GDScript function names.
They are the future integration point for the strategy DSL and should only be
renamed as a schema or strategy migration.

## Entity identity

Enemies receive IDs such as `enemy-1`. Battle events include the ID and enemy
type, so a viewer can follow the same enemy through decisions and combat without
relying on its changing position.

## Ordering semantics

A decision is logged at the current completed `turn`. Its `action_turn` points
to the next turn. The resulting `user_action` carries the same `decision_id`.
Use `sequence` as the authoritative order when multiple events share a turn.
