# Rust Simulation Core

`simulation-core/` is the Godot-independent implementation of AnaRogue's v4
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
and an optional log path; the core emits the same Schema v4 event categories used
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

Add `--output PATH` to write a replayable Schema v4 JSONL log while retaining the
summary on standard output. On macOS, write directly to the Godot project data
directory so the replay selector can discover it:

```bash
cargo run --release -- \
  --strategy aggressive \
  --seed 424242 \
  --max-turns 5000 \
  --output "$HOME/Library/Application Support/Godot/app_userdata/anarogue/rust-aggressive-424242.jsonl"
```

The CLI accepts a normal operating-system path rather than the Godot-only
`user://` URI. It creates missing parent directories and replaces an existing
file at the selected path. Use `Refresh logs` in the Godot replay client after a
run completes.

## Compatibility tests

```bash
cargo test --all-targets
```

The test suite checks the published FNV-1a/xorshift32 vectors and runs all six
cases from `examples/reference-v4/manifest-v4.json` against the Godot event-stream and final-state
baseline. GitHub Actions runs these tests independently of the Godot job.

The parity tests use the committed Godot reference logs and summaries.
CI additionally generates a Rust log and validates every event against the shared
Schema v4 contract and stream invariants.
