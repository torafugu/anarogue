# AnaRogue User Manual

## Overview

SimpleRogue is a small turn-based roguelike made with Godot 4. You explore procedurally generated dungeon floors, avoid or defeat enemies, collect gold, and descend as deeply as you can.

Each action you take advances the game by one turn. Move carefully, watch your HP, and use the stairs to continue to the next depth.

## Starting the Game

1. Open the project folder in Godot 4.
2. Run the main scene: `res://scenes/Main.tscn`.
3. The game starts immediately on Depth 1.
4. Click `Start` on the right side of the screen to begin automatic movement and attacks.

## Goal

Your goal is to survive for as many dungeon depths as possible.

Find the green stairs on each floor and step onto them to descend. When you enter a new floor, your depth increases and you recover a small amount of HP.

## Controls

| Key | Action |
| --- | --- |
| Start button | Begin automatic movement and attacks |
| Arrow Up | Manually move up or attack upward |
| Arrow Down | Manually move down or attack downward |
| Arrow Left | Manually move left or attack left |
| Arrow Right | Manually move right or attack right |
| `.` | Manually wait one turn |
| `R` | Restart the game |

## Screen Guide

### Dungeon Symbols

| Symbol | Meaning |
| --- | --- |
| `@` | Player |
| `E` | Enemy |
| `>` | Stairs to the next floor |

### HUD

The right side of the screen shows:

- Current dungeon depth
- Current and maximum HP
- Gold collected
- Control reminders
- Recent message log

The message log reports important events, such as defeating enemies, taking damage, finding a new floor, or losing the run.

The game also writes a persistent JSON Lines log to `user://simple_rogue_battle_log.jsonl`. It records player actions, floor starts, combat results, restarts, and run-ending results.

## How Turns Work

SimpleRogue is turn-based. After you click `Start`, the player takes turns automatically.

After you move, attack, or wait, enemies get a turn. Enemies may move toward you if they can sense you nearby, or attack if they are next to you.

Walking into a wall does not advance the turn.

## Movement

After `Start` is clicked, the player automatically moves one tile at a time. You can still use the arrow keys to take manual turns.

You can walk on floor tiles, but not through walls. Rooms and corridors are generated randomly each run and each floor.

## Combat

After `Start` is clicked, the player automatically attacks adjacent enemies. You can still attack manually by moving toward an enemy while standing next to it. This is called a bump attack.

Combat rules:

- The player deals fixed attack damage.
- Enemies lose HP when hit.
- Defeated enemies disappear.
- Defeated enemies drop a small amount of gold.
- Enemies attack when they are adjacent to the player.
- Enemy strength increases with dungeon depth.

## Stairs and Depth

The green `>` symbol marks the stairs.

Step onto the stairs to:

- Advance to the next dungeon depth
- Generate a new floor
- Recover up to 4 HP, without going above maximum HP

Later depths are more dangerous because enemies have more HP and attack power.

## HP, Gold, and Game Over

Your HP is shown in the HUD.

If HP reaches 0, the run ends and the game displays a Game Over message. Press `R` to start a new run from Depth 1.

Gold is collected by defeating enemies. It is shown as a score-like progress value for the current run.

## Tips

- Do not rush into rooms if your HP is low.
- The automatic player prioritizes nearby enemies, then heads for the stairs after enemies are gone.
- Use manual movement if you want to override the automatic path for a turn.
- Restart with `R` whenever you want a fresh dungeon.

## Quick Reference

- Watch the player explore rooms and corridors automatically.
- The player fights enemies by moving into them.
- Watch your HP.
- Find `>` and step on it to descend.
- Survive as long as possible.
