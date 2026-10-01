# Fixed-seed reference logs v1

The files in [`examples/reference/`](../examples/reference/) are the executable
Godot baseline for a future Rust simulation core. They are not statistical sample
runs. Given the published configuration, a compatible implementation should emit
the same ordered event objects and final summary.

## Deterministic metadata

Ordinary logs intentionally contain wall-clock timestamps, random run IDs, and a
machine-specific output path. Reference generation replaces only those metadata
values:

- every event time is `2000-01-01 00:00:00`;
- each run ID is `reference-<case-name>`;
- the logged file path is repository-relative; and
- the map size is explicitly `24 x 18` rather than derived from a viewport.

Strategy, map generation, decisions, turns, combat, rewards, and event ordering use
the same functions as an ordinary headless run. Reference mode does not alter game
rules or random-number consumption.

## Cases

[`manifest-v1.json`](../examples/reference/manifest-v1.json) is the authoritative
case list and final-state summary.

| Case | Purpose |
| --- | --- |
| `aggressive-seed-1` | Turn-budget result, enemy defeat and reward, repeated floor descent |
| `cautious-seed-1` | Cautious decisions, enemy attacks, and player defeat |
| `aggressive-seed-424242` | A second seed, multiple floor descents, and player defeat |

Together the three JSONL files cover all six event categories. The manifest
records `turn_limit` because the v2 event schema deliberately has no synthetic
terminal event for an externally imposed turn budget.

The reference-set version remains v1 because its simulation and randomness
baseline did not change. Its events now use run-log schema v2, whose
`floor_start.map_rows` field makes the same runs directly replayable in Godot.

## Regeneration

Run with Godot 4.5 from the repository root:

```bash
godot --headless --path game \
  --script res://tools/generate_reference_logs.gd
```

The generator checks every final outcome against constants in the script before
writing the manifest. Regenerating without a simulation change must leave the
committed files byte-for-byte unchanged. CI verifies that property against
[`checksums-v1.sha256`](../examples/reference/checksums-v1.sha256). When an
intentional rules change updates the baseline, review the JSONL and manifest
diffs before updating that checksum file.

Validate the generated event streams with:

```bash
cd viewer
npm run validate:logs -- ../examples/reference/*.jsonl
```

## Rust parity workflow

For each manifest case:

1. construct a `24 x 18` simulation with the specified scenario seed and strategy;
2. run until player defeat or the listed turn budget;
3. use the manifest's deterministic metadata values when serializing; and
4. compare parsed JSON objects in sequence order, then compare the final summary.

A rules improvement should not overwrite these files silently. Either explicitly
accept and review the reference diff, or introduce a new simulation/reference
version so old replays remain interpretable.
