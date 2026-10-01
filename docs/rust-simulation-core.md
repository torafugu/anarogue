# Rust Simulation Core

`simulation-core/` is the Godot-independent implementation of AnaRogue's v1
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

It deliberately does not own rendering, wall-clock timing, UI input, run IDs, or
log file paths. Event serialization remains in Godot for now. The next parity
milestone is to emit the same ordered v1 JSONL events from Rust.

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

## Compatibility tests

```bash
cargo test --all-targets
```

The test suite checks the published FNV-1a/xorshift32 vectors and runs all three
cases from `examples/reference/manifest-v1.json` against the Godot final-state
baseline. GitHub Actions runs these tests independently of the Godot job.

The current tests compare terminal state rather than the entire JSONL stream.
Until Rust event parity is implemented, Godot's committed reference logs remain
the authoritative event-level representation.
