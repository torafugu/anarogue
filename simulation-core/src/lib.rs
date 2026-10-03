use serde::{Deserialize, Serialize};
use std::collections::{HashMap, VecDeque};
use std::fmt;

const MIN_ROOM_SIZE: i32 = 5;
const MAX_ROOM_SIZE: i32 = 11;
const BASE_MAX_HP: i32 = 18;
const BASE_ATTACK: i32 = 5;
const MAX_DEPTH: u32 = 5;
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

#[derive(Clone, Debug, Eq, PartialEq)]
struct Enemy {
    id: String,
    kind: EnemyKind,
    pos: Point,
    hp: i32,
    attack: i32,
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
    player: Player,
    stairs: Point,
    turn: u32,
    next_enemy_id: u32,
    game_over: bool,
    run_outcome: Option<RunOutcome>,
}

impl Simulation {
    pub fn new(config: SimulationConfig) -> Result<Self, String> {
        let config = config.validate()?;
        let mut simulation = Self {
            config,
            map: Vec::new(),
            rooms: Vec::new(),
            enemies: Vec::new(),
            player: Player::default(),
            stairs: Point::ZERO,
            turn: 0,
            next_enemy_id: 1,
            game_over: false,
            run_outcome: None,
        };
        simulation.new_floor();
        Ok(simulation)
    }

    pub fn run(mut self) -> RunSummary {
        while !self.game_over && self.turn < self.config.max_turns {
            self.run_auto_player_turn();
        }
        self.summary()
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
        }
    }

    fn new_floor(&mut self) {
        self.map =
            vec![vec![false; self.config.map_width as usize]; self.config.map_height as usize];
        self.rooms.clear();
        self.enemies.clear();

        let floor_seed =
            PortableRng::derive_seed(self.config.scenario_seed, "floor", self.player.depth, None);
        let spawn_seed =
            PortableRng::derive_seed(self.config.scenario_seed, "spawn", self.player.depth, None);
        self.generate_dungeon(&mut PortableRng::new(floor_seed));
        self.player.pos = self.rooms[0].center();
        self.stairs = self.rooms[self.rooms.len() - 1].center();
        if self.stairs == self.player.pos {
            self.stairs = self.farthest_walkable_tile_from(self.player.pos);
        }
        self.spawn_enemies(&mut PortableRng::new(spawn_seed));
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
        let direction = match self.config.strategy {
            Strategy::AggressiveV1 => self.choose_aggressive_direction(),
            Strategy::CautiousV1 => self.choose_cautious_direction(),
        };
        if direction == Point::ZERO {
            self.turn += 1;
            self.run_enemy_turn();
        } else {
            self.player_act(direction);
        }
    }

    fn choose_aggressive_direction(&self) -> Point {
        if let Some(direction) = self.direction_to_adjacent_enemy() {
            return direction;
        }
        if !self.enemies.is_empty() {
            let target = self.nearest_enemy().pos;
            return self.find_next_step_toward(target).unwrap_or(Point::ZERO);
        }
        self.find_next_step_toward(self.stairs)
            .unwrap_or(Point::ZERO)
    }

    fn choose_cautious_direction(&self) -> Point {
        let adjacent_direction = self.direction_to_adjacent_enemy();
        let stairs_direction = self.find_low_risk_step_toward(self.stairs);
        if let Some(direction) = adjacent_direction {
            let enemy_index = self
                .enemy_at(self.player.pos + direction)
                .expect("adjacent enemy remains present");
            let can_escape_via_stairs = stairs_direction
                .is_some_and(|stairs_step| self.player.pos + stairs_step == self.stairs);
            if self.enemies[enemy_index].kind == EnemyKind::Melee && !can_escape_via_stairs {
                return direction;
            }
        }
        if let Some(direction) = stairs_direction {
            return direction;
        }
        adjacent_direction.unwrap_or(Point::ZERO)
    }

    fn find_next_step_toward(&self, destination: Point) -> Option<Point> {
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
                let new_cost = costs[&current] + 1 + self.danger_cost(next);
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

    fn nearest_enemy(&self) -> &Enemy {
        let mut best = &self.enemies[0];
        let mut best_distance = self.player.pos.distance_squared(best.pos);
        for enemy in &self.enemies {
            let distance = self.player.pos.distance_squared(enemy.pos);
            if distance < best_distance {
                best = enemy;
                best_distance = distance;
            }
        }
        best
    }

    fn player_act(&mut self, direction: Point) {
        let target = self.player.pos + direction;
        if !self.is_walkable(target) {
            return;
        }
        self.turn += 1;
        if let Some(enemy_index) = self.enemy_at(target) {
            self.attack_enemy(enemy_index);
        } else {
            self.player.pos = target;
            if self.player.pos == self.stairs {
                self.player.depth += 1;
                self.player.score += 3;
                self.player.hp = (self.player.hp + 4).min(self.player.max_hp);
                if self.player.depth >= MAX_DEPTH {
                    self.game_over = true;
                    self.run_outcome = Some(RunOutcome::DungeonCleared);
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
        self.enemies[index].hp -= damage;
        if self.enemies[index].hp > 0 {
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
            self.damage_player(enemy.attack);
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
        let distance = enemy.pos.distance_squared(self.player.pos);
        if distance <= 2 {
            if self.try_archer_retreat(index, enemy.pos) {
                return;
            }
            self.damage_player(1);
            return;
        }
        if distance <= 49 {
            if self.can_enemy_see_player(enemy.pos) {
                self.damage_player(enemy.attack);
            }
            return;
        }
        if self.can_enemy_see_player(enemy.pos) {
            let delta = self.player.pos - enemy.pos;
            let step = self.choose_enemy_step(enemy.pos, delta);
            self.try_move_enemy(index, enemy.pos + step);
        }
    }

    fn damage_player(&mut self, damage: i32) {
        self.player.hp = (self.player.hp - damage).max(0);
        if self.player.hp == 0 {
            self.game_over = true;
            self.run_outcome = Some(RunOutcome::PlayerDefeated);
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

        simulation.player_act(direction);

        assert!(simulation.game_over);
        assert_eq!(simulation.run_outcome, Some(RunOutcome::DungeonCleared));
        assert_eq!(simulation.player.depth, MAX_DEPTH);
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
