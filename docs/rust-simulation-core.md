# Rust Simulation Core

`simulation-core/` is the Godot-independent implementation of AnaRogue's v8
simulation rules. Godot remains the presentation and replay client; this crate is
the starting point for batch execution, a server API, and future machine-learning
interfaces.

## Current boundary

The Rust core owns deterministic state transitions:

- portable seed derivation and random streams;
- dungeon generation and enemy spawning;
- aggressive and cautious policy decisions;
- player movement, combat, rewards, and progression;
- melee and archer turns; and
- floor transitions and run termination at a turn budget.

It deliberately does not own rendering or UI input. The CLI supplies run metadata
and optional JSONL/database destinations; the core emits the same Schema v8 event categories used
by the Godot replay client.

## Run

From `simulation-core/`:

```bash
cargo run -- \
  --strategy aggressive \
  --seed 424242 \
  --width 24 \
  --height 18 \
  --max-turns 120
```

The command prints one JSON summary. The map dimensions are independent inputs;
they are not encoded into or substituted for the scenario seed.

To persist Runs directly, run from the repository root:

```bash
cargo run --release --manifest-path simulation-core/Cargo.toml -- \
  --strategy aggressive --seed 424242 --max-turns 5000 \
  --db logs/runs.sqlite3
```

Start `python3 tools/run_store.py serve` against that database for Godot/Web
selection and analysis. Saving does not require the API to be running. Completed
writes appear through automatic catalogue refresh; no Refresh logs button or
JSONL import is needed.

`--db` and `--output PATH` can be combined to save SQLite and export a replayable
Schema v8 JSONL. `--revision REV` optionally records the producer revision in both
outputs. CLI executions use unique Run IDs; replay events and outcomes remain
seed-reproducible. The library exposes `run_store::save_run(path, events)`.

Paths are normal OS paths, not Godot `user://` URIs. Relative paths are resolved
against the process working directory. SQLite persistence occurs once at the end
of `run_logged`; no per-turn live DB streaming is currently implemented. The
original JSON summary remains on stdout. See [Run store guide](run-store.md) for
transactions, duplicate/conflict handling, optional JSONL and API configuration.

## Compatibility tests

```bash
cargo test --all-targets
```

The test suite checks the published FNV-1a/xorshift32 vectors and runs all six
cases from `examples/reference-v8/manifest-v8.json` against the Godot event-stream and final-state
baseline. GitHub Actions runs these tests independently of the Godot job.

The parity tests use the committed Godot reference logs and summaries.
CI additionally generates a Rust log and validates every event against the shared
Schema v8 contract and stream invariants.

## Goal policy overrides

The CLI accepts `--enemy-weight`, `--item-weight`, `--stairs-weight` (0–1000,
at least one positive) and `--temperature` (1–100). Unspecified values come from
the strategy preset, regardless of option order. The Rust API exposes
`GoalPolicy`, `new_with_policy` and `new_logged_with_policy`.

```sh
cargo run --manifest-path simulation-core/Cargo.toml -- --strategy cautious \
  --seed 27 --width 44 --height 28 --max-turns 500 \
  --enemy-weight 2 --item-weight 3 --stairs-weight 4 --temperature 12 \
  --output logs/custom-goals.jsonl
```

The Godot headless runner accepts the same four policy flags. See
[simulation v8](simulation-spec-v8.md) for exact estimates and probability masses.
