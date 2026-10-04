# Run log schema v6

Schema: [`schemas/run-log-v6.schema.json`](../schemas/run-log-v6.schema.json).
V6 extends [v5](run-log-v5.md). Event `schema_version` and run-start
`simulation_version` are 6. Readers accept v1-v6; historical schemas, fixtures and
reference files retain their recorded contracts.

Player snapshots add required `weapon_kind` (`melee` / `bow`) and `attack_range`
(1 / 5). Empty equipment uses melee / 1. Gear and floor items add `weapon_kind`:
required melee / bow for weapons, null for armor and potions. `attack_bonus`
still records the raw equipment bonus. Effective `attack` equals base + bonus
for melee, or max(1, floor((base + bonus) / 2)) for bows; `defense` is unchanged.

Automatic decisions can use action type `ranged_attack`; the enemy snapshot is
the target and direction is zero. The usual in-range rule is `shoot_in_range`.
Growth decisions also select a ranged attack when already at the firing tile.
Every reachable growth candidate adds `attack_pos`; `steps` counts only moves
to that firing / melee position. See [simulation v6](simulation-spec-v6.md) for
changed retaliation estimates and the Cautious Archer mobility exception.

A valid Player shot emits `user_action` with `action: shoot`, `result: arrow_fired`,
`from`, `target`, `enemy_id` and optional `decision_id`. Invalid manual attempts
emit nothing and spend no turn. The following `enemy_hit` or
`enemy_defeated` battle result adds required `ranged` and `attacker_pos` fields.
Bump attacks use `ranged: false`; bow shots use true. Damage operands remain the
actual pre-hit attack / defense values, even when the kill levels Player up.

Replay uses battle impact events to update enemy HP / removal before drawing
the Player arrow. Shooting does not replace Archer `player_hit` events. Existing
inventory, equipment, XP observations and progression score contracts continue.

The stream validator checks weapon kind / range consistency, effective attack,
shooting radius and origin, bow-required ranged hits, damage arithmetic, and v5
progression invariants with the bow mobility exception. LOS is tested against
both engines with wall and corner scenarios.
