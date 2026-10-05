# Reference logs v8

[Manifest](../examples/reference-v8/manifest-v8.json) and
[checksums](../examples/reference-v8/checksums-v8.sha256) freeze six Godot runs,
including the former Cautious seed-27 and Aggressive seed-301 cycle cases. Their
v8 outcomes differ from v7 because goal selection is now probabilistic.

Regenerate with Godot 4.5:

```sh
godot --headless --path game --script res://tools/generate_reference_logs.gd
sha256sum -c examples/reference-v8/checksums-v8.sha256
cargo test --manifest-path simulation-core/Cargo.toml --test reference_runs
```

The generator asserts reviewed final states. Rust compares every event and final
state, ignoring only timestamps, run IDs, output paths and derived decision IDs.
Historical v1–v7 logs, manifests and checksums remain frozen. The fixed-floor /
preview snapshot uses `game/tests/fixtures/fixed-seed-v8.json`.
