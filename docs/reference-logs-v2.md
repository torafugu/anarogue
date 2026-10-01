# Fixed-seed reference logs v2

The files in [`examples/reference-v2/`](../examples/reference-v2/) are the
deterministic Godot baseline for simulation specification v2. They cover both
strategies and multiple seeds using a 24 by 18 map.

`manifest-v2.json` records each expected terminal summary. The Rust parity test
runs the same cases and compares outcome, turns, depth, HP, gold, and score.
`checksums-v2.sha256` detects any unreviewed change to the generated JSONL files
and manifest.

Regenerate the set with:

```sh
godot --headless --path game --script res://tools/generate_reference_logs.gd
```

Validate its event envelopes with:

```sh
cd viewer
npm run validate:logs -- ../examples/reference-v2/*.jsonl
```

Intentional simulation changes should create a new specification and reference
version instead of overwriting this baseline.
