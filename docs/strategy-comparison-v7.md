# Paired strategy comparison v7

The committed [report](../examples/comparison-v7/README.md),
[JSON](../examples/comparison-v7/comparison.json) and [per-run CSV](../examples/comparison-v7/runs.csv)
compare seeds 1–50, a 44×28 map and a 500-turn budget. Each seed runs both policies.
Depth 5 is completion; defeated and turn-limit outcomes are counted separately.

| Metric | Aggressive | Cautious |
| --- | ---: | ---: |
| Cleared | 44/50 (88%) | 47/50 (94%) |
| Mean final depth | 4.66 | 4.86 |
| Mean turns, cleared runs | 203.34 | 171.38 |
| Mean cumulative HP lost, all runs | 38.50 | 16.94 |
| Mean final level | 2.08 | 2.24 |
| Brute strikes received, total | 80 | 1 |
| Brute strikes missed, total | 0 | 52 |
| Brute preparations interrupted by kill | 52 | 18 |

Both clear on 41 seeds, only Aggressive on 3, only Cautious on 6; neither on 0.
No run reaches the turn limit. Here, bows and marked-tile evasion favor Cautious,
which also gets slightly more kills / growth. This describes this sample, not a
universal ranking or a statistically established balance result. All-run means
include short defeated games. Cleared-run time means compare different seed
subsets. Cumulative HP lost counts actual loss after armor (a lethal hit clamps
to remaining HP) and can exceed maximum HP because of healing.

## Reproduce and inspect

From the repository root with Python 3 and Rust / cargo installed:

```sh
python3 tools/compare_strategies.py --seeds 1-50 --width 44 --height 28 \
  --max-turns 500 --output-dir logs/strategy-comparison \
  --log-dir logs/strategy-comparison/replays
```

The command builds the release Rust CLI, runs each seed / policy, and writes
README.md, comparison.json and runs.csv. `--binary PATH` reuses an existing CLI;
`--seeds 1-10,27,301` supports custom ranges. `--log-dir` retains replayable JSONL;
otherwise temporary event logs are removed after metrics are collected. Copy a
selected log into Godot's `user://` directory and refresh the replay selector,
or load it in the web viewer. Neither report generation nor loading changes runs.

The report records parameters and a source fingerprint; no wall-clock timestamps
are used. CI repeats all 100 runs and byte-compares the three committed artifacts.
Metrics tests verify paired counts, missing / duplicate pairs, actual HP loss and
preparation accounting. Windups resolve into hits, misses, interruptions, leaving
on descent or unresolved at the end of a run; these categories sum to all windups.
