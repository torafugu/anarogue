# Run log v8

V8 extends [v7](run-log-v7.md); all previous versions remain readable. New logs
use `schema_version: 8` and `run_start.details.simulation_version: 8`.

`run_start.details` requires `goal_policy` (enemy_weight, item_weight,
stairs_weight, temperature) and `policy_seed`. This records effective preset or
custom settings, so a seed alone is not mistaken for the complete configuration.

A `weighted_goal` decision requires `observation.goal_selection`:

- `selected_kind`, `selected_id`: chosen enemy / item / stairs target.
- `target_retained`: true if memory was kept instead of drawing again.
- `draw`: integer lottery draw, or null on retention.
- `rng_before`, `rng_after`: policy RNG states; identical during retention.
- `candidates`: considered reachable wanted targets, each with kind, id, benefit,
  estimated_damage, risk, turns, revisit_penalty, utility, eligible and rejection.
  Rejection is empty, `disabled` or `estimated_lethal`.
- `distribution`: best eligible target of each enabled category, with integer
  `mass` and shared `total_mass`. On retained turns this is the **hypothetical
  redraw distribution**, not the probability of changing the retained target.

The decision action target remains a normal enemy/item/stairs snapshot. Bow
attacks use `ranged_attack`; a Brute approach wait uses `wait`; navigation uses
`move`. Urgent healing, evasion, adjacent combat and blocked-route fallback use
existing rule IDs without a lottery report.

Godot replay carries selection data into immutable frames; its status and the web
inspector show selected goal, retention, benefit/risk and redraw probabilities.
The JSON schema and stream validator check candidate utility, nonlethal eligibility,
probability denominators, distinct categories, interval selection, target identity
and the absence of RNG consumption on retention.
