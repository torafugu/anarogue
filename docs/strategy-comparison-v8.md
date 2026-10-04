# Paired strategy comparison v8

[Report](../examples/comparison-v8/README.md), [JSON](../examples/comparison-v8/comparison.json)
and [per-run CSV](../examples/comparison-v8/runs.csv) compare seeds 1–50, a 44×28
map and a 500-turn budget. Enemy/item/stairs weights are 4/2/1 for Aggressive and
1/2/4 for Cautious, with temperature 8. All initial world generation is shared.

| Metric | Aggressive | Cautious |
| --- | ---: | ---: |
| Cleared | 43/50 (86%) | 40/50 (80%) |
| Defeated | 7 | 10 |
| Turn limit | 0 | 0 |
| Mean final depth | 4.68 | 4.56 |
| Mean turns, cleared runs | 189.56 | 167.35 |
| Mean cumulative HP lost, all runs | 37.06 | 24.58 |
| Mean final level | 2.10 | 1.70 |
| Brute strikes received, total | 87 | 0 |
| Brute strikes missed, total | 0 | 75 |
| Enemy goals drawn | 187 | 118 |
| Item goals drawn | 359 | 273 |
| Stairs goals drawn | 281 | 276 |
| Goal retained decisions | 7587 | 6803 |

Both clear on 37 seeds; only Aggressive on 6, only Cautious on 3, neither on 4.
The presets produce fewer enemy goals and less damage for Cautious. Weights are
preferences over available beneficial goals, not action-frequency quotas. Emergency
combat, healing and windup evasion are excluded from goal-draw counts. Retention
counts include travel, bow shots and deliberate Brute approach waits.

Compared with [v7](strategy-comparison-v7.md), clears fall from 44 to 43 for
Aggressive and from 47 to 40 for Cautious; Cautious level growth also decreases.
The new stochastic presets are an initial behavior model, not a demonstrated
balance improvement. Lower combat growth and delayed equipment acquisition can
hurt later survival. Risk estimates use current positions and do not fully predict
moving enemies or long detours. Further tuning should compare weights and temperature
against progression, growth and survival together.

All-run averages include short defeated runs. Cleared-run turn averages compare
different seed subsets. Actual HP loss is clamped on lethal hits and may exceed
max HP due to healing. This sample is not a universal ranking.

```sh
python3 tools/compare_strategies.py --seeds 1-50 --width 44 --height 28 \
  --max-turns 500 --output-dir logs/strategy-comparison \
  --log-dir logs/strategy-comparison/replays
```

`--binary PATH` reuses a release CLI. The report records parameters and a source
fingerprint; CI byte-compares all three artifacts after repeating the 100 runs.
[Simulation v8](simulation-spec-v8.md) defines the exact evaluation and lottery.
Historical v7 reports remain frozen.
