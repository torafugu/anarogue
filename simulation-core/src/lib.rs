use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::{HashMap, VecDeque};
use std::fmt;
use std::time::{SystemTime, UNIX_EPOCH};

const MIN_ROOM_SIZE: i32 = 5;
const MAX_ROOM_SIZE: i32 = 11;
const BASE_MAX_HP: i32 = 18;
const BASE_ATTACK: i32 = 5;
const BOW_RANGE: i32 = 5;
const MAX_DEPTH: u32 = 5;
const POTION_HEAL: i32 = 8;
const INVENTORY_CAPACITY: u32 = 3;
const ZERO_SEED_FALLBACK: u32 = 0x6d2b_79f5;
const DIRECTIONS: [Point; 4] = [
    Point { x: 0, y: -1 },
    Point { x: 0, y: 1 },
    Point { x: -1, y: 0 },
    Point { x: 1, y: 0 },
];

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq, Serialize, Deserialize)]
pub struct Point {
    pub x: i32,
    pub y: i32,
}

impl Point {
    pub const ZERO: Self = Self { x: 0, y: 0 };

    fn distance_squared(self, other: Self) -> i32 {
        let dx = self.x - other.x;
        let dy = self.y - other.y;
        dx * dx + dy * dy
    }

    fn manhattan_distance(self, other: Self) -> i32 {
        (self.x - other.x).abs() + (self.y - other.y).abs()
    }
}
impl std::ops::Add for Point {
    type Output = Self;

    fn add(self, rhs: Self) -> Self::Output {
        Self {
            x: self.x + rhs.x,
            y: self.y + rhs.y,
        }
    }
}

impl std::ops::Sub for Point {
    type Output = Self;

    fn sub(self, rhs: Self) -> Self::Output {
        Self {
            x: self.x - rhs.x,
            y: self.y - rhs.y,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Strategy {
    AggressiveV1,
    CautiousV1,
}

impl Strategy {
    pub fn id(self) -> &'static str {
        match self {
            Self::AggressiveV1 => "aggressive_v1",
            Self::CautiousV1 => "cautious_v1",
        }
    }
}

impl fmt::Display for Strategy {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.id())
    }
}

impl std::str::FromStr for Strategy {
    type Err = String;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        match value {
            "aggressive" | "aggressive_v1" => Ok(Self::AggressiveV1),
            "cautious" | "cautious_v1" => Ok(Self::CautiousV1),
            _ => Err(format!("unknown strategy: {value}")),
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct SimulationConfig {
    pub scenario_seed: u32,
    pub strategy: Strategy,
    pub map_width: i32,
    pub map_height: i32,
    pub max_turns: u32,
}

impl SimulationConfig {
    pub fn validate(self) -> Result<Self, String> {
        let minimum = MAX_ROOM_SIZE + 4;
        if self.map_width < minimum || self.map_height < minimum {
            return Err(format!(
                "map dimensions must both be at least {minimum}, got {}x{}",
                self.map_width, self.map_height
            ));
        }
        Ok(self)
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RunOutcome {
    PlayerDefeated,
    DungeonCleared,
    TurnLimit,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct RunSummary {
    pub scenario_seed: u32,
    pub strategy_id: String,
    pub map_width: i32,
    pub map_height: i32,
    pub max_turns: u32,
    pub outcome: RunOutcome,
    pub turns: u32,
    pub final_depth: u32,
    pub final_hp: i32,
    pub final_gold: u32,
    pub final_score: u32,
    pub final_potions: u32,
    pub final_level: u32,
    pub final_xp: u32,
}

#[derive(Clone, Debug, Serialize)]
pub struct RunLogEvent {
    pub schema_version: u32,
    pub time: String,
    pub event: String,
    pub run_id: String,
    pub scenario_id: String,
    pub scenario_seed: u32,
    pub strategy_id: String,
    pub sequence: u32,
    pub turn: u32,
    pub depth: u32,
    pub hp: i32,
    pub gold: u32,
    pub player_state: Value,
    pub details: Value,
}

#[derive(Clone, Debug)]
pub struct LoggedRun {
    pub summary: RunSummary,
    pub events: Vec<RunLogEvent>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct Rect {
    x: i32,
    y: i32,
    width: i32,
    height: i32,
}

impl Rect {
    fn end_x(self) -> i32 {
        self.x + self.width
    }

    fn end_y(self) -> i32 {
        self.y + self.height
    }

    fn center(self) -> Point {
        Point {
            x: self.x + self.width / 2,
            y: self.y + self.height / 2,
        }
    }

    fn grown_intersects(self, other: Self) -> bool {
        let grown = Self {
            x: self.x - 1,
            y: self.y - 1,
            width: self.width + 2,
            height: self.height + 2,
        };
        grown.x < other.end_x()
            && grown.end_x() > other.x
            && grown.y < other.end_y()
            && grown.end_y() > other.y
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum EnemyKind {
    Melee,
    Archer,
    Brute,
}

impl EnemyKind {
    fn id(self) -> &'static str {
        match self {
            Self::Melee => "melee",
            Self::Archer => "archer",
            Self::Brute => "brute",
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct Enemy {
    windup_target: Option<Point>,
    id: String,
    kind: EnemyKind,
    pos: Point,
    hp: i32,
    attack: i32,
    defense: i32,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
struct FloorItem {
    weapon_kind: Option<&'static str>,
    id: String,
    #[serde(rename = "type")]
    kind: &'static str,
    pos: Point,
    attack_bonus: i32,
    defense_bonus: i32,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
struct Gear {
    weapon_kind: Option<&'static str>,
    id: String,
    #[serde(rename = "type")]
    kind: &'static str,
    attack_bonus: i32,
    defense_bonus: i32,
}

#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize)]
struct Equipment {
    weapon: Option<Gear>,
    armor: Option<Gear>,
}

#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize)]
struct Inventory {
    health_potion: u32,
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct Player {
    pos: Point,
    hp: i32,
    max_hp: i32,
    base_attack: i32,
    base_defense: i32,
    equipment: Equipment,
    gold: u32,
    score: u32,
    level: u32,
    xp: u32,
    depth: u32,
    inventory: Inventory,
}

/// Independent preferences for goal categories. Zero disables discretionary selection.
#[derive(Clone, Copy, Debug, Serialize)]
pub struct GoalPolicy {
    pub enemy_weight: u32,
    pub item_weight: u32,
    pub stairs_weight: u32,
    pub temperature: u32,
}
impl GoalPolicy {
    pub fn preset(strategy: Strategy) -> Self {
        let (enemy_weight, stairs_weight) = if strategy == Strategy::CautiousV1 {
            (1, 4)
        } else {
            (4, 1)
        };
        Self {
            enemy_weight,
            item_weight: 2,
            stairs_weight,
            temperature: 8,
        }
    }
    pub fn validate(self) -> Result<Self, String> {
        if self.enemy_weight > 1000
            || self.item_weight > 1000
            || self.stairs_weight > 1000
            || self.enemy_weight + self.item_weight + self.stairs_weight == 0
            || !(1..=100).contains(&self.temperature)
        {
            return Err("goal weights must be 0..1000 with at least one positive weight; temperature must be 1..100".into());
        }
        Ok(self)
    }
    fn weight(self, kind: &str) -> u32 {
        match kind {
            "enemy" => self.enemy_weight,
            "item" => self.item_weight,
            _ => self.stairs_weight,
        }
    }
}
#[derive(Clone)]
struct GoalCandidate {
    kind: &'static str,
    id: String,
    direction: Point,
    target: Value,
    ranged: bool,
    evaluation: Value,
}
fn goal_mass(weight: u32, gap: i32, temperature: u32) -> u32 {
    const EXP: [u32; 9] = [1000, 368, 135, 50, 18, 7, 2, 1, 1];
    weight * EXP[((gap.max(0) as u32 / temperature).min(8)) as usize]
}

#[derive(Clone, Debug)]
struct Decision {
    direction: Point,
    rule_id: &'static str,
    reason: &'static str,
    action_type: &'static str,
    target: Value,
    selected_step_danger: Option<i32>,
    progression: Option<Value>,
    goal_selection: Option<Value>,
}

struct EventLogger {
    log_file: String,
    run_id: String,
    scenario_id: String,
    timestamp: String,
    sequence: u32,
    events: Vec<RunLogEvent>,
}

impl Default for Player {
    fn default() -> Self {
        Self {
            pos: Point::ZERO,
            hp: BASE_MAX_HP,
            max_hp: BASE_MAX_HP,
            base_attack: BASE_ATTACK,
            base_defense: 0,
            equipment: Equipment::default(),
            gold: 0,
            score: 0,
            level: 1,
            xp: 0,
            depth: 1,
            inventory: Inventory::default(),
        }
    }
}

#[derive(Clone, Debug)]
pub struct PortableRng {
    state: u32,
}

impl PortableRng {
    pub fn new(seed: u32) -> Self {
        Self {
            state: if seed == 0 { ZERO_SEED_FALLBACK } else { seed },
        }
    }

    pub fn fnv1a_32(value: &str) -> u32 {
        value
            .as_bytes()
            .iter()
            .fold(2_166_136_261_u32, |hash, byte| {
                (hash ^ u32::from(*byte)).wrapping_mul(16_777_619)
            })
    }

    pub fn derive_seed(
        scenario_seed: u32,
        channel: &str,
        depth: u32,
        entity_id: Option<&str>,
    ) -> u32 {
        let mut key = format!("{scenario_seed}:{channel}:{depth}");
        if let Some(entity_id) = entity_id {
            key.push(':');
            key.push_str(entity_id);
        }
        Self::fnv1a_32(&key)
    }

    pub fn next_u32(&mut self) -> u32 {
        let mut value = self.state;
        value ^= value << 13;
        value ^= value >> 17;
        value ^= value << 5;
        self.state = value;
        value
    }

    pub fn range_inclusive(&mut self, minimum: i32, maximum: i32) -> i32 {
        assert!(minimum <= maximum);
        let span = u64::try_from(maximum - minimum + 1).expect("positive range span");
        let threshold = ((1_u64 << 32) - span) % span;
        loop {
            let value = u64::from(self.next_u32());
            if value >= threshold {
                return minimum + i32::try_from(value % span).expect("range result fits i32");
            }
        }
    }

    pub fn chance(&mut self, numerator: u32, denominator: u32) -> bool {
        assert!(denominator > 0 && numerator <= denominator);
        if numerator == 0 {
            return false;
        }
        if numerator == denominator {
            return true;
        }
        self.range_inclusive(0, denominator as i32 - 1) < numerator as i32
    }
}

pub struct Simulation {
    config: SimulationConfig,
    map: Vec<Vec<bool>>,
    rooms: Vec<Rect>,
    enemies: Vec<Enemy>,
    items: Vec<FloorItem>,
    navigation_visits: HashMap<Point, u32>,
    aggressive_target_id: Option<String>,
    growth_target_id: Option<String>,
    goal_policy: GoalPolicy,
    policy_rng: PortableRng,
    selected_goal: Option<(String, String, i32)>,
    player: Player,
    stairs: Point,
    turn: u32,
    decision_sequence: u32,
    next_enemy_id: u32,
    game_over: bool,
    run_outcome: Option<RunOutcome>,
    logger: Option<EventLogger>,
}

impl Simulation {
    pub fn new(config: SimulationConfig) -> Result<Self, String> {
        Self::create(config, None, None)
    }

    pub fn new_with_policy(config: SimulationConfig, policy: GoalPolicy) -> Result<Self, String> {
        Self::create(config, None, Some(policy))
    }
    pub fn new_logged(config: SimulationConfig, log_file: String) -> Result<Self, String> {
        Self::new_logged_with_policy(config, log_file, GoalPolicy::preset(config.strategy))
    }
    pub fn new_logged_with_policy(
        config: SimulationConfig,
        log_file: String,
        policy: GoalPolicy,
    ) -> Result<Self, String> {
        if log_file.is_empty() {
            return Err("log output path must not be empty".to_owned());
        }
        let timestamp_seconds = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_err(|error| format!("system clock is before Unix epoch: {error}"))?
            .as_secs();
        let timestamp = format_utc_timestamp(timestamp_seconds);
        let run_id = format!("rust-{}-{timestamp_seconds}", config.scenario_seed);
        let scenario_id = format!("scenario-{}", config.scenario_seed);
        Self::create(
            config,
            Some(EventLogger {
                log_file,
                run_id,
                scenario_id,
                timestamp,
                sequence: 0,
                events: Vec::new(),
            }),
            Some(policy),
        )
    }

    fn create(
        config: SimulationConfig,
        logger: Option<EventLogger>,
        policy: Option<GoalPolicy>,
    ) -> Result<Self, String> {
        let config = config.validate()?;
        let goal_policy = policy
            .unwrap_or_else(|| GoalPolicy::preset(config.strategy))
            .validate()?;
        let policy_rng = PortableRng::new(PortableRng::derive_seed(
            config.scenario_seed,
            "policy",
            0,
            None,
        ));
        let mut simulation = Self {
            config,
            map: Vec::new(),
            rooms: Vec::new(),
            enemies: Vec::new(),
            items: Vec::new(),
            navigation_visits: HashMap::new(),
            aggressive_target_id: None,
            growth_target_id: None,
            goal_policy,
            policy_rng,
            selected_goal: None,
            player: Player::default(),
            stairs: Point::ZERO,
            turn: 0,
            decision_sequence: 0,
            next_enemy_id: 1,
            game_over: false,
            run_outcome: None,
            logger,
        };
        simulation.emit_run_start();
        simulation.new_floor();
        Ok(simulation)
    }

    pub fn run(mut self) -> RunSummary {
        self.emit_start_action();
        while !self.game_over && self.turn < self.config.max_turns {
            self.run_auto_player_turn();
        }
        self.summary()
    }

    pub fn run_logged(mut self) -> LoggedRun {
        self.emit_start_action();
        while !self.game_over && self.turn < self.config.max_turns {
            self.run_auto_player_turn();
        }
        let summary = self.summary();
        let events = self
            .logger
            .take()
            .map(|logger| logger.events)
            .unwrap_or_default();
        LoggedRun { summary, events }
    }

    pub fn summary(&self) -> RunSummary {
        RunSummary {
            scenario_seed: self.config.scenario_seed,
            strategy_id: self.config.strategy.id().to_owned(),
            map_width: self.config.map_width,
            map_height: self.config.map_height,
            max_turns: self.config.max_turns,
            outcome: self.run_outcome.unwrap_or(RunOutcome::TurnLimit),
            turns: self.turn,
            final_depth: self.player.depth,
            final_hp: self.player.hp,
            final_gold: self.player.gold,
            final_score: self.player.score,
            final_potions: self.player.inventory.health_potion,
            final_level: self.player.level,
            final_xp: self.player.xp,
        }
    }

    fn emit_run_start(&mut self) {
        let Some(logger) = self.logger.as_ref() else {
            return;
        };
        let details = json!({
            "log_file": logger.log_file,
            "scenario_id": logger.scenario_id,
            "scenario_seed": self.config.scenario_seed,
            "strategy_id": self.config.strategy.id(),
            "simulation_version": 8,
            "goal_policy": self.goal_policy,
            "policy_seed": PortableRng::derive_seed(self.config.scenario_seed, "policy", 0, None),
            "comparison": false,
            "comparison_phase": 0,
        });
        self.emit_event("run_start", details);
    }

    fn emit_start_action(&mut self) {
        self.emit_event(
            "user_action",
            json!({"action": "start", "result": "auto_exploration_started"}),
        );
    }

    fn emit_event(&mut self, event: &str, details: Value) {
        let player_state = self.player_state();
        let Some(logger) = self.logger.as_mut() else {
            return;
        };
        logger.sequence += 1;
        logger.events.push(RunLogEvent {
            schema_version: 8,
            time: logger.timestamp.clone(),
            event: event.to_owned(),
            run_id: logger.run_id.clone(),
            scenario_id: logger.scenario_id.clone(),
            scenario_seed: self.config.scenario_seed,
            strategy_id: self.config.strategy.id().to_owned(),
            sequence: logger.sequence,
            turn: self.turn,
            depth: self.player.depth,
            hp: self.player.hp,
            gold: self.player.gold,
            player_state,
            details,
        });
    }

    fn player_state(&self) -> Value {
        json!({
            "pos": self.player.pos,
            "hp": self.player.hp,
            "max_hp": self.player.max_hp,
            "attack": self.effective_attack(),
            "weapon_kind": self.weapon_kind(), "attack_range": self.attack_range(),
            "defense": self.effective_defense(),
            "base_attack": self.player.base_attack,
            "base_defense": self.player.base_defense,
            "attack_bonus": self.attack_bonus(),
            "defense_bonus": self.defense_bonus(),
            "equipment": self.player.equipment,
            "gold": self.player.gold,
            "score": self.player.score,
            "level": self.player.level,
            "xp": self.player.xp,
            "inventory": self.player.inventory,
        })
    }

    fn enemy_snapshot(&self, enemy: &Enemy) -> Value {
        json!({
            "id": enemy.id,
            "type": enemy.kind.id(),
            "pos": enemy.pos,
            "hp": enemy.hp,
            "attack": enemy.attack,
            "defense": enemy.defense,
            "distance_squared": enemy.pos.distance_squared(self.player.pos),
            "windup_target": enemy.windup_target,
        })
    }

    fn enemy_snapshots(&self) -> Vec<Value> {
        self.enemies
            .iter()
            .map(|enemy| self.enemy_snapshot(enemy))
            .collect()
    }

    fn map_rows(&self) -> Vec<String> {
        self.map
            .iter()
            .map(|row| {
                row.iter()
                    .map(|walkable| if *walkable { '.' } else { '#' })
                    .collect()
            })
            .collect()
    }

    fn new_floor(&mut self) {
        self.map =
            vec![vec![false; self.config.map_width as usize]; self.config.map_height as usize];
        self.rooms.clear();
        self.enemies.clear();
        self.items.clear();

        let floor_seed =
            PortableRng::derive_seed(self.config.scenario_seed, "floor", self.player.depth, None);
        let spawn_seed =
            PortableRng::derive_seed(self.config.scenario_seed, "spawn", self.player.depth, None);
        self.generate_dungeon(&mut PortableRng::new(floor_seed));
        self.player.pos = self.rooms[0].center();
        self.navigation_visits.clear();
        self.aggressive_target_id = None;
        self.growth_target_id = None;
        self.selected_goal = None;
        self.navigation_visits.insert(self.player.pos, 1);
        self.stairs = self.rooms[self.rooms.len() - 1].center();
        if self.stairs == self.player.pos {
            self.stairs = self.farthest_walkable_tile_from(self.player.pos);
        }
        self.spawn_enemies(&mut PortableRng::new(spawn_seed));
        let item_seed =
            PortableRng::derive_seed(self.config.scenario_seed, "items", self.player.depth, None);
        self.spawn_items(&mut PortableRng::new(item_seed));
        self.emit_event(
            "floor_start",
            json!({
                "floor_seed": floor_seed,
                "spawn_seed": spawn_seed,
                "item_seed": item_seed,
                "items": self.items,
                "enemy_count": self.enemies.len(),
                "enemies": self.enemy_snapshots(),
                "map_size": {"width": self.config.map_width, "height": self.config.map_height},
                "map_rows": self.map_rows(),
                "player_pos": self.player.pos,
                "stairs_pos": self.stairs,
            }),
        );
    }

    fn spawn_items(&mut self, rng: &mut PortableRng) {
        // Independent stream: adding items never changes terrain, enemies or rewards.
        for room_index in 0..self.rooms.len().min(3) {
            let room = self.rooms[room_index];
            let mut candidates = Vec::new();
            for y in room.y + 1..room.end_y() - 1 {
                for x in room.x + 1..room.end_x() - 1 {
                    let pos = Point { x, y };
                    if pos != self.player.pos && pos != self.stairs && self.enemy_at(pos).is_none()
                    {
                        candidates.push(pos);
                    }
                }
            }
            if candidates.is_empty() {
                continue;
            }
            let pos = candidates[rng.range_inclusive(0, candidates.len() as i32 - 1) as usize];
            self.items.push(FloorItem {
                id: format!("item-{}-{}", self.player.depth, room_index + 1),
                kind: "health_potion",
                weapon_kind: None,
                pos,
                attack_bonus: 0,
                defense_bonus: 0,
            });
        }
        self.spawn_equipment();
    }

    fn attack_bonus(&self) -> i32 {
        self.player
            .equipment
            .weapon
            .as_ref()
            .map_or(0, |gear| gear.attack_bonus)
    }

    fn defense_bonus(&self) -> i32 {
        self.player
            .equipment
            .armor
            .as_ref()
            .map_or(0, |gear| gear.defense_bonus)
    }

    fn weapon_kind(&self) -> &'static str {
        self.player
            .equipment
            .weapon
            .as_ref()
            .and_then(|gear| gear.weapon_kind)
            .unwrap_or("melee")
    }
    fn attack_range(&self) -> i32 {
        if self.weapon_kind() == "bow" {
            BOW_RANGE
        } else {
            1
        }
    }
    fn effective_attack(&self) -> i32 {
        let raw = self.player.base_attack + self.attack_bonus();
        if self.weapon_kind() == "bow" {
            (raw / 2).max(1)
        } else {
            raw
        }
    }
    fn preferred_weapon_kind(&self) -> &'static str {
        if self.config.strategy == Strategy::CautiousV1 {
            "bow"
        } else {
            "melee"
        }
    }
    fn item_priority(&self, item: &FloorItem) -> i32 {
        i32::from(
            item.kind == "weapon"
                && item.weapon_kind.unwrap_or("melee") == self.preferred_weapon_kind(),
        )
    }
    fn wants_weapon(&self, item: &FloorItem) -> bool {
        if self.player.equipment.weapon.is_none() {
            return true;
        }
        let candidate_kind = item.weapon_kind.unwrap_or("melee");
        if candidate_kind != self.weapon_kind() {
            return candidate_kind == self.preferred_weapon_kind();
        }
        item.attack_bonus > self.attack_bonus()
    }
    fn effective_defense(&self) -> i32 {
        self.player.base_defense + self.defense_bonus()
    }
    fn damage(attack: i32, defense: i32) -> i32 {
        (attack - defense).max(1)
    }

    fn wants_item(&self, item: &FloorItem) -> bool {
        match item.kind {
            "health_potion" => self.player.inventory.health_potion < INVENTORY_CAPACITY,
            "weapon" => self.wants_weapon(item),
            "armor" => item.defense_bonus > self.defense_bonus(),
            _ => false,
        }
    }

    fn spawn_equipment(&mut self) {
        let mut rng = PortableRng::new(PortableRng::derive_seed(
            self.config.scenario_seed,
            "equipment",
            self.player.depth,
            None,
        ));
        for (kind, room_index) in [("weapon", 0), ("armor", self.rooms.len().min(2) - 1)] {
            let room = self.rooms[room_index];
            let mut candidates = Vec::new();
            for y in room.y + 1..room.end_y() - 1 {
                for x in room.x + 1..room.end_x() - 1 {
                    let pos = Point { x, y };
                    if pos != self.player.pos
                        && pos != self.stairs
                        && self.enemy_at(pos).is_none()
                        && !self.items.iter().any(|item| item.pos == pos)
                    {
                        candidates.push(pos);
                    }
                }
            }
            if candidates.is_empty() {
                continue;
            }
            let pos = candidates[rng.range_inclusive(0, candidates.len() as i32 - 1) as usize];
            self.items.push(FloorItem {
                id: format!("{}-{}", kind, self.player.depth),
                kind,
                weapon_kind: (kind == "weapon").then_some("melee"),
                pos,
                attack_bonus: if kind == "weapon" {
                    self.player.depth as i32 + 1
                } else {
                    0
                },
                defense_bonus: if kind == "armor" {
                    (self.player.depth as i32 + 1) / 2
                } else {
                    0
                },
            });
        }
        self.spawn_bow();
    }

    fn spawn_bow(&mut self) {
        let room = self.rooms[0];
        let mut candidates = Vec::new();
        for y in room.y + 1..room.end_y() - 1 {
            for x in room.x + 1..room.end_x() - 1 {
                let pos = Point { x, y };
                if pos != self.player.pos
                    && pos != self.stairs
                    && self.enemy_at(pos).is_none()
                    && !self.items.iter().any(|item| item.pos == pos)
                {
                    candidates.push(pos);
                }
            }
        }
        if candidates.is_empty() {
            return;
        }
        let mut rng = PortableRng::new(PortableRng::derive_seed(
            self.config.scenario_seed,
            "bows",
            self.player.depth,
            None,
        ));
        self.items.push(FloorItem {
            id: format!("bow-{}", self.player.depth),
            kind: "weapon",
            weapon_kind: Some("bow"),
            pos: candidates[rng.range_inclusive(0, candidates.len() as i32 - 1) as usize],
            attack_bonus: self.player.depth as i32 + 1,
            defense_bonus: 0,
        });
    }

    fn pick_up_items(&mut self, decision_id: &str) {
        while let Some(index) = self
            .items
            .iter()
            .position(|item| item.pos == self.player.pos && self.wants_item(item))
        {
            let item = self.items.remove(index);
            if item.kind == "health_potion" {
                self.player.inventory.health_potion += 1;
                self.emit_event(
                    "item_result",
                    json!({
                        "result": "item_picked_up", "item": item,
                        "inventory": self.player.inventory, "decision_id": decision_id,
                    }),
                );
                continue;
            }
            let gear = Gear {
                id: item.id.clone(),
                kind: item.kind,
                attack_bonus: item.attack_bonus,
                defense_bonus: item.defense_bonus,
                weapon_kind: item.weapon_kind,
            };
            let slot = if item.kind == "weapon" {
                &mut self.player.equipment.weapon
            } else {
                &mut self.player.equipment.armor
            };
            let previous = slot.replace(gear);
            if let Some(old) = &previous {
                self.items.push(FloorItem {
                    id: old.id.clone(),
                    kind: old.kind,
                    pos: self.player.pos,
                    attack_bonus: old.attack_bonus,
                    defense_bonus: old.defense_bonus,
                    weapon_kind: old.weapon_kind,
                });
            }
            self.emit_event(
                "item_result",
                json!({
                    "result": "item_equipped", "item": item, "previous_equipment": previous,
                    "equipment": self.player.equipment, "items": self.items,
                    "inventory": self.player.inventory, "decision_id": decision_id,
                }),
            );
        }
    }

    fn use_health_potion(&mut self, decision_id: &str) {
        if self.game_over
            || self.player.inventory.health_potion == 0
            || self.player.hp >= self.player.max_hp
        {
            return;
        }
        self.turn += 1;
        let hp_before = self.player.hp;
        self.player.inventory.health_potion -= 1;
        self.player.hp = (self.player.hp + POTION_HEAL).min(self.player.max_hp);
        self.emit_event(
            "user_action",
            json!({
                "action": "use_item", "result": "item_used", "item_type": "health_potion",
                "decision_id": decision_id,
            }),
        );
        self.emit_event(
            "item_result",
            json!({
                "result": "item_used", "item_type": "health_potion",
                "hp_before": hp_before, "hp_after": self.player.hp,
                "healed": self.player.hp - hp_before, "inventory": self.player.inventory,
                "decision_id": decision_id,
            }),
        );
        self.run_enemy_turn();
    }

    fn choose_item_decision(&self) -> Option<Decision> {
        let cautious = self.config.strategy == Strategy::CautiousV1;
        let threshold = if cautious { 2 } else { 3 };
        let incoming = self.incoming_damage_at(self.player.pos, None);
        if self.player.inventory.health_potion > 0
            && self.player.hp < self.player.max_hp
            && (self.player.max_hp - self.player.hp >= POTION_HEAL
                || self.player.hp * threshold <= self.player.max_hp
                || self.player.hp <= incoming)
        {
            return Some(Decision {
                direction: Point::ZERO,
                rule_id: "use_health_potion",
                reason: "Healing is efficient, HP is low, or the next enemy phase could be lethal.",
                action_type: "use_item",
                target: json!({"kind": "inventory_item", "type": "health_potion"}),
                selected_step_danger: Some(self.danger_cost(self.player.pos)),
                progression: None,
                goal_selection: None,
            });
        }
        if self.direction_to_adjacent_enemy().is_some() {
            return None;
        }
        // Cautious never gathers under current threat; its entire item route must be safe.
        if cautious && self.danger_cost(self.player.pos) > 0 {
            return None;
        }
        let limit = if cautious { 4 } else { 8 };
        let mut best: Option<(usize, Point, &FloorItem)> = None;
        for item in &self.items {
            if !self.wants_item(item) {
                continue;
            }
            if let Some((steps, direction)) = self.item_route(item.pos, limit, cautious) {
                if best.as_ref().is_none_or(|(best_steps, _, best_item)| {
                    self.item_priority(item) > self.item_priority(best_item)
                        || (self.item_priority(item) == self.item_priority(best_item)
                            && steps < *best_steps)
                }) {
                    best = Some((steps, direction, item));
                }
            }
        }
        best.map(|(_, direction, item)| Decision {
            direction,
            rule_id: match (cautious, item.kind == "health_potion") {
                (true, true) => "cautious_collect_potion", (false, true) => "collect_nearby_potion",
                (true, false) => "cautious_collect_equipment", (false, false) => "collect_nearby_equipment",
            },
            reason: if item.kind != "health_potion" { "A preferred weapon type or stronger equipment is within the item detour limit." }
                else if cautious { "A potion is within four safe steps, so the cautious strategy makes a short detour." }
                else { "A potion is within eight unobstructed steps, so the aggressive strategy gathers supplies." },
            action_type: "move", target: json!(item),
            selected_step_danger: Some(self.danger_cost(self.player.pos + direction)),
                progression: None,
            goal_selection: None,
        })
    }

    fn item_route(
        &self,
        destination: Point,
        limit: usize,
        safe_only: bool,
    ) -> Option<(usize, Point)> {
        let start = self.player.pos;
        let mut frontier = VecDeque::from([(start, 0)]);
        let mut came_from = HashMap::from([(start, start)]);
        while let Some((current, steps)) = frontier.pop_front() {
            if current == destination {
                return first_step(start, destination, &came_from)
                    .map(|direction| (steps, direction));
            }
            if steps >= limit {
                continue;
            }
            for direction in DIRECTIONS {
                let next = current + direction;
                if came_from.contains_key(&next)
                    || !self.is_walkable(next)
                    || next == self.stairs
                    || self.enemy_at(next).is_some()
                    || (safe_only && self.danger_cost(next) > 0)
                {
                    continue;
                }
                came_from.insert(next, current);
                frontier.push_back((next, steps + 1));
            }
        }
        None
    }

    fn generate_dungeon(&mut self, rng: &mut PortableRng) {
        let area = f64::from(self.config.map_width * self.config.map_height);
        let room_target = ((area / 112.0).round() as usize).max(2);
        for _ in 0..room_target * 8 {
            if self.rooms.len() >= room_target {
                break;
            }
            let width = rng.range_inclusive(MIN_ROOM_SIZE, MAX_ROOM_SIZE);
            let height = rng.range_inclusive(MIN_ROOM_SIZE, MAX_ROOM_SIZE);
            let room = Rect {
                x: rng.range_inclusive(1, self.config.map_width - width - 2),
                y: rng.range_inclusive(1, self.config.map_height - height - 2),
                width,
                height,
            };
            if self
                .rooms
                .iter()
                .any(|existing| room.grown_intersects(*existing))
            {
                continue;
            }
            self.carve_room(room);
            if let Some(previous) = self.rooms.last() {
                self.connect_rooms(previous.center(), room.center(), rng);
            }
            self.rooms.push(room);
        }

        if self.rooms.is_empty() {
            let fallback = Rect {
                x: 4,
                y: 4,
                width: 12,
                height: 10,
            };
            self.carve_room(fallback);
            self.rooms.push(fallback);
        }
    }

    fn carve_room(&mut self, room: Rect) {
        for y in room.y..room.end_y() {
            for x in room.x..room.end_x() {
                self.map[y as usize][x as usize] = true;
            }
        }
    }

    fn connect_rooms(&mut self, first: Point, second: Point, rng: &mut PortableRng) {
        if rng.chance(1, 2) {
            self.carve_horizontal(first.x, second.x, first.y);
            self.carve_vertical(first.y, second.y, second.x);
        } else {
            self.carve_vertical(first.y, second.y, first.x);
            self.carve_horizontal(first.x, second.x, second.y);
        }
    }

    fn carve_horizontal(&mut self, first_x: i32, second_x: i32, y: i32) {
        for x in first_x.min(second_x)..=first_x.max(second_x) {
            self.map[y as usize][x as usize] = true;
        }
    }

    fn carve_vertical(&mut self, first_y: i32, second_y: i32, x: i32) {
        for y in first_y.min(second_y)..=first_y.max(second_y) {
            self.map[y as usize][x as usize] = true;
        }
    }

    fn spawn_enemies(&mut self, rng: &mut PortableRng) {
        if self.rooms.len() >= 3 {
            for room_index in 1..self.rooms.len() - 1 {
                if !rng.chance(3, 4) {
                    continue;
                }
                let room = self.rooms[room_index];
                self.spawn_enemy_in_room(room, rng);
            }
        }
        if self.enemies.is_empty() {
            let room = self.rooms[self.rooms.len() - 1];
            self.spawn_enemy_in_room(room, rng);
        }
    }

    fn spawn_enemy_in_room(&mut self, room: Rect, rng: &mut PortableRng) {
        let mut pos = Point {
            x: rng.range_inclusive(room.x + 1, room.end_x() - 2),
            y: rng.range_inclusive(room.y + 1, room.end_y() - 2),
        };
        if pos == self.player.pos || pos == self.stairs || self.enemy_at(pos).is_some() {
            let Some(free_tile) = self.first_free_tile_in_room(room) else {
                return;
            };
            pos = free_tile;
        }
        let kind = if rng.chance(1, 2) {
            EnemyKind::Melee
        } else {
            EnemyKind::Archer
        };
        let id = format!("enemy-{}", self.next_enemy_id);
        self.next_enemy_id += 1;
        let mut kind_rng = PortableRng::new(PortableRng::derive_seed(
            self.config.scenario_seed,
            "enemy-kind",
            self.player.depth,
            Some(&id),
        ));
        let kind = if kind_rng.chance(1, 3) {
            EnemyKind::Brute
        } else {
            kind
        };
        let depth = self.player.depth as i32;
        let (hp, attack) = match kind {
            EnemyKind::Melee => (8 + depth * 2, 2 + depth),
            EnemyKind::Archer => (5 + depth, 1 + depth / 2),
            EnemyKind::Brute => (14 + depth * 3, 4 + depth),
        };
        self.enemies.push(Enemy {
            id,
            kind,
            windup_target: None,
            pos,
            hp,
            attack,
            defense: 0,
        });
    }

    fn first_free_tile_in_room(&self, room: Rect) -> Option<Point> {
        for y in room.y + 1..room.end_y() - 1 {
            for x in room.x + 1..room.end_x() - 1 {
                let candidate = Point { x, y };
                if candidate != self.player.pos
                    && candidate != self.stairs
                    && self.enemy_at(candidate).is_none()
                {
                    return Some(candidate);
                }
            }
        }
        None
    }

    fn farthest_walkable_tile_from(&self, origin: Point) -> Point {
        let mut best = origin;
        let mut best_distance = -1;
        for y in 0..self.config.map_height {
            for x in 0..self.config.map_width {
                let candidate = Point { x, y };
                if !self.is_walkable(candidate) {
                    continue;
                }
                let distance = origin.distance_squared(candidate);
                if distance > best_distance {
                    best = candidate;
                    best_distance = distance;
                }
            }
        }
        best
    }

    fn run_auto_player_turn(&mut self) {
        let item_decision = self.choose_item_decision();
        let decision = if item_decision
            .as_ref()
            .is_some_and(|d| d.action_type == "use_item")
        {
            item_decision.unwrap()
        } else {
            self.choose_windup_response()
                .or_else(|| {
                    if self.direction_to_adjacent_enemy().is_some() {
                        Some(match self.config.strategy {
                            Strategy::AggressiveV1 => self.choose_aggressive_decision(),
                            Strategy::CautiousV1 => self.choose_cautious_decision(),
                        })
                    } else {
                        self.choose_goal_decision()
                    }
                })
                .unwrap_or_else(|| match self.config.strategy {
                    Strategy::AggressiveV1 => self.choose_aggressive_decision(),
                    Strategy::CautiousV1 => self.choose_cautious_decision(),
                })
        };
        if matches!(
            decision.rule_id,
            "hunt_nearest_enemy" | "seek_blocking_enemy"
        ) {
            self.aggressive_target_id = decision.target["id"].as_str().map(str::to_owned);
        }
        if decision.rule_id == "hunt_for_growth" {
            self.growth_target_id = decision.target["id"].as_str().map(str::to_owned);
        } else if decision.rule_id == "descend_for_progress" {
            self.growth_target_id = None;
        }
        // A dead/disappeared goal is re-evaluated on the next discretionary turn.
        let decision_id = self.emit_decision(&decision);
        if decision.action_type == "use_item" {
            self.use_health_potion(&decision_id);
        } else if decision.action_type == "ranged_attack" {
            self.player_shoot(decision.target["id"].as_str().unwrap(), &decision_id);
        } else if decision.direction == Point::ZERO {
            self.turn += 1;
            self.emit_event(
                "user_action",
                json!({
                    "action": "auto_wait",
                    "result": "turn_advanced",
                    "decision_id": decision_id,
                }),
            );
            self.run_enemy_turn();
        } else {
            self.player_act(decision.direction, &decision_id);
        }
    }

    fn choose_windup_response(&self) -> Option<Decision> {
        if self.config.strategy != Strategy::CautiousV1 {
            return None;
        }
        let enemy = self.enemies.iter().find(|enemy| {
            enemy.kind == EnemyKind::Brute && enemy.windup_target == Some(self.player.pos)
        })?;
        let can_kill = enemy.hp <= Self::damage(self.effective_attack(), enemy.defense)
            && (enemy.pos.manhattan_distance(self.player.pos) == 1
                || self.can_player_shoot_from(self.player.pos, enemy.pos));
        if can_kill && self.incoming_damage_at(self.player.pos, Some(&enemy.id)) < self.player.hp {
            return Some(Decision {
                rule_id: "interrupt_windup", reason: "The marked Brute can be killed now; interrupt its strike before the enemy phase.",
                action_type: "attack", direction: enemy.pos - self.player.pos,
                target: self.enemy_snapshot(enemy), selected_step_danger: Some(self.danger_cost(self.player.pos)), progression: None,
            goal_selection: None,
            });
        }
        let mut best = None;
        for direction in DIRECTIONS {
            let next = self.player.pos + direction;
            if !self.is_walkable(next) || self.enemy_at(next).is_some() {
                continue;
            }
            let score = if next == self.stairs {
                -1
            } else {
                self.incoming_damage_at(next, None) * 100
                    + self.danger_cost(next)
                    + self.revisit_cost(next)
                    + next.manhattan_distance(self.stairs)
            };
            if best.is_none_or(|(_, old_score)| score < old_score) {
                best = Some((direction, score));
            }
        }
        let (direction, _) = best?;
        Some(Decision {
            rule_id: "evade_windup", reason: "A Brute marked this tile for its next heavy strike; leave the marked tile before it lands.",
            action_type: "move", direction, target: self.enemy_snapshot(enemy),
            selected_step_danger: Some(self.danger_cost(self.player.pos + direction)), progression: None,
            goal_selection: None,
        })
    }

    fn can_player_shoot_from(&self, origin: Point, target: Point) -> bool {
        self.weapon_kind() == "bow"
            && origin != target
            && origin.distance_squared(target) <= BOW_RANGE * BOW_RANGE
            && self.has_line_of_sight(origin, target)
    }
    #[cfg(test)]
    fn choose_bow_decision(&self) -> Option<Decision> {
        if self.weapon_kind() != "bow" || self.direction_to_adjacent_enemy().is_some() {
            return None;
        }
        if self.config.strategy == Strategy::CautiousV1
            && self.player.pos.manhattan_distance(self.stairs) == 1
        {
            return None;
        }
        let mut best: Option<&Enemy> = None;
        for enemy in &self.enemies {
            if !self.can_player_shoot_from(self.player.pos, enemy.pos) {
                continue;
            }
            if self.growth_target_id.as_deref() == Some(enemy.id.as_str()) {
                best = Some(enemy);
                break;
            }
            if best.is_none_or(|prior| {
                self.player.pos.distance_squared(enemy.pos)
                    < self.player.pos.distance_squared(prior.pos)
            }) {
                best = Some(enemy);
            }
        }
        let enemy = best?;
        let excluded = (enemy.hp <= Self::damage(self.effective_attack(), enemy.defense))
            .then_some(enemy.id.as_str());
        if self.incoming_damage_at(self.player.pos, excluded) >= self.player.hp {
            return None;
        }
        Some(Decision {
            rule_id: "shoot_in_range",
            reason:
                "The bow has a clear shot within five tiles; fire in place at its lower damage.",
            action_type: "ranged_attack",
            direction: Point::ZERO,
            target: self.enemy_snapshot(enemy),
            selected_step_danger: Some(self.danger_cost(self.player.pos)),
            progression: None,
            goal_selection: None,
        })
    }
    fn player_shoot(&mut self, enemy_id: &str, decision_id: &str) -> bool {
        if self.game_over {
            return false;
        }
        let Some(index) = self.enemies.iter().position(|enemy| enemy.id == enemy_id) else {
            return false;
        };
        if !self.can_player_shoot_from(self.player.pos, self.enemies[index].pos) {
            return false;
        }
        self.turn += 1;
        self.emit_event(
            "user_action",
            json!({"action": "shoot", "result": "arrow_fired", "from": self.player.pos,
            "target": self.enemies[index].pos, "enemy_id": enemy_id, "decision_id": decision_id}),
        );
        self.attack_enemy_with_mode(index, true);
        self.run_enemy_turn();
        true
    }

    fn choose_aggressive_decision(&self) -> Decision {
        if let Some(direction) = self.direction_to_adjacent_enemy() {
            let enemy = &self.enemies[self
                .enemy_at(self.player.pos + direction)
                .expect("adjacent enemy remains present")];
            return Decision {
                direction,
                rule_id: "attack_adjacent_enemy",
                reason: "An enemy is adjacent, so the default strategy attacks it.",
                action_type: "attack",
                target: self.enemy_snapshot(enemy),
                selected_step_danger: None,
                progression: None,
                goal_selection: None,
            };
        }
        if let Some(decision) = self.choose_progression_decision() {
            return decision;
        }
        if !self.enemies.is_empty() {
            let (enemy, direction) = self.aggressive_pursuit();
            let has_path = direction != Point::ZERO;
            return Decision {
                direction,
                rule_id: if has_path {
                    "hunt_nearest_enemy"
                } else {
                    "wait_no_path_to_enemy"
                },
                reason: if has_path {
                    "The aggressive strategy keeps pursuing its chosen enemy until defeated or unreachable."
                } else {
                    "No walkable path to the nearest enemy was found."
                },
                action_type: if has_path { "move" } else { "wait" },
                target: self.enemy_snapshot(enemy),
                selected_step_danger: None,
                progression: None,
                goal_selection: None,
            };
        }
        let direction = self
            .find_next_step_toward(self.stairs)
            .unwrap_or(Point::ZERO);
        let has_path = direction != Point::ZERO;
        Decision {
            direction,
            rule_id: if has_path {
                "seek_stairs"
            } else {
                "wait_no_path_to_stairs"
            },
            reason: if has_path {
                "No enemies remain, so the default strategy heads for the stairs."
            } else {
                "No walkable path to the stairs was found."
            },
            action_type: if has_path { "move" } else { "wait" },
            target: json!({"kind": "stairs", "pos": self.stairs}),
            selected_step_danger: None,
            progression: None,
            goal_selection: None,
        }
    }

    fn choose_cautious_decision(&self) -> Decision {
        let adjacent_direction = self.direction_to_adjacent_enemy();
        let stairs_direction = self.find_low_risk_step_toward(self.stairs);
        if let Some(direction) = adjacent_direction {
            let enemy_index = self
                .enemy_at(self.player.pos + direction)
                .expect("adjacent enemy remains present");
            let can_escape_via_stairs = stairs_direction
                .is_some_and(|stairs_step| self.player.pos + stairs_step == self.stairs);
            if self.enemies[enemy_index].kind != EnemyKind::Archer && !can_escape_via_stairs {
                return Decision {
                    direction,
                    rule_id: if self.enemies[enemy_index].kind == EnemyKind::Brute {
                        "attack_adjacent_brute"
                    } else {
                        "attack_pursuing_melee"
                    },
                    reason: if self.enemies[enemy_index].kind == EnemyKind::Brute {
                        "A slow Brute is adjacent; attack during its windup unless the marked strike must be evaded."
                    } else {
                        "An adjacent melee enemy can match the player's speed, so retreat would not create distance."
                    },
                    action_type: "attack",
                    target: self.enemy_snapshot(&self.enemies[enemy_index]),
                    selected_step_danger: Some(self.danger_cost(self.player.pos)),
                    progression: None,
                    goal_selection: None,
                };
            }
        }
        if adjacent_direction.is_none() {
            if let Some(decision) = self.choose_progression_decision() {
                return decision;
            }
        }
        if let Some(direction) = stairs_direction {
            let retreating = adjacent_direction.is_some();
            return Decision {
                direction,
                rule_id: if retreating {
                    "retreat_from_adjacent_enemy"
                } else {
                    "cautious_seek_stairs"
                },
                reason: if retreating {
                    "An enemy is adjacent, so the cautious strategy retreats toward the stairs."
                } else {
                    "The cautious strategy takes a low-risk route, penalizing repeated visits to avoid movement loops."
                },
                action_type: "move",
                target: json!({"kind": "stairs", "pos": self.stairs}),
                selected_step_danger: Some(self.danger_cost(self.player.pos + direction)),
                progression: None,
                goal_selection: None,
            };
        }
        if let Some(direction) = adjacent_direction {
            let enemy_index = self
                .enemy_at(self.player.pos + direction)
                .expect("adjacent enemy remains present");
            return Decision {
                direction,
                rule_id: "attack_blocking_enemy",
                reason: "No route to the stairs is open, so the cautious strategy fights.",
                action_type: "attack",
                target: self.enemy_snapshot(&self.enemies[enemy_index]),
                selected_step_danger: Some(self.danger_cost(self.player.pos)),
                progression: None,
                goal_selection: None,
            };
        }
        if !self.enemies.is_empty() {
            let (enemy, direction) = self.aggressive_pursuit();
            if direction != Point::ZERO {
                return Decision {
                    direction,
                    rule_id: "seek_blocking_enemy",
                    reason: "The stairs route is blocked; approach a reachable enemy to reopen it.",
                    action_type: "move",
                    target: self.enemy_snapshot(enemy),
                    selected_step_danger: Some(self.danger_cost(self.player.pos + direction)),
                    progression: None,
                    goal_selection: None,
                };
            }
        }
        Decision {
            direction: Point::ZERO,
            rule_id: "wait_no_safe_path",
            reason: "No route to the stairs or adjacent target is currently available.",
            action_type: "wait",
            target: json!({"kind": "stairs", "pos": self.stairs}),
            selected_step_danger: Some(self.danger_cost(self.player.pos)),
            progression: None,
            goal_selection: None,
        }
    }

    // Static, bounded estimates; enemy movement and future pickups are not simulated.
    fn progression_route(&self, destination: Point, limit: usize) -> Option<Vec<Point>> {
        let start = self.player.pos;
        let mut frontier = VecDeque::from([(start, 0)]);
        let mut came_from = HashMap::from([(start, start)]);
        while let Some((mut current, steps)) = frontier.pop_front() {
            if current == destination {
                let mut route = Vec::new();
                while current != start {
                    route.push(current);
                    current = came_from[&current];
                }
                route.reverse();
                return (!route.is_empty()).then_some(route);
            }
            if steps >= limit {
                continue;
            }
            for direction in DIRECTIONS {
                let next = current + direction;
                if came_from.contains_key(&next) || !self.is_walkable(next) {
                    continue;
                }
                if next != destination && (next == self.stairs || self.enemy_at(next).is_some()) {
                    continue;
                }
                came_from.insert(next, current);
                frontier.push_back((next, steps + 1));
            }
        }
        None
    }

    fn incoming_damage_at(&self, pos: Point, excluded_id: Option<&str>) -> i32 {
        self.enemies
            .iter()
            .filter(|enemy| Some(enemy.id.as_str()) != excluded_id)
            .map(|enemy| match enemy.kind {
                EnemyKind::Brute
                    if enemy.windup_target == Some(pos)
                        && enemy.pos.manhattan_distance(pos) == 1 =>
                {
                    Self::damage(enemy.attack, self.effective_defense())
                }
                EnemyKind::Melee if enemy.pos.manhattan_distance(pos) == 1 => {
                    Self::damage(enemy.attack, self.effective_defense())
                }
                EnemyKind::Archer
                    if self.has_line_of_sight(enemy.pos, pos)
                        && enemy.pos.distance_squared(pos) <= 2 =>
                {
                    Self::damage(1, self.effective_defense())
                }
                EnemyKind::Archer
                    if self.has_line_of_sight(enemy.pos, pos)
                        && enemy.pos.distance_squared(pos) <= 49 =>
                {
                    Self::damage(enemy.attack, self.effective_defense())
                }
                _ => 0,
            })
            .sum()
    }

    fn goal_evaluation(
        &self,
        kind: &str,
        id: &str,
        benefit: i32,
        damage: i32,
        turns: i32,
        repeated: i32,
    ) -> Value {
        let remaining = self.player.hp - damage;
        let risk = damage * 20 / self.player.hp.max(1) + (6 - remaining).max(0) * 4;
        let utility = benefit - risk - turns - repeated;
        json!({"kind": kind, "id": id, "benefit": benefit, "estimated_damage": damage,
            "risk": risk, "turns": turns, "revisit_penalty": repeated, "utility": utility,
            "eligible": remaining > 0 && self.goal_policy.weight(kind) > 0,
            "rejection": if remaining <= 0 { "estimated_lethal" } else if self.goal_policy.weight(kind) == 0 { "disabled" } else { "" }})
    }
    fn goal_candidates(&self) -> Vec<GoalCandidate> {
        let mut candidates = Vec::new();
        for enemy in &self.enemies {
            let Some(route) = self.progression_route(enemy.pos, 12) else {
                continue;
            };
            let hit_damage = Self::damage(self.effective_attack(), enemy.defense);
            let attack_turns = (enemy.hp + hit_damage - 1) / hit_damage;
            let xp_gain = if enemy.kind != EnemyKind::Melee { 5 } else { 3 };
            let mut projected_xp = self.player.xp + xp_gain;
            let mut projected_level = self.player.level;
            while projected_xp >= projected_level * 8 {
                projected_xp -= projected_level * 8;
                projected_level += 1;
            }
            let levels_gained = projected_level - self.player.level;
            let mut approach = Vec::new();
            if !self.can_player_shoot_from(self.player.pos, enemy.pos) {
                for pos in &route[..route.len() - 1] {
                    approach.push(*pos);
                    if self.can_player_shoot_from(*pos, enemy.pos) {
                        break;
                    }
                }
            }
            let attack_pos = approach.last().copied().unwrap_or(self.player.pos);
            let retaliation_turns = if enemy.kind == EnemyKind::Brute {
                let contact_turns =
                    (attack_turns - 1 - 2 * (attack_pos.manhattan_distance(enemy.pos) - 1).max(0))
                        .max(0);
                (contact_turns + i32::from(enemy.windup_target == Some(attack_pos))) / 2
            } else if enemy.kind == EnemyKind::Melee {
                (attack_turns - attack_pos.manhattan_distance(enemy.pos)).max(0)
            } else {
                attack_turns - 1
            };
            let target_attack =
                if enemy.kind != EnemyKind::Archer || attack_pos.distance_squared(enemy.pos) > 2 {
                    enemy.attack
                } else {
                    1
                };
            let mut damage =
                retaliation_turns * Self::damage(target_attack, self.effective_defense());
            damage += attack_turns * self.incoming_damage_at(attack_pos, Some(&enemy.id));
            let mut repeated_cost = 0;
            for pos in &approach {
                damage += self.incoming_damage_at(*pos, None);
                repeated_cost += self.revisit_cost(*pos);
            }

            let benefit = xp_gain as i32 * 2
                + 2
                + levels_gained as i32 * (8 + (MAX_DEPTH - 1 - self.player.depth) as i32 * 6);
            let mut direction = if self.can_player_shoot_from(self.player.pos, enemy.pos) {
                Point::ZERO
            } else {
                self.find_goal_step_toward(
                    enemy.pos,
                    self.config.strategy == Strategy::CautiousV1,
                    true,
                )
                .unwrap_or(Point::ZERO)
            };
            if direction == Point::ZERO && !self.can_player_shoot_from(self.player.pos, enemy.pos) {
                continue;
            }
            // After dodging, let the slow Brute close the final tile. Re-entering
            // its reach would start another windup before we can land a hit.
            if self.config.strategy == Strategy::CautiousV1
                && enemy.kind == EnemyKind::Brute
                && !self.can_player_shoot_from(self.player.pos, enemy.pos)
                && self.player.pos.manhattan_distance(enemy.pos) == 2
                && self.can_enemy_see_player(enemy.pos)
            {
                let next =
                    enemy.pos + self.choose_enemy_step(enemy.pos, self.player.pos - enemy.pos);
                if next != enemy.pos
                    && self.enemy_at(next).is_none()
                    && next.manhattan_distance(self.player.pos) == 1
                {
                    direction = Point::ZERO;
                }
            }
            candidates.push(GoalCandidate {
                kind: "enemy",
                id: enemy.id.clone(),
                direction,
                target: self.enemy_snapshot(enemy),
                ranged: self.can_player_shoot_from(self.player.pos, enemy.pos),
                evaluation: self.goal_evaluation(
                    "enemy",
                    &enemy.id,
                    benefit,
                    damage,
                    approach.len() as i32 + attack_turns,
                    repeated_cost,
                ),
            });
        }
        for item in &self.items {
            if !self.wants_item(item) {
                continue;
            }
            let Some(route) = self.progression_route(item.pos, 12) else {
                continue;
            };
            let Some(direction) = self.find_goal_step_toward(
                item.pos,
                self.config.strategy == Strategy::CautiousV1,
                true,
            ) else {
                continue;
            };
            let damage = route
                .iter()
                .map(|p| self.incoming_damage_at(*p, None))
                .sum();
            let repeated = route.iter().map(|p| self.revisit_cost(*p)).sum();
            let benefit = match item.kind {
                "health_potion" => {
                    POTION_HEAL.min(self.player.max_hp - self.player.hp) * 2
                        + (INVENTORY_CAPACITY - self.player.inventory.health_potion) as i32 * 4
                }
                "armor" => (item.defense_bonus - self.defense_bonus()).max(0) * 8,
                _ => {
                    let raw = self.player.base_attack + item.attack_bonus;
                    let attack = if item.weapon_kind == Some("bow") {
                        (raw / 2).max(1)
                    } else {
                        raw
                    };
                    (attack - self.effective_attack()).max(0) * 6
                        + self.item_priority(item) as i32 * 8
                }
            };
            candidates.push(GoalCandidate {
                kind: "item",
                id: item.id.clone(),
                direction,
                target: json!(item),
                ranged: false,
                evaluation: self.goal_evaluation(
                    "item",
                    &item.id,
                    benefit,
                    damage,
                    route.len() as i32,
                    repeated,
                ),
            });
        }
        if let Some(route) = self.progression_route(
            self.stairs,
            (self.config.map_width * self.config.map_height) as usize,
        ) {
            if let Some(direction) = self.find_low_risk_step_toward(self.stairs) {
                let damage = route
                    .iter()
                    .map(|p| self.incoming_damage_at(*p, None))
                    .sum();
                let repeated = route.iter().map(|p| self.revisit_cost(*p)).sum();
                let benefit = 8
                    + 4.min(self.player.max_hp - self.player.hp) * 2
                    + if self.player.depth == MAX_DEPTH - 1 {
                        20
                    } else {
                        0
                    };
                candidates.push(GoalCandidate {
                    kind: "stairs",
                    id: "stairs".into(),
                    direction,
                    target: json!({"kind": "stairs", "pos": self.stairs}),
                    ranged: false,
                    evaluation: self.goal_evaluation(
                        "stairs",
                        "stairs",
                        benefit,
                        damage,
                        route.len().min(8) as i32,
                        repeated,
                    ),
                });
            }
        }
        candidates
    }
    fn choose_goal_decision(&mut self) -> Option<Decision> {
        let candidates = self.goal_candidates();
        let eligible = |c: &GoalCandidate| c.evaluation["eligible"].as_bool() == Some(true);
        let retained = self.selected_goal.as_ref().and_then(|(kind, id, hp)| {
            if (self.player.hp - hp).abs() >= 4 {
                return None;
            }
            candidates
                .iter()
                .find(|c| c.kind == kind && c.id == *id && eligible(c))
                .cloned()
        });
        let mut lottery = Vec::new();
        for kind in ["enemy", "item", "stairs"] {
            let mut best: Option<&GoalCandidate> = None;
            for candidate in candidates.iter().filter(|c| c.kind == kind && eligible(c)) {
                if best.is_none_or(|b| {
                    candidate.evaluation["utility"].as_i64() > b.evaluation["utility"].as_i64()
                }) {
                    best = Some(candidate);
                }
            }
            if let Some(best) = best {
                lottery.push(best.clone());
            }
        }
        if lottery.is_empty() {
            self.selected_goal = None;
            return None;
        }
        let max_utility = lottery
            .iter()
            .map(|c| c.evaluation["utility"].as_i64().unwrap() as i32)
            .max()
            .unwrap();
        let masses: Vec<u32> = lottery
            .iter()
            .map(|c| {
                goal_mass(
                    self.goal_policy.weight(c.kind),
                    max_utility - c.evaluation["utility"].as_i64().unwrap() as i32,
                    self.goal_policy.temperature,
                )
            })
            .collect();
        let total: u32 = masses.iter().sum();
        let before = self.policy_rng.state;
        let draw = if retained.is_some() {
            None
        } else {
            Some(self.policy_rng.range_inclusive(0, total as i32 - 1))
        };
        let selected = if let Some(c) = &retained {
            c.clone()
        } else {
            let mut cursor = draw.unwrap() as u32;
            let index = masses
                .iter()
                .position(|mass| {
                    if cursor < *mass {
                        true
                    } else {
                        cursor -= mass;
                        false
                    }
                })
                .unwrap();
            lottery[index].clone()
        };
        if retained.is_none() {
            self.selected_goal = Some((selected.kind.into(), selected.id.clone(), self.player.hp));
        }
        let distribution: Vec<Value> = lottery
            .iter()
            .zip(&masses)
            .map(|(c, mass)| json!({"kind":c.kind,"id":c.id,"mass":mass,"total_mass":total}))
            .collect();
        let selection = json!({"selected_kind":selected.kind, "selected_id":selected.id, "target_retained":retained.is_some(),
            "draw":draw, "rng_before":before,"rng_after":self.policy_rng.state,"distribution":distribution,
            "candidates": candidates.iter().map(|c| c.evaluation.clone()).collect::<Vec<_>>()});
        Some(Decision { direction:selected.direction, rule_id:"weighted_goal", reason:"Select a goal using category preferences and benefit minus risk; retain a viable target until completion or a material HP change.",
            action_type:if selected.ranged {"ranged_attack"} else {"move"}, target:selected.target,
            selected_step_danger:Some(self.danger_cost(self.player.pos + selected.direction)), progression:None, goal_selection:Some(selection) })
    }

    fn choose_progression_decision(&self) -> Option<Decision> {
        let cautious = self.config.strategy == Strategy::CautiousV1;
        let stairs_route = self.progression_route(
            self.stairs,
            (self.config.map_width * self.config.map_height) as usize,
        )?;
        let stairs_direction = self.find_low_risk_step_toward(self.stairs)?;
        let stairs_healing = 4.min(self.player.max_hp - self.player.hp);
        let mut stairs_score =
            if cautious { 16 } else { 8 } + stairs_healing * 2 - (stairs_route.len().min(8) as i32);
        if self.player.depth == MAX_DEPTH - 1 {
            stairs_score += 20;
        }
        let mut candidates = Vec::new();
        let mut best: Option<(&Enemy, Point, i32)> = None;
        let mut locked = None;
        for enemy in &self.enemies {
            let Some(route) = self.progression_route(enemy.pos, if cautious { 6 } else { 12 })
            else {
                candidates.push(
                    json!({"enemy_id": enemy.id, "eligible": false, "rejection": "out_of_reach"}),
                );
                continue;
            };
            let hit_damage = Self::damage(self.effective_attack(), enemy.defense);
            let attack_turns = (enemy.hp + hit_damage - 1) / hit_damage;
            let xp_gain = if enemy.kind != EnemyKind::Melee { 5 } else { 3 };
            let mut projected_xp = self.player.xp + xp_gain;
            let mut projected_level = self.player.level;
            while projected_xp >= projected_level * 8 {
                projected_xp -= projected_level * 8;
                projected_level += 1;
            }
            let levels_gained = projected_level - self.player.level;
            let mut approach = Vec::new();
            if !self.can_player_shoot_from(self.player.pos, enemy.pos) {
                for pos in &route[..route.len() - 1] {
                    approach.push(*pos);
                    if self.can_player_shoot_from(*pos, enemy.pos) {
                        break;
                    }
                }
            }
            let attack_pos = approach.last().copied().unwrap_or(self.player.pos);
            let retaliation_turns = if enemy.kind == EnemyKind::Brute {
                let contact_turns =
                    (attack_turns - 1 - 2 * (attack_pos.manhattan_distance(enemy.pos) - 1).max(0))
                        .max(0);
                (contact_turns + i32::from(enemy.windup_target == Some(attack_pos))) / 2
            } else if enemy.kind == EnemyKind::Melee {
                (attack_turns - attack_pos.manhattan_distance(enemy.pos)).max(0)
            } else {
                attack_turns - 1
            };
            let target_attack =
                if enemy.kind != EnemyKind::Archer || attack_pos.distance_squared(enemy.pos) > 2 {
                    enemy.attack
                } else {
                    1
                };
            let mut damage =
                retaliation_turns * Self::damage(target_attack, self.effective_defense());
            damage += attack_turns * self.incoming_damage_at(attack_pos, Some(&enemy.id));
            let mut repeated_cost = 0;
            for pos in &approach {
                damage += self.incoming_damage_at(*pos, None);
                repeated_cost += self.revisit_cost(*pos);
            }
            let mut score = xp_gain as i32 * if cautious { 2 } else { 4 }
                + levels_gained as i32 * (8 + (MAX_DEPTH - 1 - self.player.depth) as i32 * 6);
            score -= approach.len() as i32 * if cautious { 2 } else { 1 }
                + attack_turns
                + damage * if cautious { 3 } else { 2 }
                + repeated_cost;
            let rejection = if self.player.hp - damage <= if cautious { 4 } else { 2 } {
                "hp_reserve"
            } else if cautious && enemy.kind == EnemyKind::Archer && self.weapon_kind() != "bow" {
                "mobile_target"
            } else if cautious && levels_gained == 0 {
                "no_level_up"
            } else {
                ""
            };
            candidates.push(json!({"enemy_id": enemy.id, "steps": approach.len(), "attack_pos": attack_pos, "attack_turns": attack_turns,
                "xp_gain": xp_gain, "levels_gained": levels_gained, "estimated_damage": damage, "score": score,
                "eligible": rejection.is_empty(), "rejection": rejection, "revisit_penalty": repeated_cost}));
            if !rejection.is_empty() {
                continue;
            }
            let choice = (
                enemy,
                approach
                    .first()
                    .map_or(Point::ZERO, |pos| *pos - self.player.pos),
                score,
            );
            if best.is_none_or(|(_, _, best_score)| score > best_score) {
                best = Some(choice);
            }
            if self.growth_target_id.as_deref() == Some(enemy.id.as_str()) && score > stairs_score {
                locked = Some(choice);
            }
        }
        if locked.is_some() {
            best = locked;
        }
        let fight = best.is_some_and(|(_, _, score)| score > stairs_score);
        let comparison = json!({"stairs_steps": stairs_route.len(), "stairs_healing": stairs_healing,
            "stairs_score": stairs_score, "candidates": candidates, "selected": if fight {"combat"} else {"stairs"},
            "selected_enemy_id": if fight {Some(best.unwrap().0.id.as_str())} else {None}, "target_retained": fight && locked.is_some()});
        let direction = if fight {
            best.unwrap().1
        } else {
            stairs_direction
        };
        Some(Decision {
            rule_id: if fight {
                "hunt_for_growth"
            } else {
                "descend_for_progress"
            },
            reason: if fight {
                "A survivable fight offers more XP and level-up value than descending; keep the selected target while that remains true."
            } else {
                "Descending offers more progress, recovery or completion value than the available growth fights."
            },
            action_type: if fight && direction == Point::ZERO {
                "ranged_attack"
            } else {
                "move"
            },
            direction,
            selected_step_danger: Some(self.danger_cost(self.player.pos + direction)),
            target: if fight {
                self.enemy_snapshot(best.unwrap().0)
            } else {
                json!({"kind": "stairs", "pos": self.stairs})
            },
            progression: Some(comparison),
            goal_selection: None,
        })
    }

    fn emit_decision(&mut self, decision: &Decision) -> String {
        self.decision_sequence += 1;
        let run_id = self
            .logger
            .as_ref()
            .map(|logger| logger.run_id.as_str())
            .unwrap_or("unlogged");
        let decision_id = format!("{run_id}-decision-{}", self.decision_sequence);
        let mut observation = json!({
            "player_pos": self.player.pos,
            "hp": self.player.hp,
            "max_hp": self.player.max_hp,
            "level": self.player.level,
            "xp": self.player.xp,
            "xp_to_next_level": self.player.level * 8 - self.player.xp,
            "enemy_count": self.enemies.len(),
            "enemies": self.enemy_snapshots(),
            "stairs_pos": self.stairs,
            "stairs_distance_squared": self.player.pos.distance_squared(self.stairs),
            "current_danger": self.danger_cost(self.player.pos),
            "current_tile_visits": self.navigation_visits.get(&self.player.pos).copied().unwrap_or(0),
            "items": self.items,
            "inventory": self.player.inventory,
        });
        if let Some(progression) = &decision.progression {
            observation["progression"] = progression.clone();
        }
        if let Some(selection) = &decision.goal_selection {
            observation["goal_selection"] = selection.clone();
        }
        if decision.action_type == "move" {
            observation["selected_step_revisit_cost"] =
                json!(self.revisit_cost(self.player.pos + decision.direction));
        }
        if let Some(danger) = decision.selected_step_danger {
            observation["selected_step_danger"] = json!(danger);
        }
        self.emit_event(
            "decision",
            json!({
                "decision_id": decision_id,
                "strategy_id": self.config.strategy.id(),
                "rule_id": decision.rule_id,
                "reason": decision.reason,
                "action_turn": self.turn + 1,
                "observation": observation,
                "action": {
                    "type": decision.action_type,
                    "direction": decision.direction,
                    "target": decision.target,
                },
            }),
        );
        decision_id
    }

    fn revisit_cost(&self, pos: Point) -> i32 {
        // First arrival and one legitimate return are free. Repetition grows costly.
        self.navigation_visits
            .get(&pos)
            .copied()
            .unwrap_or(0)
            .saturating_sub(2) as i32
            * 8
    }

    fn find_next_step_toward(&self, destination: Point) -> Option<Point> {
        if self.navigation_visits.values().any(|visits| *visits > 2) {
            return self.find_weighted_step_toward(destination, false);
        }
        let start = self.player.pos;
        let mut frontier = VecDeque::from([start]);
        let mut came_from = HashMap::from([(start, start)]);
        while let Some(current) = frontier.pop_front() {
            if current == destination {
                break;
            }
            for direction in DIRECTIONS {
                let next = current + direction;
                if came_from.contains_key(&next) || !self.is_path_walkable(next, destination) {
                    continue;
                }
                frontier.push_back(next);
                came_from.insert(next, current);
            }
        }
        first_step(start, destination, &came_from)
    }

    fn find_low_risk_step_toward(&self, destination: Point) -> Option<Point> {
        self.find_weighted_step_toward(destination, true)
    }

    fn find_weighted_step_toward(&self, destination: Point, use_danger: bool) -> Option<Point> {
        self.find_goal_step_toward(destination, use_danger, false)
    }
    fn find_goal_step_toward(
        &self,
        destination: Point,
        use_danger: bool,
        avoid_stairs: bool,
    ) -> Option<Point> {
        let start = self.player.pos;
        let mut frontier = vec![start];
        let mut came_from = HashMap::from([(start, start)]);
        let mut costs = HashMap::from([(start, 0_i32)]);
        while !frontier.is_empty() {
            let mut best_index = 0;
            for index in 1..frontier.len() {
                if costs[&frontier[index]] < costs[&frontier[best_index]] {
                    best_index = index;
                }
            }
            let current = frontier.remove(best_index);
            if current == destination {
                break;
            }
            for direction in DIRECTIONS {
                let next = current + direction;
                if !self.is_path_walkable(next, destination)
                    || (avoid_stairs && next == self.stairs)
                {
                    continue;
                }
                let danger = if use_danger {
                    self.danger_cost(next)
                } else {
                    0
                };
                let new_cost = costs[&current] + 1 + danger + self.revisit_cost(next);
                if !costs.contains_key(&next) || new_cost < costs[&next] {
                    costs.insert(next, new_cost);
                    came_from.insert(next, current);
                    if !frontier.contains(&next) {
                        frontier.push(next);
                    }
                }
            }
        }
        first_step(start, destination, &came_from)
    }

    fn is_path_walkable(&self, pos: Point, destination: Point) -> bool {
        self.is_walkable(pos) && (pos == destination || self.enemy_at(pos).is_none())
    }

    fn danger_cost(&self, pos: Point) -> i32 {
        self.enemies
            .iter()
            .map(|enemy| match enemy.kind {
                EnemyKind::Archer if !self.has_line_of_sight(enemy.pos, pos) => 0,
                EnemyKind::Archer => match pos.distance_squared(enemy.pos) {
                    distance if distance <= 2 => 30,
                    distance if distance <= 49 => 12,
                    distance if distance <= 80 => 3,
                    _ => 0,
                },
                EnemyKind::Brute => {
                    if enemy.windup_target == Some(pos) {
                        45
                    } else {
                        match pos.manhattan_distance(enemy.pos) {
                            1 => 12,
                            2 => 4,
                            _ => 0,
                        }
                    }
                }
                EnemyKind::Melee => match pos.manhattan_distance(enemy.pos) {
                    1 => 30,
                    2 => 8,
                    _ => 0,
                },
            })
            .sum()
    }

    fn direction_to_adjacent_enemy(&self) -> Option<Point> {
        DIRECTIONS
            .into_iter()
            .find(|direction| self.enemy_at(self.player.pos + *direction).is_some())
    }

    fn aggressive_pursuit(&self) -> (&Enemy, Point) {
        if let Some(enemy) = self
            .enemies
            .iter()
            .find(|enemy| self.aggressive_target_id.as_deref() == Some(enemy.id.as_str()))
        {
            if let Some(direction) = self.find_next_step_toward(enemy.pos) {
                return (enemy, direction);
            }
        }
        let mut candidates: Vec<_> = self.enemies.iter().collect();
        candidates.sort_by_key(|enemy| self.player.pos.distance_squared(enemy.pos));
        for enemy in &candidates {
            if let Some(direction) = self.find_next_step_toward(enemy.pos) {
                return (enemy, direction);
            }
        }
        (candidates[0], Point::ZERO)
    }

    fn player_act(&mut self, direction: Point, decision_id: &str) {
        let target = self.player.pos + direction;
        if !self.is_walkable(target) {
            self.emit_event(
                "user_action",
                json!({
                    "action": "move",
                    "result": "blocked_wall",
                    "decision_id": decision_id,
                    "direction": direction,
                    "from": self.player.pos,
                    "target": target,
                }),
            );
            return;
        }
        self.turn += 1;
        if let Some(enemy_index) = self.enemy_at(target) {
            self.emit_event(
                "user_action",
                json!({
                    "action": "attack",
                    "result": "enemy_targeted",
                    "decision_id": decision_id,
                    "enemy_id": self.enemies[enemy_index].id,
                    "direction": direction,
                    "from": self.player.pos,
                    "target": target,
                }),
            );
            self.attack_enemy(enemy_index);
        } else {
            let from = self.player.pos;
            self.player.pos = target;
            *self.navigation_visits.entry(target).or_default() += 1;
            self.emit_event(
                "user_action",
                json!({
                    "action": "move",
                    "result": "moved",
                    "decision_id": decision_id,
                    "direction": direction,
                    "from": from,
                    "target": target,
                }),
            );
            self.pick_up_items(decision_id);
            if self.player.pos == self.stairs {
                let from_depth = self.player.depth;
                let hp_before = self.player.hp;
                self.emit_event(
                    "user_action",
                    json!({
                        "action": "descend",
                        "result": "stairs_used",
                        "decision_id": decision_id,
                        "from_depth": from_depth,
                        "hp_before": hp_before,
                    }),
                );
                self.player.depth += 1;
                self.player.score += 3;
                self.player.hp = (self.player.hp + 4).min(self.player.max_hp);
                self.emit_event(
                    "floor_descend",
                    json!({"to_depth": self.player.depth, "hp_after": self.player.hp}),
                );
                if self.player.depth >= MAX_DEPTH {
                    self.game_over = true;
                    self.run_outcome = Some(RunOutcome::DungeonCleared);
                    self.emit_event(
                        "battle_result",
                        json!({
                            "result": "dungeon_cleared",
                            "final_depth": self.player.depth,
                            "final_gold": self.player.gold,
                            "final_score": self.player.score,
                            "turns": self.turn,
                            "strategy_id": self.config.strategy.id(),
                            "scenario_seed": self.config.scenario_seed,
                        }),
                    );
                    return;
                }
                self.new_floor();
                return;
            }
        }
        self.run_enemy_turn();
    }

    fn attack_enemy(&mut self, index: usize) {
        self.attack_enemy_with_mode(index, false);
    }
    fn attack_enemy_with_mode(&mut self, index: usize, ranged: bool) {
        let attack = self.effective_attack();
        let defense = self.enemies[index].defense;
        let damage = Self::damage(attack, defense);
        let hp_before = self.enemies[index].hp;
        self.enemies[index].hp -= damage;
        if self.enemies[index].hp > 0 {
            let enemy = self.enemies[index].clone();
            self.emit_event(
                "battle_result",
                json!({
                    "result": "enemy_hit",
                    "enemy_id": enemy.id,
                    "enemy_type": enemy.kind.id(),
                    "enemy_pos": enemy.pos,
                    "damage": damage, "attack_power": attack, "defense_power": defense,
                    "ranged": ranged, "attacker_pos": self.player.pos,
                    "enemy_hp_before": hp_before,
                    "enemy_hp_after": enemy.hp,
                }),
            );
            return;
        }
        let enemy = self.enemies.remove(index);
        let reward_seed = PortableRng::derive_seed(
            self.config.scenario_seed,
            "reward",
            self.player.depth,
            Some(&enemy.id),
        );
        let gold = PortableRng::new(reward_seed).range_inclusive(1, 4) as u32;
        self.player.gold += gold;
        match enemy.kind {
            EnemyKind::Melee => {
                self.player.score += 1;
                self.player.xp += 3;
            }
            EnemyKind::Archer | EnemyKind::Brute => {
                self.player.score += 2;
                self.player.xp += 5;
            }
        }
        self.check_level_up();
        self.emit_event(
            "battle_result",
            json!({
                "result": "enemy_defeated",
                "enemy_id": enemy.id,
                "enemy_type": enemy.kind.id(),
                "enemy_pos": enemy.pos,
                "damage": damage, "attack_power": attack, "defense_power": defense,
                    "ranged": ranged, "attacker_pos": self.player.pos,
                "enemy_hp_before": hp_before,
                "gold_gained": gold,
            }),
        );
    }

    fn check_level_up(&mut self) {
        let mut xp_needed = self.player.level * 8;
        while self.player.xp >= xp_needed {
            self.player.xp -= xp_needed;
            self.player.level += 1;
            self.player.max_hp += 2;
            self.player.hp = (self.player.hp + 2).min(self.player.max_hp);
            self.player.base_attack += 1;
            xp_needed = self.player.level * 8;
        }
    }

    fn run_enemy_turn(&mut self) {
        for index in 0..self.enemies.len() {
            let enemy = self.enemies[index].clone();
            match enemy.kind {
                EnemyKind::Melee => self.run_melee_turn(index, &enemy),
                EnemyKind::Archer => self.run_archer_turn(index, &enemy),
                EnemyKind::Brute => self.run_brute_turn(index, &enemy),
            }
            if self.game_over {
                break;
            }
        }
    }

    fn run_melee_turn(&mut self, index: usize, enemy: &Enemy) {
        let delta = self.player.pos - enemy.pos;
        if delta.x.abs() + delta.y.abs() == 1 {
            self.damage_player_from(enemy, enemy.attack, false);
            if self.game_over {
                return;
            }
        }
        if self.can_enemy_see_player(enemy.pos) {
            let step = self.choose_enemy_step(enemy.pos, delta);
            self.try_move_enemy(index, enemy.pos + step);
        }
    }

    fn run_brute_turn(&mut self, index: usize, enemy: &Enemy) {
        if let Some(target) = enemy.windup_target {
            self.enemies[index].windup_target = None;
            if self.player.pos == target && enemy.pos.manhattan_distance(target) == 1 {
                self.damage_player_from(enemy, enemy.attack, false);
            } else {
                self.emit_event(
                    "battle_result",
                    json!({"result": "enemy_strike_missed",
                    "enemy_id": enemy.id, "enemy_type": "brute", "enemy_pos": enemy.pos,
                    "target": target, "windup_target": null}),
                );
            }
            return;
        }
        if enemy.pos.manhattan_distance(self.player.pos) == 1 {
            self.enemies[index].windup_target = Some(self.player.pos);
            self.emit_event(
                "battle_result",
                json!({"result": "enemy_windup", "enemy_id": enemy.id,
                "enemy_type": "brute", "enemy_pos": enemy.pos, "target": self.player.pos,
                "windup_target": self.player.pos}),
            );
            return;
        }
        if self.turn % 2 == 0 && self.can_enemy_see_player(enemy.pos) {
            let step = self.choose_enemy_step(enemy.pos, self.player.pos - enemy.pos);
            self.try_move_enemy(index, enemy.pos + step);
        }
    }

    fn run_archer_turn(&mut self, index: usize, enemy: &Enemy) {
        if !self.has_line_of_sight(enemy.pos, self.player.pos) {
            return;
        }
        let distance = enemy.pos.distance_squared(self.player.pos);
        if distance <= 2 {
            if self.try_archer_retreat(index, enemy.pos) {
                return;
            }
            self.damage_player_from(enemy, 1, false);
            return;
        }
        if distance <= 49 {
            if self.can_enemy_see_player(enemy.pos) {
                self.damage_player_from(enemy, enemy.attack, true);
            }
            return;
        }
        if self.can_enemy_see_player(enemy.pos) {
            let delta = self.player.pos - enemy.pos;
            let step = self.choose_enemy_step(enemy.pos, delta);
            self.try_move_enemy(index, enemy.pos + step);
        }
    }

    fn damage_player_from(&mut self, enemy: &Enemy, damage: i32, ranged: bool) {
        let attack = damage;
        let defense = self.effective_defense();
        let damage = Self::damage(attack, defense);
        let hp_before = self.player.hp;
        self.player.hp = (self.player.hp - damage).max(0);
        let mut details = json!({
            "result": "player_hit",
            "enemy_id": enemy.id,
            "enemy_type": enemy.kind.id(),
            "enemy_pos": enemy.pos,
            "damage": damage, "attack_power": attack, "defense_power": defense,
            "player_hp_before": hp_before,
            "player_hp_after": self.player.hp,
        });
        if enemy.kind == EnemyKind::Brute {
            details["windup_target"] = Value::Null;
        }
        if ranged {
            details["ranged"] = json!(true);
        }
        self.emit_event("battle_result", details);
        if self.player.hp == 0 {
            self.game_over = true;
            self.run_outcome = Some(RunOutcome::PlayerDefeated);
            self.emit_event(
                "battle_result",
                json!({
                    "result": "player_defeated",
                    "final_depth": self.player.depth,
                    "final_gold": self.player.gold,
                    "turns": self.turn,
                    "strategy_id": self.config.strategy.id(),
                    "scenario_seed": self.config.scenario_seed,
                }),
            );
        }
    }

    fn try_archer_retreat(&mut self, index: usize, enemy_pos: Point) -> bool {
        let delta = self.player.pos - enemy_pos;
        let away_step = Point {
            x: -delta.x.signum(),
            y: -delta.y.signum(),
        };
        let away = enemy_pos + away_step;
        let candidates = [
            away,
            Point {
                x: away.x,
                y: enemy_pos.y,
            },
            Point {
                x: enemy_pos.x,
                y: away.y,
            },
        ];
        for candidate in candidates {
            if self.is_walkable(candidate)
                && candidate != self.player.pos
                && self.enemy_at(candidate).is_none()
            {
                self.enemies[index].pos = candidate;
                return true;
            }
        }
        false
    }

    fn choose_enemy_step(&self, enemy_pos: Point, delta: Point) -> Point {
        let horizontal = Point {
            x: delta.x.signum(),
            y: 0,
        };
        let vertical = Point {
            x: 0,
            y: delta.y.signum(),
        };
        let (first, second) = if delta.x.abs() > delta.y.abs() {
            (horizontal, vertical)
        } else {
            (vertical, horizontal)
        };
        if first != Point::ZERO && self.is_walkable(enemy_pos + first) {
            first
        } else if second != Point::ZERO && self.is_walkable(enemy_pos + second) {
            second
        } else {
            Point::ZERO
        }
    }

    fn try_move_enemy(&mut self, index: usize, target: Point) {
        if self.is_walkable(target) && target != self.player.pos && self.enemy_at(target).is_none()
        {
            self.enemies[index].pos = target;
        }
    }

    fn has_line_of_sight(&self, from: Point, to: Point) -> bool {
        if !self.is_walkable(from) || !self.is_walkable(to) {
            return false;
        }
        let nx = (to.x - from.x).abs();
        let ny = (to.y - from.y).abs();
        let sx = (to.x - from.x).signum();
        let sy = (to.y - from.y).signum();
        let (mut ix, mut iy) = (0, 0);
        let mut current = from;
        while ix < nx || iy < ny {
            let crossing = (1 + 2 * ix) * ny - (1 + 2 * iy) * nx;
            if crossing == 0 {
                // A corner crossing touches both side tiles: neither may be a wall.
                if !self.is_walkable(Point {
                    x: current.x + sx,
                    y: current.y,
                }) || !self.is_walkable(Point {
                    x: current.x,
                    y: current.y + sy,
                }) {
                    return false;
                }
                current.x += sx;
                current.y += sy;
                ix += 1;
                iy += 1;
            } else if crossing < 0 {
                current.x += sx;
                ix += 1;
            } else {
                current.y += sy;
                iy += 1;
            }
            if !self.is_walkable(current) {
                return false;
            }
        }
        true
    }

    fn can_enemy_see_player(&self, enemy_pos: Point) -> bool {
        enemy_pos.distance_squared(self.player.pos) <= 80
    }

    fn enemy_at(&self, pos: Point) -> Option<usize> {
        self.enemies.iter().position(|enemy| enemy.pos == pos)
    }

    fn is_walkable(&self, pos: Point) -> bool {
        pos.x >= 0
            && pos.y >= 0
            && pos.x < self.config.map_width
            && pos.y < self.config.map_height
            && self.map[pos.y as usize][pos.x as usize]
    }
}

fn first_step(
    start: Point,
    destination: Point,
    came_from: &HashMap<Point, Point>,
) -> Option<Point> {
    if !came_from.contains_key(&destination) || destination == start {
        return None;
    }
    let mut current = destination;
    while came_from[&current] != start {
        current = came_from[&current];
    }
    Some(current - start)
}

fn format_utc_timestamp(seconds_since_epoch: u64) -> String {
    let days = (seconds_since_epoch / 86_400) as i64;
    let seconds_of_day = seconds_since_epoch % 86_400;
    let hour = seconds_of_day / 3_600;
    let minute = (seconds_of_day % 3_600) / 60;
    let second = seconds_of_day % 60;
    let shifted_days = days + 719_468;
    let era = shifted_days.div_euclid(146_097);
    let day_of_era = shifted_days - era * 146_097;
    let year_of_era =
        (day_of_era - day_of_era / 1_460 + day_of_era / 36_524 - day_of_era / 146_096) / 365;
    let mut year = year_of_era + era * 400;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let month_prime = (5 * day_of_year + 2) / 153;
    let day = day_of_year - (153 * month_prime + 2) / 5 + 1;
    let month = month_prime + if month_prime < 10 { 3 } else { -9 };
    if month <= 2 {
        year += 1;
    }
    format!("{year:04}-{month:02}-{day:02} {hour:02}:{minute:02}:{second:02}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn weighted_policy_preferences_sampling_and_rng_isolation() {
        assert!(GoalPolicy {
            enemy_weight: 0,
            item_weight: 0,
            stairs_weight: 0,
            temperature: 8
        }
        .validate()
        .is_err());
        assert!(GoalPolicy {
            enemy_weight: 1001,
            ..GoalPolicy::preset(Strategy::AggressiveV1)
        }
        .validate()
        .is_err());
        assert_eq!(goal_mass(4, 0, 8), 4000);
        assert_eq!(goal_mass(1, 8, 8), 368);
        assert_eq!(goal_mass(1, 10000, 8), 1);
        assert_eq!(goal_mass(0, 0, 8), 0);
        let mut sim = item_test_simulation(Strategy::AggressiveV1);
        sim.enemies.push(Enemy {
            id: "target".into(),
            kind: EnemyKind::Melee,
            windup_target: None,
            pos: Point { x: 5, y: 2 },
            hp: 5,
            attack: 1,
            defense: 0,
        });
        let mut enemy_choices = 0;
        let mut stairs_choices = 0;
        for seed in 1..=1000 {
            sim.selected_goal = None;
            sim.policy_rng = PortableRng::new(PortableRng::derive_seed(seed, "policy", 0, None));
            let d = sim.choose_goal_decision().unwrap();
            let selection = d.goal_selection.unwrap();
            if selection["selected_kind"] == "enemy" {
                enemy_choices += 1;
            } else {
                stairs_choices += 1;
            }
            let distribution = selection["distribution"].as_array().unwrap();
            assert_eq!(distribution.len(), 2);
            assert_eq!(
                distribution
                    .iter()
                    .map(|v| v["mass"].as_u64().unwrap())
                    .sum::<u64>(),
                distribution[0]["total_mass"]
            );
        }
        assert!(
            enemy_choices > stairs_choices && stairs_choices > 20,
            "lower priority must still be selectable"
        );
        let before = sim.policy_rng.state;
        let retained = sim.choose_goal_decision().unwrap().goal_selection.unwrap();
        assert_eq!(retained["target_retained"], true);
        assert!(retained["draw"].is_null());
        assert_eq!(sim.policy_rng.state, before);
        sim.player.hp -= 4;
        assert_eq!(
            sim.choose_goal_decision().unwrap().goal_selection.unwrap()["target_retained"],
            false
        );
        let a = Simulation::new_with_policy(sim.config, GoalPolicy::preset(Strategy::AggressiveV1))
            .unwrap();
        let b = Simulation::new_with_policy(sim.config, GoalPolicy::preset(Strategy::CautiousV1))
            .unwrap();
        assert_eq!(a.map, b.map);
        assert_eq!(a.enemies, b.enemies);
        assert_eq!(a.items, b.items);
    }
    #[test]
    fn cautious_brute_goal_waits_after_dodge_and_makes_combat_progress() {
        let mut sim = item_test_simulation(Strategy::CautiousV1);
        sim.goal_policy = GoalPolicy {
            enemy_weight: 1,
            item_weight: 0,
            stairs_weight: 0,
            temperature: 8,
        };
        sim.enemies.push(test_brute(Point { x: 4, y: 2 }));
        let before = sim.player.hp;
        for _ in 0..30 {
            if sim.enemies.is_empty() {
                break;
            }
            sim.run_auto_player_turn();
        }
        assert!(
            sim.enemies.is_empty(),
            "approach / windup / evasion must not loop indefinitely"
        );
        assert_eq!(sim.player.hp, before);
    }

    #[test]
    fn portable_random_vectors_match_v1() {
        assert_eq!(PortableRng::fnv1a_32(""), 2_166_136_261);
        assert_eq!(PortableRng::fnv1a_32("hello"), 1_335_831_723);
        assert_eq!(
            PortableRng::derive_seed(424_242, "floor", 1, None),
            3_901_461_250
        );
        let mut rng = PortableRng::new(1);
        assert_eq!(
            (0..5).map(|_| rng.next_u32()).collect::<Vec<_>>(),
            vec![
                270_369,
                67_634_689,
                2_647_435_461,
                307_599_695,
                2_398_689_233
            ]
        );
    }

    #[test]
    fn utc_timestamp_format_matches_schema_v2() {
        assert_eq!(format_utc_timestamp(0), "1970-01-01 00:00:00");
        assert_eq!(format_utc_timestamp(1_767_225_600), "2026-01-01 00:00:00");
    }

    #[test]
    fn logged_run_starts_with_replay_events() {
        let logged_run = Simulation::new_logged(
            SimulationConfig {
                scenario_seed: 1,
                strategy: Strategy::AggressiveV1,
                map_width: 24,
                map_height: 18,
                max_turns: 1,
            },
            "rust-test.jsonl".to_owned(),
        )
        .expect("logged simulation starts")
        .run_logged();

        assert_eq!(logged_run.events[0].event, "run_start");
        assert_eq!(logged_run.events[1].event, "floor_start");
        assert_eq!(logged_run.events[2].event, "user_action");
        assert_eq!(logged_run.events[3].event, "decision");
        assert_eq!(logged_run.events[0].sequence, 1);
        assert_eq!(logged_run.events[0].schema_version, 8);
    }

    fn item_test_simulation(strategy: Strategy) -> Simulation {
        let mut sim = Simulation::new_logged(
            SimulationConfig {
                scenario_seed: 1,
                strategy,
                map_width: 24,
                map_height: 18,
                max_turns: 120,
            },
            "item-test.jsonl".to_owned(),
        )
        .unwrap();
        sim.map = vec![vec![true; 24]; 18];
        sim.enemies.clear();
        sim.items.clear();
        sim.player.pos = Point { x: 2, y: 2 };
        sim.stairs = Point { x: 20, y: 15 };
        sim
    }

    fn gear_item(kind: &'static str, id: &str, pos: Point, bonus: i32) -> FloorItem {
        FloorItem {
            id: id.to_owned(),
            kind,
            weapon_kind: (kind == "weapon").then_some("melee"),
            pos,
            attack_bonus: if kind == "weapon" { bonus } else { 0 },
            defense_bonus: if kind == "armor" { bonus } else { 0 },
        }
    }

    fn bow_gear(bonus: i32) -> Gear {
        Gear {
            id: "test-bow".to_owned(),
            kind: "weapon",
            weapon_kind: Some("bow"),
            attack_bonus: bonus,
            defense_bonus: 0,
        }
    }

    #[test]
    fn weapon_preference_is_stable_and_bow_damage_is_lower() {
        let mut sim = item_test_simulation(Strategy::CautiousV1);
        let sword = gear_item("weapon", "sword", sim.player.pos, 2);
        sim.items.push(sword);
        sim.pick_up_items("sword");
        assert_eq!(sim.effective_attack(), 7);
        assert_eq!(sim.attack_range(), 1);
        let bow = FloorItem {
            id: "bow".to_owned(),
            kind: "weapon",
            weapon_kind: Some("bow"),
            pos: sim.player.pos,
            attack_bonus: 2,
            defense_bonus: 0,
        };
        sim.items.push(bow.clone());
        sim.pick_up_items("bow");
        sim.pick_up_items("again");
        assert_eq!(sim.weapon_kind(), "bow");
        assert_eq!(sim.effective_attack(), 3);
        assert_eq!(sim.attack_range(), 5);
        assert_eq!(sim.items.len(), 1);
        assert_eq!(sim.items[0].weapon_kind, Some("melee"));
        assert!(!sim.wants_item(&gear_item("weapon", "strong-sword", sim.player.pos, 99)));
        assert!(!sim.wants_item(&bow));
        let mut upgraded = bow.clone();
        upgraded.attack_bonus = 3;
        assert!(sim.wants_item(&upgraded));
        sim.config.strategy = Strategy::AggressiveV1;
        assert!(sim.wants_item(&gear_item("weapon", "weak-sword", sim.player.pos, 1)));
        sim.pick_up_items("melee-preferred");
        upgraded.attack_bonus = 99;
        assert!(!sim.wants_item(&upgraded));
        sim.player.equipment.weapon = None;
        sim.items = vec![
            gear_item("weapon", "near-melee", Point { x: 3, y: 2 }, 2),
            FloorItem {
                pos: Point { x: 5, y: 2 },
                ..bow
            },
        ];
        sim.config.strategy = Strategy::CautiousV1;
        assert_eq!(sim.choose_item_decision().unwrap().target["id"], "bow");
    }

    #[test]
    fn player_bow_range_los_turn_cost_and_growth() {
        let mut sim = item_test_simulation(Strategy::CautiousV1);
        sim.player.equipment.weapon = Some(bow_gear(2));
        sim.enemies.push(Enemy {
            id: "target".to_owned(),
            kind: EnemyKind::Melee,
            windup_target: None,
            pos: Point { x: 7, y: 2 },
            hp: 10,
            attack: 3,
            defense: 0,
        });
        assert!(sim.can_player_shoot_from(sim.player.pos, Point { x: 7, y: 2 }));
        assert!(sim.can_player_shoot_from(sim.player.pos, Point { x: 5, y: 6 }));
        assert!(!sim.can_player_shoot_from(sim.player.pos, Point { x: 8, y: 2 }));
        sim.map[2][4] = false;
        assert!(!sim.player_shoot("target", "wall"));
        assert_eq!(sim.turn, 0);
        sim.map[2][4] = true;
        sim.map[2][3] = false;
        assert!(!sim.can_player_shoot_from(sim.player.pos, Point { x: 3, y: 3 }));
        sim.map[2][3] = true;
        assert!(!sim.player_shoot("missing", "missing"));
        assert_eq!(sim.turn, 0);
        assert_eq!(
            sim.choose_bow_decision().unwrap().action_type,
            "ranged_attack"
        );
        assert!(sim.player_shoot("target", "shot"));
        assert_eq!(sim.turn, 1);
        assert_eq!(sim.player.pos, Point { x: 2, y: 2 });
        assert_eq!(sim.enemies[0].hp, 7);
        assert_eq!(sim.enemies[0].pos, Point { x: 6, y: 2 });
        let comparison = sim
            .choose_progression_decision()
            .unwrap()
            .progression
            .unwrap();
        assert_eq!(comparison["candidates"][0]["steps"], 0);
        assert_eq!(comparison["candidates"][0]["estimated_damage"], 0);
        sim.enemies[0].hp = 1;
        sim.enemies[0].defense = 20;
        sim.player.xp = 5;
        assert!(sim.player_shoot("target", "kill"));
        assert!(sim.enemies.is_empty());
        assert_eq!(sim.player.level, 2);
        assert_eq!(sim.player.xp, 0);
        assert_eq!(sim.player.base_attack, 6);
        assert_eq!(sim.effective_attack(), 4);
    }

    #[test]
    fn bow_counterfire_healing_priority_and_adjacent_combat() {
        let mut sim = item_test_simulation(Strategy::CautiousV1);
        sim.player.equipment.weapon = Some(bow_gear(2));
        sim.items
            .push(gear_item("armor", "armor", sim.player.pos, 1));
        sim.pick_up_items("armor");
        sim.enemies.push(Enemy {
            id: "archer".to_owned(),
            kind: EnemyKind::Archer,
            windup_target: None,
            pos: Point { x: 7, y: 2 },
            hp: 20,
            attack: 3,
            defense: 0,
        });
        assert!(sim.player_shoot("archer", "shot"));
        assert_eq!(sim.player.hp, 16);
        sim.player.hp = 8;
        sim.player.inventory.health_potion = 1;
        assert_eq!(sim.choose_item_decision().unwrap().action_type, "use_item");
        sim.player.hp = 1;
        sim.player.inventory.health_potion = 0;
        assert!(sim.choose_bow_decision().is_none());
        sim.stairs = Point { x: 3, y: 2 };
        assert_eq!(sim.choose_cautious_decision().target["kind"], "stairs");
        sim.stairs = Point { x: 20, y: 15 };
        sim.player.hp = 18;
        sim.enemies[0].kind = EnemyKind::Melee;
        sim.enemies[0].pos = Point { x: 3, y: 2 };
        assert!(sim.choose_bow_decision().is_none());
        assert_eq!(
            sim.choose_cautious_decision().rule_id,
            "attack_pursuing_melee"
        );
        sim.player.equipment.weapon = None;
        let before = sim.turn;
        assert!(!sim.player_shoot("archer", "no-bow"));
        assert_eq!(sim.turn, before);
    }

    fn test_brute(pos: Point) -> Enemy {
        Enemy {
            id: "brute-test".to_owned(),
            kind: EnemyKind::Brute,
            windup_target: None,
            pos,
            hp: 17,
            attack: 5,
            defense: 0,
        }
    }

    #[test]
    fn brute_moves_slowly_winds_up_and_strikes_the_locked_tile() {
        let mut sim = item_test_simulation(Strategy::AggressiveV1);
        sim.enemies.push(test_brute(Point { x: 4, y: 2 }));
        sim.turn = 1;
        sim.run_enemy_turn();
        assert_eq!(sim.enemies[0].pos, Point { x: 4, y: 2 });
        sim.turn = 2;
        sim.run_enemy_turn();
        assert_eq!(sim.enemies[0].pos, Point { x: 3, y: 2 });
        sim.turn = 3;
        sim.run_enemy_turn();
        assert_eq!(sim.enemies[0].windup_target, Some(sim.player.pos));
        assert_eq!(sim.player.hp, 18);
        assert_eq!(sim.incoming_damage_at(sim.player.pos, None), 5);
        assert_eq!(sim.incoming_damage_at(Point { x: 2, y: 3 }, None), 0);
        sim.player.pos = Point { x: 3, y: 3 }; // Remains adjacent, but on a different tile.
        sim.turn = 4;
        sim.run_enemy_turn();
        assert_eq!(sim.player.hp, 18);
        assert_eq!(sim.enemies[0].windup_target, None);
        assert_eq!(
            sim.logger.as_ref().unwrap().events.last().unwrap().details["result"],
            "enemy_strike_missed"
        );
        sim.turn = 5;
        sim.run_enemy_turn();
        sim.player.equipment.armor = Some(Gear {
            id: "armor".into(),
            kind: "armor",
            weapon_kind: None,
            attack_bonus: 0,
            defense_bonus: 2,
        });
        sim.turn = 6;
        sim.run_enemy_turn();
        assert_eq!(sim.player.hp, 15);
        assert_eq!(sim.enemies[0].windup_target, None);
        assert_eq!(
            sim.logger.as_ref().unwrap().events.last().unwrap().details["windup_target"],
            Value::Null
        );
    }

    #[test]
    fn cautious_evades_brute_but_interrupts_a_killable_strike() {
        let mut sim = item_test_simulation(Strategy::CautiousV1);
        let mut brute = test_brute(Point { x: 3, y: 2 });
        brute.windup_target = Some(sim.player.pos);
        sim.enemies.push(brute);
        let escape = sim.choose_windup_response().unwrap();
        assert_eq!(escape.rule_id, "evade_windup");
        assert_eq!(
            sim.incoming_damage_at(sim.player.pos + escape.direction, None),
            0
        );
        sim.run_auto_player_turn();
        assert_eq!(sim.player.hp, 18);
        assert_eq!(sim.enemies[0].windup_target, None);
        sim.player.pos = Point { x: 2, y: 2 };
        sim.enemies[0].windup_target = Some(sim.player.pos);
        sim.enemies[0].hp = 1;
        sim.player.xp = 3;
        assert_eq!(
            sim.choose_windup_response().unwrap().rule_id,
            "interrupt_windup"
        );
        // Another adjacent enemy must not steal the finishing attack.
        let mut other = test_brute(Point { x: 2, y: 1 });
        other.kind = EnemyKind::Melee;
        other.id = "other".into();
        other.attack = 1;
        sim.enemies.push(other);
        sim.run_auto_player_turn();
        assert_eq!(sim.enemies.len(), 1);
        assert_eq!(sim.enemies[0].id, "other");
        assert_eq!(sim.player.level, 2);
        assert_eq!(sim.player.xp, 0);
        assert_eq!(sim.player.score, 2);
        let mut trapped = item_test_simulation(Strategy::CautiousV1);
        let mut brute = test_brute(Point { x: 3, y: 2 });
        brute.windup_target = Some(trapped.player.pos);
        trapped.enemies.push(brute);
        for p in [
            Point { x: 2, y: 1 },
            Point { x: 2, y: 3 },
            Point { x: 1, y: 2 },
        ] {
            trapped.map[p.y as usize][p.x as usize] = false;
        }
        assert!(trapped.choose_windup_response().is_none());
        trapped.config.strategy = Strategy::AggressiveV1;
        assert!(trapped.choose_windup_response().is_none());
    }

    #[test]
    fn brute_growth_estimate_uses_alternating_strikes_and_spawn_is_paired() {
        let mut sim = item_test_simulation(Strategy::AggressiveV1);
        sim.enemies.push(test_brute(Point { x: 3, y: 2 }));
        let c = sim
            .choose_progression_decision()
            .unwrap()
            .progression
            .unwrap();
        assert_eq!(c["candidates"][0]["xp_gain"], 5);
        assert_eq!(c["candidates"][0]["estimated_damage"], 5);
        sim.enemies[0].windup_target = Some(sim.player.pos);
        let c = sim
            .choose_progression_decision()
            .unwrap()
            .progression
            .unwrap();
        assert_eq!(c["candidates"][0]["estimated_damage"], 10);
        let config = SimulationConfig {
            scenario_seed: 27,
            strategy: Strategy::AggressiveV1,
            map_width: 44,
            map_height: 28,
            max_turns: 500,
        };
        let a = Simulation::new(config).unwrap();
        let c = Simulation::new(SimulationConfig {
            strategy: Strategy::CautiousV1,
            ..config
        })
        .unwrap();
        assert_eq!(a.enemies, c.enemies);
        assert_eq!(a.items, c.items);
        assert!(a.enemies.iter().any(|e| e.kind == EnemyKind::Brute));
    }

    #[test]
    fn equipment_upgrades_drop_previous_without_extra_turns_or_potion_capacity() {
        let mut sim = item_test_simulation(Strategy::AggressiveV1);
        sim.player.inventory.health_potion = INVENTORY_CAPACITY;
        let next = sim.player.pos + DIRECTIONS[3];
        sim.items.push(gear_item("weapon", "sword", next, 2));
        sim.items.push(gear_item("armor", "vest", next, 1));
        sim.player_act(DIRECTIONS[3], "equip");
        assert_eq!(sim.turn, 1);
        assert_eq!(sim.effective_attack(), BASE_ATTACK + 2);
        assert_eq!(sim.effective_defense(), 1);
        assert_eq!(sim.player.inventory.health_potion, INVENTORY_CAPACITY);
        assert!(sim.items.is_empty());
        sim.items.push(gear_item("weapon", "better-sword", next, 4));
        sim.pick_up_items("upgrade");
        assert_eq!(sim.effective_attack(), BASE_ATTACK + 4);
        assert_eq!(sim.items[0].id, "sword");
        assert_eq!(sim.items[0].pos, next);
        let event = sim.logger.as_ref().unwrap().events.last().unwrap();
        assert_eq!(event.details["result"], "item_equipped");
        assert_eq!(event.details["previous_equipment"]["id"], "sword");
        sim.items.push(gear_item("weapon", "equal-sword", next, 4));
        sim.pick_up_items("no-downgrade");
        assert_eq!(
            sim.player.equipment.weapon.as_ref().unwrap().id,
            "better-sword"
        );
        assert_eq!(sim.items.len(), 2);
        sim.new_floor();
        assert_eq!(sim.attack_bonus(), 4);
        assert_eq!(sim.defense_bonus(), 1);
        sim.player = Player::default();
        assert_eq!(sim.attack_bonus(), 0);
        assert_eq!(sim.defense_bonus(), 0);
    }

    #[test]
    fn level_growth_does_not_stack_equipment_and_defense_applies_to_all_hits() {
        let mut sim = item_test_simulation(Strategy::AggressiveV1);
        sim.items
            .push(gear_item("weapon", "sword", sim.player.pos, 2));
        sim.items
            .push(gear_item("armor", "vest", sim.player.pos, 2));
        sim.pick_up_items("equip");
        sim.player.xp = 8;
        sim.check_level_up();
        assert_eq!(sim.player.base_attack, BASE_ATTACK + 1);
        assert_eq!(sim.effective_attack(), BASE_ATTACK + 3);
        assert_eq!(sim.player.base_defense, 0);
        assert_eq!(sim.defense_bonus(), 2);
        sim.pick_up_items("again");
        assert_eq!(sim.effective_attack(), BASE_ATTACK + 3);
        let enemy = Enemy {
            id: "target".to_owned(),
            kind: EnemyKind::Melee,
            windup_target: None,
            pos: Point { x: 3, y: 2 },
            hp: 20,
            attack: 5,
            defense: 0,
        };
        sim.enemies.push(enemy.clone());
        sim.attack_enemy(0);
        assert_eq!(sim.enemies[0].hp, 12);
        sim.enemies[0].defense = 20;
        sim.attack_enemy(0);
        assert_eq!(sim.enemies[0].hp, 11);
        let hp = sim.player.hp;
        sim.damage_player_from(&enemy, 5, false);
        assert_eq!(sim.player.hp, hp - 3);
        sim.damage_player_from(&enemy, 5, true);
        assert_eq!(sim.player.hp, hp - 6);
        sim.damage_player_from(&enemy, 1, false);
        assert_eq!(sim.player.hp, hp - 7);
        assert_eq!(Simulation::damage(3, 20), 1);
    }

    #[test]
    fn equipment_policy_ignores_weaker_gear_and_accounts_for_armor_in_healing() {
        let mut sim = item_test_simulation(Strategy::AggressiveV1);
        sim.player.inventory.health_potion = INVENTORY_CAPACITY;
        let next = sim.player.pos + DIRECTIONS[3];
        sim.items.push(gear_item("armor", "vest", next, 2));
        assert_eq!(
            sim.choose_item_decision().unwrap().rule_id,
            "collect_nearby_equipment"
        );
        sim.player_act(DIRECTIONS[3], "equip");
        sim.items.push(gear_item(
            "armor",
            "weaker",
            sim.player.pos + DIRECTIONS[3],
            1,
        ));
        assert!(sim.choose_item_decision().is_none());
        let enemy = Enemy {
            id: "archer".to_owned(),
            kind: EnemyKind::Archer,
            windup_target: None,
            pos: Point { x: 7, y: 2 },
            hp: 6,
            attack: 14,
            defense: 0,
        };
        sim.enemies.push(enemy);
        sim.player.hp = 14; // Unarmored shot would be lethal, armored shot is 12.
        assert!(sim.choose_item_decision().is_none());
        sim.player.equipment.armor = None;
        assert_eq!(
            sim.choose_item_decision().unwrap().rule_id,
            "use_health_potion"
        );
    }

    #[test]
    fn pickup_is_part_of_movement_and_capacity_leaves_item_on_floor() {
        let mut sim = item_test_simulation(Strategy::AggressiveV1);
        let pos = sim.player.pos + DIRECTIONS[3];
        sim.items.push(FloorItem {
            id: "potion".to_owned(),
            kind: "health_potion",
            pos,
            attack_bonus: 0,
            defense_bonus: 0,
            weapon_kind: None,
        });
        sim.player_act(DIRECTIONS[3], "pickup");
        assert_eq!(sim.turn, 1);
        assert_eq!(sim.player.inventory.health_potion, 1);
        assert!(sim.items.is_empty());
        assert_eq!(
            sim.logger.as_ref().unwrap().events.last().unwrap().details["result"],
            "item_picked_up"
        );
        sim.items.push(FloorItem {
            id: "overflow".to_owned(),
            kind: "health_potion",
            pos,
            attack_bonus: 0,
            defense_bonus: 0,
            weapon_kind: None,
        });
        sim.player.inventory.health_potion = INVENTORY_CAPACITY;
        sim.pick_up_items("full");
        assert_eq!(sim.items.len(), 1);
        sim.player.depth += 1;
        sim.new_floor();
        assert_eq!(sim.player.inventory.health_potion, INVENTORY_CAPACITY);
    }

    #[test]
    fn potion_heals_before_enemy_phase_and_invalid_use_consumes_nothing() {
        let mut sim = item_test_simulation(Strategy::AggressiveV1);
        sim.player.inventory.health_potion = 2;
        sim.use_health_potion("full-hp");
        assert_eq!(sim.turn, 0);
        assert_eq!(sim.player.inventory.health_potion, 2);
        sim.player.hp = 15;
        sim.enemies.push(Enemy {
            id: "attacker".to_owned(),
            kind: EnemyKind::Melee,
            windup_target: None,
            pos: sim.player.pos + DIRECTIONS[3],
            hp: 10,
            attack: 3,
            defense: 0,
        });
        sim.use_health_potion("heal");
        assert_eq!(sim.turn, 1);
        assert_eq!(sim.player.hp, 15); // 15 -> 18 -> 15, after the enemy attacks.
        assert_eq!(sim.player.inventory.health_potion, 1);
        let events = &sim.logger.as_ref().unwrap().events;
        let used = events
            .iter()
            .find(|event| event.event == "item_result")
            .unwrap();
        assert_eq!(used.details["healed"], 3);
        assert_eq!(used.player_state["hp"], 18);
        assert_eq!(events.last().unwrap().details["result"], "player_hit");
        sim.player.inventory.health_potion = 0;
        sim.use_health_potion("empty");
        assert_eq!(sim.turn, 1);
        sim.player.inventory.health_potion = 1;
        sim.game_over = true;
        sim.use_health_potion("dead");
        assert_eq!(sim.turn, 1);
    }

    #[test]
    fn item_policy_respects_threat_capacity_and_entire_safe_route() {
        let mut sim = item_test_simulation(Strategy::CautiousV1);
        let pos = sim.player.pos + DIRECTIONS[3];
        sim.items.push(FloorItem {
            id: "safe".to_owned(),
            kind: "health_potion",
            pos,
            attack_bonus: 0,
            defense_bonus: 0,
            weapon_kind: None,
        });
        assert_eq!(
            sim.choose_item_decision().unwrap().rule_id,
            "cautious_collect_potion"
        );
        sim.player.inventory.health_potion = INVENTORY_CAPACITY;
        assert!(sim.choose_item_decision().is_none());
        sim.player.hp = 9;
        assert_eq!(sim.choose_item_decision().unwrap().action_type, "use_item");
        sim.player.hp = sim.player.max_hp;
        sim.player.inventory.health_potion = 0;
        sim.enemies.push(Enemy {
            id: "guard".to_owned(),
            kind: EnemyKind::Melee,
            windup_target: None,
            pos: Point { x: 5, y: 2 },
            hp: 10,
            attack: 3,
            defense: 0,
        });
        assert!(sim.choose_item_decision().is_none()); // The target has danger even though start is safe.
        sim.config.strategy = Strategy::AggressiveV1;
        assert_eq!(
            sim.choose_item_decision().unwrap().rule_id,
            "collect_nearby_potion"
        );
        sim.stairs = pos;
        assert!(sim.choose_item_decision().is_none()); // Never descend on an item detour.
        sim.stairs = Point { x: 20, y: 15 };
        sim.player.inventory.health_potion = 1;
        sim.player.hp = 17;
        sim.enemies[0].pos = sim.player.pos + DIRECTIONS[3];
        sim.enemies[0].attack = 17;
        assert_eq!(sim.choose_item_decision().unwrap().action_type, "use_item");
    }

    #[test]
    fn repeated_visits_prefer_a_detour_but_do_not_block_required_backtracking() {
        let mut sim = item_test_simulation(Strategy::CautiousV1);
        sim.navigation_visits.clear();
        let repeated = Point { x: 3, y: 2 };
        let destination = Point { x: 6, y: 2 };
        sim.navigation_visits.insert(repeated, 2);
        assert_eq!(sim.revisit_cost(repeated), 0);
        assert_eq!(
            sim.find_low_risk_step_toward(destination),
            Some(DIRECTIONS[3])
        );
        sim.navigation_visits.insert(repeated, 3);
        assert_eq!(sim.revisit_cost(repeated), 8);
        assert_eq!(
            sim.find_low_risk_step_toward(destination),
            Some(DIRECTIONS[0])
        );
        assert_eq!(sim.find_next_step_toward(destination), Some(DIRECTIONS[0]));
        sim.map = vec![vec![false; 24]; 18];
        for x in 2..=6 {
            sim.map[2][x] = true;
        }
        assert_eq!(
            sim.find_low_risk_step_toward(destination),
            Some(DIRECTIONS[3])
        );
        sim.new_floor();
        assert_eq!(sim.navigation_visits.len(), 1);
        assert_eq!(sim.navigation_visits[&sim.player.pos], 1);
    }

    #[test]
    fn movement_history_counts_only_successful_moves() {
        let mut sim = item_test_simulation(Strategy::CautiousV1);
        sim.navigation_visits.clear();
        let start = sim.player.pos;
        sim.navigation_visits.insert(start, 1);
        sim.player_act(DIRECTIONS[3], "right");
        sim.player_act(DIRECTIONS[2], "left");
        assert_eq!(sim.navigation_visits[&start], 2);
        assert_eq!(sim.revisit_cost(start), 0);
        sim.player_act(DIRECTIONS[3], "right-again");
        sim.player_act(DIRECTIONS[2], "left-again");
        assert_eq!(sim.navigation_visits[&start], 3);
        assert_eq!(sim.revisit_cost(start), 8);
        sim.player.inventory.health_potion = 1;
        sim.player.hp = 9;
        sim.use_health_potion("heal");
        assert_eq!(sim.navigation_visits[&start], 3);
        sim.map[1][2] = false;
        sim.player_act(DIRECTIONS[0], "wall");
        assert_eq!(sim.navigation_visits.len(), 2);
    }

    #[test]
    fn cautious_growth_compares_level_threshold_equipment_and_completion() {
        let mut sim = item_test_simulation(Strategy::CautiousV1);
        sim.enemies = vec![Enemy {
            id: "growth".to_owned(),
            kind: EnemyKind::Melee,
            windup_target: None,
            pos: Point { x: 4, y: 2 },
            hp: 5,
            attack: 1,
            defense: 0,
        }];
        assert_eq!(
            sim.choose_cautious_decision().rule_id,
            "descend_for_progress"
        );
        sim.player.xp = 5;
        let d = sim.choose_cautious_decision();
        assert_eq!(d.rule_id, "hunt_for_growth");
        assert_eq!(d.progression.unwrap()["candidates"][0]["levels_gained"], 1);
        sim.player.level = 2;
        assert_eq!(
            sim.choose_cautious_decision().rule_id,
            "descend_for_progress"
        );
        sim.player.level = 1;
        sim.player.depth = 4;
        assert_eq!(
            sim.choose_cautious_decision().rule_id,
            "descend_for_progress"
        );
        sim.player.depth = 1;
        sim.player.hp = 5;
        assert_eq!(
            sim.choose_cautious_decision().progression.unwrap()["candidates"][0]["rejection"],
            "hp_reserve"
        );
        sim.player.hp = 18;
        sim.enemies[0].hp = 10;
        sim.enemies[0].attack = 5;
        assert_eq!(
            sim.choose_cautious_decision().rule_id,
            "descend_for_progress"
        );
        sim.player.equipment.armor = Some(Gear {
            id: "armor".to_owned(),
            kind: "armor",
            attack_bonus: 0,
            defense_bonus: 4,
            weapon_kind: None,
        });
        let d = sim.choose_cautious_decision();
        assert_eq!(d.rule_id, "hunt_for_growth");
        assert_eq!(
            d.progression.unwrap()["candidates"][0]["estimated_damage"],
            2
        );
        sim.enemies[0].defense = 4;
        assert_eq!(
            sim.choose_cautious_decision().rule_id,
            "descend_for_progress"
        );
        sim.enemies[0].defense = 0;
        sim.enemies[0].kind = EnemyKind::Archer;
        assert_eq!(
            sim.choose_cautious_decision().progression.unwrap()["candidates"][0]["rejection"],
            "mobile_target"
        );
    }

    #[test]
    fn weighted_enemy_goal_retains_target_and_rejects_lethal_fights() {
        let mut sim = item_test_simulation(Strategy::AggressiveV1);
        sim.enemies = vec![Enemy {
            id: "first".to_owned(),
            kind: EnemyKind::Melee,
            windup_target: None,
            pos: Point { x: 5, y: 2 },
            hp: 5,
            attack: 1,
            defense: 0,
        }];
        sim.goal_policy = GoalPolicy {
            enemy_weight: 1,
            item_weight: 0,
            stairs_weight: 0,
            temperature: 8,
        };
        sim.choose_goal_decision().unwrap();
        assert_eq!(
            sim.selected_goal.as_ref().map(|g| g.1.as_str()),
            Some("first")
        );
        // Choose a closer, equally rewarding enemy, but retain the viable target.
        sim.enemies[0].pos = Point { x: 7, y: 2 };
        sim.enemies.push(Enemy {
            id: "closer".to_owned(),
            kind: EnemyKind::Melee,
            windup_target: None,
            pos: Point { x: 3, y: 4 },
            hp: 5,
            attack: 1,
            defense: 0,
        });
        assert_eq!(sim.choose_goal_decision().unwrap().target["id"], "first");
        sim.enemies[0].hp = 100;
        sim.enemies[0].attack = 20;
        assert_ne!(sim.choose_goal_decision().unwrap().target["id"], "first");
        sim.enemies.truncate(1);
        sim.enemies[0].hp = 5;
        sim.enemies[0].attack = 1;
        sim.navigation_visits.insert(Point { x: 4, y: 2 }, 10);
        assert_eq!(sim.choose_goal_decision().unwrap().target["id"], "first");
        assert_eq!(
            sim.choose_goal_decision().unwrap().goal_selection.unwrap()["target_retained"],
            true
        );
        sim.new_floor();
        assert!(sim.selected_goal.is_none());
    }

    #[test]
    fn growth_routes_respect_walls_other_enemies_and_stairs() {
        let mut sim = item_test_simulation(Strategy::AggressiveV1);
        sim.map.iter_mut().for_each(|row| row.fill(false));
        for x in 2..6 {
            sim.map[2][x] = true;
        }
        sim.stairs = Point { x: 3, y: 2 };
        assert!(sim.progression_route(Point { x: 4, y: 2 }, 12).is_none());
        sim.map[2][3] = false;
        assert!(sim.choose_progression_decision().is_none());
        sim.map[2][3] = true;
        sim.stairs = Point { x: 5, y: 2 };
        sim.enemies.push(Enemy {
            id: "blocker".to_owned(),
            kind: EnemyKind::Melee,
            windup_target: None,
            pos: Point { x: 3, y: 2 },
            hp: 5,
            attack: 1,
            defense: 0,
        });
        assert!(sim.progression_route(Point { x: 4, y: 2 }, 12).is_none());
    }

    #[test]
    fn aggressive_keeps_target_and_reselects_when_dead_or_unreachable() {
        let mut sim = item_test_simulation(Strategy::AggressiveV1);
        let enemy = |id: &str, x, y| Enemy {
            id: id.to_owned(),
            kind: EnemyKind::Archer,
            windup_target: None,
            pos: Point { x, y },
            hp: 6,
            attack: 1,
            defense: 0,
        };
        for direction in DIRECTIONS {
            let wall = sim.stairs + direction;
            sim.map[wall.y as usize][wall.x as usize] = false;
        }
        sim.enemies = vec![enemy("first", 8, 2), enemy("second", 2, 9)];
        sim.goal_policy = GoalPolicy {
            enemy_weight: 1,
            item_weight: 0,
            stairs_weight: 0,
            temperature: 8,
        };
        sim.choose_goal_decision().unwrap();
        assert_eq!(
            sim.selected_goal.as_ref().map(|g| g.1.as_str()),
            Some("first")
        );
        // Another enemy becomes closer; the pursuit must not reverse.
        sim.enemies[1].pos = Point { x: 3, y: 5 };
        assert_eq!(sim.choose_goal_decision().unwrap().target["id"], "first");
        // Healing does not erase the pursuit.
        sim.player.inventory.health_potion = 1;
        sim.player.hp = 9;
        sim.run_auto_player_turn();
        assert_eq!(
            sim.selected_goal.as_ref().map(|g| g.1.as_str()),
            Some("first")
        );
        // Healing preserves memory, then a material HP change allows a new draw.
        sim.selected_goal.as_mut().unwrap().2 = sim.player.hp;
        assert_eq!(sim.choose_goal_decision().unwrap().target["id"], "first");
        let locked = sim.enemies[0].pos;
        for direction in DIRECTIONS {
            let wall = locked + direction;
            sim.map[wall.y as usize][wall.x as usize] = false;
        }
        assert_eq!(sim.choose_goal_decision().unwrap().target["id"], "second");
        sim.enemies.remove(0);
        assert_eq!(sim.choose_goal_decision().unwrap().target["id"], "second");
        sim.new_floor();
        assert!(sim.selected_goal.is_none());
    }

    #[test]
    fn aggressive_seed_301_does_not_alternate_pursuit_targets() {
        let logged = Simulation::new_logged(
            SimulationConfig {
                scenario_seed: 301,
                strategy: Strategy::AggressiveV1,
                map_width: 64,
                map_height: 40,
                max_turns: 500,
            },
            "aggressive-cycle.jsonl".to_owned(),
        )
        .unwrap()
        .run_logged();
        let decisions: Vec<_> = logged
            .events
            .iter()
            .filter(|event| event.event == "decision")
            .collect();
        for window in decisions.windows(12) {
            let cycling = window
                .iter()
                .all(|event| event.details["action"]["type"] == "move")
                && window
                    .iter()
                    .enumerate()
                    .all(|(i, e)| e.player_state["pos"] == window[i % 2].player_state["pos"])
                && window[0].player_state["pos"] != window[1].player_state["pos"];
            assert!(
                !cycling,
                "Aggressive sustained a two-tile movement cycle in seed 301"
            );
        }
    }

    #[test]
    fn cautious_seed_27_breaks_the_pursuer_oscillation() {
        let logged = Simulation::new_logged(
            SimulationConfig {
                scenario_seed: 27,
                strategy: Strategy::CautiousV1,
                map_width: 44,
                map_height: 28,
                max_turns: 500,
            },
            "cycle-regression.jsonl".to_owned(),
        )
        .unwrap()
        .run_logged();
        assert_ne!(logged.summary.outcome, RunOutcome::TurnLimit);
        let decisions: Vec<_> = logged
            .events
            .iter()
            .filter(|event| event.event == "decision")
            .collect();
        assert!(decisions
            .iter()
            .any(|event| event.details["observation"]["current_tile_visits"]
                .as_u64()
                .unwrap()
                >= 3));
        // Old code alternated between (13,15) and (14,15) for 487 decisions.
        for window in decisions.windows(12) {
            let first = &window[0].player_state["pos"];
            let second = &window[1].player_state["pos"];
            let cycling = first != second
                && window.iter().enumerate().all(|(index, event)| {
                    event.depth == window[0].depth
                        && event.details["action"]["type"] == "move"
                        && &event.player_state["pos"] == if index % 2 == 0 { first } else { second }
                });
            assert!(
                !cycling,
                "Cautious entered an extended two-tile movement cycle"
            );
        }
    }

    #[test]
    fn item_spawns_are_deterministic_valid_and_strategy_independent() {
        for seed in [1, 424242, 20260928] {
            let config = SimulationConfig {
                scenario_seed: seed,
                strategy: Strategy::AggressiveV1,
                map_width: 24,
                map_height: 18,
                max_turns: 120,
            };
            let a = Simulation::new(config).unwrap();
            let b = Simulation::new(SimulationConfig {
                strategy: Strategy::CautiousV1,
                ..config
            })
            .unwrap();
            assert_eq!(a.items, b.items);
            assert!(!a.items.is_empty());
            for item in &a.items {
                assert!(a.is_walkable(item.pos));
                assert_ne!(item.pos, a.player.pos);
                assert_ne!(item.pos, a.stairs);
                assert!(a.enemy_at(item.pos).is_none());
            }
        }
    }

    #[test]
    fn reaching_depth_five_clears_the_dungeon() {
        let mut simulation = Simulation::new(SimulationConfig {
            scenario_seed: 1,
            strategy: Strategy::AggressiveV1,
            map_width: 24,
            map_height: 18,
            max_turns: 120,
        })
        .expect("simulation starts");
        simulation.player.depth = MAX_DEPTH - 1;
        simulation.new_floor();
        simulation.enemies.clear();
        let direction = DIRECTIONS
            .into_iter()
            .find(|direction| simulation.is_walkable(simulation.stairs - *direction))
            .expect("stairs have an adjacent walkable tile");
        simulation.player.pos = simulation.stairs - direction;

        simulation.player_act(direction, "test-decision");

        assert!(simulation.game_over);
        assert_eq!(simulation.run_outcome, Some(RunOutcome::DungeonCleared));
        assert_eq!(simulation.player.depth, MAX_DEPTH);
    }

    #[test]
    fn line_of_sight_blocks_walls_and_corners_symmetrically() {
        let mut sim = item_test_simulation(Strategy::AggressiveV1);
        let from = Point { x: 2, y: 2 };
        for to in [
            Point { x: 8, y: 2 },
            Point { x: 2, y: 8 },
            Point { x: 8, y: 5 },
            Point { x: 5, y: 8 },
            Point { x: 6, y: 6 },
        ] {
            assert!(sim.has_line_of_sight(from, to));
            assert!(sim.has_line_of_sight(to, from));
        }
        sim.map[2][5] = false;
        assert!(!sim.has_line_of_sight(from, Point { x: 8, y: 2 }));
        assert!(!sim.has_line_of_sight(Point { x: 8, y: 2 }, from));
        sim.map[2][5] = true; // An open doorway restores the ray.
        assert!(sim.has_line_of_sight(from, Point { x: 8, y: 2 }));
        sim.map[2][3] = false;
        assert!(!sim.has_line_of_sight(from, Point { x: 6, y: 6 }));
        assert!(!sim.has_line_of_sight(Point { x: 6, y: 6 }, from));
        sim.map[2][3] = true;
        sim.map[3][2] = false;
        assert!(!sim.has_line_of_sight(from, Point { x: 6, y: 6 }));
        sim.map[3][2] = true;
        sim.map[3][3] = false;
        assert!(!sim.has_line_of_sight(from, Point { x: 6, y: 6 }));
        sim.map[3][3] = true;
        sim.map[3][4] = false; // A shallow ray intersects this wall.
        assert!(!sim.has_line_of_sight(from, Point { x: 8, y: 5 }));
        assert!(!sim.has_line_of_sight(Point { x: 8, y: 5 }, from));
        assert!(sim.has_line_of_sight(from, from));
        assert!(!sim.has_line_of_sight(from, Point { x: -1, y: 2 }));
    }

    #[test]
    fn archer_cover_matches_damage_danger_and_healing_prediction() {
        let mut sim = item_test_simulation(Strategy::CautiousV1);
        let enemy = Enemy {
            id: "covered-archer".to_owned(),
            kind: EnemyKind::Archer,
            windup_target: None,
            pos: Point { x: 6, y: 2 },
            hp: 6,
            attack: 14,
            defense: 0,
        };
        sim.enemies.push(enemy.clone());
        sim.player.hp = 14;
        sim.player.inventory.health_potion = 1;
        sim.map[2][4] = false;
        let events_before = sim.logger.as_ref().unwrap().events.len();
        sim.run_archer_turn(0, &enemy);
        assert_eq!(sim.player.hp, 14);
        assert_eq!(sim.logger.as_ref().unwrap().events.len(), events_before);
        assert_eq!(sim.danger_cost(sim.player.pos), 0);
        assert!(sim.choose_item_decision().is_none());
        sim.map[2][4] = true;
        assert_eq!(sim.danger_cost(sim.player.pos), 12);
        assert_eq!(
            sim.choose_item_decision().unwrap().rule_id,
            "use_health_potion"
        );
        sim.enemies[0].attack = 2;
        let visible = sim.enemies[0].clone();
        sim.run_archer_turn(0, &visible);
        assert_eq!(sim.player.hp, 12);
        assert_eq!(
            sim.logger.as_ref().unwrap().events.last().unwrap().details["ranged"],
            true
        );
        sim.enemies[0].pos = Point { x: 10, y: 2 }; // Visible but outside bow range.
        let distant = sim.enemies[0].clone();
        sim.run_archer_turn(0, &distant);
        assert_eq!(sim.player.hp, 12);
        assert_ne!(sim.enemies[0].pos, distant.pos);
        // Diagonal close combat must also respect a blocking corner.
        sim.enemies[0].pos = Point { x: 3, y: 3 };
        sim.map[2][3] = false;
        let diagonal = sim.enemies[0].clone();
        sim.run_archer_turn(0, &diagonal);
        assert_eq!(sim.player.hp, 12);
        assert_eq!(sim.enemies[0].pos, diagonal.pos);
    }

    #[test]
    fn cornered_archer_does_not_also_fire_a_ranged_attack() {
        let mut simulation = Simulation::new(SimulationConfig {
            scenario_seed: 1,
            strategy: Strategy::AggressiveV1,
            map_width: 24,
            map_height: 18,
            max_turns: 120,
        })
        .expect("simulation starts");
        simulation.map = vec![vec![false; 24]; 18];
        simulation.player.pos = Point { x: 2, y: 1 };
        simulation.map[1][1] = true;
        simulation.map[1][2] = true;
        simulation.enemies = vec![Enemy {
            id: "cornered-archer".to_owned(),
            kind: EnemyKind::Archer,
            windup_target: None,
            pos: Point { x: 1, y: 1 },
            hp: 6,
            attack: 3,
            defense: 0,
        }];
        let archer = simulation.enemies[0].clone();

        simulation.run_archer_turn(0, &archer);

        assert_eq!(simulation.player.hp, BASE_MAX_HP - 1);
        assert!(!simulation.game_over);
    }
}
