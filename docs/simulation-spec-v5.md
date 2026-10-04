# Simulation specification v5

V5 extends [v4](simulation-spec-v4.md) with growth-aware exploration decisions.
Combat, leveling, equipment, floor generation and RNG streams are unchanged.
A level costs `level * 8` XP and gives +1 base attack, +2 max HP and up to 2 HP
recovery. Melee kills grant 3 XP; Archer kills grant 5 XP. XP is level-local.

## Priority and alternatives

Potion use and existing nearby-item collection remain first. Existing adjacent
combat / escape rules remain next: Aggressive attacks; Cautious fights pursuing
melee unless it can immediately descend, and retreats from an adjacent Archer.
Otherwise, compare a fight for growth with descending. If no unoccupied route
to the stairs exists, preserve the old blocked-route combat / pursuit fallback.

Both strategies evaluate each reachable enemy. Combat approaches use a stable
UP, DOWN, LEFT, RIGHT BFS through floor tiles. Other enemies and stairs block an
approach; only the destination enemy tile is permitted. The route limit includes
that destination: Aggressive 12 steps, Cautious 6. `steps` in a candidate is the
number of moves to become adjacent, so its maximum is 11 / 5 respectively.

The staircase distance is an unweighted shortest-route estimate through currently
unoccupied tiles. Actual staircase movement uses the existing weighted pathfinder
with danger and revisit penalties. The estimate may be shorter than the chosen
safe route. Stairs recover up to 4 HP; leaving Depth 4 completes the dungeon.

## Combat estimate

Use effective attack and enemy defense to estimate the attack count:
`attack_turns = ceil(enemy.hp / max(1, player.attack - enemy.defense))`.
Project the kill's XP through the same level thresholds as actual leveling.

Estimated damage is the sum of:

- Snapshot incoming damage after each approach move, excluding the enemy tile.
- `(attack_turns - 1)` retaliations from the target: melee attack, or Archer punch.
- Other enemies' snapshot incoming damage at the attacking tile on every attack,
  including the final killing attack's subsequent enemy phase.

Incoming damage uses effective defense and the minimum damage of 1. Archer
visibility uses the existing symmetric supercover LOS, including corner blocking.
Future level-up healing, future potion use and pickups are not credited for safety.
A candidate is rejected if estimated remaining HP is at most 2 (Aggressive) or 4
(Cautious). Cautious also rejects Archers, whose retreat makes the stationary
estimate unreliable, and kills that cannot yield an immediate level-up.

These are conservative preferences around a **static estimate**, not a complete
lookahead or a survival guarantee. Enemy movement, Archer retreats and congestion
can change the actual cost. Logs and viewer labels explicitly call damage an
estimate. A new log is required to observe the new decisions.

## Scores

These integer weights are an initial, inspectable policy, not probabilities or
expected game score. Let `remaining_floors = 4 - depth` and let `L` be the number
of levels projected from the kill.

| Term | Aggressive | Cautious |
| --- | ---: | ---: |
| XP reward multiplier | 4 | 2 |
| Per approach move penalty | 1 | 2 |
| Per estimated HP lost penalty | 2 | 3 |
| Stairs base value | 8 | 16 |
| HP reserve required after estimated fight | >2 | >4 |

`combat_score = xp_gain * XP_multiplier + L * (8 + remaining_floors * 6)
- steps * move_penalty - attack_turns - estimated_damage * damage_penalty
- revisit_penalty`.

`revisit_penalty` sums the existing tile revisit costs along the approach, without
including the destination enemy tile. This discourages chasing through the same
positions repeatedly while leaving necessary staircase backtracking possible.

`stairs_score = stairs_base + stairs_healing * 2 - min(stairs_steps, 8)
+ (20 if depth == 4 else 0)`.

Choose the highest eligible combat score only if it **strictly exceeds** the
stairs score; ties favor stairs. Enemy order breaks combat ties. Keep a selected
growth target while it is eligible and still beats stairs, even if another enemy
now scores higher. This prevents switching targets as enemies move. Item use and
collection preserve this target; descending / restarting clears it. If it dies,
is unreachable or becomes unfavorable, re-evaluate alternatives. Existing legacy
pursuit memory still handles the no-stairs-route fallback.

Rules are `hunt_for_growth` and `descend_for_progress`. An example on Depth 1:
Cautious, Lv 1, XP 5, HP 18, attack 5, an enemy two tiles away with HP 5 / attack 1.
That melee kill grants 3 XP and a level, with one approach move, one attack and
estimated damage 1: combat score 26. Distant stairs score 8, so fight. At XP 0,
the same fight yields no level and is rejected. At Depth 4, the future growth
bonus is smaller and the completion bonus favors descending.

## Logs, UI and verification

New runs use [Schema v5](run-log-v5.md), with level/XP observations and the scored
alternatives. Godot replay shows the selected comparison; the web event details
show all candidates and rejection reasons. The web run comparison includes final
level and XP. Historical schemas, logs and fixtures v1-v4 remain intact.

Godot and Rust have threshold, defense, safety, mobility, route and revisit tests,
plus full event parity against [reference v5](reference-logs-v5.md). The existing
seed-27 and seed-301 navigation regressions still check that pursuit does not
stall in a repeated movement cycle.
