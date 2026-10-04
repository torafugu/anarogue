# Run log schema v5

Schema: [`schemas/run-log-v5.schema.json`](../schemas/run-log-v5.schema.json).
V5 retains the v4 player, item, equipment and battle event contracts. Event
`schema_version` and run-start `simulation_version` are 5. Readers support v1-v5;
historical schemas and reference files have not been rewritten.

Every decision observation additionally requires `level`, `xp` and
`xp_to_next_level = level * 8 - xp`, matching that event's player snapshot.
Growth-versus-descent decisions include `observation.progression`:

- `stairs_steps`: shortest unoccupied route length, not the eventual safe route.
- `stairs_healing`: up to 4 HP available on descent.
- `stairs_score`: policy value of descending.
- `candidates`: enemy order, with one evaluation per enemy.
- `selected`: `combat` or `stairs`.
- `selected_enemy_id`: chosen enemy ID, or null for stairs.
- `target_retained`: whether the current viable growth target was kept.

A reachable candidate has `enemy_id`, `steps` (approach moves, excluding the
attack), `attack_turns`, `xp_gain`, `levels_gained`, `estimated_damage`,
`revisit_penalty`, `score`, `eligible` and `rejection`. An enemy beyond the bounded
route search has only `enemy_id`, `eligible: false` and `rejection: out_of_reach`.
This includes walls, other enemies and stairs blocking its route.

Other rejection values: `hp_reserve`, `mobile_target` (Cautious Archer chase),
`no_level_up` (Cautious cannot level from this kill), or an empty string for an
eligible candidate. Eligible does not imply selected: its score must beat stairs,
and a viable existing target may be retained over a higher-scoring alternative.
See [simulation v5](simulation-spec-v5.md) for formulas and limitations.

The validator checks XP observations, projected levels and attack count, score
arithmetic, safety rejection and selected-action consistency. V4's equipment and
damage invariants also apply to v5. Potion / adjacent-combat decisions need not
contain a progression comparison because they take precedence.

The Rust CLI summary adds `final_level` and `final_xp`, independently of JSONL.
