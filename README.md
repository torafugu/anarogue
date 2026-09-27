# AnaRogue

A tiny Godot 4 roguelike starter.

## Play

Open this folder in Godot 4 and run the main scene.

Controls:

- Click `Start` on the right side to begin automatic movement and attacks
- Arrow keys: manually move or attack
- `.`: manually wait
- `R`: restart

## Current Features

- Procedural room-and-corridor dungeon generation
- Automatic player movement and bump attacks
- Turn-based player and enemy actions
- Two enemy types:
  - **Melee** — charges and attacks up close
  - **Archer** — keeps distance and fires arrows; retreats when cornered
- Stairs to deeper floors; enemies scale with depth
- HP, depth, gold, **score**, and message log HUD
- Score system: 1 point per turn, 2 points per kill
- JSON Lines action and battle log at `user://simple_rogue_battle_log.jsonl`
- Versioned run-log schema with automatic-player observations, selected rules,
  actions, and human-readable decision reasons

See [Run log schema v1](docs/run-log-v1.md) for the event contract and
[`examples/sample-run-v1.jsonl`](examples/sample-run-v1.jsonl) for sample data.
