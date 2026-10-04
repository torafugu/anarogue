export type EventName =
  | "run_start"
  | "floor_start"
  | "decision"
  | "user_action"
  | "battle_result"
  | "floor_descend"
  | string;

export interface Vector2i {
  x: number;
  y: number;
}

export interface ItemSnapshot {
  id: string;
  type: "health_potion" | "weapon" | "armor";
  attack_bonus?: number;
  defense_bonus?: number;
  pos: Vector2i;
}

export interface GearSnapshot {
  id: string;
  type: "weapon" | "armor";
  attack_bonus: number;
  weapon_kind?: "melee" | "bow" | null;
  defense_bonus: number;
}

export interface PlayerState {
  pos: Vector2i;
  hp: number;
  max_hp: number;
  attack: number;
  defense?: number;
  base_attack?: number;
  base_defense?: number;
  attack_bonus?: number;
  defense_bonus?: number;
  equipment?: { weapon: GearSnapshot | null; armor: GearSnapshot | null };
  gold: number;
  score: number;
  weapon_kind?: "melee" | "bow";
  attack_range?: number;
  level: number;
  xp: number;
  inventory?: { health_potion: number };
}

export interface EnemySnapshot {
  id: string;
  type: "melee" | "archer" | string;
  pos: Vector2i;
  hp: number;
  attack: number;
  defense?: number;
  windup_target?: Vector2i | null;
  distance_squared?: number;
}

export interface ProgressionComparison {
  stairs_steps: number;
  stairs_healing: number;
  stairs_score: number;
  selected: "combat" | "stairs";
  selected_enemy_id: string | null;
  target_retained: boolean;
  candidates: {
    enemy_id: string;
    eligible: boolean;
    rejection: "" | "hp_reserve" | "no_level_up" | "mobile_target" | "out_of_reach";
    steps?: number;
    attack_turns?: number;
    attack_pos?: Vector2i;
    xp_gain?: number;
    levels_gained?: number;
    estimated_damage?: number;
    score?: number;
    revisit_penalty?: number;
  }[];
}

export interface DecisionDetails {
  decision_id: string;
  strategy_id: string;
  rule_id: string;
  reason: string;
  action_turn: number;
  observation: {
    player_pos: Vector2i;
    hp: number;
    max_hp: number;
    enemy_count: number;
    enemies: EnemySnapshot[];
    stairs_pos: Vector2i;
    stairs_distance_squared: number;
    items?: ItemSnapshot[];
    inventory?: { health_potion: number };
    current_danger?: number;
    selected_step_danger?: number;
    selected_step_revisit_cost?: number;
    current_tile_visits?: number;
    level?: number;
    xp?: number;
    xp_to_next_level?: number;
    progression?: ProgressionComparison;
  };
  action: {
    type: "move" | "attack" | "wait" | string;
    direction: Vector2i;
    target: Record<string, unknown>;
  };
}

export interface RunEvent {
  schema_version?: number;
  time: string;
  event: EventName;
  run_id: string;
  scenario_id?: string;
  scenario_seed?: number;
  strategy_id?: string;
  sequence: number;
  turn: number;
  depth: number;
  hp: number;
  gold: number;
  player_state?: PlayerState;
  details: Record<string, unknown>;
}

export interface ParsedLog {
  runs: Map<string, RunEvent[]>;
  warnings: string[];
}

export interface RunSummary {
  turns: number;
  maxDepth: number;
  kills: number;
  damageTaken: number;
  potionsPickedUp: number;
  potionsUsed: number;
  hpHealed: number;
  gold: number;
  score: number;
  level: number;
  xp: number;
  decisions: number;
  finalHp: number;
  result: "defeated" | "cleared" | "restarted" | "active";
}

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const asNumber = (value: unknown, fallback = 0): number =>
  typeof value === "number" && Number.isFinite(value) ? value : fallback;

const asString = (value: unknown, fallback = ""): string =>
  typeof value === "string" ? value : fallback;

const legacyPlayerState = (record: Record<string, unknown>): PlayerState => ({
  pos: { x: 0, y: 0 },
  hp: asNumber(record.hp),
  max_hp: Math.max(asNumber(record.hp), 1),
  attack: 0,
  gold: asNumber(record.gold),
  score: 0,
  level: 1,
  xp: 0,
});

function normalizeEvent(value: unknown, lineNumber: number): RunEvent {
  if (!isRecord(value)) {
    throw new Error(`Line ${lineNumber} is not a JSON object.`);
  }

  const event = asString(value.event);
  const runId = asString(value.run_id);
  if (!event || !runId) {
    throw new Error(`Line ${lineNumber} is missing event or run_id.`);
  }

  const state = isRecord(value.player_state)
    ? (value.player_state as unknown as PlayerState)
    : legacyPlayerState(value);

  return {
    schema_version:
      typeof value.schema_version === "number" ? value.schema_version : undefined,
    time: asString(value.time),
    event,
    run_id: runId,
    scenario_id: asString(value.scenario_id) || undefined,
    scenario_seed:
      typeof value.scenario_seed === "number" ? value.scenario_seed : undefined,
    strategy_id: asString(value.strategy_id) || undefined,
    sequence: asNumber(value.sequence, lineNumber),
    turn: asNumber(value.turn),
    depth: Math.max(asNumber(value.depth, 1), 1),
    hp: asNumber(value.hp, state.hp),
    gold: asNumber(value.gold, state.gold),
    player_state: state,
    details: isRecord(value.details) ? value.details : {},
  };
}

export function parseJsonLines(source: string): ParsedLog {
  const runs = new Map<string, RunEvent[]>();
  const warnings: string[] = [];
  const lines = source.split(/\r?\n/);

  lines.forEach((line, index) => {
    if (!line.trim()) return;
    let raw: unknown;
    try {
      raw = JSON.parse(line);
    } catch (error) {
      const message = error instanceof Error ? error.message : "Invalid JSON";
      throw new Error(`Line ${index + 1}: ${message}`);
    }

    const event = normalizeEvent(raw, index + 1);
    if (event.schema_version !== 1 && event.schema_version !== 2 && event.schema_version !== 3 && event.schema_version !== 4 && event.schema_version !== 5 && event.schema_version !== 6 && event.schema_version !== 7) {
      warnings.push(
        `Run ${event.run_id} contains legacy or unsupported schema data.`,
      );
    }
    const run = runs.get(event.run_id) ?? [];
    run.push(event);
    runs.set(event.run_id, run);
  });

  for (const events of runs.values()) {
    events.sort((a, b) => a.sequence - b.sequence);
  }

  if (runs.size === 0) {
    throw new Error("No AnaRogue events were found in this file.");
  }

  return { runs, warnings: [...new Set(warnings)] };
}

export function summarizeRun(events: RunEvent[]): RunSummary {
  const last = events.at(-1);
  let kills = 0;
  let damageTaken = 0;
  let decisions = 0;
  let potionsPickedUp = 0;
  let potionsUsed = 0;
  let hpHealed = 0;
  let result: RunSummary["result"] = "active";

  for (const event of events) {
    if (event.event === "decision") decisions += 1;
    if (event.event === "item_result") {
      if (event.details.result === "item_picked_up") potionsPickedUp += 1;
      if (event.details.result === "item_used") {
        potionsUsed += 1;
        hpHealed += asNumber(event.details.healed);
      }
    }
    if (event.event !== "battle_result") continue;
    const eventResult = asString(event.details.result);
    if (eventResult === "enemy_defeated") kills += 1;
    if (eventResult === "player_hit") {
      damageTaken += asNumber(event.details.damage);
    }
    if (eventResult === "player_defeated") result = "defeated";
    if (eventResult === "dungeon_cleared") result = "cleared";
    if (eventResult === "restart") result = "restarted";
  }

  return {
    turns: Math.max(...events.map((event) => event.turn), 0),
    maxDepth: Math.max(...events.map((event) => event.depth), 1),
    kills,
    damageTaken,
    potionsPickedUp,
    potionsUsed,
    hpHealed,
    gold: last?.player_state?.gold ?? last?.gold ?? 0,
    score: last?.player_state?.score ?? 0,
    level: last?.player_state?.level ?? 1,
    xp: last?.player_state?.xp ?? 0,
    decisions,
    finalHp: last?.player_state?.hp ?? last?.hp ?? 0,
    result,
  };
}

export function decisionDetails(event: RunEvent): DecisionDetails | null {
  if (event.event !== "decision" || !isRecord(event.details)) return null;
  const details = event.details as unknown as DecisionDetails;
  return typeof details.rule_id === "string" ? details : null;
}

export function eventCategory(event: RunEvent): string {
  if (event.event === "decision") return "decision";
  if (event.event === "battle_result") return "combat";
  if (event.event === "user_action" || event.event === "item_result") return "action";
  return "floor";
}

export function describeEvent(event: RunEvent): { title: string; body: string } {
  const details = event.details;
  if (event.event === "battle_result" && details.result === "enemy_windup") {
    const target = details.target as Vector2i;
    return { title: "Brute winds up", body: `Heavy strike next turn at (${target.x}, ${target.y}). Move off this tile to avoid it.` };
  }
  if (event.event === "battle_result" && details.result === "enemy_strike_missed") {
    return { title: "Brute's strike missed", body: "The marked tile was empty. The Brute must wind up again before another strike." };
  }
  if (event.event === "user_action" && details.action === "shoot") {
    return { title: "Player fired a bow", body: `Target: ${asString(details.enemy_id)}. One turn consumed.` };
  }
  if (event.event === "item_result") {
    if (details.result === "item_equipped") {
      const item = details.item as GearSnapshot;
      return { title: `${item.type === "weapon" ? item.weapon_kind === "bow" ? "Bow" : "Melee weapon" : "Armor"} equipped`, body: `${item.id} · ATK +${item.attack_bonus} · DEF +${item.defense_bonus}. ${details.previous_equipment ? "Previous equipment dropped on the floor." : "Previously empty slot."}` };
    }
    return details.result === "item_picked_up"
      ? { title: "Health potion picked up", body: `Inventory: ${asNumber((details.inventory as Record<string, unknown>)?.health_potion)}/3.` }
      : { title: `Health potion restored ${asNumber(details.healed)} HP`, body: `HP ${asNumber(details.hp_before)} → ${asNumber(details.hp_after)}.` };
  }
  if (event.event === "decision") {
    const decision = decisionDetails(event);
    return {
      title: decision?.rule_id ?? "Decision",
      body: decision?.reason ?? "Automatic strategy selected an action.",
    };
  }
  if (event.event === "floor_start") {
    return {
      title: `Entered depth ${event.depth}`,
      body: `${asNumber(details.enemy_count)} enemies detected on this floor.`,
    };
  }
  if (event.event === "floor_descend") {
    return {
      title: `Descended to depth ${asNumber(details.to_depth, event.depth)}`,
      body: `HP after recovery: ${asNumber(details.hp_after, event.hp)}.`,
    };
  }
  if (event.event === "user_action") {
    return {
      title: `${asString(details.action, "Action")} · ${asString(details.result)}`,
      body: asString(details.decision_id, "Manual input or lifecycle action."),
    };
  }
  if (event.event === "battle_result") {
    const result = asString(details.result, "Combat event");
    if (result === "player_hit") {
      return {
        title: `Player hit for ${asNumber(details.damage)}`,
        body: `${asString(details.enemy_type, "enemy")} ${asString(details.enemy_id)}`.trim(),
      };
    }
    if (result === "enemy_defeated") {
      return {
        title: `${asString(details.enemy_type, "Enemy")} defeated`,
        body: `${asString(details.enemy_id)} · +${asNumber(details.gold_gained)} gold`,
      };
    }
    if (result === "player_defeated") {
      return { title: "Run ended", body: `Defeated on depth ${event.depth}.` };
    }
    if (result === "dungeon_cleared") {
      return { title: "Dungeon cleared", body: `Cleared on turn ${event.turn}.` };
    }
    return { title: result.replaceAll("_", " "), body: "Combat result" };
  }
  if (event.event === "run_start") {
    return {
      title: "Run started",
      body: `Strategy: ${asString(details.strategy_id, "unknown")}`,
    };
  }
  return { title: event.event.replaceAll("_", " "), body: "" };
}
