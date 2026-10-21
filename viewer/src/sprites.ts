import player from "../../game/assets/tiny-dungeon/Tiles/tile_0096.png";
import melee from "../../game/assets/tiny-dungeon/Tiles/tile_0121.png";
import archer from "../../game/assets/tiny-dungeon/Tiles/tile_0112.png";
import brute from "../../game/assets/tiny-dungeon/Tiles/tile_0110.png";
import potion from "../../game/assets/tiny-dungeon/Tiles/tile_0115.png";
import sword from "../../game/assets/tiny-dungeon/Tiles/tile_0104.png";
import armor from "../../game/assets/tiny-dungeon/Tiles/tile_0101.png";
import bow from "../../game/assets/anarogue/bow.svg";

// Same source files as Godot's dungeon_sprites.gd; no duplicated image assets.
export const sprites = {player, melee, archer, brute, potion, sword, armor, bow};
export function enemySprite(kind: string): string {
  return kind === "archer" ? archer : kind === "brute" ? brute : melee;
}
export function itemSprite(item: {type: string; weapon_kind?: string | null}): string {
  return item.type === "weapon" ? item.weapon_kind === "bow" ? bow : sword : item.type === "armor" ? armor : potion;
}
