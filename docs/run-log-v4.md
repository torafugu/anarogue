# Run log schema v4

Schema: [`schemas/run-log-v4.schema.json`](../schemas/run-log-v4.schema.json).
V4 retains the v3 event envelope with `schema_version: 4` and run-start
`simulation_version: 4`. Readers continue to support v1-v3.

Every player snapshot includes `base_attack`, `base_defense`, `attack_bonus`,
`defense_bonus`, effective `attack`/`defense`, and `equipment`. Equipment has
`weapon` and `armor` slots, each either null or `{id, type, attack_bonus,
defense_bonus}`. Equipped gear has no floor position. Potion inventory remains
`{health_potion}`. Enemy snapshots add `defense` (currently 0 for spawned enemies).

Floor item snapshots have `{id, type, pos, attack_bonus, defense_bonus}`. Type is
`health_potion`, `weapon` or `armor`; potions have zero modifiers. Floor-start and
decision observations include all remaining gear and potions.

`item_result` adds an `item_equipped` result containing the picked-up `item`,
nullable `previous_equipment`, resulting `equipment`, complete remaining floor
`items`, potion `inventory` and `decision_id`. The previous item, if present, is
on the player's tile in `items`. This event updates replay state immediately.
Potion `item_picked_up` and `item_used` retain their v3 semantics.

Hit/defeat events that carry `damage` also carry `attack_power` and `defense_power`.
These are the actual operands before the hit/level gain:
`damage = max(1, attack_power - defense_power)`. Player `attack` and `defense` are
always base + modifier. The validator checks these equations, equipment slots,
equipment/floor consistency, inventory and potion-heal invariants.

The log schema is versioned because v3's item type and player shape cannot express
gear. V3 files are preserved unchanged; new simulations produce v4.
