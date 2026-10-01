# Run log schema v2

Version 2 keeps the v1 event envelope and event categories, and makes each floor
self-contained for replay. Its complete JSON Schema is
[`schemas/run-log-v2.schema.json`](../schemas/run-log-v2.schema.json).

## Change from v1

Every `floor_start.details` object now contains `map_rows` in addition to the v1
fields. It is an array of strings with one character per tile:

```json
{
  "map_size": { "width": 5, "height": 3 },
  "map_rows": [
    "#####",
    "#...#",
    "#####"
  ]
}
```

- `#` is a wall.
- `.` is a walkable floor tile.
- The number of rows must equal `map_size.height`.
- Every row length must equal `map_size.width`.

Actors are not embedded in the tile strings. Initial actor positions still come
from the other `floor_start` fields, and decision frames contain the current
player, enemy, and stairs snapshots.

This removes the replay client's dependency on the dungeon generator. A future
Godot or web client can render an old floor even after generation rules have
changed. Version 1 remains valid and supported by the web validator, but it cannot
render terrain without an external source.

## Godot replay frames

The Godot replay client builds visual frames from:

1. `floor_start` for terrain and initial actors;
2. `decision` for the complete pre-action observation; and
3. terminal `player_defeated` events for the final player state.

The current replay is intentionally decision-granular. Event-level interpolation,
projectile animation, and explicit enemy-movement events can be added later
without moving simulation rules back into Godot.
