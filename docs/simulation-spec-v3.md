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

## Logs and compatibility

New simulations emit [Schema v3](run-log-v3.md). V1/v2 schemas and reference logs
remain historical artifacts and are supported by the viewers. The current
regression baseline is [reference v3](reference-logs-v3.md).

V3 also fixes the Godot defeat-event damage field: record the attack used for the
hit before awarding XP, rather than the attack after a possible level-up. This
changes logging only, not the damage applied.
