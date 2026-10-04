# Fixed-seed reference logs v5

[`examples/reference-v5/`](../examples/reference-v5/) is the current Godot baseline
for [simulation v5](simulation-spec-v5.md). It covers both strategies, growth and
descent scoring, equipment, healing, completion / defeat, and movement regressions.
Historical v1-v4 reference logs and fixtures remain unchanged.

Rust compares every event plus final outcome, turns, depth, HP, gold, score,
potions, level and XP. Only timestamps, run IDs, log paths and decision IDs are
excluded. Scoring and rejection reasons are included in event parity.

```sh
godot --headless --path game --script res://tools/generate_reference_logs.gd
sha256sum -c examples/reference-v5/checksums-v5.sha256
cd simulation-core
cargo test --all-targets
cd ../viewer
npm run validate:logs -- ../examples/reference-v5/*.jsonl
```

The generator freezes reviewed final states. Intentional changes require review
of event differences and final outcomes before updating expectations/checksums.
The small `growth_test.gd` / Rust unit scenarios independently exercise exact XP
thresholds, equipment-sensitive choices, HP reserve, Archer mobility, route
blocking, revisit costs and stable target selection.
