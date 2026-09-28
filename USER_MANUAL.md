# AnaRogue User Manual

## Overview

SimpleRogue is a small turn-based roguelike made with Godot 4. You explore procedurally generated dungeon floors, avoid or defeat enemies, collect gold, and descend as deeply as you can.

Each action you take advances the game by one turn. Move carefully, watch your HP, and use the stairs to continue to the next depth.

## Starting the Game

1. Open the project folder in Godot 4.
2. Run the main scene: `res://scenes/Main.tscn`.
3. The game starts immediately on Depth 1.
4. Choose an automatic strategy on the right side of the screen.
5. Click `Start selected strategy`, or run both strategies with
   `Compare both — same seed`.

## Goal

Your goal is to survive for as many dungeon depths as possible.

Find the green stairs on each floor and step onto them to descend. When you enter a new floor, your depth increases and you recover a small amount of HP.

## Controls

| Key | Action |
| --- | --- |
| Strategy menu | Choose Aggressive or Cautious behavior |
| Start selected strategy | Begin one automatic run |
| Compare both — same seed | Run Aggressive, then Cautious, on matching floors |
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
| `E` | Melee enemy |
| `A` | Archer enemy |
| `>` | Stairs to the next floor |

### HUD

The right side of the screen shows:

- Current dungeon depth
- Current and maximum HP
- Gold collected
- Control reminders
- Recent message log

The message log reports important events, such as defeating enemies, taking damage, finding a new floor, or losing the run.

The game also writes a persistent JSON Lines log to `user://anarogue.jsonl`. It records player actions, floor starts, combat results, restarts, and run-ending results.

## How Turns Work

SimpleRogue is turn-based. After you click `Start`, the player takes turns automatically.

After you move, attack, or wait, enemies get a turn. Enemies may move toward you if they can sense you nearby, or attack if they are next to you.

### Automatic Strategies

**Aggressive** attacks adjacent enemies, hunts the nearest remaining enemy, and
only heads for the stairs after clearing the floor.

**Cautious** heads for the stairs immediately. Its pathfinder assigns extra cost
to tiles threatened by melee enemies and archers, so it prefers safer detours.
It avoids combat before contact, but attacks a melee enemy once caught because
both move at the same speed and retreating cannot open a gap. If the stairs are
one step away, it escapes instead. It also attacks when no route to the stairs
is open and an enemy blocks it.

Comparison mode gives both strategies the same scenario seed. Floor generation,
enemy placement, and each enemy's gold reward are derived separately from that
seed, so different decisions do not change the scenario itself.

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
- Enemy strength increases with dungeon depth.

### Enemy Types

**Melee (`E`)** — Charges toward you and attacks when adjacent. Hits hard up close.

**Archer (`A`)** — Stays at range and fires arrows. If you get close, it tries to retreat to a safer distance before shooting again. If cornered, it punches for low damage. Archers have less HP than melee enemies, so closing the gap quickly is a viable strategy.

## Stairs and Depth

The green stair-step icon inside an outlined square marks the stairs.

Step onto the stairs to:

- Advance to the next dungeon depth
- Earn 3 score points
- Generate a new floor
- Recover up to 4 HP, without going above maximum HP

Later depths are more dangerous because enemies have more HP and attack power.

## HP, Gold, and Game Over

Your HP is shown in the HUD.

If HP reaches 0, the run ends and the game displays a Game Over message. Press `R` to start a new run from Depth 1.

Gold is collected by defeating enemies. It is shown as a score-like progress value for the current run.

Score starts at 0. Defeating a melee enemy earns 1 point, defeating an archer earns 2 points, and descending to the next depth earns 3 points. Taking turns does not award points.

## Tips

- Do not rush into rooms if your HP is low.
- Aggressive is useful for collecting kills and gold; Cautious is useful for
  testing survival and depth-first behavior.
- Use manual movement if you want to override the automatic path for a turn.
- Restart with `R` whenever you want a fresh dungeon.

## Quick Reference

- Watch the player explore rooms and corridors automatically.
- The player fights enemies by moving into them.
- Watch your HP.
- Find `>` and step on it to descend.
- Survive as long as possible.
