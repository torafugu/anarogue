# AnaRogue

A tiny Godot 4 roguelike starter.

## Run and Replay in Godot

The replay client selects Runs from a persistent SQLite catalogue. From the
repository root, build the Rust simulator and start the local API:

```bash
cargo build --release --manifest-path simulation-core/Cargo.toml
python3 tools/run_store.py serve
```

Open `game/` in Godot 4 and run the project. The main screen offers **Run**
and **Replay**. Run opens settings for seed, strategy, enemy/treasure/stairs
weights and maximum turns. Start a Run to execute Rust through the API; the
result is saved to SQLite and opens in Replay when complete. Strategy changes
restore its preset weights, which can then be adjusted individually.

Replay lets you select a saved Run by strategy, seed,
result and short ID. The list updates automatically; there is no file selector
or Refresh logs button. API failures fall back to the bundled sample and retry.
The original JSONL events remain available for export and offline replay.

Controls:

- Run selector: choose a stored Run; changing it restarts playback
- `Previous` / `Next` or left / right arrows: step through decision frames
- `Play` or space: automatically advance the replay
- The maze uses large tiles and follows Player; only the surrounding area is shown
- `Home`: return to the main screen

The mobile replay layout uses 40 px text and large buttons. The scrollable log
and Player panels take more vertical space, leaving a smaller maze viewport with
the same large tiles. The catalogue updates without interrupting playback.
See [Persistent Run store](docs/run-store.md) for import, watch, endpoint,
mobile connection and database/API details.

The former live simulation is retained at `game/scenes/main.tscn`, but it is no
longer the project's default responsibility.

## Current Features

- Procedural room-and-corridor dungeon generation
- Automatic player movement and bump attacks
- Repeated-visit path costs prevent pursuit-induced movement loops
- Two automatic strategies:
  - **Aggressive** — prefers melee weapons and weights enemy/item/stairs goals 4/2/1
  - **Cautious** — prefers bows and weights enemy/item/stairs goals 1/2/4
- Adjustable enemy/item/stairs priorities and temperature; weighted random goal selection
- Pure decision previews and an independent policy RNG with reproducible draws
- Same-seed comparison mode with deterministic floor layouts, enemy spawns, and
  per-enemy rewards
- Floor health potions, automatic pickup and persistent inventory (up to 3)
- Potion use restores up to 8 HP and consumes one turn before enemy actions
- Automatic gathering and healing, with benefit/risk estimates and persistent goals
- Weapon and armor slots with automatic upgrades, separate base stats and bonuses
- Melee weapons favor damage; bows reach five tiles with clear line of sight and half attack
- Aggressive prefers melee equipment; Cautious prefers bows; `F` fires manually
- Damage = max(1, effective attack - effective defense)
- Item pickup/use/equipment frames in Godot replay and resource totals in the web viewer
- Turn-based player and enemy actions
- Three enemy types:
  - **Melee** — charges and attacks up close
  - **Archer** — keeps distance and fires arrows; retreats when cornered
  - **Brute** — slow movement; telegraphs a heavy strike on a fixed adjacent tile
- Stairs to deeper floors; enemies scale with depth
- HP, depth, gold, **score**, and message log HUD
- Score system: 1 point per melee kill, 2 points per Archer or Brute kill, and 3 points
  per depth descended; no points per turn. Runs start at 0 points.
- JSON Lines action and battle log at `user://anarogue.jsonl`
- Versioned run-log schema with automatic-player observations, selected rules,
  actions, and human-readable decision reasons

See [Simulation specification v8](docs/simulation-spec-v8.md) for the current
state and turn-processing rules, [Run log schema v1](docs/run-log-v1.md) and
[Run log schema v2](docs/run-log-v2.md) and
[Run log schema v3](docs/run-log-v3.md) and
[Run log schema v8](docs/run-log-v8.md) for the event contracts,
[Portable randomness specification v1](docs/randomness-v1.md)
for cross-runtime seed derivation and PRNG behavior,
[Fixed-seed reference logs v8](docs/reference-logs-v8.md) for the Godot-to-Rust
compatibility baseline, [Rust Simulation Core](docs/rust-simulation-core.md) for
the Godot-independent batch implementation, and
[`examples/sample-run-v1.jsonl`](examples/sample-run-v1.jsonl) for sample data.

## Run viewer

The Vite + TypeScript viewer in [`viewer/`](viewer/) lists the stored Runs and
provides strategy/seed/result filtering and policy/version-separated aggregates.
It turns a selected Run into a summary,
HP chart, route map, searchable event stream, and decision inspector. Runs with
the same seed and compatible versions can be compared across source files.

```bash
cd viewer
npm install
npm run dev
```

## Run headless simulation

Run one automatic game without opening the UI. The runner advances turns as fast
as possible, writes the same v8 event stream as the interactive game, and prints
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
event to the v8 stream.

## Tests

Verify repeated movement recovery and required backtracking with:

```bash
godot --headless --path game --script res://tests/navigation_test.gd
```

Verify Player bow range, wall occlusion, damage, weapon preferences and replay with:

```bash
godot --headless --path game --script res://tests/bow_test.gd
```

Verify equipment upgrades, base stats, damage and replay with:

```bash
godot --headless --path game --script res://tests/equipment_test.gd
```

Verify item pickup, capacity, healing, strategy decisions and replay with:

```bash
godot --headless --path game --script res://tests/items_test.gd
```

Verify Archer wall and corner occlusion with Godot 4.5:

```sh
godot --headless --path game --script res://tests/line_of_sight_test.gd
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

Review the fixture diff before committing it. A fixture update changes the v8
simulation baseline described in
[Simulation specification v8](docs/simulation-spec-v8.md).

Run the Rust simulation-core compatibility suite with:

```bash
cd simulation-core
cargo test --all-targets
```

The Rust tests execute six fixed-seed full-run cases and compare every event
and final state with the Godot reference baseline.

The Rust CLI can save Runs directly into the catalogue without a JSONL import.
From the repository root:

```bash
cargo run --release --manifest-path simulation-core/Cargo.toml -- \
  --strategy aggressive --seed 424242 --max-turns 5000 \
  --db logs/runs.sqlite3
```

The API (`python3 tools/run_store.py serve`) reads this same database; Godot and
Web refresh their Run lists automatically. Add `--output logs/run.jsonl` to also
export JSONL and `--revision <producer-commit>` to record the source revision.
Direct persistence commits the complete Run after simulation finishes. See
[Run store guide](docs/run-store.md) for details.

Regenerate the deterministic full-run reference logs with:

```bash
godot --headless --path game \
  --script res://tools/generate_reference_logs.gd
```

With no simulation change, this command must leave `examples/reference-v8/`
byte-for-byte unchanged. See
[Fixed-seed reference logs v8](docs/reference-logs-v8.md) for the cases and Rust
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

Growth-aware exploration compares XP / projected levels and estimated combat cost with descent, recovery and completion. See [simulation v8](docs/simulation-spec-v8.md). The web viewer shows the candidate scores and final level / XP for strategy comparisons.

Compare both policies across seeds with:

```sh
python3 tools/compare_strategies.py --seeds 1-50 --output-dir logs/strategy-comparison
```

See [the paired comparison](docs/strategy-comparison-v8.md) for the frozen
100-run results, parameters, replay logs and interpretation limits.

Verify Brute cadence, fixed targets, evasion and replay with:

```sh
godot --headless --path game --script res://tests/brute_test.gd
python3 -m unittest discover -s tools -p 'test_*.py'
```
