extends Node2D

const ReplayData := preload("res://scripts/replay_log.gd")
const DEFAULT_REPLAY := "res://../examples/reference/aggressive-seed-1.jsonl"
const AUTO_STEP_SECONDS := 0.28

const COLOR_BG := Color("#15171d")
const COLOR_WALL := Color("#303845")
const COLOR_FLOOR := Color("#242a32")
const COLOR_GRID := Color("#343c49")
const COLOR_PLAYER := Color("#f2d16b")
const COLOR_MELEE := Color("#d85f5f")
const COLOR_ARCHER := Color("#6ecbff")
const COLOR_STAIRS := Color("#79c7a6")

var replay := ReplayData.new()
var frame_index := 0
var playing := false
var auto_elapsed := 0.0
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
			var color := COLOR_FLOOR if row.substr(x, 1) == "." else COLOR_WALL
			draw_rect(rect, color)
			draw_rect(rect, COLOR_GRID, false, 1.0)

	draw_actor(frame["stairs_pos"], origin, tile_size, COLOR_STAIRS, 0.28)
	for enemy_value in frame["enemies"]:
		var enemy: Dictionary = enemy_value
		var color := COLOR_ARCHER if enemy.get("type", "") == "archer" else COLOR_MELEE
		draw_actor(enemy.get("pos", {}), origin, tile_size, color, 0.31)
	var player: Dictionary = frame["player_state"]
	draw_actor(player.get("pos", {}), origin, tile_size, COLOR_PLAYER, 0.34)


func draw_actor(
	position_value: Dictionary,
	origin: Vector2,
	tile_size: float,
	color: Color,
	radius_scale: float
) -> void:
	if not position_value.has("x") or not position_value.has("y"):
		return
	var center := origin + Vector2(position_value["x"] + 0.5, position_value["y"] + 0.5) * tile_size
	draw_circle(center, tile_size * radius_scale, color)
