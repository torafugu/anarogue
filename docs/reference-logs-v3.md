# Fixed-seed reference logs v3

[`examples/reference-v3/`](../examples/reference-v3/) is the current deterministic
Godot baseline for [simulation v3](simulation-spec-v3.md) and Schema v3.
Four 24x18 cases, a 44x28 Cautious pursuit-cycle regression and a 64x40 Aggressive target-switching regression cover gathering and healing under both strategies, player defeat,
dungeon completion, the turn limit and recovery from repeated movement. `manifest-v3.json` includes expected final
inventory. V1 and v2 files remain unchanged historical references.

The Rust test compares the complete event stream as well as final outcomes,
turns, depth, HP, gold, score and potion count. Only runtime-specific timestamps,
run IDs, log paths and decision IDs are excluded from event comparison.

```sh
godot --headless --path game --script res://tools/generate_reference_logs.gd
sha256sum -c examples/reference-v3/checksums-v3.sha256
cd simulation-core
cargo test --all-targets
cd ../viewer
npm run validate:logs -- ../examples/reference-v3/*.jsonl
```

When rules change intentionally, review expected summaries, fixture changes and
reference diffs before updating the checksums. The generator freezes the expected
summaries, so accidental changes fail regeneration.
