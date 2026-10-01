extends Node2D

const ReplayData := preload("res://scripts/replay_log.gd")
const DEFAULT_REPLAY := "res://../examples/reference/aggressive-seed-1.jsonl"
const AUTO_STEP_SECONDS := 0.28
const ARROW_FLIGHT_DURATION := 0.28
const ARROW_IMPACT_DURATION := 0.12

const COLOR_BG := Color("#15171d")
const COLOR_WALL := Color("#303845")
const COLOR_WALL_EDGE := Color("#465266")
const COLOR_FLOOR := Color("#242a32")
const COLOR_FLOOR_ALT := Color("#29313b")
const COLOR_PLAYER := Color("#f2d16b")
const COLOR_MELEE := Color("#d85f5f")
const COLOR_ARCHER := Color("#6ecbff")
const COLOR_STAIRS := Color("#79c7a6")
const COLOR_TEXT := Color("#e7e1cf")

var replay := ReplayData.new()
var frame_index := 0
var playing := false
var auto_elapsed := 0.0
var arrow_elapsed := 0.0
var font := ThemeDB.fallback_font
var run_selector: OptionButton
var status_label: Label
var play_button: Button
var file_dialog: FileDialog


func _ready() -> void:
	create_controls()
	get_viewport().size_changed.connect(layout_controls)
	layout_controls()
	var replay_path := command_line_replay_path()
	if replay_path.is_empty():
		replay_path = DEFAULT_REPLAY
	load_replay(replay_path)


func create_controls() -> void:
	run_selector = OptionButton.new()
	run_selector.item_selected.connect(select_run_at)
	add_child(run_selector)

	var open_button := make_button("Open JSONL", open_file_dialog)
	open_button.name = "OpenButton"
	var previous_button := make_button("Previous", previous_frame)
	previous_button.name = "PreviousButton"
	play_button = make_button("Play", toggle_playing)
	play_button.name = "PlayButton"
	var next_button := make_button("Next", next_frame)
	next_button.name = "NextButton"
	var simulator_button := make_button("Live check", open_live_simulator)
	simulator_button.name = "SimulatorButton"

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 18)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status_label)

	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.add_filter("*.jsonl", "AnaRogue JSON Lines")
	file_dialog.file_selected.connect(load_replay)
	add_child(file_dialog)


func make_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	add_child(button)
	return button


func layout_controls() -> void:
	var width := get_viewport_rect().size.x
	run_selector.position = Vector2(16, 16)
	run_selector.size = Vector2(minf(340, width - 32), 44)
	var button_names := [
		"OpenButton", "PreviousButton", "PlayButton", "NextButton", "SimulatorButton"
	]
	var x := 16.0
	for button_name in button_names:
		var button: Button = get_node(button_name)
		button.position = Vector2(x, 72)
		button.size = Vector2(132, 44)
		x += 140
	status_label.position = Vector2(16, 126)
	status_label.size = Vector2(width - 32, 82)
	queue_redraw()


func load_replay(path: String) -> void:
	var error := replay.load_file(path)
	if error != OK:
		status_label.text = "Could not open replay: %s (error %d)" % [path, error]
		queue_redraw()
		return
	run_selector.clear()
	for run_id in replay.run_ids:
		run_selector.add_item(run_id)
	run_selector.select(replay.run_ids.size() - 1)
	frame_index = 0
	playing = false
	play_button.text = "Play"
	update_status()
	queue_redraw()


func select_run_at(index: int) -> void:
	if replay.select_run(replay.run_ids[index]):
		frame_index = 0
		playing = false
		play_button.text = "Play"
		update_status()
		queue_redraw()


func previous_frame() -> void:
	set_frame(frame_index - 1)


func next_frame() -> void:
	set_frame(frame_index + 1)


func set_frame(index: int) -> void:
	if replay.frames.is_empty():
		return
	frame_index = clampi(index, 0, replay.frames.size() - 1)
	arrow_elapsed = 0.0
	if frame_index == replay.frames.size() - 1:
		playing = false
		play_button.text = "Play"
	update_status()
	queue_redraw()


func toggle_playing() -> void:
	if replay.frames.is_empty():
		return
	if frame_index == replay.frames.size() - 1:
		frame_index = 0
	playing = not playing
	play_button.text = "Pause" if playing else "Play"
	auto_elapsed = 0.0
	update_status()
	queue_redraw()


func _process(delta: float) -> void:
	if is_arrow_animating():
		arrow_elapsed += delta
		queue_redraw()
		return
	if not playing:
		return
	auto_elapsed += delta
	if auto_elapsed >= AUTO_STEP_SECONDS:
		auto_elapsed = 0.0
		set_frame(frame_index + 1)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.keycode == KEY_LEFT:
		previous_frame()
	elif event.keycode == KEY_RIGHT:
		next_frame()
	elif event.keycode == KEY_SPACE:
		toggle_playing()


func open_file_dialog() -> void:
	file_dialog.popup_centered_ratio(0.8)


func open_live_simulator() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func command_line_replay_path() -> String:
	var arguments := OS.get_cmdline_user_args()
	for index in range(arguments.size()):
		if arguments[index] == "--replay" and index + 1 < arguments.size():
			return arguments[index + 1]
		if arguments[index].begins_with("--replay="):
			return arguments[index].trim_prefix("--replay=")
	return ""


func update_status() -> void:
	if replay.frames.is_empty():
		status_label.text = "No replay frames."
		return
	var frame: Dictionary = replay.frames[frame_index]
	var player: Dictionary = frame["player_state"]
	var rule: String = frame["rule_id"]
	var line := "%s  ·  frame %d/%d  ·  turn %d  ·  depth %d  ·  HP %d/%d"
	status_label.text = line % [
		frame["strategy_id"], frame_index + 1, replay.frames.size(), frame["turn"],
		frame["depth"], player.get("hp", 0), player.get("max_hp", 0)
	]
	if not rule.is_empty():
		status_label.text += "\n%s — %s" % [rule, frame["reason"]]
	elif frame["kind"] == "ranged_hit":
		status_label.text += "\nArcher ranged attack"
	elif not replay.warnings.is_empty():
		status_label.text += "\n%s" % replay.warnings[0]


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), COLOR_BG)
	if replay.frames.is_empty():
		return
	var frame: Dictionary = replay.frames[frame_index]
	var rows: Array = frame["map_rows"]
	if rows.is_empty():
		return
	var map_height := rows.size()
	var map_width: int = str(rows[0]).length()
	var available := Vector2(get_viewport_rect().size.x - 32, get_viewport_rect().size.y - 236)
	var tile_size := minf(available.x / map_width, available.y / map_height)
	var origin := Vector2(
		(get_viewport_rect().size.x - map_width * tile_size) * 0.5,
		220
	)
	for y in range(map_height):
		var row := str(rows[y])
		for x in range(map_width):
			var rect := Rect2(origin + Vector2(x, y) * tile_size, Vector2.ONE * tile_size)
			if row.substr(x, 1) == ".":
				var floor_color := COLOR_FLOOR if (x + y) % 2 == 0 else COLOR_FLOOR_ALT
				draw_rect(rect, floor_color)
			else:
				draw_rect(rect, COLOR_WALL)
				draw_rect(rect.grow(-tile_size * 0.2), COLOR_WALL_EDGE)

	draw_stairs_icon(frame["stairs_pos"], origin, tile_size)
	for enemy_value in frame["enemies"]:
		var enemy: Dictionary = enemy_value
		var color := COLOR_ARCHER if enemy.get("type", "") == "archer" else COLOR_MELEE
		var symbol := "A" if enemy.get("type", "") == "archer" else "E"
		draw_actor(enemy.get("pos", {}), origin, tile_size, color, symbol)
	var player: Dictionary = frame["player_state"]
	draw_actor(player.get("pos", {}), origin, tile_size, COLOR_PLAYER, "@")
	draw_arrow(frame["arrow"], origin, tile_size)


func draw_actor(
	position_value: Dictionary,
	origin: Vector2,
	tile_size: float,
	color: Color,
	symbol: String
) -> void:
	if not position_value.has("x") or not position_value.has("y"):
		return
	var center := origin + Vector2(position_value["x"] + 0.5, position_value["y"] + 0.5) * tile_size
	draw_circle(center, tile_size * 0.42, color)
	var symbol_size := int(tile_size * 0.75)
	var text_size := font.get_string_size(
		symbol, HORIZONTAL_ALIGNMENT_CENTER, -1, symbol_size
	)
	draw_string(
		font,
		center - text_size * 0.5 + Vector2(0, tile_size * 0.55),
		symbol,
		HORIZONTAL_ALIGNMENT_CENTER,
		-1,
		symbol_size,
		COLOR_BG
	)


func draw_stairs_icon(position_value: Dictionary, origin: Vector2, tile_size: float) -> void:
	if not position_value.has("x") or not position_value.has("y"):
		return
	var tile_origin := origin + Vector2(position_value["x"], position_value["y"]) * tile_size
	var scale := tile_size / 40.0
	var badge := Rect2(tile_origin + Vector2.ONE * 4.0 * scale, Vector2.ONE * 32.0 * scale)
	draw_rect(badge, COLOR_BG)
	draw_rect(badge, COLOR_STAIRS, false, 2.0 * scale)
	var steps := PackedVector2Array([
		tile_origin + Vector2(9, 12) * scale,
		tile_origin + Vector2(16, 12) * scale,
		tile_origin + Vector2(16, 19) * scale,
		tile_origin + Vector2(23, 19) * scale,
		tile_origin + Vector2(23, 26) * scale,
		tile_origin + Vector2(30, 26) * scale,
	])
	draw_polyline(steps, COLOR_STAIRS, 3.0 * scale, true)
	draw_line(
		tile_origin + Vector2(9, 31) * scale,
		tile_origin + Vector2(30, 31) * scale,
		COLOR_STAIRS,
		2.0 * scale,
		true
	)


func is_arrow_animating() -> bool:
	if replay.frames.is_empty():
		return false
	var frame: Dictionary = replay.frames[frame_index]
	return (
		not frame["arrow"].is_empty()
		and arrow_elapsed < ARROW_FLIGHT_DURATION + ARROW_IMPACT_DURATION
	)


func draw_arrow(arrow: Dictionary, origin: Vector2, tile_size: float) -> void:
	if arrow.is_empty() or not is_arrow_animating():
		return
	var from_value: Dictionary = arrow["from"]
	var to_value: Dictionary = arrow["to"]
	if not from_value.has("x") or not to_value.has("x"):
		return
	var arrow_origin := origin + Vector2(from_value["x"] + 0.5, from_value["y"] + 0.5) * tile_size
	var target := origin + Vector2(to_value["x"] + 0.5, to_value["y"] + 0.5) * tile_size
	if arrow_elapsed < ARROW_FLIGHT_DURATION:
		var direction := (target - arrow_origin).normalized()
		var perpendicular := Vector2(-direction.y, direction.x)
		var tip := arrow_origin.lerp(target, arrow_elapsed / ARROW_FLIGHT_DURATION)
		var tail := tip - direction * tile_size * 0.55
		draw_line(
			tail - direction * tile_size * 0.3,
			tip,
			Color(0.43, 0.8, 1.0, 0.3),
			maxf(2.0, tile_size * 0.15),
			true
		)
		draw_line(tail, tip, COLOR_ARCHER, maxf(1.0, tile_size * 0.075), true)
		draw_colored_polygon(PackedVector2Array([
			tip,
			tip - direction * tile_size * 0.225 + perpendicular * tile_size * 0.125,
			tip - direction * tile_size * 0.225 - perpendicular * tile_size * 0.125,
		]), COLOR_TEXT)
	else:
		var progress := (arrow_elapsed - ARROW_FLIGHT_DURATION) / ARROW_IMPACT_DURATION
		var color := COLOR_ARCHER
		color.a = 1.0 - progress
		draw_arc(
			target,
			tile_size * (0.25 + progress * 0.4),
			0.0,
			TAU,
			32,
			color,
			maxf(1.0, tile_size * 0.075),
			true
		)
