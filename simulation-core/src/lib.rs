use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::{HashMap, VecDeque};
use std::fmt;
use std::time::{SystemTime, UNIX_EPOCH};

const MIN_ROOM_SIZE: i32 = 5;
const MAX_ROOM_SIZE: i32 = 11;
const BASE_MAX_HP: i32 = 18;
const BASE_ATTACK: i32 = 5;
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
}

impl EnemyKind {
    fn id(self) -> &'static str {
        match self {
            Self::Melee => "melee",
            Self::Archer => "archer",
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct Enemy {
    id: String,
    kind: EnemyKind,
    pos: Point,
    hp: i32,
    attack: i32,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
struct FloorItem {
    id: String,
    #[serde(rename = "type")]
    kind: &'static str,
    pos: Point,
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
    attack: i32,
    gold: u32,
    score: u32,
    level: u32,
    xp: u32,
    depth: u32,
    inventory: Inventory,
}

#[derive(Clone, Debug)]
struct Decision {
    direction: Point,
    rule_id: &'static str,
    reason: &'static str,
    action_type: &'static str,
    target: Value,
    selected_step_danger: Option<i32>,
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
            attack: BASE_ATTACK,
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
        Self::create(config, None)
    }

    pub fn new_logged(config: SimulationConfig, log_file: String) -> Result<Self, String> {
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
        )
    }

    fn create(config: SimulationConfig, logger: Option<EventLogger>) -> Result<Self, String> {
        let config = config.validate()?;
        let mut simulation = Self {
            config,
            map: Vec::new(),
            rooms: Vec::new(),
            enemies: Vec::new(),
            items: Vec::new(),
            navigation_visits: HashMap::new(),
            aggressive_target_id: None,
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
            "simulation_version": 3,
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
            schema_version: 3,
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
            "attack": self.player.attack,
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
            "distance_squared": enemy.pos.distance_squared(self.player.pos),
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
                pos,
            });
        }
    }

    fn pick_up_items(&mut self, decision_id: &str) {
        let Some(index) = self
            .items
            .iter()
            .position(|item| item.pos == self.player.pos)
        else {
            return;
        };
        if self.player.inventory.health_potion >= INVENTORY_CAPACITY {
            return;
        }
        let item = self.items.remove(index);
        self.player.inventory.health_potion += 1;
        self.emit_event(
            "item_result",
            json!({
                "result": "item_picked_up", "item": item,
                "inventory": self.player.inventory, "decision_id": decision_id,
            }),
        );
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
        let incoming: i32 = self
            .enemies
            .iter()
            .map(|enemy| match enemy.kind {
                EnemyKind::Melee if enemy.pos.manhattan_distance(self.player.pos) == 1 => {
                    enemy.attack
                }
                EnemyKind::Archer
                    if self.has_line_of_sight(enemy.pos, self.player.pos)
                        && enemy.pos.distance_squared(self.player.pos) <= 2 =>
                {
                    1
                }
                EnemyKind::Archer
                    if self.has_line_of_sight(enemy.pos, self.player.pos)
                        && enemy.pos.distance_squared(self.player.pos) <= 49 =>
                {
                    enemy.attack
                }
                _ => 0,
            })
            .sum();
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
            });
        }
        if self.player.inventory.health_potion >= INVENTORY_CAPACITY
            || self.direction_to_adjacent_enemy().is_some()
        {
            return None;
        }
        // Cautious never gathers under current threat; its entire item route must be safe.
        if cautious && self.danger_cost(self.player.pos) > 0 {
            return None;
        }
        let limit = if cautious { 4 } else { 8 };
        let mut best: Option<(usize, Point, &FloorItem)> = None;
        for item in &self.items {
            if let Some((steps, direction)) = self.item_route(item.pos, limit, cautious) {
                if best
                    .as_ref()
                    .is_none_or(|(best_steps, _, _)| steps < *best_steps)
                {
                    best = Some((steps, direction, item));
                }
            }
        }
        best.map(|(_, direction, item)| Decision {
            direction,
            rule_id: if cautious { "cautious_collect_potion" } else { "collect_nearby_potion" },
            reason: if cautious { "A potion is within four safe steps, so the cautious strategy makes a short detour." }
                else { "A potion is within eight unobstructed steps, so the aggressive strategy gathers supplies." },
            action_type: "move", target: json!(item),
            selected_step_danger: Some(self.danger_cost(self.player.pos + direction)),
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
        let depth = self.player.depth as i32;
        let (hp, attack) = match kind {
            EnemyKind::Melee => (8 + depth * 2, 2 + depth),
            EnemyKind::Archer => (5 + depth, 1 + depth / 2),
        };
        self.enemies.push(Enemy {
            id,
            kind,
            pos,
            hp,
            attack,
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
        let decision = self
            .choose_item_decision()
            .unwrap_or_else(|| match self.config.strategy {
                Strategy::AggressiveV1 => self.choose_aggressive_decision(),
                Strategy::CautiousV1 => self.choose_cautious_decision(),
            });
        if decision.rule_id == "hunt_nearest_enemy" {
            self.aggressive_target_id = decision.target["id"].as_str().map(str::to_owned);
        }
        let decision_id = self.emit_decision(&decision);
        if decision.action_type == "use_item" {
            self.use_health_potion(&decision_id);
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
            };
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
            if self.enemies[enemy_index].kind == EnemyKind::Melee && !can_escape_via_stairs {
                return Decision {
                    direction,
                    rule_id: "attack_pursuing_melee",
                    reason: "An adjacent melee enemy can match the player's speed, so retreat would not create distance.",
                    action_type: "attack",
                    target: self.enemy_snapshot(&self.enemies[enemy_index]),
                    selected_step_danger: Some(self.danger_cost(self.player.pos)),
                };
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
            };
        }
        Decision {
            direction: Point::ZERO,
            rule_id: "wait_no_safe_path",
            reason: "No route to the stairs or adjacent target is currently available.",
            action_type: "wait",
            target: json!({"kind": "stairs", "pos": self.stairs}),
            selected_step_danger: Some(self.danger_cost(self.player.pos)),
        }
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
            "enemy_count": self.enemies.len(),
            "enemies": self.enemy_snapshots(),
            "stairs_pos": self.stairs,
            "stairs_distance_squared": self.player.pos.distance_squared(self.stairs),
            "current_danger": self.danger_cost(self.player.pos),
            "current_tile_visits": self.navigation_visits.get(&self.player.pos).copied().unwrap_or(0),
            "items": self.items,
            "inventory": self.player.inventory,
        });
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
                if !self.is_path_walkable(next, destination) {
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
        let damage = self.player.attack;
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
                    "damage": damage,
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
            EnemyKind::Archer => {
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
                "damage": damage,
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
            self.player.attack += 1;
            xp_needed = self.player.level * 8;
        }
    }

    fn run_enemy_turn(&mut self) {
        for index in 0..self.enemies.len() {
            let enemy = self.enemies[index].clone();
            match enemy.kind {
                EnemyKind::Melee => self.run_melee_turn(index, &enemy),
                EnemyKind::Archer => self.run_archer_turn(index, &enemy),
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
        let hp_before = self.player.hp;
        self.player.hp = (self.player.hp - damage).max(0);
        let mut details = json!({
            "result": "player_hit",
            "enemy_id": enemy.id,
            "enemy_type": enemy.kind.id(),
            "enemy_pos": enemy.pos,
            "damage": damage,
            "player_hp_before": hp_before,
            "player_hp_after": self.player.hp,
        });
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
        assert_eq!(logged_run.events[0].schema_version, 3);
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

    #[test]
    fn pickup_is_part_of_movement_and_capacity_leaves_item_on_floor() {
        let mut sim = item_test_simulation(Strategy::AggressiveV1);
        let pos = sim.player.pos + DIRECTIONS[3];
        sim.items.push(FloorItem {
            id: "potion".to_owned(),
            kind: "health_potion",
            pos,
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
            pos: sim.player.pos + DIRECTIONS[3],
            hp: 10,
            attack: 3,
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
            pos: Point { x: 5, y: 2 },
            hp: 10,
            attack: 3,
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
    fn aggressive_keeps_target_and_reselects_when_dead_or_unreachable() {
        let mut sim = item_test_simulation(Strategy::AggressiveV1);
        let enemy = |id: &str, x, y| Enemy {
            id: id.to_owned(),
            kind: EnemyKind::Archer,
            pos: Point { x, y },
            hp: 6,
            attack: 1,
        };
        sim.enemies = vec![enemy("first", 8, 2), enemy("second", 2, 9)];
        sim.run_auto_player_turn();
        assert_eq!(sim.aggressive_target_id.as_deref(), Some("first"));
        // Another enemy becomes closer; the pursuit must not reverse.
        sim.enemies[1].pos = Point { x: 3, y: 5 };
        assert_eq!(sim.choose_aggressive_decision().target["id"], "first");
        // Healing does not erase the pursuit.
        sim.player.inventory.health_potion = 1;
        sim.player.hp = 9;
        sim.run_auto_player_turn();
        assert_eq!(sim.aggressive_target_id.as_deref(), Some("first"));
        assert_eq!(sim.choose_aggressive_decision().target["id"], "first");
        let locked = sim.enemies[0].pos;
        for direction in DIRECTIONS {
            let wall = locked + direction;
            sim.map[wall.y as usize][wall.x as usize] = false;
        }
        assert_eq!(sim.choose_aggressive_decision().target["id"], "second");
        sim.enemies.remove(0);
        assert_eq!(sim.choose_aggressive_decision().target["id"], "second");
        sim.new_floor();
        assert!(sim.aggressive_target_id.is_none());
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
        for window in decisions.windows(3) {
            let cycling = window
                .iter()
                .all(|event| event.details["action"]["type"] == "move")
                && window[0].player_state["pos"] == window[2].player_state["pos"]
                && window[0].player_state["pos"] != window[1].player_state["pos"];
            assert!(
                !cycling,
                "Aggressive reversed between two tiles in seed 301"
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
            pos: Point { x: 6, y: 2 },
            hp: 6,
            attack: 14,
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
            pos: Point { x: 1, y: 1 },
            hp: 6,
            attack: 3,
        }];
        let archer = simulation.enemies[0].clone();

        simulation.run_archer_turn(0, &archer);

        assert_eq!(simulation.player.hp, BASE_MAX_HP - 1);
        assert!(!simulation.game_over);
    }
}
