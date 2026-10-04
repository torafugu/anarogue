# Simulation specification v4

V4 extends [v3](simulation-spec-v3.md) with weapons, armor, explicit base stats and
attack-minus-defense damage. Portable RNG v1, floor generation, enemy generation,
turn ordering, pursuit memory and Archer wall/corner visibility remain unchanged.

## Player abilities and equipment

A run starts with base attack 5, base defense 0, no weapon and no armor. Equipment
has an ID, type (`weapon` or `armor`), attack bonus and defense bonus. It has no
position while equipped. There is one slot per type and no spare equipment bag.
The existing inventory holds up to three health potions independently of gear.

- Effective attack = base attack + equipped weapon attack bonus.
- Effective defense = base defense + equipped armor defense bonus.
- Level gains increase base attack by 1 and preserve equipment modifiers. Existing
  HP/XP progression is unchanged; base defense does not grow automatically.
- Equipment persists across floors, but a new run clears both slots.

Each playable floor attempts to place one weapon in the starting room and one
armor in the second room (or the starting room if it is the only room). Candidates
exclude the player, stairs, enemies and other items. The independent `equipment`
RNG stream preserves potion placement and all existing terrain/enemy/reward streams.
Weapon attack bonus = depth + 1; armor defense bonus = floor((depth + 1) / 2).
Unused modifiers are 0. These simple values are the initial equipment balance.

## Pickup, automatic equipment and policy

Successful movement first logs the move, then processes eligible items at the
new position, before the enemy phase. A potion pickup increments inventory. Gear
is eligible only if its relevant modifier is strictly greater than the equipped
modifier (0 for an empty slot). Eligible gear is immediately equipped, the previous
gear is dropped on the same tile, and `item_equipped` records the resulting floor
items and equipment. Pickup and equipment cost no extra turn. Equal/weaker gear
remains on the floor, preventing repeated swaps. Multiple eligible items at a tile
are processed in deterministic item order.

Emergency healing still has priority. Adjacent combat also takes priority over
an item detour. Aggressive collects eligible items within 8 steps; Cautious within
4 fully safe steps and only when its current tile is safe. The nearest eligible
item wins, with floor-item order breaking ties. Gear detours use
`collect_nearby_equipment` / `cautious_collect_equipment`; potion rules retain their
IDs. A full potion inventory does not prevent collecting equipment.

## Combat

All hits use `damage = max(1, attack_power - defense_power)`. Player attacks use
effective attack against enemy defense. Enemy melee, arrows and cornered Archer
punches use their existing attack power against effective player defense. Current
enemy spawns have defense 0; the model supports nonzero enemy defense. The incoming
hit estimate for emergency healing also subtracts armor, with a minimum of 1 per
hit. Cautious's existing danger weights remain positional threat heuristics.

Battle events record the actual pre-hit attack/defense operands and computed
damage. A kill that levels the player records the attack used before that level
gain. HP is still clamped at 0 for player damage; logged damage is the calculated
hit, even if it exceeds remaining HP. Archer line of sight gates actual shots and
incoming-hit prediction as in the final v3 implementation.

## Logs and validation

New runs emit [Schema v4](run-log-v4.md). [Reference v4](reference-logs-v4.md) covers
six full runs. Historical v1-v3 schemas, logs and fixtures remain available and
readable. Old JSONL files replay their recorded behavior; generate a new log to
see equipment. The Godot replay and web viewer show effective stats, their base
and modifier components, floor gear and equipment changes.
