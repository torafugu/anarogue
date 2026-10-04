# Strategy comparison: simulation v7

Seeds: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50. Map: 44×28. Budget: 500 turns.

| Metric | Aggressive | Cautious |
| --- | ---: | ---: |
| Clears / runs | 44/50 | 47/50 |
| Clear rate | 88% | 94% |
| Defeats | 6 | 3 |
| Turn limits | 0 | 0 |
| Mean final depth | 4.66 | 4.86 |
| Mean turns (clears only) | 203.34 | 171.38 |
| Mean HP lost (all runs) | 38.50 | 16.94 |
| Mean final level | 2.08 | 2.24 |
| Mean score | 17.38 | 18.84 |
| Mean Brute kills | 1.36 | 1.68 |
| Mean bow shots | 0 | 13.58 |
| Brute windups | 132 | 71 |
| Brute hits | 80 | 1 |
| Brute misses | 0 | 52 |
| Brute interrupted by kill | 52 | 18 |
| Brute windups left on descent | 0 | 0 |
| Brute unresolved | 0 | 0 |

Paired outcomes: both_clear=41, aggressive_only_clear=3, cautious_only_clear=6, neither_clear=0, aggressive_deeper=3, cautious_deeper=6, equal_depth=41.

Both policies use identical seeds, layouts, initial enemies and items. Depth 5 means completion.
These are descriptive results for the listed sample and map size, not a general balance claim.
HP lost includes armor mitigation and clamps a lethal hit to remaining HP; healing can make cumulative loss exceed maximum HP.
All-run damage and level averages include short defeated runs. Clear-only turns can compare different subsets of seeds.
Raw per-run data and paired completion counts are supplied to make these differences visible.

Source fingerprint (core + policy): `23d3d6a84397da0781bc877b4f1a7f91ab1a00b185d908707f58fd2ea4f6dd6e`.
