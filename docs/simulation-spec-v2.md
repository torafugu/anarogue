# Simulation specification v2

Version 2 extends [simulation specification v1](simulation-spec-v1.md) with three
rules that prevent empty or non-terminating floors. Unless overridden below, v1
remains normative.

## Enemy population

The existing 3-in-4 spawn check still applies to every intermediate room. If it
produces no enemies, the simulator makes one fallback spawn attempt in the last
room. The chosen tile must not contain the player, stairs, or another enemy. If
the random tile is occupied, the first free interior tile in row-major order is
used.

As a result, every playable floor has at least one enemy whenever its last room
contains a free interior tile. The standard map generator guarantees such a tile.

## Single-room floors

If the first and last room are the same, the initial player and stairs positions
would both be the room center. The stairs are instead moved to the walkable tile
with the greatest squared Euclidean distance from the player. Ties are resolved
in row-major scan order.

## Terminal depth

Depth 5 is the dungeon goal. When the player uses the stairs on depth 4:

1. the accepted action consumes one turn;
2. depth becomes 5;
3. the normal descent score and healing are applied;
4. `floor_descend` is logged with `to_depth: 5`; and
5. the run ends immediately with outcome `dungeon_cleared`.

No depth-5 floor is generated and enemies do not take a turn after the terminal
descent. Player death remains the `player_defeated` outcome; reaching a configured
turn cap remains `turn_limit` in batch summaries.

## Compatibility

These changes alter random-number consumption and fixed-seed results. Godot and
the Rust Simulation Core must implement the same v2 rules. The v1 reference logs
remain historical fixtures; current parity uses `examples/reference-v2`.
