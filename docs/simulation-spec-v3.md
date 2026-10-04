# Simulation specification v3

V3 extends [v2](simulation-spec-v2.md) with floor items, persistent inventory and
health-potion actions. All other v2 rules remain in force. Rust and the legacy
Godot live simulator implement the same rules; replay clients use recorded state.

## Floor items and inventory

- Item definition: `health_potion`, healing power 8 HP.
- A new run starts with `{ "health_potion": 0 }`. Capacity is 3 potions.
- Inventory persists between floors and clears on restart.
- Each of the first three rooms gets one potion if it contains an eligible tile.
  Enumerate interior tiles in row-major order, excluding the initial player,
  stairs and enemies, then draw one candidate index with the portable PRNG.
- Use the independent seed `derive_seed(scenario_seed, "items", depth)`. Terrain,
  enemy spawn and per-enemy reward streams are unchanged from v2.
- IDs are `item-<depth>-<room index + 1>`. No drops or item respawns are added.
- Entering an item tile automatically transfers its potion into inventory before
  the enemy phase, with no additional turn. A full inventory leaves it on the
  floor; re-enter the tile after making room to collect it.
- Uncollected items disappear on descent. Enemies can walk over items and do not
  collect or destroy them.

## Use action

Using one potion consumes one turn, decrements inventory and heals
`min(8, max_hp - hp)` before the normal enemy phase. The player does not move.
Full HP, empty inventory and an ended run reject use without spending a turn,
changing inventory or executing enemies. In the live check, `H` uses a potion.

## Automatic item rules

Both strategies first consider healing. Use a potion when HP is below maximum,
one is available, and any of these conditions holds:

1. Missing HP is at least 8 (the entire potion can be used).
2. HP is at most one third of maximum for Aggressive, or one half for Cautious.
3. HP is at most estimated immediate incoming damage.

The estimate sums adjacent melee attacks, 1 damage for archers within squared
range 2, and archer attack within squared range 49. It is a conservative heuristic:
archer retreat can remove its immediate attack, and healing does not guarantee
survival. Integer multiplication is used for fraction comparisons.

If healing was not selected, consider gathering before the original strategy:

- Do not gather at capacity or with an orthogonally adjacent enemy.
- Aggressive: gather a reachable potion within 8 steps.
- Cautious: gather within 4 steps, only when both the current tile and every tile
  on the route have zero existing `danger_cost`.
- Item routes use BFS, neighbor order up/down/left/right, blocking walls, enemies
  (including the destination) and stairs. These detours cannot descend.
- Pick the shortest eligible route; ties use item insertion order.
- Re-evaluate after every action. If no item rule applies, use the original
  Aggressive/Cautious combat and stair rules.

Items are currently fully observable, like the existing floor-level enemies and
stairs; fog of war is not introduced. Danger retains v2's radius-based model.
Strategy IDs remain `aggressive_v1` and `cautious_v1`; the ruleset change is
identified separately by `run_start.details.simulation_version: 3`.

## Movement-cycle recovery

Each floor tracks successful player arrivals at each tile, counting the initial
spawn as one visit. Attacks, waits, rejected moves and potion use do not add
visits. A new floor or restart clears the history.

Pathfinding adds `8 * max(0, visits - 2)` to the cost of entering a tile. The first
arrival and one return are free. Cautious adds this to its existing danger cost;
Aggressive keeps its normal BFS until any tile has been visited three times, then
uses weighted shortest paths with the same revisit cost and no danger weighting.
This is a soft penalty: mandatory backtracking remains possible. Item detours
retain their existing bounded BFS rules.

This corrects a pursuit cycle reproduced with Cautious, seed 27, 44x28: the player
alternated between (13,15) and (14,15) while a melee enemy mirrored the movement
three tiles below. Recomputing a route against each new enemy position flipped
the chosen direction. In the original movement-correction baseline, the maximum alternating run was
6 decisions and the run advanced until defeat at turn 134, rather than oscillating
to the 500-turn limit. With wall-aware Archer vision, the current baseline reaches
depth 3 and ends at turn 209. This fixes navigation; it does not guarantee survival.

## Logs and compatibility

New simulations emit [Schema v3](run-log-v3.md). V1/v2 schemas and reference logs
remain historical artifacts and are supported by the viewers. The current
regression baseline is [reference v3](reference-logs-v3.md).

V3 also fixes the Godot defeat-event damage field: record the attack used for the
hit before awarding XP, rather than the attack after a possible level-up. This
changes logging only, not the damage applied.

### Aggressive pursuit target

Aggressive chooses the nearest reachable enemy and remembers its ID when a pursuit
move is executed. A change in which enemy is geometrically closest does not change
the target. Defeated or unreachable targets are replaced, and a new floor resets
the ID. Adjacent attacks, potion collection and healing retain priority and do not
erase the remembered target. Equal-distance candidates retain spawn order.
The existing `hunt_nearest_enemy` rule ID now describes initial selection plus
continued pursuit; the action target and reason expose the current choice.

The 64x40, seed-301 regression previously alternated between stationary archers
and produced a ten-decision two-tile cycle despite revisit costs. Remembering the
target removes those reversals in this case. This is a navigation correction,
not a guarantee that Aggressive survives combat.

### Archer line of sight

Archer attacks and pursuit require a clear straight ray between tile centers.
The integer grid traversal checks every tile crossed by the ray; at an exact
corner crossing, both adjoining side tiles must be floors. Walls and map bounds
block vision. Floor items, stairs and other actors do not block vision.
The rule is symmetric when the ray is reversed. Detection and bow ranges remain
squared distances 80 and 49, and the existing close-combat/retreat rule remains
squared distance 2; blocked corners also prevent close combat through a wall.
An Archer without a clear ray takes no action, matching the existing unseen-enemy
behavior. Melee enemies retain their existing distance-based detection.

Archer danger costs and the next-turn incoming-damage estimate use the same ray
check, so a concealed Archer does not trigger retreat or emergency potion use.
Wall-aware danger changes routes and outcomes; regenerate logs to replay the new
rules. Historical v1/v2 reference logs remain unchanged.
