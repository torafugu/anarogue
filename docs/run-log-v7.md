# Run log schema v7

Schema: [`schemas/run-log-v7.schema.json`](../schemas/run-log-v7.schema.json).
V7 extends [v6](run-log-v6.md); event schema and run-start simulation version are 7.
Readers retain v1–v6 support and historical files have not been rewritten.

`enemy_snapshot.type` and battle `enemy_type` additionally accept `brute`. Every
enemy snapshot requires `windup_target`, either a vector tile for a prepared Brute
or null; melee and Archer must use null. A marked tile must be cardinal-adjacent
to its Brute. Decision action targets use the same snapshots.

Two new `battle_result` variants:

- `enemy_windup`: enemy ID, type=brute, enemy position, `target` and matching
  `windup_target`; both target fields are Player's tile when preparation starts.
- `enemy_strike_missed`: the same enemy / old target fields, `windup_target: null`.

Brute `player_hit` uses normal attack / defense / HP operands and adds
`windup_target: null`. It is a melee hit. Killing a prepared Brute uses the normal
`enemy_defeated` contract; the next enemy phase cannot strike. The stream validator
requires preparation on the previous turn before a hit or miss, checks the fixed
target, and clears pending preparation on death or floor transition.

Cautious rules add `evade_windup` (move; target Brute snapshot),
`interrupt_windup` (finishing attack against the marked Brute) and
`attack_adjacent_brute` (attack). Growth rewards for Brute are 5 XP. Existing v6
weapon, range, score arithmetic and damage invariants remain applicable.

Replay makes windup and resolution frames, preserving historical marker state.
Brute bow impacts retain the Player arrow and immediate enemy HP / removal.
