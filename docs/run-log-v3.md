# Run log schema v3

The complete event contract is
[`schemas/run-log-v3.schema.json`](../schemas/run-log-v3.schema.json).
V3 retains v2 terrain and combat events and adds:

- `run_start.details.simulation_version: 3` to distinguish simulation rules.
- `player_state.inventory: { health_potion: 0..3 }` on every event.
- `floor_start.details.item_seed` and `items`, each item carrying `id`, `type`
  (`health_potion`) and `pos`.
- Decision observations include current `items` and `inventory`.
- Optional `current_tile_visits` and `selected_step_revisit_cost` describe navigation
  memory and the selected move's repeat penalty. Older v3 logs remain valid.
- Decision targets can be a floor item or
  `{ kind: "inventory_item", type: "health_potion" }`.
- `use_item` is a decision action and a `user_action` with result `item_used`.
- `item_result` records `item_picked_up` (the floor item and resulting inventory)
  or `item_used` (`item_type`, `hp_before`, `hp_after`, actual `healed`, inventory).
  These results include `decision_id`; it is empty for manual pickup/use.

## Ordering

Pickup: `decision` -> accepted move -> `item_picked_up` -> enemy phase.
Use: `decision` -> `user_action(use_item)` -> `item_used` -> enemy phase.
A pickup shares the movement turn; use advances one turn. Item-result snapshots
are taken after inventory/healing changes and before enemy attacks. The turn
budget includes use actions.

Godot replay inserts item-result frames, removes picked-up floor items immediately
and shows inventory and actual recovery. Web logs show resource totals, inventory,
item events and remaining floor potions at the selected event. Old logs default to
empty item state and retain their original schema validation. Same-seed comparisons
are grouped only within the same simulation version.
