# Player DSL v1

Home → Run has an optional **Player DSL** editor and **Validate DSL** button.
An empty editor uses the existing strategy unchanged. Only declared settings
are overridden. Rules are evaluated in source order BEFORE default healing,
Brute avoidance, adjacent combat and weighted goal selection. If no rule is
executable, all existing default behavior remains available. `fallback explore`
is optional and explicitly names that same fallback.

Use Validate DSL to check a program without generating a Run. Run and AutoRun
also validate before queue acceptance; syntax/type errors do not create a job
or write any Run to SQLite. Errors name the line and column. The interpreter
does not execute Python, JavaScript, shell commands or arbitrary Rust.

```text
policy {
  treasure_weight = 5
}

rule "Recover" {
  when self.hp_percent <= 35 and self.potions > 0
  do use_potion
}

rule "Counter Archer" {
  target nearest enemy where type == archer and shootable
  when self.weapon == bow
  do shoot target
}
```

## Settings

| Setting | Range | Inherits when omitted |
| --- | --- | --- |
| enemy_weight | integer 0..1000 | Strategy / Run form Enemy weight |
| treasure_weight | integer 0..1000 | Strategy / Run form Treasure weight |
| stairs_weight | integer 0..1000 | Strategy / Run form Stairs weight |
| temperature | integer 1..100 | Default policy temperature |

`treasure_weight` maps to the engine/log field `item_weight`. Zero is an explicit
override, not an omitted value. At least one effective goal weight must remain
positive, even if the program contains an unconditional rule. Map settings and
max turns remain controlled by the Run form. AutoRun applies the same source
to every combination; a fixed DSL weight overrides the corresponding sweep
value, so avoid sweeping that weight if duplicate effective policies are unwanted.

## Rules and targets

```text
rule "Rule name" {
  target nearest enemy where type == archer and visible
  when self.hp_percent > 50
  do move_toward target
}
```

Each rule has an optional target declaration, optional `when`, and exactly one
`do` in that order. Rule names must be nonempty quoted strings and unique.
Targets are `nearest enemy`, `nearest item`, or `nearest stairs`. `where` filters
the target list BEFORE choosing its nearest member. Distance is Euclidean;
equal-distance enemies/items are ordered by ID for reproducibility. `when` is
evaluated against that selected target. No matching target, a false condition,
or an unavailable action skips to the next rule without consuming a Turn.

## Conditions

| Field | Meaning |
| --- | --- |
| self.hp / self.max_hp | Current / maximum HP |
| self.hp_percent | Current HP as a percentage from 0 to 100 |
| self.potions | Number of carried health potions |
| self.attack | Effective attack, including the Bow damage reduction |
| self.weapon | `bow` or `melee` |
| target.hp / hp | Enemy HP; 0 for targets without HP |
| target.distance / distance | Straight-line distance to target |
| target.type / type | `melee`, `archer`, `brute`, `health_potion`, `weapon`, `armor`, `stairs` |
| target.visible / visible | Line of sight from Player, without a separate vision radius |
| target.shootable / shootable | An enemy target, Bow equipped, within range, clear line of sight |

Target fields require a target declaration. Bare target field names and their
`target.` forms are equivalent. Literals are numbers, `true` / `false`, and the
unquoted enum words above. Operators are `==`, `!=`, `<`, `<=`, `>`, `>=`, `not`,
`and`, `or` and parentheses. Precedence is parentheses/not, comparisons, and, or;
write `not (target.distance < 5)` for a negated comparison. Numeric comparisons
require numbers; weapon/type comparisons require the appropriate enum values.
There are no variables, loops, user functions or memory between Turns in v1.

## Actions

| Action | Availability and effect |
| --- | --- |
| shoot target | Enemy target; Bow equipped and target shootable |
| attack target | Enemy target in a cardinally adjacent tile; attacks using current effective attack |
| move_toward target | Take one step along the existing pathfinder; an occupied enemy destination results in a melee attack |
| use_potion | A carried potion and missing HP; consumes one potion |
| wait | Always available; consumes one Turn and lets enemies act |

Exactly one action is chosen per Turn, then every rule is evaluated again next
Turn. Movement is not a multi-Turn commitment. An unconditional `wait` really
does override automatic healing and Brute evasion. Put safety rules earlier if
you want to retain them while overriding other behavior.

## Replay, persistence and comparison

Decision reasons include the evaluated rule names with `condition false`,
`no matching target`, `action unavailable`, or `selected`. The Godot Replay Turn
log and browser decision details show these reasons. Default decisions after
fallback include the skipped-rule trace as well.

The full source, DSL version and SHA-256 hash are saved in `run_start.details.dsl`.
Execution metadata also retains the source. A `dsl-v1:<hash>` suffix in
`code_revision` keeps different programs in separate analysis/ranking groups.
Whitespace/comments also affect this source identity. Empty/whitespace-only
source preserves the original v8 event stream and identity behavior.

## CLI

```bash
# Validate only; no database or Run is created.
simulation-core/target/release/anarogue-sim --validate-dsl yes < examples/player-dsl/counter-archer.dsl

# Execute and store a Run using the program.
simulation-core/target/release/anarogue-sim --dsl-stdin yes --db logs/runs.sqlite3 --max-turns 5000 < examples/player-dsl/counter-archer.dsl
```

Limits: 16 KB UTF-8 source, 4096 tokens, 64 rules, expression depth 32. `#` starts
a line comment. Semicolons are not used. Duplicate settings/blocks/rule names,
unknown names, invalid targets/actions, incompatible types and out-of-range
settings are rejected before execution. Updating this feature requires rebuilding
the Rust executable, restarting the Python API, and restarting the Godot client.

## API

`POST /api/dsl/validate` takes the same settings object as `/api/jobs`, including
optional `dsl` source, and returns `valid`, `rules`, `policy_overrides`, and
`effective_policy`. `/api/jobs` and `/api/batches` also accept `dsl`. The API
always uses the configured simulator to validate the source; request data
cannot choose an executable or file path. Validation failures return HTTP 400
without accepting a job. The legacy Godot manual simulator is not a DSL runtime;
the DSL runs in the Rust simulator used by Home → Run / AutoRun and the CLI.
