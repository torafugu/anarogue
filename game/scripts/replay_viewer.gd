extends Node2D

const ReplayData := preload("res://scripts/replay_log.gd")
const DEFAULT_REPLAY := "res://../examples/reference-v8/aggressive-seed-424242.jsonl"
const REPLAY_TILE_SIZE := 96.0
const INFO_TOP := 126.0
const INFO_HEIGHT := 224.0
const MAP_TOP := INFO_TOP + INFO_HEIGHT + 16.0
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

var maze_view: Control
var maze_canvas: Node2D
var replay := ReplayData.new()
var frame_index := 0
var log_entries: Array[String] = []
var displayed_log_frame := -1
var playing := false
var auto_elapsed := 0.0
var arrow_elapsed := 0.0
var font := ThemeDB.fallback_font
var log_selector: OptionButton
var run_selector: OptionButton
var status_label: RichTextLabel
var player_label: RichTextLabel
var log_panel: PanelContainer
var player_panel: PanelContainer
var map_overlay: PanelContainer
var map_status_label: Label
var play_button: Button
var result_popup: PanelContainer
var result_title: Label
var result_stats: Label


func _ready() -> void:
	create_controls()
	get_viewport().size_changed.connect(layout_controls)
	layout_controls()
	var replay_path := command_line_replay_path()
	if not replay_path.is_empty():
		add_external_log_option(replay_path)
		load_replay(replay_path)
	elif not refresh_log_files():
		add_external_log_option(DEFAULT_REPLAY, "Bundled sample")
		load_replay(DEFAULT_REPLAY)


func create_controls() -> void:
	maze_view = Control.new()
	maze_view.name = "MazeViewport"
	maze_view.clip_contents = true
	maze_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(maze_view)
	maze_canvas = Node2D.new()
	maze_canvas.name = "MazeCanvas"
	maze_canvas.draw.connect(draw_maze)
	maze_view.add_child(maze_canvas)
	log_selector = OptionButton.new()
	log_selector.name = "LogSelector"
	log_selector.tooltip_text = "JSONL files stored in user://"
	log_selector.item_selected.connect(load_log_at)
	add_child(log_selector)

	run_selector = OptionButton.new()
	run_selector.name = "RunSelector"
	run_selector.tooltip_text = "Run contained in the selected JSONL file"
	run_selector.item_selected.connect(select_run_at)
	add_child(run_selector)

	var refresh_button := make_button("Refresh logs", reload_log_files)
	refresh_button.name = "RefreshButton"
	var previous_button := make_button("Previous", previous_frame)
	previous_button.name = "PreviousButton"
	play_button = make_button("Play", toggle_playing)
	play_button.name = "PlayButton"
	var next_button := make_button("Next", next_frame)
	next_button.name = "NextButton"
	var simulator_button := make_button("Live check", open_live_simulator)
	simulator_button.name = "SimulatorButton"

	log_panel = make_info_panel("LogPanel")
	status_label = make_info_text("LogText")
	log_panel.add_child(status_label)
	player_panel = make_info_panel("PlayerPanel")
	player_label = make_info_text("PlayerInfo")
	player_panel.add_child(player_label)

	map_overlay = PanelContainer.new()
	map_overlay.name = "MapOverlay"
	map_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_overlay.z_index = 1
	var overlay_style := StyleBoxFlat.new()
	overlay_style.bg_color = Color(0.05, 0.06, 0.08, 0.85)
	overlay_style.set_content_margin_all(8)
	map_overlay.add_theme_stylebox_override("panel", overlay_style)
	map_status_label = Label.new()
	map_status_label.add_theme_font_size_override("font_size", 18)
	map_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_overlay.add_child(map_status_label)
	add_child(map_overlay)
	map_overlay.hide()

	result_popup = PanelContainer.new()
	result_popup.name = "ResultPopup"
	result_popup.z_index = 2
	result_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0, 0, 0, 0.85)
	panel_style.set_content_margin_all(24)
	result_popup.add_theme_stylebox_override("panel", panel_style)
	var contents := VBoxContainer.new()
	contents.add_theme_constant_override("separation", 16)
	result_popup.add_child(contents)
	result_title = Label.new()
	result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_title.add_theme_font_size_override("font_size", 44)
	contents.add_child(result_title)
	result_stats = Label.new()
	result_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_stats.add_theme_font_size_override("font_size", 26)
	contents.add_child(result_stats)
	var hint := Label.new()
	hint.text = "Press Play to watch again."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 24)
	contents.add_child(hint)
	add_child(result_popup)
	result_popup.hide()

func make_info_panel(panel_name: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = panel_name
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#20252e")
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	return panel

func make_info_text(text_name: String) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.name = text_name
	label.add_theme_font_size_override("normal_font_size", 18)
	label.scroll_active = true
	label.selection_enabled = true
	return label

func map_rect() -> Rect2:
	var viewport_size := get_viewport_rect().size
	return Rect2(Vector2(16, MAP_TOP), Vector2(maxf(1, viewport_size.x - 32), maxf(1, viewport_size.y - MAP_TOP - 16)))

func camera_origin(frame: Dictionary) -> Vector2:
	var area := map_rect()
	var rows: Array = frame["map_rows"]
	if rows.is_empty() or str(rows[0]).is_empty():
		return Vector2.ZERO
	var world_size := Vector2(str(rows[0]).length(), rows.size()) * REPLAY_TILE_SIZE
	var position: Dictionary = frame["player_state"].get("pos", {})
	var player_center := Vector2(position.get("x", 0) + 0.5, position.get("y", 0) + 0.5) * REPLAY_TILE_SIZE
	var origin := Vector2.ZERO
	for axis in [0, 1]:
		if world_size[axis] <= area.size[axis]:
			origin[axis] = (area.size[axis] - world_size[axis]) * 0.5
		else:
			origin[axis] = -clampf(player_center[axis] - area.size[axis] * 0.5, 0, world_size[axis] - area.size[axis])
	return origin

func layout_map_overlay() -> void:
	var area := map_rect()
	maze_view.position = area.position
	maze_view.size = area.size
	maze_canvas.queue_redraw()
	map_overlay.position = area.position + Vector2(8, 8)
	map_overlay.size = Vector2.ZERO # Let the single-line badge fit its contents.

func make_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	add_child(button)
	return button


func layout_controls() -> void:
	var width := get_viewport_rect().size.x
	var selector_width := minf(420, (width - 40) * 0.5)
	log_selector.position = Vector2(16, 16)
	log_selector.size = Vector2(selector_width, 44)
	run_selector.position = Vector2(24 + selector_width, 16)
	run_selector.size = Vector2(minf(420, width - selector_width - 40), 44)
	var button_names := [
		"RefreshButton", "PreviousButton", "PlayButton", "NextButton", "SimulatorButton"
	]
	var x := 16.0
	for button_name in button_names:
		var button: Button = get_node(button_name)
		button.position = Vector2(x, 72)
		button.size = Vector2(132, 44)
		x += 140
	var available_width := width - 32
	var player_width := clampf(available_width * 0.42, 280, 440)
	var log_width := available_width - player_width - 16
	log_panel.position = Vector2(16, INFO_TOP)
	log_panel.size = Vector2(log_width, INFO_HEIGHT)
	player_panel.position = Vector2(32 + log_width, INFO_TOP)
	player_panel.size = Vector2(player_width, INFO_HEIGHT)
	layout_map_overlay()
	layout_result_popup()
	queue_redraw()


func layout_result_popup() -> void:
	var viewport_size := get_viewport_rect().size
	var area := map_rect()
	result_popup.size = Vector2(maxf(0, minf(560, viewport_size.x - 32)), 190)
	result_popup.position = Vector2(
		(viewport_size.x - result_popup.size.x) * 0.5,
		area.position.y + maxf(0, (area.size.y - result_popup.size.y) * 0.5)
	)


func refresh_log_files(preferred_path: String = "") -> bool:
	var logs: Array[Dictionary] = []
	var directory := DirAccess.open("user://")
	if directory == null:
		return false
	for file_name in directory.get_files():
		if not file_name.to_lower().ends_with(".jsonl"):
			continue
		var path := "user://%s" % file_name
		logs.append({
			"name": file_name,
			"path": path,
			"modified": FileAccess.get_modified_time(path),
		})
	logs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["modified"]) > int(b["modified"])
	)
	log_selector.clear()
	for log_entry in logs:
		log_selector.add_item(str(log_entry["name"]))
		log_selector.set_item_metadata(log_selector.item_count - 1, log_entry["path"])
	if logs.is_empty():
		return false
	var selected_index := 0
	for index in range(log_selector.item_count):
		if str(log_selector.get_item_metadata(index)) == preferred_path:
			selected_index = index
			break
	log_selector.select(selected_index)
	load_log_at(selected_index)
	return true


func reload_log_files() -> void:
	var preferred_path := replay.source_path if replay.source_path.begins_with("user://") else ""
	if not refresh_log_files(preferred_path):
		status_label.text = "No JSONL logs found in user://"
		queue_redraw()


func load_log_at(index: int) -> void:
	if index < 0 or index >= log_selector.item_count:
		return
	load_replay(str(log_selector.get_item_metadata(index)))


func add_external_log_option(path: String, label: String = "") -> void:
	log_selector.clear()
	log_selector.add_item(label if not label.is_empty() else path.get_file())
	log_selector.set_item_metadata(0, path)
	log_selector.select(0)


func load_replay(path: String) -> void:
	reset_log_history()
	var error := replay.load_file(path)
	if error != OK:
		update_status()
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
		reset_log_history()
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
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.is_pressed() or key_event.is_echo():
		return
	if key_event.keycode == KEY_LEFT:
		previous_frame()
	elif key_event.keycode == KEY_RIGHT:
		next_frame()
	elif key_event.keycode == KEY_SPACE:
		toggle_playing()


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
	result_popup.hide()
	if replay.frames.is_empty():
		status_label.text = "No replay frames."
		player_label.text = ""
		map_overlay.hide()
		return
	var frame: Dictionary = replay.frames[frame_index]
	var player: Dictionary = frame["player_state"]
	var outcome: String = frame.get("outcome", "")
	if frame["kind"] == "terminal" and outcome in ["player_defeated", "dungeon_cleared"]:
		var cleared := outcome == "dungeon_cleared"
		result_title.text = "Dungeon Cleared" if cleared else "Game Over"
		result_title.add_theme_color_override("font_color", COLOR_STAIRS if cleared else Color("#ff8a80"))
		result_stats.text = "Lv %d  |  Score %d  |  Depth %d" % [
			player.get("level", 1), player.get("score", 0), frame["depth"]
		]
		result_popup.show()
		layout_result_popup()
	map_status_label.text = "Depth %d   ·   Frame %d/%d   ·   Turn %d" % [frame["depth"], frame_index + 1, replay.frames.size(), frame["turn"]]
	map_overlay.show()
	layout_map_overlay()
	var raw_attack_text := "%d+%d" % [player.get("base_attack", player.get("attack", 0)), player.get("attack_bonus", 0)]
	if player.get("weapon_kind", "melee") == "bow":
		raw_attack_text = "(%s)/2" % raw_attack_text
	var equipment: Dictionary = player.get("equipment", {})
	var weapon = equipment.get("weapon")
	var armor = equipment.get("armor")
	player_label.text = "Lv %d · XP %d/%d\nHP %d/%d\nATK %d [%s] · DEF %d (%d+%d)\n%s range %d · Potions %d/3\nW %s\nD %s\nStrategy %s" % [
		player.get("level", 1), player.get("xp", 0), int(player.get("level", 1)) * 8,
		player.get("hp", 0), player.get("max_hp", 0), player.get("attack", 0), raw_attack_text,
		player.get("defense", 0), player.get("base_defense", 0), player.get("defense_bonus", 0),
		player.get("weapon_kind", "melee"), player.get("attack_range", 1), int(player.get("inventory", {}).get("health_potion", 0)),
		weapon["id"] if weapon != null else "none", armor["id"] if armor != null else "none", frame["strategy_id"]
	]
	update_log_history()

func reset_log_history() -> void:
	log_entries.clear()
	displayed_log_frame = -1
	status_label.text = ""

func update_log_history() -> void:
	if displayed_log_frame == frame_index:
		return
	if log_entries.is_empty():
		for entry in replay.frames:
			log_entries.append(format_log_entry(entry))
		if not replay.warnings.is_empty():
			log_entries[0] += "\nWarning: " + replay.warnings[0]
	var scrollbar := status_label.get_v_scroll_bar()
	var old_scroll := scrollbar.value
	var follow_latest := displayed_log_frame < 0 or frame_index != displayed_log_frame + 1 or old_scroll >= scrollbar.max_value - scrollbar.page - 2
	status_label.scroll_following = follow_latest
	if frame_index == displayed_log_frame + 1:
		status_label.add_text(("\n\n" if displayed_log_frame >= 0 else "") + log_entries[frame_index])
	else:
		status_label.text = "\n\n".join(log_entries.slice(0, frame_index + 1))
	if follow_latest:
		status_label.scroll_to_line(maxi(0, status_label.get_line_count() - 1))
	else:
		scrollbar.value = old_scroll
	displayed_log_frame = frame_index

func format_log_entry(frame: Dictionary) -> String:
	var rule: String = frame["rule_id"]
	var text := ""
	var goal: Dictionary = frame.get("goal_selection", {})
	if not goal.is_empty():
		text += "\nGoal %s / %s · %s" % [goal["selected_kind"], goal["selected_id"], "retained (no draw)" if goal["target_retained"] else "drawn"]
		for candidate in goal["candidates"]:
			if candidate["kind"] == goal["selected_kind"] and candidate["id"] == goal["selected_id"]:
				text += " · benefit %d − risk %d · utility %d" % [candidate["benefit"], candidate["risk"], candidate["utility"]]
		var chances: Array[String] = []
		for entry in goal["distribution"]:
			chances.append("%s %.1f%%" % [entry["kind"], 100.0 * entry["mass"] / entry["total_mass"]])
		text += " · redraw: " + ", ".join(chances)
	var progression: Dictionary = frame.get("progression", {})
	if not progression.is_empty():
		var best_score := "none"
		for candidate in progression["candidates"]:
			if candidate["eligible"] and (best_score == "none" or int(candidate["score"]) > int(best_score)):
				best_score = str(candidate["score"])
		if progression["selected"] == "combat":
			for candidate in progression["candidates"]:
				if candidate["enemy_id"] == progression["selected_enemy_id"]:
					best_score = str(candidate["score"])
		text += "\nGrowth %s vs stairs %d · %s" % [best_score, progression["stairs_score"], progression["selected"]]
	if frame["kind"] == "item_result":
		text += "\n%s" % frame["reason"]
	elif not rule.is_empty():
		text += "\n%s" % rule if not progression.is_empty() else "\n%s — %s" % [rule, frame["reason"]]
	elif frame["kind"] == "brute_result":
		text += "\n%s" % frame["reason"]
	elif frame["kind"] == "player_ranged_hit":
		text += "\nPlayer bow shot"
		if not str(frame["reason"]).is_empty():
			text += " · " + str(frame["reason"])
	elif frame["kind"] == "ranged_hit":
		text += "\nArcher ranged attack"
	elif frame["kind"] == "floor_start":
		text += "\nFloor %d starts." % frame["depth"]
	elif frame["kind"] == "terminal":
		text += "\n" + ("Dungeon cleared." if frame["outcome"] == "dungeon_cleared" else "Player defeated.")

	return "[Turn %d] %s" % [frame["turn"], text.strip_edges()]


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), COLOR_BG)
	if maze_canvas != null:
		maze_canvas.queue_redraw()

func draw_maze() -> void:
	maze_canvas.draw_rect(Rect2(Vector2.ZERO, maze_view.size), COLOR_BG)
	if replay.frames.is_empty():
		return
	var frame: Dictionary = replay.frames[frame_index]
	var rows: Array = frame["map_rows"]
	if rows.is_empty():
		return
	var map_height := rows.size()
	var map_width: int = str(rows[0]).length()
	var area := map_rect()
	var tile_size := REPLAY_TILE_SIZE
	var origin := camera_origin(frame)
	var first_x := clampi(int(floor(-origin.x / tile_size)), 0, map_width)
	var first_y := clampi(int(floor(-origin.y / tile_size)), 0, map_height)
	var last_x := clampi(int(ceil((area.size.x - origin.x) / tile_size)), 0, map_width)
	var last_y := clampi(int(ceil((area.size.y - origin.y) / tile_size)), 0, map_height)
	for y in range(first_y, last_y):
		var row := str(rows[y])
		for x in range(first_x, last_x):
			var rect := Rect2(origin + Vector2(x, y) * tile_size, Vector2.ONE * tile_size)
			if row.substr(x, 1) == ".":
				var floor_color := COLOR_FLOOR if (x + y) % 2 == 0 else COLOR_FLOOR_ALT
				maze_canvas.draw_rect(rect, floor_color)
			else:
				maze_canvas.draw_rect(rect, COLOR_WALL)
				maze_canvas.draw_rect(rect.grow(-tile_size * 0.2), COLOR_WALL_EDGE)

	draw_stairs_icon(frame["stairs_pos"], origin, tile_size)
	for item_value in frame.get("items", []):
		var item: Dictionary = item_value
		draw_actor(item.get("pos", {}), origin, tile_size, Color("#de8fe8"), ("B" if item.get("weapon_kind", "melee") == "bow" else "W") if item.get("type", "") == "weapon" else ("D" if item.get("type", "") == "armor" else "+"))
	for enemy_value in frame["enemies"]:
		var enemy: Dictionary = enemy_value
		var color := COLOR_ARCHER if enemy.get("type", "") == "archer" else COLOR_MELEE
		var symbol := "O" if enemy.get("type", "") == "brute" else ("A" if enemy.get("type", "") == "archer" else "E")
		if enemy.get("windup_target") != null:
			var mark: Dictionary = enemy["windup_target"]
			maze_canvas.draw_rect(Rect2(origin + Vector2(mark["x"], mark["y"]) * tile_size, Vector2.ONE * tile_size).grow(-1), Color("#e76767"), false, 2.0)
		draw_actor(enemy.get("pos", {}), origin, tile_size, Color("#ce8e4c") if enemy.get("type", "") == "brute" else color, symbol)
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
	maze_canvas.draw_circle(center, tile_size * 0.42, color)
	var symbol_size := int(tile_size * 0.75)
	var text_size := font.get_string_size(
		symbol, HORIZONTAL_ALIGNMENT_CENTER, -1, symbol_size
	)
	maze_canvas.draw_string(
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
	maze_canvas.draw_rect(badge, COLOR_BG)
	maze_canvas.draw_rect(badge, COLOR_STAIRS, false, 2.0 * scale)
	var steps := PackedVector2Array([
		tile_origin + Vector2(9, 12) * scale,
		tile_origin + Vector2(16, 12) * scale,
		tile_origin + Vector2(16, 19) * scale,
		tile_origin + Vector2(23, 19) * scale,
		tile_origin + Vector2(23, 26) * scale,
		tile_origin + Vector2(30, 26) * scale,
	])
	maze_canvas.draw_polyline(steps, COLOR_STAIRS, 3.0 * scale, true)
	maze_canvas.draw_line(
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
		maze_canvas.draw_line(
			tail - direction * tile_size * 0.3,
			tip,
			Color(0.43, 0.8, 1.0, 0.3),
			maxf(2.0, tile_size * 0.15),
			true
		)
		maze_canvas.draw_line(tail, tip, COLOR_PLAYER if arrow.get("player_shot", false) else COLOR_ARCHER, maxf(1.0, tile_size * 0.075), true)
		maze_canvas.draw_colored_polygon(PackedVector2Array([
			tip,
			tip - direction * tile_size * 0.225 + perpendicular * tile_size * 0.125,
			tip - direction * tile_size * 0.225 - perpendicular * tile_size * 0.125,
		]), COLOR_TEXT)
	else:
		var progress := (arrow_elapsed - ARROW_FLIGHT_DURATION) / ARROW_IMPACT_DURATION
		var color := COLOR_PLAYER if arrow.get("player_shot", false) else COLOR_ARCHER
		color.a = 1.0 - progress
		maze_canvas.draw_arc(
			target,
			tile_size * (0.25 + progress * 0.4),
			0.0,
			TAU,
			32,
			color,
			maxf(1.0, tile_size * 0.075),
			true
		)
