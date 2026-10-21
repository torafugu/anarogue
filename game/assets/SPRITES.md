# AnaRogue sprite mapping

Tiny Dungeon 1.0 by Kenney is CC0. The original package and License.txt live in
`tiny-dungeon/` and are kept unchanged. `anarogue/bow.svg` is an original AnaRogue
addition, dedicated to CC0, drawn to match the pack's 16px palette.

| Role | Original image | Legacy symbol |
| --- | --- | --- |
| Player | tiny-dungeon/Tiles/tile_0096.png (knight) | @ |
| Melee | tiny-dungeon/Tiles/tile_0121.png (skeleton) | E |
| Archer | tiny-dungeon/Tiles/tile_0112.png (green hood), bow overlay | A |
| Brute | tiny-dungeon/Tiles/tile_0110.png (red monster) | O |
| Potion | tiny-dungeon/Tiles/tile_0115.png (red flask) | + |
| Melee weapon | tiny-dungeon/Tiles/tile_0104.png (sword) | W |
| Defense equipment | tiny-dungeon/Tiles/tile_0101.png (shield) | D |
| Bow | anarogue/bow.svg | B |

Godot maps these in `game/scripts/dungeon_sprites.gd`; browser maps them in
`viewer/src/sprites.ts`, importing the same original files. Update both maps
when replacing an image. To add art without modifying upstream originals, put
it under `anarogue/`. Sprites are static: no animation sheets or log changes
are required. Role colors remain as subtle background badges. Floors, walls,
stairs, arrows and Brute windup markers keep their existing rendering.
