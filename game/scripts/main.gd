extends Node2D

const PortableRandom := preload("res://scripts/portable_rng.gd")

enum StrategyType {
	AGGRESSIVE,
	CAUTIOUS,
}

const HUD_WIDTH := 360.0
const TILE_SIZE := 40
const MIN_ROOM_SIZE := 5
const MAX_ROOM_SIZE := 11
const AUTO_TURN_DELAY := 0.18
const ARROW_FLIGHT_DURATION := 0.28
const ARROW_IMPACT_DURATION := 0.12

const TILE_WALL := 0
const TILE_FLOOR := 1
const DEFAULT_LOG_FILE_PATH := "user://anarogue.jsonl"
const LOG_SCHEMA_VERSION := 5
const POTION_HEAL := 8
const INVENTORY_CAPACITY := 3
const BASE_MAX_HP := 18
const BASE_ATTACK := 5
const MAX_DEPTH := 5
const COMPARISON_TRANSITION_DELAY := 1.0

const COLORS := {
	"bg": Color("#15171d"),
	"wall": Color("#303845"),
	"wall_edge": Color("#465266"),
	"floor": Color("#242a32"),
	"floor_alt": Color("#29313b"),
	"player": Color("#f2d16b"),
	"enemy": Color("#d85f5f"),
	"archer": Color("#6ecbff"),
	"stairs": Color("#79c7a6"),
	"text": Color("#e7e1cf"),
	"muted": Color("#9aa4b2"),
	"danger": Color("#ff8a80"),
	"panel": Color("#20252e"),
}

var map_width := 44
var map_height := 28
var map_scale := 1.0
var map_offset := Vector2.ZERO

var metadata_rng := RandomNumberGenerator.new()
var map: Array = []
var rooms: Array[Rect2i] = []
var enemies: Array[Dictionary] = []
var items: Array[Dictionary] = []
var navigation_visits: Dictionary = {}
var aggressive_target_id := ""
var growth_target_id := ""
var player := {
	"pos": Vector2i.ZERO,
	"hp": 18,
	"max_hp": 18,
	"base_attack": 5,
	"base_defense": 0,
	"equipment": {"weapon": null, "armor": null},
	"gold": 0,
	"score": 0,
	"level": 1,
	"xp": 0,
	"depth": 1,
	"inventory": {"health_potion": 0},
}
var stairs_pos := Vector2i.ZERO
var messages: Array[String] = []
var game_over := false
var run_outcome := ""
var font := ThemeDB.fallback_font
var log_file: FileAccess
var run_id := ""
var turn_count := 0
var event_sequence := 0
var decision_sequence := 0
var next_enemy_id := 1
var auto_turn_elapsed := 0.0
var auto_exploration_started := false
var scenario_seed := 0
var active_strategy: StrategyType = StrategyType.AGGRESSIVE
var comparison_active := false
var comparison_phase := 0
var comparison_transition_elapsed := 0.0
var start_button: Button
var compare_button: Button
var strategy_option: OptionButton
var arrows: Array[Dictionary] = []
var headless_mode := false
var log_file_path := DEFAULT_LOG_FILE_PATH
var truncate_log_on_open := false
var configured_map_width := 0
var configured_map_height := 0
var fixed_run_id := ""
var fixed_event_time := ""
var logged_file_path := ""

func _ready() -> void:
	metadata_rng.randomize()
	if not headless_mode:
		scenario_seed = create_scenario_seed()
		create_controls()
		get_viewport().size_changed.connect(update_layout)
	open_log_file()
	start_run_log()
	new_floor()

func configure_headless(seed_value: int, strategy: StrategyType, output_path: String) -> void:
	headless_mode = true
	scenario_seed = seed_value
	active_strategy = strategy
	log_file_path = output_path
	truncate_log_on_open = true

func configure_headless_map(width: int, height: int) -> void:
	assert(headless_mode)
	assert(width >= MAX_ROOM_SIZE + 4)
	assert(height >= MAX_ROOM_SIZE + 4)
	configured_map_width = width
	configured_map_height = height

func configure_reference_log(
	run_id_value: String,
	event_time: String,
	display_path: String
) -> void:
	assert(headless_mode)
	assert(not run_id_value.is_empty())
	assert(not event_time.is_empty())
	fixed_run_id = run_id_value
	fixed_event_time = event_time
	logged_file_path = display_path

func start_automatic_run() -> void:
	if game_over:
		return

	comparison_phase = 0
	auto_exploration_started = true
	auto_turn_elapsed = 0.0
	update_controls_state()
	log_user_action("start", "auto_exploration_started")
	add_message("%s strategy started." % strategy_display_name(active_strategy))
	queue_redraw()

func close_log_file() -> void:
	if log_file:
		log_file.flush()
		log_file.close()
		log_file = null

func _process(delta: float) -> void:
	# Finish projectiles even when the final shot has ended the run.
	if not arrows.is_empty():
		for i in range(arrows.size() - 1, -1, -1):
			arrows[i]["elapsed"] += delta
			if arrows[i]["elapsed"] >= ARROW_FLIGHT_DURATION + ARROW_IMPACT_DURATION:
				arrows.remove_at(i)
		queue_redraw()
		return

	if game_over:
		if comparison_active and comparison_phase == 0:
			comparison_transition_elapsed += delta
			if comparison_transition_elapsed >= COMPARISON_TRANSITION_DELAY:
				start_cautious_comparison_run()
		return

	if not auto_exploration_started:
		return

	auto_turn_elapsed += delta
	if auto_turn_elapsed < AUTO_TURN_DELAY:
		return

	auto_turn_elapsed = 0.0
	run_auto_player_turn()

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return

	if Input.is_action_just_pressed("restart"):
		log_user_action("restart", "new_run")
		log_battle_result("restart", {
			"reason": "user_restart",
		})
		comparison_active = false
		comparison_phase = 0
		restart_game(false, false)
		return

	if game_over or not arrows.is_empty():
		return

	if event is InputEventKey and event.keycode == KEY_H:
		use_health_potion()
		return
	var direction := Vector2i.ZERO
	if Input.is_action_just_pressed("move_up"):
		direction = Vector2i.UP
	elif Input.is_action_just_pressed("move_down"):
		direction = Vector2i.DOWN
	elif Input.is_action_just_pressed("move_left"):
		direction = Vector2i.LEFT
	elif Input.is_action_just_pressed("move_right"):
		direction = Vector2i.RIGHT
	elif Input.is_action_just_pressed("wait_turn"):
		turn_count += 1
		log_user_action("wait", "turn_advanced")
		add_message("You listen to the dungeon.")
		run_enemy_turn()
		queue_redraw()
		return

	if direction != Vector2i.ZERO:
		player_act(direction)

func restart_game(reuse_scenario: bool = false, auto_start: bool = false) -> void:
	if not reuse_scenario:
		scenario_seed = create_scenario_seed()

	player["max_hp"] = BASE_MAX_HP
	player["hp"] = BASE_MAX_HP
	player["base_attack"] = BASE_ATTACK
	player["base_defense"] = 0
	player["equipment"] = {"weapon": null, "armor": null}
	player["gold"] = 0
	player["score"] = 0
	player["level"] = 1
	player["xp"] = 0
	player["inventory"] = {"health_potion": 0}
	player["depth"] = 1
	turn_count = 0
	event_sequence = 0
	decision_sequence = 0
	next_enemy_id = 1
	auto_turn_elapsed = 0.0
	auto_exploration_started = auto_start
	game_over = false
	run_outcome = ""
	messages.clear()
	start_run_log()
	new_floor()
	if auto_start:
		log_user_action("start", "auto_exploration_started", {
			"comparison": comparison_active,
		})
		add_message("%s strategy started." % strategy_display_name(active_strategy))
	update_controls_state()

func create_controls() -> void:
	strategy_option = OptionButton.new()
	strategy_option.add_item("Aggressive — hunt every enemy", StrategyType.AGGRESSIVE)
	strategy_option.add_item("Cautious — avoid danger", StrategyType.CAUTIOUS)
	strategy_option.select(StrategyType.AGGRESSIVE)
	strategy_option.size = Vector2(HUD_WIDTH - 32, 48)
	strategy_option.add_theme_font_size_override("font_size", 18)
	strategy_option.item_selected.connect(_on_strategy_selected)
	add_child(strategy_option)

	start_button = Button.new()
	start_button.text = "Start selected strategy"
	start_button.size = Vector2(HUD_WIDTH - 32, 52)
	start_button.add_theme_font_size_override("font_size", 20)
	start_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	start_button.focus_mode = Control.FOCUS_NONE
	start_button.pressed.connect(_on_start_button_pressed)
	add_child(start_button)

	compare_button = Button.new()
	compare_button.text = "Compare both — same seed"
	compare_button.size = Vector2(HUD_WIDTH - 32, 52)
	compare_button.add_theme_font_size_override("font_size", 18)
	compare_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	compare_button.focus_mode = Control.FOCUS_NONE
	compare_button.pressed.connect(_on_compare_button_pressed)
	add_child(compare_button)

func _on_strategy_selected(index: int) -> void:
	if auto_exploration_started or comparison_active:
		return
	active_strategy = index
	comparison_phase = 0
	log_battle_result("restart", {
		"reason": "strategy_changed",
	})
	restart_game(true, false)

func _on_start_button_pressed() -> void:
	start_automatic_run()

func _on_compare_button_pressed() -> void:
	if auto_exploration_started:
		return
	comparison_active = true
	comparison_phase = 0
	comparison_transition_elapsed = 0.0
	active_strategy = StrategyType.AGGRESSIVE
	strategy_option.select(StrategyType.AGGRESSIVE)
	scenario_seed = create_scenario_seed()
	restart_game(true, true)

func start_cautious_comparison_run() -> void:
	comparison_phase = 1
	comparison_transition_elapsed = 0.0
	active_strategy = StrategyType.CAUTIOUS
	strategy_option.select(StrategyType.CAUTIOUS)
	restart_game(true, true)

func update_controls_state() -> void:
	if not start_button or not compare_button or not strategy_option:
		return

	var controls_available := not auto_exploration_started and not comparison_active
	start_button.visible = controls_available
	start_button.disabled = not controls_available or game_over
	compare_button.visible = controls_available
	compare_button.disabled = not controls_available or game_over
	strategy_option.disabled = not controls_available

func create_scenario_seed() -> int:
	return metadata_rng.randi()

func strategy_id(strategy: StrategyType) -> String:
	return "cautious_v1" if strategy == StrategyType.CAUTIOUS else "aggressive_v1"

func strategy_display_name(strategy: StrategyType) -> String:
	return "Cautious" if strategy == StrategyType.CAUTIOUS else "Aggressive"

func current_scenario_id() -> String:
	return "scenario-%d" % scenario_seed

func map_available_size() -> Vector2:
	var viewport_size := get_viewport_rect().size
	return Vector2(maxf(viewport_size.x - HUD_WIDTH, TILE_SIZE), viewport_size.y)

func update_layout() -> void:
	var available := map_available_size()
	var grid_size := Vector2(map_width, map_height) * TILE_SIZE
	map_scale = minf(available.x / grid_size.x, available.y / grid_size.y)
	map_offset = (available - grid_size * map_scale) * 0.5
	if strategy_option and start_button and compare_button:
		strategy_option.position = Vector2(available.x + 16, 292)
		start_button.position = Vector2(available.x + 16, 350)
		compare_button.position = Vector2(available.x + 16, 412)
	queue_redraw()

func new_floor() -> void:
	arrows.clear()
	if configured_map_width > 0 and configured_map_height > 0:
		map_width = configured_map_width
		map_height = configured_map_height
	else:
		# Generate for the current viewport; resizing an active floor preserves the run.
		var available := map_available_size()
		map_width = maxi(MAX_ROOM_SIZE + 4, int(available.x / TILE_SIZE))
		map_height = maxi(MAX_ROOM_SIZE + 4, int(available.y / TILE_SIZE))
	update_layout()
	map.clear()
	rooms.clear()
	enemies.clear()
	items.clear()
	for y in range(map_height):
		var row := []
		for x in range(map_width):
			row.append(TILE_WALL)
		map.append(row)

	var floor_seed := derived_seed("floor", player["depth"])
	var spawn_seed := derived_seed("spawn", player["depth"])
	var floor_rng := PortableRandom.new(floor_seed)
	var spawn_rng := PortableRandom.new(spawn_seed)

	generate_dungeon(floor_rng)
	player["pos"] = rooms[0].get_center()
	navigation_visits.clear()
	aggressive_target_id = ""
	growth_target_id = ""
	navigation_visits[player["pos"]] = 1
	stairs_pos = rooms[rooms.size() - 1].get_center()
	if stairs_pos == player["pos"]:
		stairs_pos = farthest_walkable_tile_from(player["pos"])
	spawn_enemies(spawn_rng)
	var item_seed := derived_seed("items", player["depth"])
	spawn_items(PortableRandom.new(item_seed))
	log_event("floor_start", {
		"floor_seed": floor_seed,
		"spawn_seed": spawn_seed,
		"item_seed": item_seed,
		"items": items_to_log(),
		"enemy_count": enemies.size(),
		"enemies": enemies_to_log(),
		"map_size": {"width": map_width, "height": map_height},
		"map_rows": map_rows_to_log(),
		"player_pos": vector_to_log(player["pos"]),
		"stairs_pos": vector_to_log(stairs_pos),
	})
	add_message("Depth %d. Find the green stairs." % player["depth"])
	queue_redraw()

func spawn_items(item_rng: PortableRandom) -> void:
	for room_index in range(mini(rooms.size(), 3)):
		var room := rooms[room_index]
		var candidates: Array[Vector2i] = []
		for y in range(room.position.y + 1, room.end.y - 1):
			for x in range(room.position.x + 1, room.end.x - 1):
				var pos := Vector2i(x, y)
				if pos != player["pos"] and pos != stairs_pos and enemy_at(pos) == -1:
					candidates.append(pos)
		if candidates.is_empty():
			continue
		var pos := candidates[item_rng.randi_range(0, candidates.size() - 1)]
		items.append({"id": "item-%d-%d" % [player["depth"], room_index + 1], "type": "health_potion", "pos": pos})
	spawn_equipment()

func attack_bonus() -> int:
	var weapon = player["equipment"]["weapon"]
	return int(weapon["attack_bonus"]) if weapon != null else 0

func defense_bonus() -> int:
	var armor = player["equipment"]["armor"]
	return int(armor["defense_bonus"]) if armor != null else 0

func effective_attack() -> int:
	return int(player["base_attack"]) + attack_bonus()

func effective_defense() -> int:
	return int(player["base_defense"]) + defense_bonus()

func calculate_damage(attack: int, defense: int) -> int:
	return maxi(1, attack - defense)

func wants_item(item: Dictionary) -> bool:
	match item["type"]:
		"health_potion": return player["inventory"]["health_potion"] < INVENTORY_CAPACITY
		"weapon": return int(item.get("attack_bonus", 0)) > attack_bonus()
		"armor": return int(item.get("defense_bonus", 0)) > defense_bonus()
	return false

func spawn_equipment() -> void:
	var equipment_rng := PortableRandom.new(derived_seed("equipment", player["depth"]))
	for kind in ["weapon", "armor"]:
		var room_index := 0 if kind == "weapon" else mini(rooms.size(), 2) - 1
		var room := rooms[room_index]
		var candidates: Array[Vector2i] = []
		for y in range(room.position.y + 1, room.end.y - 1):
			for x in range(room.position.x + 1, room.end.x - 1):
				var pos := Vector2i(x, y)
				var occupied := false
				for item in items:
					if item["pos"] == pos:
						occupied = true
				if pos != player["pos"] and pos != stairs_pos and enemy_at(pos) == -1 and not occupied:
					candidates.append(pos)
		if candidates.is_empty():
			continue
		var pos := candidates[equipment_rng.randi_range(0, candidates.size() - 1)]
		items.append({"id": "%s-%d" % [kind, player["depth"]], "type": kind, "pos": pos,
			"attack_bonus": int(player["depth"]) + 1 if kind == "weapon" else 0,
			"defense_bonus": (int(player["depth"]) + 1) / 2 if kind == "armor" else 0})

func item_to_log(item: Dictionary) -> Dictionary:
	return {"id": item["id"], "type": item["type"], "pos": vector_to_log(item["pos"]),
		"attack_bonus": int(item.get("attack_bonus", 0)), "defense_bonus": int(item.get("defense_bonus", 0))}

func items_to_log() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in items:
		result.append(item_to_log(item))
	return result

func pick_up_items(decision_id: String = "") -> void:
	var index := 0
	while index < items.size():
		var item := items[index]
		if item["pos"] != player["pos"] or not wants_item(item):
			index += 1
			continue
		items.remove_at(index)
		if item["type"] == "health_potion":
			player["inventory"]["health_potion"] += 1
			log_event("item_result", {"result": "item_picked_up", "item": item_to_log(item),
				"inventory": player["inventory"].duplicate(), "decision_id": decision_id})
			add_message("Picked up a health potion.")
			continue
		var slot: String = item["type"]
		var previous = player["equipment"][slot]
		player["equipment"][slot] = {"id": item["id"], "type": slot,
			"attack_bonus": int(item.get("attack_bonus", 0)), "defense_bonus": int(item.get("defense_bonus", 0))}
		if previous != null:
			var dropped: Dictionary = previous.duplicate(true)
			dropped["pos"] = player["pos"]
			items.append(dropped)
		log_event("item_result", {"result": "item_equipped", "item": item_to_log(item),
			"previous_equipment": previous, "equipment": player["equipment"].duplicate(true),
			"items": items_to_log(), "inventory": player["inventory"].duplicate(), "decision_id": decision_id})
		add_message("Equipped %s." % slot)

func use_health_potion(decision_id: String = "") -> void:
	if game_over or player["inventory"]["health_potion"] == 0 or player["hp"] >= player["max_hp"]:
		return
	turn_count += 1
	var hp_before: int = player["hp"]
	player["inventory"]["health_potion"] -= 1
	player["hp"] = mini(player["hp"] + POTION_HEAL, player["max_hp"])
	var action_details := {"item_type": "health_potion"}
	add_decision_reference(action_details, decision_id)
	log_user_action("use_item", "item_used", action_details)
	log_event("item_result", {
		"result": "item_used", "item_type": "health_potion",
		"hp_before": hp_before, "hp_after": player["hp"], "healed": player["hp"] - hp_before,
		"inventory": player["inventory"].duplicate(), "decision_id": decision_id,
	})
	add_message("Health potion restored %d HP." % [player["hp"] - hp_before])
	run_enemy_turn()
	queue_redraw()

func choose_item_decision(decision_id: String) -> Dictionary:
	var cautious := active_strategy == StrategyType.CAUTIOUS
	var threshold := 2 if cautious else 3
	var player_pos: Vector2i = player["pos"]
	var incoming := incoming_damage_at(player_pos)
	if player["inventory"]["health_potion"] > 0 and player["hp"] < player["max_hp"] and (
		player["max_hp"] - player["hp"] >= POTION_HEAL
		or player["hp"] * threshold <= player["max_hp"] or player["hp"] <= incoming
	):
		return {
			"decision_id": decision_id, "direction": Vector2i.ZERO,
			"rule_id": "use_health_potion",
			"reason": "Healing is efficient, HP is low, or the next enemy phase could be lethal.",
			"action_type": "use_item", "target": {"kind": "inventory_item", "type": "health_potion"},
			"selected_step_danger": danger_cost(player_pos),
		}
	if direction_to_adjacent_enemy() != Vector2i.ZERO:
		return {}
	if cautious and danger_cost(player_pos) > 0:
		return {}
	var limit := 4 if cautious else 8
	var best: Dictionary = {}
	for item in items:
		if not wants_item(item):
			continue
		var route := item_route(item["pos"], limit, cautious)
		if not route.is_empty() and (best.is_empty() or route["steps"] < best["steps"]):
			best = route
			best["item"] = item
	if best.is_empty():
		return {}
	var direction: Vector2i = best["direction"]
	var is_potion: bool = best["item"]["type"] == "health_potion"
	return {
		"decision_id": decision_id, "direction": direction,
		"rule_id": ("cautious_collect_potion" if cautious else "collect_nearby_potion") if is_potion else ("cautious_collect_equipment" if cautious else "collect_nearby_equipment"),
		"reason": "A stronger piece of equipment is within the item detour limit." if not is_potion else (
			"A potion is within four safe steps, so the cautious strategy makes a short detour."
			if cautious else "A potion is within eight unobstructed steps, so the aggressive strategy gathers supplies."
		),
		"action_type": "move", "target": item_to_log(best["item"]),
		"selected_step_danger": danger_cost(player_pos + direction),
	}

func item_route(destination: Vector2i, limit: int, safe_only: bool) -> Dictionary:
	var start: Vector2i = player["pos"]
	var frontier: Array[Vector2i] = [start]
	var came_from := {start: start}
	var costs := {start: 0}
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		if current == destination:
			if current == start:
				return {}
			var step := destination
			while came_from[step] != start:
				step = came_from[step]
			return {"steps": costs[current], "direction": step - start}
		if costs[current] >= limit:
			continue
		for direction in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = current + direction
			if came_from.has(next) or not is_walkable(next) or next == stairs_pos or enemy_at(next) != -1:
				continue
			if safe_only and danger_cost(next) > 0:
				continue
			came_from[next] = current
			costs[next] = costs[current] + 1
			frontier.append(next)
	return {}

func derived_seed(channel: String, depth: int) -> int:
	return PortableRandom.derive_seed(scenario_seed, channel, depth)

func generate_dungeon(floor_rng: PortableRandom) -> void:
	var room_target := maxi(2, int(round(map_width * map_height / 112.0)))
	for i in range(room_target * 8):
		if rooms.size() >= room_target:
			break

		var w := floor_rng.randi_range(MIN_ROOM_SIZE, MAX_ROOM_SIZE)
		var h := floor_rng.randi_range(MIN_ROOM_SIZE, MAX_ROOM_SIZE)
		var x := floor_rng.randi_range(1, map_width - w - 2)
		var y := floor_rng.randi_range(1, map_height - h - 2)
		var room := Rect2i(x, y, w, h)

		var overlaps := false
		for existing in rooms:
			if room.grow(1).intersects(existing):
				overlaps = true
				break

		if overlaps:
			continue

		carve_room(room)
		if not rooms.is_empty():
			connect_rooms(rooms.back().get_center(), room.get_center(), floor_rng)
		rooms.append(room)

	if rooms.is_empty():
		var fallback := Rect2i(4, 4, 12, 10)
		carve_room(fallback)
		rooms.append(fallback)

func carve_room(room: Rect2i) -> void:
	for y in range(room.position.y, room.end.y):
		for x in range(room.position.x, room.end.x):
			map[y][x] = TILE_FLOOR

func connect_rooms(a: Vector2i, b: Vector2i, floor_rng: PortableRandom) -> void:
	if floor_rng.chance(1, 2):
		carve_horizontal(a.x, b.x, a.y)
		carve_vertical(a.y, b.y, b.x)
	else:
		carve_vertical(a.y, b.y, a.x)
		carve_horizontal(a.x, b.x, b.y)

func carve_horizontal(x1: int, x2: int, y: int) -> void:
	for x in range(mini(x1, x2), maxi(x1, x2) + 1):
		map[y][x] = TILE_FLOOR

func carve_vertical(y1: int, y2: int, x: int) -> void:
	for y in range(mini(y1, y2), maxi(y1, y2) + 1):
		map[y][x] = TILE_FLOOR

func spawn_enemies(spawn_rng: PortableRandom) -> void:
	for i in range(1, rooms.size() - 1):
		if not spawn_rng.chance(3, 4):
			continue
		spawn_enemy_in_room(rooms[i], spawn_rng)
	if enemies.is_empty():
		spawn_enemy_in_room(rooms.back(), spawn_rng)

func spawn_enemy_in_room(room: Rect2i, spawn_rng: PortableRandom) -> void:
	var pos := Vector2i(
		spawn_rng.randi_range(room.position.x + 1, room.end.x - 2),
		spawn_rng.randi_range(room.position.y + 1, room.end.y - 2)
	)
	if pos == player["pos"] or pos == stairs_pos or enemy_at(pos) != -1:
		pos = first_free_tile_in_room(room)
	if pos == Vector2i(-1, -1):
		return
	var enemy_type := "melee" if spawn_rng.chance(1, 2) else "archer"
	var enemy_id := "enemy-%d" % next_enemy_id
	next_enemy_id += 1
	if enemy_type == "archer":
		enemies.append({
			"id": enemy_id,
			"type": "archer",
			"pos": pos,
			"hp": 5 + player["depth"],
			"attack": 1 + player["depth"] / 2, "defense": 0,
		})
	else:
		enemies.append({
			"id": enemy_id,
			"type": "melee",
			"pos": pos,
			"hp": 8 + player["depth"] * 2,
			"attack": 2 + player["depth"], "defense": 0,
		})

func first_free_tile_in_room(room: Rect2i) -> Vector2i:
	for y in range(room.position.y + 1, room.end.y - 1):
		for x in range(room.position.x + 1, room.end.x - 1):
			var candidate := Vector2i(x, y)
			if candidate != player["pos"] and candidate != stairs_pos and enemy_at(candidate) == -1:
				return candidate
	return Vector2i(-1, -1)

func farthest_walkable_tile_from(origin: Vector2i) -> Vector2i:
	var best := origin
	var best_distance := -1
	for y in range(map_height):
		for x in range(map_width):
			var candidate := Vector2i(x, y)
			if not is_walkable(candidate):
				continue
			var distance := origin.distance_squared_to(candidate)
			if distance > best_distance:
				best = candidate
				best_distance = distance
	return best

func run_auto_player_turn() -> void:
	decision_sequence += 1
	var decision_id := "%s-decision-%d" % [run_id, decision_sequence]
	var decision := choose_auto_player_decision(decision_id)
	if decision["rule_id"] == "hunt_nearest_enemy":
		aggressive_target_id = decision["target"]["id"]
	if decision["rule_id"] == "hunt_for_growth":
		growth_target_id = decision["target"]["id"]
	elif decision["rule_id"] == "descend_for_progress":
		growth_target_id = ""
	log_auto_decision(decision)
	if decision["action_type"] == "use_item":
		use_health_potion(decision_id)
		return
	var direction: Vector2i = decision["direction"]
	if direction == Vector2i.ZERO:
		turn_count += 1
		log_user_action("auto_wait", "turn_advanced", {
			"decision_id": decision["decision_id"],
		})
		add_message("You listen to the dungeon.")
		run_enemy_turn()
		queue_redraw()
		return

	player_act(direction, decision["decision_id"])

func choose_auto_player_decision(decision_id: String) -> Dictionary:
	var item_decision := choose_item_decision(decision_id)
	if not item_decision.is_empty():
		return item_decision
	if active_strategy == StrategyType.CAUTIOUS:
		return choose_cautious_decision(decision_id)
	return choose_aggressive_decision(decision_id)

func choose_aggressive_decision(decision_id: String) -> Dictionary:
	var adjacent_enemy_direction := direction_to_adjacent_enemy()
	if adjacent_enemy_direction != Vector2i.ZERO:
		var adjacent_enemy := enemies[enemy_at(player["pos"] + adjacent_enemy_direction)]
		return {
			"decision_id": decision_id,
			"rule_id": "attack_adjacent_enemy",
			"reason": "An enemy is adjacent, so the default strategy attacks it.",
			"action_type": "attack",
			"direction": adjacent_enemy_direction,
			"target": enemy_to_log(adjacent_enemy),
		}

	var progression := choose_progression_decision(decision_id)
	if not progression.is_empty():
		return progression

	if not enemies.is_empty():
		var pursuit := aggressive_pursuit()
		var target_enemy: Dictionary = pursuit["enemy"]
		var direction: Vector2i = pursuit["direction"]
		var has_path := direction != Vector2i.ZERO
		var reason := (
			"The aggressive strategy keeps pursuing its chosen enemy until defeated or unreachable."
			if has_path
			else "No walkable path to the nearest enemy was found."
		)
		return {
			"decision_id": decision_id,
			"rule_id": "hunt_nearest_enemy" if has_path else "wait_no_path_to_enemy",
			"reason": reason,
			"action_type": "move" if has_path else "wait",
			"direction": direction,
			"target": enemy_to_log(target_enemy),
		}

	var stairs_direction := find_next_step_toward(stairs_pos)
	var has_stairs_path := stairs_direction != Vector2i.ZERO
	var stairs_reason := (
		"No enemies remain, so the default strategy heads for the stairs."
		if has_stairs_path
		else "No walkable path to the stairs was found."
	)
	return {
		"decision_id": decision_id,
		"rule_id": "seek_stairs" if has_stairs_path else "wait_no_path_to_stairs",
		"reason": stairs_reason,
		"action_type": "move" if has_stairs_path else "wait",
		"direction": stairs_direction,
		"target": {
			"kind": "stairs",
			"pos": vector_to_log(stairs_pos),
		},
	}

func choose_cautious_decision(decision_id: String) -> Dictionary:
	var adjacent_enemy_direction := direction_to_adjacent_enemy()
	var stairs_direction := find_low_risk_step_toward(stairs_pos)
	if adjacent_enemy_direction != Vector2i.ZERO:
		var adjacent_enemy := enemies[enemy_at(player["pos"] + adjacent_enemy_direction)]
		var player_pos: Vector2i = player["pos"]
		var can_escape_via_stairs: bool = (
			stairs_direction != Vector2i.ZERO
			and player_pos + stairs_direction == stairs_pos
		)
		if adjacent_enemy["type"] == "melee" and not can_escape_via_stairs:
			return {
				"decision_id": decision_id,
				"rule_id": "attack_pursuing_melee",
				"reason": (
					"An adjacent melee enemy can match the player's speed, "
					+ "so retreat would not create distance."
				),
				"action_type": "attack",
				"direction": adjacent_enemy_direction,
				"selected_step_danger": danger_cost(player["pos"]),
				"target": enemy_to_log(adjacent_enemy),
			}

	if adjacent_enemy_direction == Vector2i.ZERO:
		var progression := choose_progression_decision(decision_id)
		if not progression.is_empty():
			return progression

	if stairs_direction != Vector2i.ZERO:
		var retreating := adjacent_enemy_direction != Vector2i.ZERO
		return {
			"decision_id": decision_id,
			"rule_id": "retreat_from_adjacent_enemy" if retreating else "cautious_seek_stairs",
			"reason": (
				"An enemy is adjacent, so the cautious strategy retreats toward the stairs."
				if retreating
				else "The cautious strategy takes a low-risk route, penalizing repeated visits to avoid movement loops."
			),
			"action_type": "move",
			"direction": stairs_direction,
			"selected_step_danger": danger_cost(player["pos"] + stairs_direction),
			"target": {
				"kind": "stairs",
				"pos": vector_to_log(stairs_pos),
			},
		}

	if adjacent_enemy_direction != Vector2i.ZERO:
		var blocking_enemy := enemies[enemy_at(player["pos"] + adjacent_enemy_direction)]
		return {
			"decision_id": decision_id,
			"rule_id": "attack_blocking_enemy",
			"reason": "No route to the stairs is open, so the cautious strategy fights.",
			"action_type": "attack",
			"direction": adjacent_enemy_direction,
			"selected_step_danger": danger_cost(player["pos"]),
			"target": enemy_to_log(blocking_enemy),
		}

	return {
		"decision_id": decision_id,
		"rule_id": "wait_no_safe_path",
		"reason": "No route to the stairs or adjacent target is currently available.",
		"action_type": "wait",
		"direction": Vector2i.ZERO,
		"selected_step_danger": danger_cost(player["pos"]),
		"target": {
			"kind": "stairs",
			"pos": vector_to_log(stairs_pos),
		},
	}

# Static, bounded estimates: enemy movement and future item pickups are not simulated.
func progression_route(destination: Vector2i, limit: int) -> Array[Vector2i]:
	var start: Vector2i = player["pos"]
	var frontier: Array[Vector2i] = [start]
	var came_from := {start: start}
	var steps := {start: 0}
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		if current == destination:
			var route: Array[Vector2i] = []
			while current != start:
				route.push_front(current)
				current = came_from[current]
			return route
		if steps[current] >= limit:
			continue
		for direction in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = current + direction
			if came_from.has(next) or not is_walkable(next):
				continue
			if next != destination and (next == stairs_pos or enemy_at(next) != -1):
				continue
			came_from[next] = current
			steps[next] = steps[current] + 1
			frontier.append(next)
	return []

func incoming_damage_at(pos: Vector2i, excluded_id: String = "") -> int:
	var total := 0
	for enemy in enemies:
		if enemy["id"] == excluded_id:
			continue
		var enemy_pos: Vector2i = enemy["pos"]
		var delta := pos - enemy_pos
		if enemy["type"] == "melee" and absi(delta.x) + absi(delta.y) == 1:
			total += calculate_damage(int(enemy["attack"]), effective_defense())
		elif enemy["type"] == "archer" and has_line_of_sight(enemy_pos, pos):
			var distance := pos.distance_squared_to(enemy_pos)
			if distance <= 2:
				total += calculate_damage(1, effective_defense())
			elif distance <= 49:
				total += calculate_damage(int(enemy["attack"]), effective_defense())
	return total

func choose_progression_decision(decision_id: String) -> Dictionary:
	var cautious := active_strategy == StrategyType.CAUTIOUS
	var stairs_route := progression_route(stairs_pos, map_width * map_height)
	if stairs_route.is_empty():
		return {} # Preserve existing blocked-route combat / pursuit behavior.
	var stairs_direction := find_low_risk_step_toward(stairs_pos)
	if stairs_direction == Vector2i.ZERO:
		return {}
	var stairs_healing: int = mini(4, player["max_hp"] - player["hp"])
	var stairs_score: int = (16 if cautious else 8) + stairs_healing * 2 - mini(stairs_route.size(), 8)
	if player["depth"] == MAX_DEPTH - 1:
		stairs_score += 20
	var candidates: Array[Dictionary] = []
	var best: Dictionary = {}
	var locked: Dictionary = {}
	for enemy in enemies:
		var route := progression_route(enemy["pos"], 6 if cautious else 12)
		if route.is_empty():
			candidates.append({"enemy_id": enemy["id"], "eligible": false, "rejection": "out_of_reach"})
			continue
		var hit_damage := calculate_damage(effective_attack(), int(enemy.get("defense", 0)))
		var attack_turns := int((int(enemy["hp"]) + hit_damage - 1) / hit_damage)
		var xp_gain := 5 if enemy["type"] == "archer" else 3
		var projected_xp: int = player["xp"] + xp_gain
		var projected_level: int = player["level"]
		while projected_xp >= projected_level * 8:
			projected_xp -= projected_level * 8
			projected_level += 1
		var levels_gained: int = projected_level - player["level"]
		var attack_pos: Vector2i = player["pos"] if route.size() == 1 else route[route.size() - 2]
		var damage := (attack_turns - 1) * calculate_damage(1 if enemy["type"] == "archer" else int(enemy["attack"]), effective_defense())
		damage += attack_turns * incoming_damage_at(attack_pos, enemy["id"])
		var repeated_cost := 0
		for index in range(route.size() - 1):
			damage += incoming_damage_at(route[index])
			repeated_cost += revisit_cost(route[index])
		var score: int = xp_gain * (2 if cautious else 4) + levels_gained * (8 + (MAX_DEPTH - 1 - player["depth"]) * 6)
		score -= (route.size() - 1) * (2 if cautious else 1) + attack_turns + damage * (3 if cautious else 2) + repeated_cost
		var rejection := ""
		if player["hp"] - damage <= (4 if cautious else 2):
			rejection = "hp_reserve"
		elif cautious and enemy["type"] == "archer":
			rejection = "mobile_target"
		elif cautious and levels_gained == 0:
			rejection = "no_level_up"
		var candidate := {"enemy_id": enemy["id"], "steps": route.size() - 1, "attack_turns": attack_turns,
			"xp_gain": xp_gain, "levels_gained": levels_gained, "estimated_damage": damage, "score": score,
			"eligible": rejection.is_empty(), "rejection": rejection, "revisit_penalty": repeated_cost}
		candidates.append(candidate)
		if not rejection.is_empty():
			continue
		var choice := {"enemy": enemy, "direction": route[0] - player["pos"], "score": score}
		if best.is_empty() or score > best["score"]:
			best = choice
		if enemy["id"] == growth_target_id and score > stairs_score:
			locked = choice
	if not locked.is_empty():
		best = locked
	var fight: bool = not best.is_empty() and best["score"] > stairs_score
	var comparison := {"stairs_steps": stairs_route.size(), "stairs_healing": stairs_healing,
		"stairs_score": stairs_score, "candidates": candidates, "selected": "combat" if fight else "stairs",
		"selected_enemy_id": best["enemy"]["id"] if fight else null, "target_retained": fight and not locked.is_empty()}
	var direction: Vector2i = best["direction"] if fight else stairs_direction
	return {"decision_id": decision_id, "rule_id": "hunt_for_growth" if fight else "descend_for_progress",
		"reason": "A survivable fight offers more XP and level-up value than descending; keep the selected target while that remains true." if fight else "Descending offers more progress, recovery or completion value than the available growth fights.",
		"action_type": "move", "direction": direction, "selected_step_danger": danger_cost(player["pos"] + direction),
		"target": enemy_to_log(best["enemy"]) if fight else {"kind": "stairs", "pos": vector_to_log(stairs_pos)},
		"progression": comparison}

func choose_auto_player_direction() -> Vector2i:
	return choose_auto_player_decision("preview")["direction"]

func revisit_cost(pos: Vector2i) -> int:
	return maxi(0, int(navigation_visits.get(pos, 0)) - 2) * 8

func find_low_risk_step_toward(destination: Vector2i) -> Vector2i:
	return find_weighted_step_toward(destination, true)

func find_weighted_step_toward(destination: Vector2i, use_danger: bool) -> Vector2i:
	var start: Vector2i = player["pos"]
	var frontier: Array[Vector2i] = [start]
	var came_from := {start: start}
	var cost_so_far := {start: 0}
	var directions := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

	while not frontier.is_empty():
		var best_index := 0
		for i in range(1, frontier.size()):
			if cost_so_far[frontier[i]] < cost_so_far[frontier[best_index]]:
				best_index = i
		var current: Vector2i = frontier.pop_at(best_index)
		if current == destination:
			break

		for direction in directions:
			var next: Vector2i = current + direction
			if not is_cautious_path_walkable(next, destination):
				continue
			var danger := danger_cost(next) if use_danger else 0
			var new_cost: int = cost_so_far[current] + 1 + danger + revisit_cost(next)
			if not cost_so_far.has(next) or new_cost < cost_so_far[next]:
				cost_so_far[next] = new_cost
				came_from[next] = current
				if not frontier.has(next):
					frontier.append(next)

	if not came_from.has(destination):
		return Vector2i.ZERO

	var current := destination
	while came_from[current] != start:
		current = came_from[current]
	return current - start

func is_cautious_path_walkable(pos: Vector2i, destination: Vector2i) -> bool:
	if not is_walkable(pos):
		return false
	return pos == destination or enemy_at(pos) == -1

func danger_cost(pos: Vector2i) -> int:
	var total := 0
	for enemy in enemies:
		var enemy_pos: Vector2i = enemy["pos"]
		var delta: Vector2i = pos - enemy_pos
		var manhattan := absi(delta.x) + absi(delta.y)
		var distance_squared := pos.distance_squared_to(enemy_pos)
		if enemy["type"] == "archer":
			if not has_line_of_sight(enemy_pos, pos):
				continue
			if distance_squared <= 2:
				total += 30
			elif distance_squared <= 49:
				total += 12
			elif distance_squared <= 80:
				total += 3
		else:
			if manhattan == 1:
				total += 30
			elif manhattan == 2:
				total += 8
	return total

func direction_to_adjacent_enemy() -> Vector2i:
	var directions := [
		Vector2i.UP,
		Vector2i.DOWN,
		Vector2i.LEFT,
		Vector2i.RIGHT,
	]
	for direction in directions:
		if enemy_at(player["pos"] + direction) != -1:
			return direction
	return Vector2i.ZERO

func nearest_enemy_pos() -> Vector2i:
	return nearest_enemy()["pos"]

func nearest_enemy() -> Dictionary:
	var best_enemy: Dictionary = enemies[0]
	var best_distance: int = player["pos"].distance_squared_to(best_enemy["pos"])
	for enemy in enemies:
		var enemy_pos: Vector2i = enemy["pos"]
		var distance: int = player["pos"].distance_squared_to(enemy_pos)
		if distance < best_distance:
			best_distance = distance
			best_enemy = enemy
	return best_enemy

func aggressive_pursuit() -> Dictionary:
	for enemy in enemies:
		if enemy["id"] == aggressive_target_id:
			var direction := find_next_step_toward(enemy["pos"])
			if direction != Vector2i.ZERO:
				return {"enemy": enemy, "direction": direction}
	var candidates := enemies.duplicate()
	# Stable insertion sort preserves enemy order for equal distances.
	for index in range(1, candidates.size()):
		var enemy: Dictionary = candidates[index]
		var cursor := index
		while cursor > 0 and player["pos"].distance_squared_to(candidates[cursor - 1]["pos"]) > player["pos"].distance_squared_to(enemy["pos"]):
			candidates[cursor] = candidates[cursor - 1]
			cursor -= 1
		candidates[cursor] = enemy
	for enemy in candidates:
		var direction := find_next_step_toward(enemy["pos"])
		if direction != Vector2i.ZERO:
			return {"enemy": enemy, "direction": direction}
	return {"enemy": candidates[0], "direction": Vector2i.ZERO}

func find_next_step_toward(destination: Vector2i) -> Vector2i:
	for visits in navigation_visits.values():
		if int(visits) > 2:
			return find_weighted_step_toward(destination, false)
	var start: Vector2i = player["pos"]
	var frontier: Array[Vector2i] = [start]
	var came_from := {
		start: start,
	}
	var directions := [
		Vector2i.UP,
		Vector2i.DOWN,
		Vector2i.LEFT,
		Vector2i.RIGHT,
	]

	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		if current == destination:
			break

		for direction in directions:
			var next: Vector2i = current + direction
			if came_from.has(next):
				continue
			if not is_auto_path_walkable(next, destination):
				continue

			frontier.append(next)
			came_from[next] = current

	if not came_from.has(destination):
		return Vector2i.ZERO

	var current := destination
	while came_from[current] != start:
		current = came_from[current]

	return current - start

func is_auto_path_walkable(pos: Vector2i, destination: Vector2i) -> bool:
	if not is_walkable(pos):
		return false
	return pos == destination or enemy_at(pos) == -1

func player_act(direction: Vector2i, decision_id: String = "") -> void:
	var target: Vector2i = player["pos"] + direction
	if not is_walkable(target):
		var blocked_details := {
			"direction": vector_to_log(direction),
			"from": vector_to_log(player["pos"]),
			"target": vector_to_log(target),
		}
		add_decision_reference(blocked_details, decision_id)
		log_user_action("move", "blocked_wall", blocked_details)
		return

	turn_count += 1
	var enemy_index := enemy_at(target)
	if enemy_index != -1:
		var attack_details := {
			"direction": vector_to_log(direction),
			"from": vector_to_log(player["pos"]),
			"target": vector_to_log(target),
			"enemy_id": enemies[enemy_index]["id"],
		}
		add_decision_reference(attack_details, decision_id)
		log_user_action("attack", "enemy_targeted", attack_details)
		attack_enemy(enemy_index)
	else:
		var from_pos: Vector2i = player["pos"]
		player["pos"] = target
		navigation_visits[target] = int(navigation_visits.get(target, 0)) + 1
		var move_details := {
			"direction": vector_to_log(direction),
			"from": vector_to_log(from_pos),
			"target": vector_to_log(target),
		}
		add_decision_reference(move_details, decision_id)
		log_user_action("move", "moved", move_details)
		pick_up_items(decision_id)
		if player["pos"] == stairs_pos:
			var descend_details := {
				"from_depth": player["depth"],
				"hp_before": player["hp"],
			}
			add_decision_reference(descend_details, decision_id)
			log_user_action("descend", "stairs_used", descend_details)
			player["depth"] = player["depth"] + 1
			player["score"] += 3
			player["hp"] = mini(player["max_hp"], player["hp"] + 4)
			log_event("floor_descend", {
				"to_depth": player["depth"],
				"hp_after": player["hp"],
			})
			if player["depth"] >= MAX_DEPTH:
				handle_dungeon_cleared()
				return
			new_floor()
			return

	run_enemy_turn()
	queue_redraw()

func attack_enemy(index: int) -> void:
	var enemy := enemies[index]
	var enemy_hp_before: int = enemy["hp"]
	var attack := effective_attack()
	var defense := int(enemy.get("defense", 0))
	var damage := calculate_damage(attack, defense)
	enemy["hp"] = enemy["hp"] - damage
	if enemy["hp"] <= 0:
		var enemy_pos: Vector2i = enemy["pos"]
		enemies.remove_at(index)
		var gold := gold_reward_for_enemy(enemy)
		player["gold"] = player["gold"] + gold
		player["score"] += 2 if enemy["type"] == "archer" else 1
		var xp_gain := 5 if enemy["type"] == "archer" else 3
		player["xp"] += xp_gain
		check_level_up()
		log_battle_result("enemy_defeated", {
			"enemy_id": enemy["id"],
			"enemy_type": enemy["type"],
			"enemy_pos": vector_to_log(enemy_pos),
			"damage": damage, "attack_power": attack, "defense_power": defense,
			"enemy_hp_before": enemy_hp_before,
			"gold_gained": gold,
		})
		add_message("Enemy defeated. +%d gold." % gold)
	else:
		enemies[index] = enemy
		log_battle_result("enemy_hit", {
			"enemy_id": enemy["id"],
			"enemy_type": enemy["type"],
			"enemy_pos": vector_to_log(enemy["pos"]),
			"damage": damage, "attack_power": attack, "defense_power": defense,
			"enemy_hp_before": enemy_hp_before,
			"enemy_hp_after": enemy["hp"],
		})
		add_message("You hit the enemy.")

func gold_reward_for_enemy(enemy: Dictionary) -> int:
	var reward_seed := PortableRandom.derive_seed(
		scenario_seed,
		"reward",
		player["depth"],
		enemy["id"]
	)
	var reward_rng := PortableRandom.new(reward_seed)
	return reward_rng.randi_range(1, 4)

func check_level_up() -> void:
	var xp_needed: int = player["level"] * 8
	while player["xp"] >= xp_needed:
		player["xp"] -= xp_needed
		player["level"] += 1
		player["max_hp"] += 2
		player["hp"] = mini(player["hp"] + 2, player["max_hp"])
		player["base_attack"] += 1
		xp_needed = player["level"] * 8
		add_message("Level up! Now level %d." % player["level"])

func run_enemy_turn() -> void:
	for i in range(enemies.size()):
		var enemy := enemies[i]
		var enemy_pos: Vector2i = enemy["pos"]
		var delta: Vector2i = player["pos"] - enemy_pos

		if enemy["type"] == "archer":
			run_archer_turn(i, enemy, enemy_pos)
		else:
			run_melee_turn(i, enemy, enemy_pos, delta)
		if game_over:
			break

func run_melee_turn(index: int, enemy: Dictionary, enemy_pos: Vector2i, delta: Vector2i) -> void:
	if abs(delta.x) + abs(delta.y) == 1:
		var hp_before: int = player["hp"]
		var dmg := calculate_damage(int(enemy["attack"]), effective_defense())
		player["hp"] = maxi(player["hp"] - dmg, 0)
		log_battle_result("player_hit", {
			"enemy_id": enemy["id"],
			"enemy_type": enemy["type"],
			"enemy_pos": vector_to_log(enemy_pos),
			"damage": dmg, "attack_power": enemy["attack"], "defense_power": effective_defense(),
			"player_hp_before": hp_before,
			"player_hp_after": player["hp"],
		})
		add_message("Enemy hits you for %d." % dmg)
		if player["hp"] <= 0:
			handle_player_defeat()
		return

	if can_enemy_see_player(enemy_pos):
		var step := choose_enemy_step(enemy_pos, delta)
		var target: Vector2i = enemy_pos + step
		if is_walkable(target) and target != player["pos"] and enemy_at(target) == -1:
			enemy["pos"] = target
			enemies[index] = enemy

func run_archer_turn(index: int, enemy: Dictionary, enemy_pos: Vector2i) -> void:
	if not has_line_of_sight(enemy_pos, player["pos"]):
		return
	var dist_sq := enemy_pos.distance_squared_to(player["pos"])

	# Adjacent: try to retreat, otherwise melee for 1
	if dist_sq <= 2:
		if try_archer_retreat(index, enemy, enemy_pos):
			return
		# Cornered — weak melee attack
		var hp_before: int = player["hp"]
		var melee_dmg := calculate_damage(1, effective_defense())
		player["hp"] = maxi(player["hp"] - melee_dmg, 0)
		log_battle_result("player_hit", {
			"enemy_id": enemy["id"],
			"enemy_pos": vector_to_log(enemy_pos),
			"damage": melee_dmg, "attack_power": 1, "defense_power": effective_defense(),
			"player_hp_before": hp_before,
			"player_hp_after": player["hp"],
			"enemy_type": "archer",
		})
		add_message("Archer punches you for %d." % melee_dmg)
		if player["hp"] <= 0:
			handle_player_defeat()
		return

	# In bow range (2-7 tiles): fire arrow
	if dist_sq <= 49:
		if can_enemy_see_player(enemy_pos):
			if not headless_mode:
				arrows.append({
					"from": Vector2(enemy_pos) * TILE_SIZE + Vector2.ONE * TILE_SIZE * 0.5,
					"to": Vector2(player["pos"]) * TILE_SIZE + Vector2.ONE * TILE_SIZE * 0.5,
					"elapsed": 0.0,
				})
				queue_redraw()
			var dmg := calculate_damage(int(enemy["attack"]), effective_defense())
			var hp_before: int = player["hp"]
			player["hp"] = maxi(player["hp"] - dmg, 0)
			log_battle_result("player_hit", {
				"enemy_id": enemy["id"],
				"enemy_pos": vector_to_log(enemy_pos),
				"damage": dmg, "attack_power": enemy["attack"], "defense_power": effective_defense(),
				"player_hp_before": hp_before,
				"player_hp_after": player["hp"],
				"enemy_type": "archer",
				"ranged": true,
			})
			add_message("Archer shoots you for %d." % dmg)
			if player["hp"] <= 0:
				handle_player_defeat()
		return

	# Too far: move toward player
	if can_enemy_see_player(enemy_pos):
		var delta: Vector2i = player["pos"] - enemy_pos
		var step := choose_enemy_step(enemy_pos, delta)
		var target: Vector2i = enemy_pos + step
		if is_walkable(target) and target != player["pos"] and enemy_at(target) == -1:
			enemy["pos"] = target
			enemies[index] = enemy

func try_archer_retreat(index: int, enemy: Dictionary, enemy_pos: Vector2i) -> bool:
	var delta_to_player := Vector2i(player["pos"]) - enemy_pos
	var away_step := Vector2i(-signi(delta_to_player.x), -signi(delta_to_player.y))
	var away: Vector2i = enemy_pos + away_step
	var candidates: Array[Vector2i] = [
		away,
		Vector2i(away.x, enemy_pos.y),
		Vector2i(enemy_pos.x, away.y),
	]
	for candidate in candidates:
		if is_walkable(candidate) and candidate != player["pos"] and enemy_at(candidate) == -1:
			enemy["pos"] = candidate
			enemies[index] = enemy
			return true
	return false

func has_line_of_sight(from: Vector2i, to: Vector2i) -> bool:
	if not is_walkable(from) or not is_walkable(to):
		return false
	var nx := absi(to.x - from.x)
	var ny := absi(to.y - from.y)
	var sx := signi(to.x - from.x)
	var sy := signi(to.y - from.y)
	var ix := 0
	var iy := 0
	var current := from
	while ix < nx or iy < ny:
		var crossing := (1 + 2 * ix) * ny - (1 + 2 * iy) * nx
		if crossing == 0:
			# Block corner grazing through either adjoining wall.
			if not is_walkable(current + Vector2i(sx, 0)) or not is_walkable(current + Vector2i(0, sy)):
				return false
			current += Vector2i(sx, sy)
			ix += 1
			iy += 1
		elif crossing < 0:
			current.x += sx
			ix += 1
		else:
			current.y += sy
			iy += 1
		if not is_walkable(current):
			return false
	return true

func can_enemy_see_player(enemy_pos: Vector2i) -> bool:
	return enemy_pos.distance_squared_to(player["pos"]) <= 80

func choose_enemy_step(enemy_pos: Vector2i, delta: Vector2i) -> Vector2i:
	var horizontal := Vector2i(signi(delta.x), 0)
	var vertical := Vector2i(0, signi(delta.y))
	var first := horizontal if abs(delta.x) > abs(delta.y) else vertical
	var second := vertical if first == horizontal else horizontal

	if first != Vector2i.ZERO and is_walkable(enemy_pos + first):
		return first
	if second != Vector2i.ZERO and is_walkable(enemy_pos + second):
		return second
	return Vector2i.ZERO

func signi(value: int) -> int:
	if value > 0:
		return 1
	if value < 0:
		return -1
	return 0

func handle_player_defeat() -> void:
	player["hp"] = 0
	game_over = true
	run_outcome = "player_defeated"
	auto_exploration_started = false
	log_battle_result("player_defeated", {
		"final_depth": player["depth"],
		"final_gold": player["gold"],
		"turns": turn_count,
		"strategy_id": strategy_id(active_strategy),
		"scenario_seed": scenario_seed,
	})
	if comparison_active and comparison_phase == 0:
		add_message("Aggressive run finished. Cautious starts next.")
	elif comparison_active and comparison_phase == 1:
		comparison_active = false
		add_message("Comparison complete. Review both runs in the viewer.")
	else:
		add_message("You fell. Press R to restart.")
	update_controls_state()
	queue_redraw()

func handle_dungeon_cleared() -> void:
	game_over = true
	run_outcome = "dungeon_cleared"
	auto_exploration_started = false
	log_battle_result("dungeon_cleared", {
		"final_depth": player["depth"],
		"final_gold": player["gold"],
		"final_score": player["score"],
		"turns": turn_count,
		"strategy_id": strategy_id(active_strategy),
		"scenario_seed": scenario_seed,
	})
	if comparison_active and comparison_phase == 0:
		add_message("Aggressive run cleared the dungeon. Cautious starts next.")
	elif comparison_active and comparison_phase == 1:
		comparison_active = false
		add_message("Comparison complete. Review both runs in the viewer.")
	else:
		add_message("Dungeon cleared.")
	update_controls_state()
	queue_redraw()

func enemy_at(pos: Vector2i) -> int:
	for i in range(enemies.size()):
		if enemies[i]["pos"] == pos:
			return i
	return -1

func is_walkable(pos: Vector2i) -> bool:
	if pos.x < 0 or pos.y < 0 or pos.x >= map_width or pos.y >= map_height:
		return false
	return map[pos.y][pos.x] == TILE_FLOOR

func map_rows_to_log() -> Array[String]:
	var result: Array[String] = []
	for y in range(map_height):
		var row := ""
		for x in range(map_width):
			row += "." if map[y][x] == TILE_FLOOR else "#"
		result.append(row)
	return result

func add_message(text: String) -> void:
	messages.push_front(text)
	if messages.size() > 5:
		messages.pop_back()

func open_log_file() -> void:
	if truncate_log_on_open:
		log_file = FileAccess.open(log_file_path, FileAccess.WRITE_READ)
	elif FileAccess.file_exists(log_file_path):
		log_file = FileAccess.open(log_file_path, FileAccess.READ_WRITE)
		if log_file:
			log_file.seek_end()
	else:
		log_file = FileAccess.open(log_file_path, FileAccess.WRITE_READ)

	if not log_file:
		push_warning("Could not open log file: %s" % log_file_path)

func start_run_log() -> void:
	run_id = (
		fixed_run_id
		if not fixed_run_id.is_empty()
		else "%d-%d" % [Time.get_unix_time_from_system(), metadata_rng.randi()]
	)
	event_sequence = 0
	decision_sequence = 0
	next_enemy_id = 1
	log_event("run_start", {
		"log_file": logged_file_path if not logged_file_path.is_empty() else log_file_path,
		"scenario_id": current_scenario_id(),
		"scenario_seed": scenario_seed,
		"strategy_id": strategy_id(active_strategy),
		"simulation_version": 5,
		"comparison": comparison_active,
		"comparison_phase": comparison_phase,
	})

func log_auto_decision(decision: Dictionary) -> void:
	var action := {
		"type": decision["action_type"],
		"direction": vector_to_log(decision["direction"]),
		"target": decision["target"],
	}
	var observation := build_decision_observation()
	if decision.has("progression"):
		observation["progression"] = decision["progression"].duplicate(true)
	if decision["action_type"] == "move":
		observation["selected_step_revisit_cost"] = revisit_cost(player["pos"] + decision["direction"])
	if decision.has("selected_step_danger"):
		observation["selected_step_danger"] = decision["selected_step_danger"]
	log_event("decision", {
		"decision_id": decision["decision_id"],
		"strategy_id": strategy_id(active_strategy),
		"rule_id": decision["rule_id"],
		"reason": decision["reason"],
		"action_turn": turn_count + 1,
		"observation": observation,
		"action": action,
	})

func build_decision_observation() -> Dictionary:
	return {
		"player_pos": vector_to_log(player["pos"]),
		"hp": player["hp"],
		"max_hp": player["max_hp"],
		"level": player["level"],
		"xp": player["xp"],
		"xp_to_next_level": player["level"] * 8 - player["xp"],
		"enemy_count": enemies.size(),
		"enemies": enemies_to_log(),
		"stairs_pos": vector_to_log(stairs_pos),
		"stairs_distance_squared": player["pos"].distance_squared_to(stairs_pos),
		"current_danger": danger_cost(player["pos"]),
		"current_tile_visits": int(navigation_visits.get(player["pos"], 0)),
		"items": items_to_log(),
		"inventory": player["inventory"].duplicate(),
	}

func add_decision_reference(details: Dictionary, decision_id: String) -> void:
	if not decision_id.is_empty():
		details["decision_id"] = decision_id

func log_user_action(action: String, result: String, details: Dictionary = {}) -> void:
	var event_details := details.duplicate()
	event_details["action"] = action
	event_details["result"] = result
	log_event("user_action", event_details)

func log_battle_result(result: String, details: Dictionary = {}) -> void:
	var event_details := details.duplicate()
	event_details["result"] = result
	log_event("battle_result", event_details)

func log_event(event_name: String, details: Dictionary = {}) -> void:
	if not log_file:
		return

	event_sequence += 1
	var record := {
		"schema_version": LOG_SCHEMA_VERSION,
		"time": (
			fixed_event_time
			if not fixed_event_time.is_empty()
			else Time.get_datetime_string_from_system(false, true)
		),
		"event": event_name,
		"run_id": run_id,
		"scenario_id": current_scenario_id(),
		"scenario_seed": scenario_seed,
		"strategy_id": strategy_id(active_strategy),
		"sequence": event_sequence,
		"turn": turn_count,
		"depth": player["depth"],
		"hp": player["hp"],
		"gold": player["gold"],
		"player_state": player_state_to_log(),
		"details": details,
	}
	log_file.store_line(JSON.stringify(record))
	log_file.flush()

func vector_to_log(value: Vector2i) -> Dictionary:
	return {
		"x": value.x,
		"y": value.y,
	}

func player_state_to_log() -> Dictionary:
	return {
		"pos": vector_to_log(player["pos"]),
		"hp": player["hp"],
		"max_hp": player["max_hp"],
		"attack": effective_attack(), "defense": effective_defense(),
		"base_attack": player["base_attack"], "base_defense": player["base_defense"],
		"attack_bonus": attack_bonus(), "defense_bonus": defense_bonus(),
		"equipment": player["equipment"].duplicate(true),
		"gold": player["gold"],
		"score": player["score"],
		"level": player["level"],
		"xp": player["xp"],
		"inventory": player["inventory"].duplicate(),
	}

func enemy_to_log(enemy: Dictionary) -> Dictionary:
	return {
		"id": enemy["id"],
		"type": enemy["type"],
		"pos": vector_to_log(enemy["pos"]),
		"hp": enemy["hp"],
		"attack": enemy["attack"], "defense": int(enemy.get("defense", 0)),
		"distance_squared": player["pos"].distance_squared_to(enemy["pos"]),
	}

func enemies_to_log() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for enemy in enemies:
		result.append(enemy_to_log(enemy))
	return result

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), COLORS["bg"])
	draw_set_transform(map_offset, 0.0, Vector2.ONE * map_scale)
	draw_dungeon()
	draw_entities()
	draw_arrows()
	draw_set_transform(Vector2.ZERO)
	draw_hud()
	if game_over:
		draw_game_over()

func draw_arrows() -> void:
	for arrow in arrows:
		var origin: Vector2 = arrow["from"]
		var target: Vector2 = arrow["to"]
		var elapsed: float = arrow["elapsed"]
		if elapsed < ARROW_FLIGHT_DURATION:
			var direction := (target - origin).normalized()
			var perpendicular := Vector2(-direction.y, direction.x)
			var tip := origin.lerp(target, elapsed / ARROW_FLIGHT_DURATION)
			var tail := tip - direction * 22.0
			draw_line(tail - direction * 12.0, tip, Color(0.43, 0.8, 1.0, 0.3), 6.0, true)
			draw_line(tail, tip, COLORS["archer"], 3.0, true)
			draw_colored_polygon(PackedVector2Array([
				tip, tip - direction * 9.0 + perpendicular * 5.0,
				tip - direction * 9.0 - perpendicular * 5.0,
			]), COLORS["text"])
		else:
			var progress := (elapsed - ARROW_FLIGHT_DURATION) / ARROW_IMPACT_DURATION
			var color: Color = COLORS["archer"]
			color.a = 1.0 - progress
			draw_arc(target, 10.0 + progress * 16.0, 0.0, TAU, 32, color, 3.0, true)

func draw_dungeon() -> void:
	for y in range(map_height):
		for x in range(map_width):
			var pos := Vector2(x * TILE_SIZE, y * TILE_SIZE)
			var rect := Rect2(pos, Vector2(TILE_SIZE, TILE_SIZE))
			if map[y][x] == TILE_WALL:
				draw_rect(rect, COLORS["wall"])
				draw_rect(rect.grow(-TILE_SIZE * 0.2), COLORS["wall_edge"])
			else:
				var color: Color = COLORS["floor"] if (x + y) % 2 == 0 else COLORS["floor_alt"]
				draw_rect(rect, color)

	draw_stairs_icon()

func draw_stairs_icon() -> void:
	var origin := Vector2(stairs_pos) * TILE_SIZE
	var badge := Rect2(origin + Vector2.ONE * 4, Vector2.ONE * 32)
	draw_rect(badge, COLORS["bg"])
	draw_rect(badge, COLORS["stairs"], false, 2.0)
	var steps := PackedVector2Array([
		origin + Vector2(9, 12), origin + Vector2(16, 12),
		origin + Vector2(16, 19), origin + Vector2(23, 19),
		origin + Vector2(23, 26), origin + Vector2(30, 26),
	])
	draw_polyline(steps, COLORS["stairs"], 3.0, true)
	draw_line(origin + Vector2(9, 31), origin + Vector2(30, 31), COLORS["stairs"], 2.0, true)

func draw_entities() -> void:
	for item in items:
		draw_tile_symbol(item["pos"], "W" if item["type"] == "weapon" else ("D" if item["type"] == "armor" else "+"), Color("#de8fe8"))
	for enemy in enemies:
		var symbol := "A" if enemy["type"] == "archer" else "E"
		var color := COLORS["archer"] if enemy["type"] == "archer" else COLORS["enemy"]
		draw_tile_symbol(enemy["pos"], symbol, color)
	draw_tile_symbol(player["pos"], "@", COLORS["player"])

func draw_tile_symbol(tile: Vector2i, symbol: String, color: Color) -> void:
	var center := Vector2(tile.x * TILE_SIZE + TILE_SIZE * 0.5, tile.y * TILE_SIZE + TILE_SIZE * 0.5)
	draw_circle(center, TILE_SIZE * 0.42, color)
	var symbol_size := int(TILE_SIZE * 0.75)
	var text_size := font.get_string_size(symbol, HORIZONTAL_ALIGNMENT_CENTER, -1, symbol_size)
	draw_string(font, center - text_size * 0.5 + Vector2(0, TILE_SIZE * 0.55), symbol, HORIZONTAL_ALIGNMENT_CENTER, -1, symbol_size, COLORS["bg"])

func draw_hud() -> void:
	var hud_x := map_available_size().x + 16
	var viewport_size := get_viewport_rect().size
	var panel := Rect2(hud_x - 16, 0, HUD_WIDTH, viewport_size.y)
	draw_rect(panel, COLORS["panel"])

	draw_string(font, Vector2(hud_x, 48), "SimpleRogue", HORIZONTAL_ALIGNMENT_LEFT, -1, 36, COLORS["text"])
	draw_string(font, Vector2(hud_x, 100), "Depth %d" % player["depth"], HORIZONTAL_ALIGNMENT_LEFT, -1, 28, COLORS["text"])
	draw_string(font, Vector2(hud_x, 138), "Lv %d · XP %d/%d" % [player["level"], player["xp"], player["level"] * 8], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, COLORS["text"])
	draw_string(font, Vector2(hud_x, 176), "HP %d/%d" % [player["hp"], player["max_hp"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 28, COLORS["danger"] if player["hp"] <= 6 else COLORS["text"])
	draw_string(font, Vector2(hud_x, 214), "Gold %d" % player["gold"], HORIZONTAL_ALIGNMENT_LEFT, -1, 28, COLORS["text"])
	draw_string(font, Vector2(hud_x, 252), "Score %d" % player["score"], HORIZONTAL_ALIGNMENT_LEFT, -1, 28, COLORS["text"])
	draw_string(
		font,
		Vector2(hud_x, 280),
		"%s · seed %d" % [strategy_display_name(active_strategy), scenario_seed],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		17,
		COLORS["muted"],
	)

	draw_string(font, Vector2(hud_x, 430), "ATK %d (%d+%d)  DEF %d (%d+%d)" % [effective_attack(), player["base_attack"], attack_bonus(), effective_defense(), player["base_defense"], defense_bonus()], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, COLORS["text"])
	draw_string(font, Vector2(hud_x, 470), "Potions %d/%d · H: use" % [player["inventory"]["health_potion"], INVENTORY_CAPACITY], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, COLORS["text"])
	draw_string(font, Vector2(hud_x, 500), "Arrows/. still work", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, COLORS["muted"])
	draw_string(font, Vector2(hud_x, 536), "R: restart", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, COLORS["muted"])

	draw_string(font, Vector2(hud_x, 584), "Log", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, COLORS["text"])
	var log_y := 620.0
	for message in messages:
		var message_size := font.get_multiline_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, HUD_WIDTH - 32, 22)
		if log_y + message_size.y > viewport_size.y:
			break
		draw_multiline_string(font, Vector2(hud_x, log_y), message, HORIZONTAL_ALIGNMENT_LEFT, HUD_WIDTH - 32, 22, -1, COLORS["muted"])
		log_y += message_size.y + 12

func draw_game_over() -> void:
	var overlay_origin := (map_available_size() - Vector2(560, 190)) * 0.5
	draw_set_transform(overlay_origin)
	var rect := Rect2(0, 0, 560, 190)
	draw_rect(rect, Color(0, 0, 0, 0.72))
	var title := "Dungeon Cleared" if run_outcome == "dungeon_cleared" else "Game Over"
	var title_color: Color = COLORS["stairs"] if run_outcome == "dungeon_cleared" else COLORS["danger"]
	draw_string(font, Vector2(110, 60), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 44, title_color)
	draw_string(font, Vector2(36, 110), "Lv %d  |  Score %d  |  Depth %d" % [player["level"], player["score"], player["depth"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, COLORS["text"])
	draw_string(font, Vector2(36, 156), "Press R to try another run.", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, COLORS["text"])
