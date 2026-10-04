# Fixed-seed reference logs v6

[`examples/reference-v6/`](../examples/reference-v6/) is the Godot baseline for
[simulation v6](simulation-spec-v6.md). Six runs cover both strategies, Player
bows, equipment preferences, healing, growth / descent and movement regressions.
Historical v1-v5 reference logs and fixtures remain unchanged.

Rust compares every event plus final outcome, turns, depth, HP, gold, score,
potions, level and XP. Only timestamps, run IDs, log paths and decision IDs are
excluded. Bow actions, damage, equipment kind, growth scores and rejections are
included in parity.

```sh
godot --headless --path game --script res://tools/generate_reference_logs.gd
sha256sum -c examples/reference-v6/checksums-v6.sha256
cd simulation-core
cargo test --all-targets
cd ../viewer
npm run validate:logs -- ../examples/reference-v6/*.jsonl
```

The generator freezes reviewed final states in its expectations. Changes require
review of events and outcomes before updating expectations and checksums.
`bow_test.gd` and Rust unit scenarios independently cover exact range / LOS,
lower damage, stable strategy preferences, enemy turns, XP, healing and replay
impact frames. Navigation tests retain cycle assertions with the v6 outcomes:
Cautious seed 27 clears in 192 turns; Aggressive seed 301 is defeated in 168 turns.
These cases verify determinism and regressions rather than statistical balance.
