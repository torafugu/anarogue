# Fixed-seed reference logs v7

[`examples/reference-v7/`](../examples/reference-v7/) freezes six Godot runs for
[simulation v7](simulation-spec-v7.md). It retains both navigation regression
seeds, both weapon strategies, healing, growth / descent, completion and defeat.
Historical reference logs / fixtures v1–v6 remain untouched.

Rust compares every event and final outcome, turns, depth, HP, gold, score,
potions, level and XP. Only timestamps, run IDs, paths and decision IDs are excluded.
Brute state, windup / strike events and dodge reasons are part of parity.

```sh
godot --headless --path game --script res://tools/generate_reference_logs.gd
sha256sum -c examples/reference-v7/checksums-v7.sha256
cd simulation-core
cargo test --all-targets
cd ../viewer
npm run validate:logs -- ../examples/reference-v7/*.jsonl
```

Expectations freeze reviewed final outcomes; checksum changes require review.
Cautious seed 27 completes in 203 turns; Aggressive seed 301 is defeated in 182.
Navigation tests keep their cycle checks with those v7 deterministic outcomes.
`brute_test.gd` and Rust unit tests independently exercise the new transitions.
The full 100-run strategy comparison is separately frozen and reproduced in CI.
