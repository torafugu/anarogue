# Strategy comparison: simulation v8

Presets (enemy / item / stairs): Aggressive 4 / 2 / 1, Cautious 1 / 2 / 4; temperature 8.

Seeds: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50. Map: 44×28. Budget: 500 turns.

| Metric | Aggressive | Cautious |
| --- | ---: | ---: |
| Clears / runs | 43/50 | 40/50 |
| Clear rate | 86% | 80% |
| Defeats | 7 | 10 |
| Turn limits | 0 | 0 |
| Mean final depth | 4.68 | 4.56 |
| Mean turns (clears only) | 189.56 | 167.35 |
| Mean HP lost (all runs) | 37.06 | 24.58 |
| Mean final level | 2.10 | 1.70 |
| Mean score | 17.48 | 14.76 |
| Mean Brute kills | 1.32 | 0.60 |
| Mean bow shots | 0 | 4.24 |
| Brute windups | 123 | 89 |
| Brute hits | 87 | 0 |
| Brute misses | 0 | 75 |
| Brute interrupted by kill | 36 | 14 |
| Brute windups left on descent | 0 | 0 |
| Brute unresolved | 0 | 0 |

Paired outcomes: both_clear=37, aggressive_only_clear=6, cautious_only_clear=3, neither_clear=4, aggressive_deeper=6, cautious_deeper=3, equal_depth=41.

Both policies use identical seeds, layouts, initial enemies and items. Depth 5 means completion.
These are descriptive results for the listed sample and map size, not a general balance claim.
HP lost includes armor mitigation and clamps a lethal hit to remaining HP; healing can make cumulative loss exceed maximum HP.
All-run damage and level averages include short defeated runs. Clear-only turns can compare different subsets of seeds.
Raw per-run data and paired completion counts are supplied to make these differences visible.

Source fingerprint (core + policy): `421a6d80bd6bb8e2f8b54e2836413d6f6ace21232ec21e2bbf0fe7588a480d9d`.
