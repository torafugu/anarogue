# Simulation specification v8

V8 keeps the v7 world, items, equipment, enemies, XP, combat, turn processing and
rewards described in [v7](simulation-spec-v7.md). It replaces discretionary
exploration selection with weighted **enemy / item / stairs** goals. A strategy
still supplies weapon preference, healing thresholds and emergency combat rules.

## Policy and selection

| Setting | Aggressive preset | Cautious preset | Valid values |
| --- | ---: | ---: | --- |
| Enemy weight | 4 | 1 | Integer 0–1000 |
| Item weight | 2 | 2 | Integer 0–1000 |
| Stairs weight | 1 | 4 | Integer 0–1000 |
| Temperature | 8 | 8 | Integer 1–100 |

At least one weight must be positive. Zero disables **discretionary** selection
of that category; healing, adjacent combat and blocked-route recovery can still
act when necessary. Weights express preferences, not fixed observed action ratios.

1. Efficient / urgent potion use takes precedence.
2. Cautious responds to a marked Brute strike, including a kill that interrupts it.
3. Adjacent enemies use existing combat / escape behavior.
4. Otherwise evaluate reachable enemies, wanted items and the stairs. Choose the
   highest-utility target of each enabled category, preserving stable spawn order
   on ties. The lottery contains at most three entries, so additional enemies do
   not increase the category's probability simply through their count.
5. Retain the selected target while eligible, present and reachable, until floor
   change or an absolute HP change of at least 4 from selection. Do not redraw on
   each movement step or consume randomness during retention. Emergency actions
   preserve memory; subsequent normal evaluation may invalidate it.
6. If no eligible lottery goal exists, retain the previous combat/navigation
   fallback. When the stairs are blocked, Cautious approaches a reachable enemy
   rather than waiting forever. Fallback is outside the discretionary lottery.

Enemy / item evaluation uses a 12-step shortest-route horizon, blocked by other
enemies and stairs except the destination. Unreachable / unwanted targets do not
enter evaluation. Weighted movement toward these targets cannot cross stairs.
Movement penalties for danger (Cautious) and repeated visits remain active. A
single reversal can be legitimate after an item pickup or changing enemy threat;
sustained alternating movement is checked in navigation regressions.

Cautious pursuing a Brute without a bow waits at distance two when the Brute can
close into an empty adjacent tile. This permits attacking after its slow approach
instead of repeatedly entering reach, dodging and re-entering without landing a
hit. Windup evasion still has precedence. Waiting consumes a normal enemy phase.

## Common utility

All scores use integers and are policy estimates, not probabilities of death.
For each candidate:

```
remaining_hp = hp - estimated_damage
risk = floor(estimated_damage * 20 / max(1, hp)) + max(0, 6 - remaining_hp) * 4
utility = benefit - risk - turns - revisit_penalty
eligible = remaining_hp > 0 and category_weight > 0
```

| Goal | Benefit | Time / damage estimate |
| --- | --- | --- |
| Enemy | `2 * XP + 2 + levels_gained * (8 + (4 - depth) * 6)` | Approach steps + attacks needed; existing v7 retaliation and other-enemy damage estimates |
| Potion | `2 * min(8, missing_hp) + 4 * (3 - carried_potions)` | Route length; sum current incoming damage along route |
| Armor | `8 * max(0, new_defense_bonus - old_bonus)` | Same route estimate |
| Weapon | `6 * max(0, new_effective_attack - current_attack) + 8` for preferred kind, otherwise no kind bonus | Includes bow half-attack calculation; same route estimate |
| Stairs | `8 + 2 * min(4, missing_hp) + 20` when leaving depth 4 | Time penalty capped at 8; damage / revisits summed across the full route |

The enemy +2 is a fixed expected-loot value, not a preview of the reward RNG.
Wanted equipment still obeys the existing weapon-kind preference and strict
upgrade rules; full potion inventory excludes additional potions. Level benefit
uses the actual XP threshold (`level * 8`) and accounts for multiple levels.
Revisit penalty is the sum of existing `max(0, visits - 2) * 8` route costs.

Damage uses current enemy positions, armor, attack range and line of sight. Enemy
movement, future item benefits and future floor threats are not fully simulated.
Evaluation uses the shortest route; movement may choose a longer weighted detour.
A nonlethal estimate therefore cannot guarantee survival. Stairs healing affects
benefit only; it does not permit a lethal approach. These limitations are visible
in the v8 comparison rather than treated as a balance guarantee.

## Portable probabilities

V8 approximates softmax without cross-engine floating point differences:

```
gap = max_utility - candidate_utility
bucket = min(8, floor(gap / temperature))
exp_table = [1000, 368, 135, 50, 18, 7, 2, 1, 1]
mass = category_weight * exp_table[bucket]
probability = mass / sum(masses)
```

This deliberately quantizes scores in temperature-sized buckets and retains a
small positive tail for every eligible enabled category. Higher temperature makes
utility differences matter less; preferences still apply. Log exact integer
numerators / denominator rather than rounded percentages. A uniform integer draw
in `[0, total_mass - 1]` selects cumulative intervals in enemy, item, stairs order.

Use Portable RNG v1 with `derive_seed(scenario_seed, "policy", 0)` and an empty
entity ID. The policy stream persists across floors, resets at run restart and is
independent of map, enemy, item, reward and metadata streams. Godot previews clone
its state and do not commit either target memory or randomness.

See [run log v8](run-log-v8.md), [reference logs v8](reference-logs-v8.md) and
[paired comparison v8](strategy-comparison-v8.md).
