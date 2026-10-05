# AnaRogue User Manual

## Overview

AnaRogue is a small turn-based roguelike made with Godot 4. You explore procedurally generated dungeon floors, avoid or defeat enemies, collect gold, and descend as deeply as you can.

Each action you take advances the game by one turn. Move carefully, watch your HP, and use the stairs to continue to the next depth.

## Starting the Game

1. Open `game/` in Godot 4 and run the project to open the replay client.
2. Select a JSONL log, or use the bundled v8 reference. Pickup and healing have their own frames.
   Below the buttons, the left panel shows the current event and decision log; the right panel shows Level/XP, HP, ATK, DEF, potions, weapon (W), armor (D), and strategy. Each panel scrolls independently. Depth, frame number, and turn appear in a badge over the top of the maze.
3. For a live run, select `Live check` (`res://scenes/main.tscn`); it starts on Depth 1.
4. Choose an automatic strategy on the right side of the screen.
5. Click `Start selected strategy`, or run both strategies with
   `Compare both — same seed`.

## Goal

Your goal is to reach Depth 5. Floors 1–4 are playable; descending from Depth 4 completes the dungeon.

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
| `H` | Use one health potion in Live check |
| `F` | Fire an equipped bow at a visible enemy in Live check |
| `R` | Restart the game |

## Screen Guide

### Dungeon Symbols

| Symbol | Meaning |
| --- | --- |
| `@` | Player |
| `E` | Melee enemy |
| `A` | Archer enemy |
| `O` | Brute: slow enemy with a heavy telegraphed strike |
| Red tile outline | Brute will strike this tile next enemy phase |
| Purple `+` | Health potion |
| `W` | Melee weapon |
| `B` | Bow |
| `D` | Armor |
| `>` | Stairs to the next floor |

### HUD

The right side of the screen shows:

- Current dungeon depth
- Player level and XP toward the next level (for example, `Lv 2 · XP 5/16`)
- Current and maximum HP
- Health potions carried (0–3)
- Gold collected
- Control reminders
- Recent message log

XP is progress within the current level, not lifetime XP. The next level requires
`current level × 8` XP; leveling up spends that amount and carries any remainder
forward. The Godot replay status and the web viewer event details also show level
and XP for the selected frame or event.

The message log reports important events, such as defeating enemies, taking damage, finding a new floor, or losing the run.

The game also writes a persistent JSON Lines log to `user://anarogue.jsonl`. It records player actions, floor starts, combat results, restarts, and run-ending results.

## How Turns Work

AnaRogue is turn-based. After you click `Start`, the player takes turns automatically.

After you move, attack, or wait, enemies get a turn. Enemies may move toward you if they can sense you nearby, or attack if they are next to you.

### Automatic Strategies

**Aggressive** attacks adjacent enemies, then compares growth from combat with
descent. It values XP even before a level-up and pursues a worthwhile, survivable
fight. When descending offers more value, it may leave enemies behind.

**Cautious** normally heads for the stairs, but can take a short melee detour
when the next kill would yield a level-up and its estimated cost beats descent.
Without a bow, it avoids chasing retreating Archers for growth. Its pathfinder assigns extra cost
to tiles threatened by melee enemies and archers, so it prefers safer detours.
At range, an equipped bow can engage visible enemies. It attacks a melee enemy once caught because
both move at the same speed and retreating cannot open a gap. If the stairs are
one step away, it escapes instead. It also attacks when no route to the stairs
is open and an enemy blocks it.

Comparison mode gives both strategies the same scenario seed. Floor generation,
enemy placement, potion placement, and each enemy's gold reward are derived separately from that
seed, so different decisions do not change the scenario itself.

Walking into a wall does not advance the turn. The pathfinder remembers visited
tiles and adds a growing cost after the second visit, so changing enemy positions
do not trap the player in an endless back-and-forth. Returning through a corridor
remains possible; this is a preference, not a movement restriction.

## Movement

After `Start` is clicked, the player automatically moves one tile at a time. You can still use the arrow keys to take manual turns.

You can walk on floor tiles, but not through walls. Rooms and corridors are generated randomly each run and each floor.

## Health Potions

Step onto a purple `+` to collect a potion automatically. Pickup is part of the
movement turn. Carry up to 3; a full inventory leaves the potion on the floor.
Use `H` in Live check to restore up to 8 HP. Use consumes a turn and enemies act
immediately afterward. At full HP or with no potion, pressing `H` does nothing.
Potions carry over to the next floor and clear on restart. Uncollected potions
are left behind when descending.

Both strategies use potions when a full 8 HP can be recovered, HP is low, or the
estimated next enemy phase could be lethal. Aggressive gathers potions within
8 unobstructed steps; Cautious only gathers within 4 steps along an entirely
unthreatened route. Neither detours for items while an enemy is adjacent.
Full details are in [simulation v3](docs/simulation-spec-v3.md).

The web viewer shows potions found/used, actual HP healed and current inventory.
Pickup/use events are included under the Actions filter.

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

Score starts at 0. Defeating a melee enemy earns 1 point, defeating an archer or Brute earns 2 points, and descending to the next depth earns 3 points. Taking turns does not award points.

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

Archer arrows require a clear line of sight through floor tiles. Walls, including
corners grazed by a diagonal shot, block attacks. Cover also removes the Archer's
contribution to automatic exploration's danger and emergency-healing estimates.

## Weapons, armor and combat

Floor icons are `+` for healing potions, `W` for melee weapons, `B` for bows and `D` for armor.
You have one weapon slot and one armor slot. Moving onto wanted equipment picks
it up and equips it immediately, within the same movement turn. Aggressive prefers
melee weapons; Cautious prefers bows, even if the other kind has a higher bonus.
Within the same kind, only a higher bonus is an upgrade. An empty weapon slot
accepts either kind until a preferred weapon is found. Previous gear is
dropped on that tile. Unwanted equipment stays on the floor; it does not
cause repeated swapping. Gear is separate from the three-potion capacity.
Equipment survives floor transitions and is cleared when starting a new run.

Melee effective attack = base attack + weapon bonus. Bow effective attack =
max(1, floor((base attack + weapon bonus) / 2)). For base attack 5 and bonus 2,
melee attack is 7 and bow attack is 3. Effective defense = base defense +
armor bonus. Damage = max(1, attack - defense), for melee and arrows alike. Existing
enemies have zero defense. Level gains increase base attack, keeping the equipment
bonus unchanged. The replay and web viewer show these components separately.

Each playable floor places one melee weapon, one bow and one armor when a free tile is available.
Weapon bonus is depth + 1; armor bonus is floor((depth + 1) / 2). Aggressive looks
for upgrades within eight steps; Cautious within four fully safe steps. Emergency
healing estimates damage after armor. New runs use Schema v8; earlier logs remain readable and retain their recorded outcomes.

## Growth and descent decisions

Exploration uses your current level, XP, effective attack and defense. A kill near
the next level is worth more, especially on early floors where +1 base attack and
+2 max HP have longer to help. Costly fights, repeated approaches, recovery from
stairs and completing Depth 4 favor descending. Both strategies preserve a viable
growth target to avoid reversing toward whichever enemy happens to be nearer.
Potion use, item gathering and adjacent combat/escape retain their priority.

Godot replay displays growth versus stairs scores. In the web viewer, select a
`hunt_for_growth` or `descend_for_progress` decision to see **Growth vs. descent**:
XP reward, projected levels, attack count, estimated damage, revisit penalties,
scores and reasons a fight was skipped. Comparison cards show final level and XP.
The scores are policy preferences, not actual score rewards. Damage is a static
estimate using current enemy positions; it does not guarantee survival. Generate
a new v8 log to see this behavior; earlier logs retain their original decisions.

## Player bows

A bow reaches five tiles in a circle (`dx² + dy² <= 25`) and requires the same
wall and corner line-of-sight check as Archer arrows. A shot takes one turn,
leaves the player in place and is followed by the enemy phase. Arrows are unlimited.
Press `F` to shoot the current visible growth target, or the nearest visible enemy.
An invalid shot spends no turn. Bump attacks with a bow also use its lower attack.

Automatic healing takes priority over shooting. With no adjacent enemy, both
strategies shoot an in-range target before taking item detours. Automatic shooting
skips a shot when predicted immediate counterfire would be lethal; Cautious also
yields to its normal progression comparison when stairs are one step away.
Adjacent combat and escape retain their existing rules. There is no automatic
kiting. Growth estimates stop the approach at the first firing position and
account for low bow damage and melee enemies closing the gap. Archer movement
can still change actual costs.

Godot replay draws Player arrows in yellow and updates enemy HP / removal in the
impact frame. Both viewers show weapon kind and range. Generate a new v8 log to
see bows; historical logs keep their recorded behavior.

## Brute and strategy comparisons

Brute moves one tile every two turns. Once adjacent, it spends an enemy phase
winding up and marks your tile in red. On its next phase it strikes that same
tile for high damage; moving off it makes the strike miss, even if you stay
adjacent. Killing it first interrupts the strike. Its high HP means the first hit
will often not be enough. A kill gives 5 XP and 2 score.

Aggressive keeps attacking; Cautious avoids the marked tile unless it can safely
finish the kill. Emergency healing still comes first. Brute attacks are included
in path danger and growth estimates. In live play you can dodge with arrow keys.
Replay shows preparation, hits and misses so the decision can be inspected.

For multiple seeds, use `tools/compare_strategies.py`; it writes a report, JSON
and a per-run CSV. The [50-seed comparison](docs/strategy-comparison-v7.md) records
44/50 clears for Aggressive and 47/50 for Cautious on a 44×28 map. These results
describe the listed scenarios rather than guaranteeing either policy is stronger.

## Weighted exploration priorities (v8)

Before starting a live run, select a preset and open **Goals: enemy … / items … /
stairs … / T …**. Adjust each priority and the temperature, then apply. Weights
range from 0 to 1000; zero disables discretionary selection of that category.
At least one must be positive. Temperature ranges from 1 to 100; a higher value
gives lower-utility goals more chances. Selecting another preset resets overrides;
**Compare both** uses the two presets on the same seed.

Aggressive starts at enemy/item/stairs **4/2/1**, Cautious at **1/2/4**, both with
temperature **8**. These are preferences, not guaranteed proportions of actions.
Weapon preference and emergency response still follow the preset.

The player weighs XP and level growth, healing and equipment improvement, and
stairs progress against estimated HP loss, travel and revisits. It draws a goal
when needed and keeps the same target until completion, invalidation or an HP
change of at least 4. Efficient/urgent healing, adjacent combat and marked Brute
strikes take precedence. When pursuing a Brute, Cautious can wait after dodging
so the slow enemy approaches before the next attack.

Select a `weighted_goal` decision in the web viewer to see benefit, estimated
damage, risk, utility and draw chances. Godot replay shows the same decision
summary. **Retained** means no new draw occurred; displayed probabilities describe
a hypothetical redraw. Old logs keep their original decisions.

See [v8 comparison](docs/strategy-comparison-v8.md) for 50 paired seeds and
[exact evaluation rules](docs/simulation-spec-v8.md) for estimates and limitations.
