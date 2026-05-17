# SimpleRogue User Manual

## Overview

SimpleRogue is a small turn-based roguelike made with Godot 4. You explore procedurally generated dungeon floors, avoid or defeat enemies, collect gold, and descend as deeply as you can.

Each action you take advances the game by one turn. Move carefully, watch your HP, and use the stairs to continue to the next depth.

## Starting the Game

1. Open the project folder in Godot 4.
2. Run the main scene: `res://scenes/Main.tscn`.
3. The game starts immediately on Depth 1.

## Goal

Your goal is to survive for as many dungeon depths as possible.

Find the green stairs on each floor and step onto them to descend. When you enter a new floor, your depth increases and you recover a small amount of HP.

## Controls

| Key | Action |
| --- | --- |
| Arrow Up | Move up or attack upward |
| Arrow Down | Move down or attack downward |
| Arrow Left | Move left or attack left |
| Arrow Right | Move right or attack right |
| `.` | Wait one turn |
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

SimpleRogue is turn-based.

After you move, attack, or wait, enemies get a turn. Enemies may move toward you if they can sense you nearby, or attack if they are next to you.

Walking into a wall does not advance the turn.

## Movement

Use the arrow keys to move one tile at a time.

You can walk on floor tiles, but not through walls. Rooms and corridors are generated randomly each run and each floor.

## Combat

To attack an enemy, move toward the enemy while standing next to it. This is called a bump attack.

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
- Use corridors to fight enemies one at a time.
- Waiting with `.` can let enemies approach when you want to hold position.
- Head for the stairs when survival matters more than gold.
- Restart with `R` whenever you want a fresh dungeon.

## Quick Reference

- Explore rooms and corridors.
- Fight enemies by moving into them.
- Watch your HP.
- Find `>` and step on it to descend.
- Survive as long as possible.
