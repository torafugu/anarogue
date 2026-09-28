# AnaRogue

A tiny Godot 4 roguelike starter.

## Play

Open this folder in Godot 4 and run the main scene.

Controls:

- Choose `Aggressive` or `Cautious`, then click `Start selected strategy`
- Click `Compare both — same seed` to run both strategies on matching floors
- Arrow keys: manually move or attack
- `.`: manually wait
- `R`: restart

## Current Features

- Procedural room-and-corridor dungeon generation
- Automatic player movement and bump attacks
- Two automatic strategies:
  - **Aggressive** — hunts every enemy, then seeks the stairs
  - **Cautious** — takes a danger-weighted route to the stairs and only fights
    when its path is blocked
- Same-seed comparison mode with deterministic floor layouts, enemy spawns, and
  per-enemy rewards
- Turn-based player and enemy actions
- Two enemy types:
  - **Melee** — charges and attacks up close
  - **Archer** — keeps distance and fires arrows; retreats when cornered
- Stairs to deeper floors; enemies scale with depth
- HP, depth, gold, **score**, and message log HUD
- Score system: 1 point per melee kill, 2 points per archer kill, and 3 points per depth descended; no points per turn. Runs start at 0 points.
- JSON Lines action and battle log at `user://simple_rogue_battle_log.jsonl`
- Versioned run-log schema with automatic-player observations, selected rules,
  actions, and human-readable decision reasons

See [Run log schema v1](docs/run-log-v1.md) for the event contract and
[`examples/sample-run-v1.jsonl`](examples/sample-run-v1.jsonl) for sample data.

## Run viewer

The Vite + TypeScript viewer in [`viewer/`](viewer/) turns a run into a summary,
HP chart, route map, searchable event stream, and decision inspector. Runs with
the same scenario ID are grouped into an Aggressive vs. Cautious comparison.

```bash
cd viewer
npm install
npm run dev
```
