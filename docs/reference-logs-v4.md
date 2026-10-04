# Fixed-seed reference logs v4

[`examples/reference-v4/`](../examples/reference-v4/) is the current Godot baseline
for [simulation v4](simulation-spec-v4.md). Six cases cover both strategies, potion
and equipment collection, upgrades, damage, completion and defeat. Four use 24x18;
the Cautious seed-27 and Aggressive seed-301 movement regressions use 44x28 and
64x40. Item detours legitimately retrace a route, so the Aggressive regression
checks pursuit reversals separately from detours for equipment.

The Rust parity test compares every event plus final outcome, turns, depth, HP,
gold, score and potions. Only timestamps, run IDs, log paths and decision IDs are
excluded. Historical v1-v3 reference logs and fixtures remain unchanged.

```sh
godot --headless --path game --script res://tools/generate_reference_logs.gd
sha256sum -c examples/reference-v4/checksums-v4.sha256
cd simulation-core
cargo test --all-targets
cd ../viewer
npm run validate:logs -- ../examples/reference-v4/*.jsonl
```

The generator freezes reviewed outcomes. Intentional rule changes require review
of final outcomes and event diffs before updating expectations and checksums.
