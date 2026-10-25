extends SceneTree

const ReplayViewer := preload("res://scripts/replay_viewer.gd")
const ReplayData := preload("res://scripts/replay_log.gd")

class TestViewer extends ReplayViewer:
	func _ready() -> void:
		create_controls()
		layout_controls()

var failures: Array[String] = []

func _init() -> void:
	run_tests.call_deferred()

func run_tests() -> void:
	var viewer := TestViewer.new()
	root.add_child(viewer)
	check_arrow_scenes(viewer)
	check_camera_geometry(viewer)
	await check_layout_sizes()
	await check_turn_log(viewer)
	check_reference_arrow_targets()
	for file_name in ["aggressive-seed-1.jsonl", "cautious-seed-1.jsonl"]:
		viewer.load_replay("res://../examples/reference-v2/" + file_name)
		check(not viewer.result_popup.visible, "popup hidden at replay start")
		viewer.set_turn(viewer.replay.turns.size() - 1)
		check(viewer.replay.turns.back()["outcome"] == "player_defeated", "defeat outcome preserved")
		check(viewer.result_popup.visible, "defeat popup visible for " + file_name)
		check(viewer.result_title.text == "Game Over", "defeat title is Game Over")
		check(not viewer.playing, "playback stops at terminal frame")
		viewer.previous_turn()
		check(not viewer.result_popup.visible, "stepping back hides popup")
		viewer.next_turn()
		check(viewer.result_popup.visible, "returning to defeat shows popup")
		viewer.toggle_playing()
		check(not viewer.result_popup.visible, "replaying hides popup")
		viewer.playing = false

	viewer.load_replay("res://../examples/reference-v5/aggressive-seed-424242.jsonl")
	var growth_frame := -1
	for index in range(viewer.replay.turns.size()):
		if viewer.replay.turns[index]["log_frames"].any(func(f): return f["rule_id"] == "hunt_for_growth"):
			growth_frame = index
			break
	check(growth_frame >= 0, "v5 reference contains a growth decision")
	if growth_frame >= 0:
		viewer.set_turn(growth_frame)
		var player: Dictionary = viewer.replay.turns[growth_frame]["player_state"]
		check(viewer.player_labels["level"].text == "Lv %d" % player["level"], "growth replay shows current level")
		check(viewer.player_labels["xp"].text == "XP %d/%d" % [player["xp"], player["level"] * 8], "growth replay shows current XP threshold")
		check(viewer.status_label.text.contains("Growth ") and viewer.status_label.text.contains("vs stairs"), "growth replay renders the comparison")

	viewer.load_replay("res://../examples/reference-v6/cautious-seed-1.jsonl")
	var shot_frame := -1
	for index in range(viewer.replay.turns.size()):
		if viewer.replay.turns[index]["log_frames"].any(func(f): return f["kind"] == "player_ranged_hit"):
			shot_frame = index
			break
	check(shot_frame >= 0, "v6 reference contains a Player bow shot")
	if shot_frame >= 0:
		viewer.set_turn(shot_frame)
		check(viewer.status_label.text.contains("Player bow shot"), "replay labels Player arrows")
		check(not viewer.replay.turns[shot_frame]["arrow"].is_empty(), "Turn snapshot retains its bow animation")
		check(viewer.player_labels["weapon_kind"].text == "Weapon type bow" and viewer.player_labels["range"].text == "Range 5", "replay shows bow kind and range")

	viewer.load_replay("res://../examples/reference-v7/cautious-seed-27-cycle.jsonl")
	var windup_frame := -1
	for index in range(viewer.replay.turns.size()):
		if viewer.replay.turns[index]["log_frames"].any(func(f): return f["kind"] == "brute_result" and f["reason"].contains("winds up")):
			windup_frame = index
			break
	check(windup_frame >= 0, "v7 reference contains Brute preparation")
	if windup_frame >= 0:
		viewer.set_turn(windup_frame)
		check(viewer.status_label.text.contains("Brute winds up"), "replay labels Brute preparation")
		check(viewer.replay.turns[windup_frame]["enemies"].any(func(e): return e.get("windup_target") != null), "replay exposes the marked tile")

	# Completion may have no new floor_start event at the deepest floor.
	var replay := ReplayData.new()
	viewer.replay.turns = replay.build_turns([
		{"event": "floor_start", "turn": 0, "depth": 4, "details": {"map_rows": ["..."]}},
		{"event": "battle_result", "turn": 1, "depth": 5, "player_state": {"level": 3, "score": 12},
			"details": {"result": "dungeon_cleared"}},
	])
	viewer.set_turn(1)
	check(viewer.result_popup.visible, "completion popup visible")
	check(viewer.result_title.text == "Dungeon Cleared", "completion title preserved")
	check(viewer.result_stats.text == "Lv 3  |  Score 12  |  Depth 5", "terminal stats displayed")
	viewer.free()
	if failures.is_empty():
		print("Replay popup tests passed.")
		quit(0)
	else:
		for failure in failures:
			printerr(failure)
		quit(1)

func check_layout_sizes() -> void:
	for dimensions in [Vector2i(1080, 1920), Vector2i(1080, 1440), Vector2i(1440, 1920), Vector2i(720, 1280)]:
		var viewport := SubViewport.new()
		viewport.size = dimensions
		root.add_child(viewport)
		var viewer := TestViewer.new()
		viewport.add_child(viewer)
		viewer.load_replay("res://../examples/reference-v8/aggressive-seed-424242.jsonl")
		await process_frame
		await process_frame
		var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
		var controls: Array[Control] = [
			viewer.run_selector,
			viewer.get_node("PreviousButton"), viewer.play_button, viewer.get_node("NextButton"),
			viewer.get_node("SimulatorButton"),
			viewer.log_panel, viewer.player_panel, viewer.maze_view,
		]
		for i in range(controls.size()):
			check(bounds.encloses(controls[i].get_rect()), "control stays within viewport %s" % dimensions)
			for j in range(i + 1, controls.size()):
				check(not controls[i].get_rect().intersects(controls[j].get_rect()), "controls do not overlap at %s" % dimensions)
		check(viewer.get_node_or_null("CatalogStatus") == null, "catalog count is removed")
		check(not viewer.player_labels.has("strategy"), "player status omits strategy")
		check(viewer.player_labels.size() == 10, "each player stat has a dedicated Label")
		var player_scroll: ScrollContainer = viewer.player_panel.get_node("PlayerScroll")
		check(player_scroll.get_v_scroll_bar().max_value > player_scroll.get_v_scroll_bar().page, "individual status labels remain scrollable")
		for label in viewer.player_labels.values():
			check(label.size.x <= player_scroll.size.x, "status labels fit panel width")
		var button_y: float = viewer.play_button.position.y
		for name in ["PreviousButton", "NextButton", "SimulatorButton"]:
			check(is_equal_approx(viewer.get_node(name).position.y, button_y), "all playback buttons share one row")
		check(viewer.get_node("PreviousButton").text == "|◀" and viewer.get_node("NextButton").text == "▶|", "step controls use symbols")
		check(viewer.play_button.text == "▶", "paused playback shows play symbol")
		viewer.toggle_playing()
		check(viewer.play_button.text == "⏸", "playing shows pause symbol")
		viewer.toggle_playing()
		var badge_size := viewer.map_overlay.size
		# Include digit-count boundaries and the terminal frame after container layout settles.
		for index in [8, 9, 98, 99, viewer.replay.turns.size() - 1]:
			viewer.set_turn(index)
			await process_frame
			await process_frame
			check(viewer.map_overlay.size.is_equal_approx(badge_size), "badge size stays fixed at frame %d / %s" % [index, dimensions])
			check(viewer.map_status_label.get_line_count() == 1, "badge remains a single line")
		check(viewer.play_button.text == "▶", "terminal frame restores play symbol")
		check(viewer.map_rect().encloses(viewer.result_popup.get_rect()), "result popup fits maze at %s" % dimensions)
		check(viewer.map_rect().encloses(viewer.map_overlay.get_rect()), "depth/frame/turn badge fits maze at %s" % dimensions)
		viewport.free()

func check_camera_geometry(viewer: TestViewer) -> void:
	var frame := {"map_rows": [], "player_state": {"pos": {"x": 22, "y": 14}}}
	for _row in range(28):
		frame["map_rows"].append(".".repeat(44))
	var area := viewer.map_rect()
	var tile: float = viewer.REPLAY_TILE_SIZE
	check(tile > area.size.x / 44, "tiles stay large rather than fitting the full dungeon")
	var center := Vector2(22.5, 14.5) * tile
	var origin := viewer.camera_origin(frame)
	check((origin + center).is_equal_approx(area.size * 0.5), "camera centers on Player in the dungeon interior")
	frame["player_state"]["pos"]["x"] += 1
	check(is_equal_approx(viewer.camera_origin(frame).x, origin.x - tile), "camera follows a one-tile Player movement")
	frame["player_state"]["pos"] = {"x": 0, "y": 0}
	check(viewer.camera_origin(frame) == Vector2.ZERO, "camera clamps at top-left dungeon edge")
	frame["player_state"]["pos"] = {"x": 43, "y": 27}
	check(viewer.camera_origin(frame).is_equal_approx(area.size - Vector2(44, 28) * tile), "camera clamps at bottom-right dungeon edge")
	frame["map_rows"] = ["..."]
	check(viewer.camera_origin(frame).is_equal_approx((area.size - Vector2(3, 1) * tile) * 0.5), "small maps are centered without shrinking tiles")
	check(viewer.maze_view.clip_contents, "map drawing is clipped away from controls and information")
	check(viewer.maze_view.get_rect() == area, "maze and overlay share the same display region")

func check_turn_log(viewer: TestViewer) -> void:
	viewer.load_replay("res://../examples/reference-v8/aggressive-seed-424242.jsonl")
	var initial := viewer.status_label.get_parsed_text()
	check(not initial.contains("Decision for Turn 1"), "Turn zero only shows initialization")
	viewer.next_turn()
	var first := viewer.status_label.get_parsed_text()
	check(viewer.replay.turns[viewer.turn_index]["turn"] == 1, "Next advances a whole Turn")
	check(first.contains("Decision for Turn 1") and first.contains("moved"), "decision and movement share the executed Turn")
	check(not first.contains("run_start") and not first.contains("Decision for Turn 2"), "only current Turn logs are displayed")
	check(not viewer.map_status_label.text.contains("Frame"), "badge no longer shows Frame")
	viewer.next_turn()
	check(viewer.replay.turns[viewer.turn_index]["turn"] == 2, "next step reaches Turn two")
	check(not viewer.status_label.text.contains("Decision for Turn 1"), "advancing replaces previous Turn logs")
	viewer.previous_turn()
	check(viewer.status_label.get_parsed_text() == first, "rewinding restores the selected Turn log")
	await process_frame
	await process_frame
	var scrollbar := viewer.status_label.get_v_scroll_bar()
	scrollbar.value = scrollbar.max_value
	viewer.next_turn()
	await process_frame
	await process_frame
	check(scrollbar.value == 0, "changing Turns resets log scrolling to the top")
	viewer.toggle_playing()
	viewer._process(viewer.AUTO_STEP_SECONDS)
	check(viewer.replay.turns[viewer.turn_index]["turn"] == 3, "automatic playback advances one whole Turn")
	viewer.toggle_playing()
	viewer.load_replay("res://../examples/reference-v8/cautious-seed-2.jsonl")
	check(viewer.displayed_log_turn == 0 and not viewer.status_label.text.contains("Decision for Turn 1"), "switching Runs resets to initialization")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append("FAIL: " + message)

func check_arrow_scenes(viewer) -> void:
	for enemy_type in ["melee", "brute"]:
		var events := [
			{"event": "floor_start", "turn": 0, "depth": 1, "player_state": {"pos": {"x": 0, "y": 0}}, "details": {
				"map_rows": ["......"], "enemies": [
					{"id": "victim", "type": enemy_type, "hp": 2, "pos": {"x": 3, "y": 0}},
					{"id": "archer", "type": "archer", "hp": 5, "pos": {"x": 5, "y": 0}}]}},
			{"event": "battle_result", "turn": 1, "depth": 1, "player_state": {"pos": {"x": 0, "y": 0}}, "details": {
				"result": "enemy_defeated", "ranged": true, "enemy_id": "victim", "enemy_type": enemy_type,
				"attacker_pos": {"x": 0, "y": 0}, "enemy_pos": {"x": 3, "y": 0}, "enemy_hp_before": 2, "enemy_hp_after": 0}},
			{"event": "battle_result", "turn": 1, "depth": 1, "player_state": {"pos": {"x": 0, "y": 0}, "hp": 16}, "details": {
				"result": "player_hit", "ranged": true, "enemy_id": "archer", "enemy_type": "archer", "enemy_pos": {"x": 5, "y": 0}}},
			{"event": "decision", "turn": 1, "depth": 1, "player_state": {"pos": {"x": 0, "y": 0}, "hp": 16}, "details": {
				"action_turn": 2, "observation": {"enemies": [{"id": "archer", "type": "archer", "hp": 5, "pos": {"x": 4, "y": 0}}]}}},
		]
		viewer.replay.turns = viewer.replay.build_turns(events)
		viewer.set_turn(1)
		check(viewer.replay.turns[1]["arrow_frames"].size() == 2, "all shots in a Turn are retained in event order")
		var shot: Dictionary = viewer.display_frame()
		check(shot["arrow"].get("player_shot", false), "Player shot animates first")
		check(shot["enemies"].any(func(e): return e["id"] == "victim" and e["pos"] == shot["arrow"]["to"] and e["hp"] == 2), "fatal arrow has a visible victim at its endpoint: " + enemy_type)
		viewer.arrow_elapsed = viewer.ARROW_FLIGHT_DURATION + viewer.ARROW_IMPACT_DURATION + 0.01
		shot = viewer.display_frame()
		check(not shot["arrow"].get("player_shot", false), "Archer retaliation animates second")
		check(shot["enemies"].any(func(e): return e["id"] == "archer" and e["pos"] == shot["arrow"]["from"]), "Archer arrow starts at the attack-time shooter")
		check(not shot["enemies"].any(func(e): return e["id"] == "victim"), "killed victim is absent during retaliation")
		viewer.arrow_elapsed = 2.0 * (viewer.ARROW_FLIGHT_DURATION + viewer.ARROW_IMPACT_DURATION)
		check(not viewer.is_arrow_animating(), "animation ends after all shots")
		check(viewer.display_frame()["enemies"].size() == 1 and viewer.display_frame()["enemies"][0]["pos"]["x"] == 4, "after animation, final Turn state is displayed")
		viewer.set_turn(1)
		check(viewer.is_arrow_animating() and viewer.display_frame()["arrow"].get("player_shot", false), "stepping back to a Turn restarts its shots")
		# A surviving enemy can move later in the same Turn; the arrow must
		# still hit its original tile while the completed snapshot stays current.
		events[1]["details"]["result"] = "enemy_hit"
		events[1]["details"]["enemy_hp_after"] = 1
		events[3]["details"]["observation"]["enemies"].append({"id": "victim", "type": enemy_type, "hp": 1, "pos": {"x": 2, "y": 0}})
		viewer.replay.turns = viewer.replay.build_turns(events)
		viewer.set_turn(1)
		check(viewer.display_frame()["enemies"].any(func(e): return e["id"] == "victim" and e["pos"]["x"] == 3), "moving survivor stays at attack-time position during flight")
		check(viewer.replay.turns[1]["enemies"].any(func(e): return e["id"] == "victim" and e["pos"]["x"] == 2), "final survivor position is preserved separately")
		check(viewer.replay.turns[0]["enemies"][0]["hp"] == 2, "animation does not mutate previous Turns")

func check_reference_arrow_targets() -> void:
	var replay := ReplayData.new()
	var shots_checked := 0
	for path in ["res://../examples/reference-v6/cautious-seed-1.jsonl", "res://../examples/reference-v8/cautious-seed-1.jsonl", "res://../examples/reference-v8/aggressive-seed-424242.jsonl"]:
		check(replay.load_file(path) == OK, "load arrow regression reference")
		for turn in replay.turns:
			for shot in turn["arrow_frames"]:
				shots_checked += 1
				var arrow: Dictionary = shot["arrow"]
				if arrow.get("player_shot", false):
					check(shot["enemies"].any(func(e): return e["id"] == shot["details"]["enemy_id"] and e["pos"] == arrow["to"]), "reference Player arrow points to its visible target")
				else:
					check(shot["enemies"].any(func(e): return e["id"] == shot["details"]["enemy_id"] and e["pos"] == arrow["from"]), "reference Archer arrow begins at its visible shooter")
	check(shots_checked > 0, "real references contain arrow animations")
