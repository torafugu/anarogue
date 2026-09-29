# AnaRogue

A tiny Godot 4 roguelike starter.

## Play

Open this folder in Godot 4 and run the main scene.

Controls:

- Choose `Aggressive` or `Cautious`, then click `Start selected strategy`
- Click `Compare both — same seed` to run both strategies on matching floors
- Arrow keys: manually move or attack
- `.`: manually wait
- `R`: restart

## Current Features

- Procedural room-and-corridor dungeon generation
- Automatic player movement and bump attacks
- Two automatic strategies:
  - **Aggressive** — hunts every enemy, then seeks the stairs
  - **Cautious** — takes a danger-weighted route to the stairs and only fights
    when its path is blocked
- Same-seed comparison mode with deterministic floor layouts, enemy spawns, and
  per-enemy rewards
- Turn-based player and enemy actions
- Two enemy types:
  - **Melee** — charges and attacks up close
  - **Archer** — keeps distance and fires arrows; retreats when cornered
- Stairs to deeper floors; enemies scale with depth
- HP, depth, gold, **score**, and message log HUD
- Score system: 1 point per melee kill, 2 points per archer kill, and 3 points
  per depth descended; no points per turn. Runs start at 0 points.
- JSON Lines action and battle log at `user://anarogue.jsonl`
- Versioned run-log schema with automatic-player observations, selected rules,
  actions, and human-readable decision reasons

See [Simulation specification v1](docs/simulation-spec-v1.md) for the current
state and turn-processing rules, [Run log schema v1](docs/run-log-v1.md) for the
event contract, and
[`examples/sample-run-v1.jsonl`](examples/sample-run-v1.jsonl) for sample data.

## Run viewer

The Vite + TypeScript viewer in [`viewer/`](viewer/) turns a run into a summary,
HP chart, route map, searchable event stream, and decision inspector. Runs with
the same scenario ID are grouped into an Aggressive vs. Cautious comparison.

```bash
cd viewer
npm install
npm run dev
```

## Run headless simulation

Run one automatic game without opening the UI. The runner advances turns as fast
as possible, writes the same v1 event stream as the interactive game, and prints
a final `HEADLESS_RUN_SUMMARY` line to standard output.

```bash
godot --headless --path game \
  --script res://tools/headless_run.gd -- \
  --strategy aggressive \
  --seed 424242 \
  --max-turns 5000 \
  --output ../logs/aggressive-424242.jsonl
```

`--strategy` accepts `aggressive` or `cautious`. Relative output paths are
resolved from `game/`; absolute paths and `user://` paths are also accepted. The
output file is replaced on each invocation. Defaults are equivalent to:

```text
--strategy aggressive --seed 424242 --max-turns 5000 \
--output user://anarogue-headless.jsonl
```

The process exits successfully whether the player is defeated or the turn limit
is reached. Read the summary's `outcome` field to distinguish
`player_defeated` from `turn_limit`. A turn-limit stop does not add a synthetic
event to the v1 stream.

## Tests

Run the fixed-seed simulation regression suite with Godot 4.5:

```bash
godot --headless --path game \
  --script res://tests/fixed_seed_regression.gd
```

The committed fixture freezes dungeon tiles, rooms, actors, deterministic rewards,
and the first Aggressive and Cautious decisions for three scenario/depth/map-size
combinations. When a simulation change is intentional, regenerate it with:

```bash
godot --headless --path game \
  --script res://tests/fixed_seed_regression.gd -- --write-fixture
```

Review the fixture diff before committing it. A fixture update changes the v1
simulation baseline described in
[Simulation specification v1](docs/simulation-spec-v1.md).

Validate JSONL events against the v1 JSON Schema and stream invariants with:

```bash
cd viewer
npm install
npm run validate:logs
```

Pass one or more JSONL paths after `--` to validate other logs:

```bash
npm run validate:logs -- ../path/to/anarogue.jsonl
```
