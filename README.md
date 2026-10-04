# AnaRogue

A tiny Godot 4 roguelike starter.

## Replay in Godot

Open `game/` in Godot 4 and run the project. The default scene is a replay client,
not the simulator. It lists JSONL files in `user://`, selects the most recently
modified log, and falls back to the committed Aggressive seed-424242 v3 reference run when
no user log exists.

Controls:

- log selector: choose a JSONL file stored directly in `user://`
- `Refresh logs`: rescan `user://` after generating a log
- `Previous` / `Next` or left / right arrows: step through decision frames
- `Play` or space: automatically advance the replay
- run selector: switch runs when one JSONL file contains multiple runs
- `Live check`: open the legacy Godot simulator for occasional visual checks

The former live simulation is retained at `game/scenes/main.tscn`, but it is no
longer the project's default responsibility.

## Current Features

- Procedural room-and-corridor dungeon generation
- Automatic player movement and bump attacks
- Repeated-visit path costs prevent pursuit-induced movement loops
- Two automatic strategies:
  - **Aggressive** — hunts every enemy, then seeks the stairs
  - **Cautious** — takes a danger-weighted route to the stairs and only fights
    when its path is blocked
- Same-seed comparison mode with deterministic floor layouts, enemy spawns, and
  per-enemy rewards
- Floor health potions, automatic pickup and persistent inventory (up to 3)
- Potion use restores up to 8 HP and consumes one turn before enemy actions
- Automatic gathering and healing, with conservative safe detours for Cautious
- Item pickup/use frames in Godot replay and resource totals in the web viewer
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

See [Simulation specification v3](docs/simulation-spec-v3.md) for the current
state and turn-processing rules, [Run log schema v1](docs/run-log-v1.md) and
[Run log schema v2](docs/run-log-v2.md) and
[Run log schema v3](docs/run-log-v3.md) for the event contracts,
[Portable randomness specification v1](docs/randomness-v1.md)
for cross-runtime seed derivation and PRNG behavior,
[Fixed-seed reference logs v3](docs/reference-logs-v3.md) for the Godot-to-Rust
compatibility baseline, [Rust Simulation Core](docs/rust-simulation-core.md) for
the Godot-independent batch implementation, and
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
as possible, writes the same v3 event stream as the interactive game, and prints
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
output file is replaced on each invocation. Keep the standalone `--` before the
runner arguments; `--output PATH` and `--output=PATH` are both accepted. For
compatibility, runner arguments placed before the separator are also detected.
Defaults are equivalent to:

```text
--strategy aggressive --seed 424242 --max-turns 5000 \
--output user://anarogue-headless.jsonl
```

The process exits successfully whether the player is defeated or the turn limit
is reached. Read the summary's `outcome` field to distinguish
`player_defeated` from `turn_limit`. A turn-limit stop does not add a synthetic
event to the v3 stream.

## Tests

Verify repeated movement recovery and required backtracking with:

```bash
godot --headless --path game --script res://tests/navigation_test.gd
```

Verify item pickup, capacity, healing, strategy decisions and replay with:

```bash
godot --headless --path game --script res://tests/items_test.gd
```

Run the fixed-seed simulation regression suite with Godot 4.5:

```bash
godot --headless --path game \
  --script res://tests/fixed_seed_regression.gd
```

Verify the portable FNV-1a and xorshift32 test vectors with:

```bash
godot --headless --path game \
  --script res://tests/portable_rng_test.gd
```

The committed fixture freezes dungeon tiles, rooms, actors, deterministic rewards,
and the first Aggressive and Cautious decisions for four scenario/depth/map-size
combinations. When a simulation change is intentional, regenerate it with:

```bash
godot --headless --path game \
  --script res://tests/fixed_seed_regression.gd -- --write-fixture
```

Review the fixture diff before committing it. A fixture update changes the v3
simulation baseline described in
[Simulation specification v3](docs/simulation-spec-v3.md).

Run the Rust simulation-core compatibility suite with:

```bash
cd simulation-core
cargo test --all-targets
```

The Rust tests execute five fixed-seed full-run cases and compare every event
and final state with the Godot reference baseline.

The Rust CLI can also write a replayable Schema v3 log directly into Godot's
macOS application-data folder:

```bash
cd simulation-core
cargo run --release -- \
  --strategy aggressive \
  --seed 424242 \
  --max-turns 5000 \
  --output "$HOME/Library/Application Support/Godot/app_userdata/anarogue/rust-aggressive-424242.jsonl"
```

Return to the Godot replay client and select `Refresh logs` after the run.

Regenerate the deterministic full-run reference logs with:

```bash
godot --headless --path game \
  --script res://tools/generate_reference_logs.gd
```

With no simulation change, this command must leave `examples/reference-v3/`
byte-for-byte unchanged. See
[Fixed-seed reference logs v3](docs/reference-logs-v3.md) for the cases and Rust
parity workflow.

Validate JSONL events against their versioned JSON Schema and stream invariants with:

```bash
cd viewer
npm install
npm run validate:logs
```

Pass one or more JSONL paths after `--` to validate other logs:

```bash
npm run validate:logs -- ../path/to/anarogue.jsonl
```
