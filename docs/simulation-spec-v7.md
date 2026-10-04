# Simulation specification v7

V7 extends [v6](simulation-spec-v6.md) with a third enemy kind, Brute, and a
Cautious response to telegraphed attacks. Player bows, weapon preferences,
progression weights and existing enemy behavior retain their v6 contracts.

## Brute (O)

| Property | Rule |
| --- | --- |
| HP | 14 + depth × 3 |
| Attack | 4 + depth |
| Defense | 0 |
| Kill reward | 5 XP, 2 score; deterministic gold 1–4 |
| Movement | One cardinal tile on even-numbered Player turns only |
| Detection / movement | Existing melee detection radius and legal movement rules |
| Attack | Wind up at an adjacent Player tile, then strike that fixed tile next enemy phase |

A Brute that has no prepared strike checks adjacency on every enemy phase,
including odd turns. If adjacent, it marks Player's tile without moving or dealing
damage. Next phase it clears the marker and strikes that tile. If Player moved,
the strike misses even if Player remains adjacent on another tile. A strike
consumes the phase; it cannot also move or prepare another strike. Killing Brute
before the enemy phase interrupts the prepared strike. Armor and minimum damage
apply as usual. There is no persistent damage zone or ranged heavy attack.

Each existing spawn consumes the same original melee / Archer kind draw, then
uses independent `enemy-kind` RNG derived from seed, depth and enemy ID to replace
that kind with Brute at probability 1/3. Enemy count, positions, IDs, room layouts,
items and reward streams are unaffected by this extra random draw. Brutes are not
guaranteed on every floor. Both policies encounter identical initial scenarios.

## Decisions and estimates

Healing remains first. Before shooting or gathering, Cautious checks whether its
current tile is marked by a Brute. It can stay and finish a kill when its next hit
kills the threatening Brute and other immediate incoming damage is survivable.
Otherwise it selects a legal adjacent unoccupied tile with minimum cost:
`100 * immediate_damage + danger + revisit_cost + Manhattan_distance_to_stairs`.
An immediately reachable staircase has cost -1. Direction order UP, DOWN, LEFT,
RIGHT breaks ties. If no legal dodge exists, normal combat continues. Finishing attacks use `interrupt_windup`; dodges use `evade_windup`; the enemy snapshot is its target. Aggressive keeps attacking.

Without an unavoidable marked strike, Cautious attacks an adjacent Brute using
`attack_adjacent_brute`, subject to its existing immediate-stairs escape rule.
Item detours and growth comparisons remain later priorities. This avoids treating
a slow Brute like a retreating Archer or blindly fleeing without a windup.

Immediate incoming damage from Brute is nonzero only on its marked adjacent tile.
Path danger is 45 on that tile, otherwise 12 adjacent / 4 two Manhattan tiles away.
This distinguishes preparing danger from damage that can land next phase.

Growth candidates grant 5 XP for Brute. Let N be projected attack turns and d the
Manhattan gap at `attack_pos`. Estimated adjacent enemy phases before the killing
attack are `C = max(0, N - 1 - 2 * max(0, d - 1))`. Estimated target retaliations
are `floor((C + ready) / 2)`, where ready=1 if Brute already marks `attack_pos`.
Use its full attack after armor. Approach and collateral estimates retain v6.
This is a static estimate, not exact prediction of movement timing or future dodges.

## Logs, replay and comparisons

New runs use [Schema v7](run-log-v7.md). Every enemy snapshot includes nullable
`windup_target`. Windup, missed strike and hit events show the transition.
Godot live / replay and the web map display O for Brute and a red outline on the
marked tile. Historical schemas, reference logs and fixtures v1–v6 stay unchanged.

Godot and Rust independently test movement cadence, preparation without damage,
fixed target, armor, evasion, interruption, blocked routes and growth estimates.
Six [reference runs](reference-logs-v7.md) compare full event streams and outcomes.
The [50-seed comparison](strategy-comparison-v7.md) is reproducible in CI.
