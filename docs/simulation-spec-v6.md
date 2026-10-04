# Simulation specification v6

V6 extends [v5](simulation-spec-v5.md) with Player bows and strategy-dependent
weapon selection. Level thresholds, armor, rewards and progression weights stay
as specified in v5. New runs use [Schema v6](run-log-v6.md).

## Equipment and damage

There is one weapon slot. Weapon kind is `melee` or `bow`; an empty slot counts
as melee for combat. Aggressive prefers melee; Cautious prefers bows. A preferred
kind replaces a nonpreferred kind regardless of bonus. Within the same kind,
only strictly higher attack bonus replaces the weapon. An empty slot accepts
either kind. Previous gear drops on the pickup tile; it will not be re-equipped
if unwanted. Armor still upgrades only by defense bonus.

| Weapon | Effective attack | Range | Preferred strategy |
| --- | --- | --- | --- |
| Melee / unarmed | base attack + weapon bonus | 1 adjacent tile | Aggressive |
| Bow | max(1, floor((base attack + weapon bonus) / 2)) | Euclidean radius 5 | Cautious |

For base attack 5 and bonus 2, melee attack is 7 and bow attack is 3. All hits use
`max(1, effective attack - enemy defense)`. Bump attacks with a bow use the same
reduced attack. Level-up increases base attack before the bow scaling is applied.

Each floor adds a bow with bonus `depth + 1` in the first room, if a free interior
tile exists. It excludes Player, stairs, enemies and other items. The independent
`bows` random stream preserves existing potion / melee / armor placement and RNG
streams. Bow IDs are `bow-{depth}`; melee and armor generation retain v4 rules.
Nearby item searches rank wanted preferred weapons before other items, then
shortest route. Existing strategy detour limits and safety constraints apply.

## Shooting and priority

Shooting requires a bow, a living target on the current floor, squared distance
at most 25 and the symmetric supercover LOS used by Archers. Exact diagonal
corner contacts are blocked by either adjoining wall. Invalid shots spend no
turn. Valid shots spend one turn, leave Player in place, deal damage / grant the
normal kill rewards and XP, then run the enemy phase. Arrows are unlimited.
Enemy Archers retain their existing range and combat rules.

Automatic decisions choose healing first. With no adjacent enemy, a bow shoots
an in-range visible target before item detours, unless predicted immediate
counterfire is lethal. This check excludes the target if the shot kills it.
Cautious also yields to the normal item / growth / descent logic when stairs are
one step away. The current growth target is preferred when visible, otherwise
the nearest visible enemy is chosen; enemy order breaks distance ties.

Adjacent enemies retain existing combat / escape rules. Without a shot, item
collection and v5 progression comparisons run normally. No automatic kiting is
added. Manual `F` uses the same target selection and shot validity, but does not
apply automatic adjacent / stairs / counterfire guards.

## Growth estimate

The bounded enemy-route BFS and v5 scores are retained. The approach stops at the
first route tile with a valid bow shot, or contains zero moves when the current
position already allows a shot. `attack_pos` records this tile. Melee approaches
still stop adjacent. The search continues to require a reachable enemy route,
even if shooting across a disconnected gap would be possible.

Attack count uses the equipped weapon's effective attack. Melee target
retaliations are `max(0, attack_turns - Manhattan(attack_pos, enemy.pos))`, allowing
initial shots while the enemy closes the gap. Archer target retaliations remain
`attack_turns - 1`; use its ranged attack when squared distance exceeds 2, else
its punch of 1. Other enemies contribute static incoming damage at the attack
tile on every shot. Approach damage and revisit cost sum only the truncated
approach. Cautious no longer rejects an Archer solely for mobility when holding
a bow; HP reserve and immediate-level-up requirements still apply.

This remains a static estimate: actual enemy movement, retreat and congestion
can change costs. In-range opportunistic shooting takes precedence over scored
growth comparisons. These initial damage / range values are covered by boundary
and deterministic tests; they are not a statistical balance claim.

## Presentation and verification

Floor symbols are W (melee), B (bow), D (armor), + (potion). Live HUD and both log
viewers show weapon kind, range and reduced bow attack. Godot replay draws Player
arrows in yellow, updates enemy HP immediately and retains the killing arrow
when removing the defeated enemy. Historical v1-v5 files remain intact.

Godot and Rust cover preferences, stable swaps, damage, exact range boundaries,
wall / corner LOS, turn cost, enemy counterfire, healing priority and growth.
Six [v6 reference runs](reference-logs-v6.md) compare complete event streams and
final state across engines, including both prior movement-cycle regressions.
