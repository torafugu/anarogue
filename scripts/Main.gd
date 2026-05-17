extends Node2D

const MAP_WIDTH := 44
const MAP_HEIGHT := 28
const TILE_SIZE := 20
const ROOM_ATTEMPTS := 70
const MAX_ROOMS := 11
const MIN_ROOM_SIZE := 5
const MAX_ROOM_SIZE := 11

const TILE_WALL := 0
const TILE_FLOOR := 1
const LOG_FILE_PATH := "user://simple_rogue_battle_log.jsonl"

const COLORS := {
	"bg": Color("#15171d"),
	"wall": Color("#303845"),
	"wall_edge": Color("#465266"),
	"floor": Color("#242a32"),
	"floor_alt": Color("#29313b"),
	"player": Color("#f2d16b"),
	"enemy": Color("#d85f5f"),
	"stairs": Color("#79c7a6"),
	"text": Color("#e7e1cf"),
	"muted": Color("#9aa4b2"),
	"danger": Color("#ff8a80"),
	"panel": Color("#20252e"),
}

var rng := RandomNumberGenerator.new()
var map: Array = []
var rooms: Array[Rect2i] = []
var enemies: Array[Dictionary] = []
var player := {
	"pos": Vector2i.ZERO,
	"hp": 18,
	"max_hp": 18,
	"attack": 5,
	"gold": 0,
	"depth": 1,
}
var stairs_pos := Vector2i.ZERO
var messages: Array[String] = []
var game_over := false
var font := ThemeDB.fallback_font
var log_file: FileAccess
var run_id := ""
var turn_count := 0

func _ready() -> void:
	rng.randomize()
	open_log_file()
	start_run_log()
	new_floor()

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return

	if Input.is_action_just_pressed("restart"):
		log_user_action("restart", "new_run")
		log_battle_result("restart", {
			"reason": "user_restart",
		})
		restart_game()
		return

	if game_over:
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

func restart_game() -> void:
	player["hp"] = player["max_hp"]
	player["gold"] = 0
	player["depth"] = 1
	turn_count = 0
	game_over = false
	messages.clear()
	start_run_log()
	new_floor()

func new_floor() -> void:
	map.clear()
	rooms.clear()
	enemies.clear()
	for y in range(MAP_HEIGHT):
		var row := []
		for x in range(MAP_WIDTH):
			row.append(TILE_WALL)
		map.append(row)

	generate_dungeon()
	player["pos"] = rooms[0].get_center()
	stairs_pos = rooms[rooms.size() - 1].get_center()
	spawn_enemies()
	log_event("floor_start", {
		"enemy_count": enemies.size(),
		"player_pos": vector_to_log(player["pos"]),
		"stairs_pos": vector_to_log(stairs_pos),
	})
	add_message("Depth %d. Find the green stairs." % player["depth"])
	queue_redraw()

func generate_dungeon() -> void:
	for i in range(ROOM_ATTEMPTS):
		if rooms.size() >= MAX_ROOMS:
			break

		var w := rng.randi_range(MIN_ROOM_SIZE, MAX_ROOM_SIZE)
		var h := rng.randi_range(MIN_ROOM_SIZE, MAX_ROOM_SIZE)
		var x := rng.randi_range(1, MAP_WIDTH - w - 2)
		var y := rng.randi_range(1, MAP_HEIGHT - h - 2)
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
			connect_rooms(rooms.back().get_center(), room.get_center())
		rooms.append(room)

	if rooms.is_empty():
		var fallback := Rect2i(4, 4, 12, 10)
		carve_room(fallback)
		rooms.append(fallback)

func carve_room(room: Rect2i) -> void:
	for y in range(room.position.y, room.end.y):
		for x in range(room.position.x, room.end.x):
			map[y][x] = TILE_FLOOR

func connect_rooms(a: Vector2i, b: Vector2i) -> void:
	if rng.randf() < 0.5:
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

func spawn_enemies() -> void:
	for i in range(1, rooms.size() - 1):
		if rng.randf() > 0.75:
			continue
		var room := rooms[i]
		var pos := Vector2i(
			rng.randi_range(room.position.x + 1, room.end.x - 2),
			rng.randi_range(room.position.y + 1, room.end.y - 2)
		)
		enemies.append({
			"pos": pos,
			"hp": 8 + player["depth"] * 2,
			"attack": 2 + player["depth"],
		})

func player_act(direction: Vector2i) -> void:
	var target: Vector2i = player["pos"] + direction
	if not is_walkable(target):
		log_user_action("move", "blocked_wall", {
			"direction": vector_to_log(direction),
			"from": vector_to_log(player["pos"]),
			"target": vector_to_log(target),
		})
		return

	turn_count += 1
	var enemy_index := enemy_at(target)
	if enemy_index != -1:
		log_user_action("attack", "enemy_targeted", {
			"direction": vector_to_log(direction),
			"from": vector_to_log(player["pos"]),
			"target": vector_to_log(target),
		})
		attack_enemy(enemy_index)
	else:
		var from_pos: Vector2i = player["pos"]
		player["pos"] = target
		log_user_action("move", "moved", {
			"direction": vector_to_log(direction),
			"from": vector_to_log(from_pos),
			"target": vector_to_log(target),
		})
		if player["pos"] == stairs_pos:
			log_user_action("descend", "stairs_used", {
				"from_depth": player["depth"],
				"hp_before": player["hp"],
			})
			player["depth"] = player["depth"] + 1
			player["hp"] = mini(player["max_hp"], player["hp"] + 4)
			log_event("floor_descend", {
				"to_depth": player["depth"],
				"hp_after": player["hp"],
			})
			new_floor()
			return

	run_enemy_turn()
	queue_redraw()

func attack_enemy(index: int) -> void:
	var enemy := enemies[index]
	var enemy_hp_before: int = enemy["hp"]
	enemy["hp"] = enemy["hp"] - player["attack"]
	if enemy["hp"] <= 0:
		var enemy_pos: Vector2i = enemy["pos"]
		enemies.remove_at(index)
		var gold := rng.randi_range(1, 4)
		player["gold"] = player["gold"] + gold
		log_battle_result("enemy_defeated", {
			"enemy_pos": vector_to_log(enemy_pos),
			"damage": player["attack"],
			"enemy_hp_before": enemy_hp_before,
			"gold_gained": gold,
		})
		add_message("Enemy defeated. +%d gold." % gold)
	else:
		enemies[index] = enemy
		log_battle_result("enemy_hit", {
			"enemy_pos": vector_to_log(enemy["pos"]),
			"damage": player["attack"],
			"enemy_hp_before": enemy_hp_before,
			"enemy_hp_after": enemy["hp"],
		})
		add_message("You hit the enemy.")

func run_enemy_turn() -> void:
	for i in range(enemies.size()):
		var enemy := enemies[i]
		var enemy_pos: Vector2i = enemy["pos"]
		var delta: Vector2i = player["pos"] - enemy_pos

		if abs(delta.x) + abs(delta.y) == 1:
			var hp_before: int = player["hp"]
			player["hp"] = player["hp"] - enemy["attack"]
			log_battle_result("player_hit", {
				"enemy_pos": vector_to_log(enemy_pos),
				"damage": enemy["attack"],
				"player_hp_before": hp_before,
				"player_hp_after": maxi(player["hp"], 0),
			})
			add_message("Enemy hits you for %d." % enemy["attack"])
			if player["hp"] <= 0:
				player["hp"] = 0
				game_over = true
				log_battle_result("player_defeated", {
					"final_depth": player["depth"],
					"final_gold": player["gold"],
					"turns": turn_count,
				})
				add_message("You fell. Press R to restart.")
			continue

		if can_enemy_see_player(enemy_pos):
			var step := choose_enemy_step(enemy_pos, delta)
			var target: Vector2i = enemy_pos + step
			if is_walkable(target) and target != player["pos"] and enemy_at(target) == -1:
				enemy["pos"] = target
				enemies[i] = enemy

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

func enemy_at(pos: Vector2i) -> int:
	for i in range(enemies.size()):
		if enemies[i]["pos"] == pos:
			return i
	return -1

func is_walkable(pos: Vector2i) -> bool:
	if pos.x < 0 or pos.y < 0 or pos.x >= MAP_WIDTH or pos.y >= MAP_HEIGHT:
		return false
	return map[pos.y][pos.x] == TILE_FLOOR

func add_message(text: String) -> void:
	messages.push_front(text)
	if messages.size() > 5:
		messages.pop_back()

func open_log_file() -> void:
	if FileAccess.file_exists(LOG_FILE_PATH):
		log_file = FileAccess.open(LOG_FILE_PATH, FileAccess.READ_WRITE)
		if log_file:
			log_file.seek_end()
	else:
		log_file = FileAccess.open(LOG_FILE_PATH, FileAccess.WRITE_READ)

	if not log_file:
		push_warning("Could not open log file: %s" % LOG_FILE_PATH)

func start_run_log() -> void:
	run_id = "%d-%d" % [Time.get_unix_time_from_system(), rng.randi()]
	log_event("run_start", {
		"log_file": LOG_FILE_PATH,
	})

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

	var record := {
		"time": Time.get_datetime_string_from_system(false, true),
		"event": event_name,
		"run_id": run_id,
		"turn": turn_count,
		"depth": player["depth"],
		"hp": player["hp"],
		"gold": player["gold"],
		"details": details,
	}
	log_file.store_line(JSON.stringify(record))
	log_file.flush()

func vector_to_log(value: Vector2i) -> Dictionary:
	return {
		"x": value.x,
		"y": value.y,
	}

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), COLORS["bg"])
	draw_dungeon()
	draw_entities()
	draw_hud()
	if game_over:
		draw_game_over()

func draw_dungeon() -> void:
	for y in range(MAP_HEIGHT):
		for x in range(MAP_WIDTH):
			var pos := Vector2(x * TILE_SIZE, y * TILE_SIZE)
			var rect := Rect2(pos, Vector2(TILE_SIZE, TILE_SIZE))
			if map[y][x] == TILE_WALL:
				draw_rect(rect, COLORS["wall"])
				draw_rect(rect.grow(-4), COLORS["wall_edge"])
			else:
				var color: Color = COLORS["floor"] if (x + y) % 2 == 0 else COLORS["floor_alt"]
				draw_rect(rect, color)

	draw_tile_symbol(stairs_pos, ">", COLORS["stairs"])

func draw_entities() -> void:
	for enemy in enemies:
		draw_tile_symbol(enemy["pos"], "E", COLORS["enemy"])
	draw_tile_symbol(player["pos"], "@", COLORS["player"])

func draw_tile_symbol(tile: Vector2i, symbol: String, color: Color) -> void:
	var center := Vector2(tile.x * TILE_SIZE + TILE_SIZE * 0.5, tile.y * TILE_SIZE + TILE_SIZE * 0.5)
	draw_circle(center, TILE_SIZE * 0.42, color)
	var text_size := font.get_string_size(symbol, HORIZONTAL_ALIGNMENT_CENTER, -1, 15)
	draw_string(font, center - text_size * 0.5 + Vector2(0, 11), symbol, HORIZONTAL_ALIGNMENT_CENTER, -1, 15, COLORS["bg"])

func draw_hud() -> void:
	var hud_x := MAP_WIDTH * TILE_SIZE + 16
	var viewport_size := get_viewport_rect().size
	var panel := Rect2(hud_x - 8, 0, viewport_size.x - hud_x + 8, viewport_size.y)
	draw_rect(panel, COLORS["panel"])

	draw_string(font, Vector2(hud_x, 36), "SimpleRogue", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, COLORS["text"])
	draw_string(font, Vector2(hud_x, 76), "Depth %d" % player["depth"], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, COLORS["text"])
	draw_string(font, Vector2(hud_x, 104), "HP %d/%d" % [player["hp"], player["max_hp"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, COLORS["danger"] if player["hp"] <= 6 else COLORS["text"])
	draw_string(font, Vector2(hud_x, 132), "Gold %d" % player["gold"], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, COLORS["text"])

	draw_string(font, Vector2(hud_x, 190), "Arrows: move/attack", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COLORS["muted"])
	draw_string(font, Vector2(hud_x, 214), ". : wait", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COLORS["muted"])
	draw_string(font, Vector2(hud_x, 238), "R: restart", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COLORS["muted"])

	draw_string(font, Vector2(hud_x, 306), "Log", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, COLORS["text"])
	for i in range(messages.size()):
		draw_string(font, Vector2(hud_x, 336 + i * 24), messages[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLORS["muted"])

func draw_game_over() -> void:
	var rect := Rect2(230, 250, 500, 140)
	draw_rect(rect, Color(0, 0, 0, 0.72))
	draw_string(font, Vector2(350, 306), "Game Over", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, COLORS["danger"])
	draw_string(font, Vector2(326, 344), "Press R to try another run.", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, COLORS["text"])
