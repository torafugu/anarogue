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
	for file_name in ["aggressive-seed-1.jsonl", "cautious-seed-1.jsonl"]:
		viewer.load_replay("res://../examples/reference-v2/" + file_name)
		check(not viewer.result_popup.visible, "popup hidden at replay start")
		viewer.set_frame(viewer.replay.frames.size() - 1)
		check(viewer.replay.frames.back()["outcome"] == "player_defeated", "defeat outcome preserved")
		check(viewer.result_popup.visible, "defeat popup visible for " + file_name)
		check(viewer.result_title.text == "Game Over", "defeat title is Game Over")
		check(not viewer.playing, "playback stops at terminal frame")
		viewer.previous_frame()
		check(not viewer.result_popup.visible, "stepping back hides popup")
		viewer.next_frame()
		check(viewer.result_popup.visible, "returning to defeat shows popup")
		viewer.toggle_playing()
		check(not viewer.result_popup.visible, "replaying hides popup")
		viewer.playing = false

	viewer.load_replay("res://../examples/reference-v5/aggressive-seed-424242.jsonl")
	var growth_frame := -1
	for index in range(viewer.replay.frames.size()):
		if viewer.replay.frames[index]["rule_id"] == "hunt_for_growth":
			growth_frame = index
			break
	check(growth_frame >= 0, "v5 reference contains a growth decision")
	if growth_frame >= 0:
		viewer.set_frame(growth_frame)
		var player: Dictionary = viewer.replay.frames[growth_frame]["player_state"]
		check(viewer.status_label.text.contains("Lv %d" % player["level"]), "growth replay shows current level")
		check(viewer.status_label.text.contains("XP %d/%d" % [player["xp"], player["level"] * 8]), "growth replay shows current XP threshold")
		check(viewer.status_label.text.contains("Growth ") and viewer.status_label.text.contains("vs stairs"), "growth replay renders the comparison")

	viewer.load_replay("res://../examples/reference-v6/cautious-seed-1.jsonl")
	var shot_frame := -1
	for index in range(viewer.replay.frames.size()):
		if viewer.replay.frames[index]["kind"] == "player_ranged_hit":
			shot_frame = index
			break
	check(shot_frame >= 0, "v6 reference contains a Player bow shot")
	if shot_frame >= 0:
		viewer.set_frame(shot_frame)
		check(viewer.status_label.text.contains("Player bow shot"), "replay labels Player arrows")
		check(viewer.status_label.text.contains("bow range 5"), "replay shows bow kind and range")

	# Completion may have no new floor_start event at the deepest floor.
	var replay := ReplayData.new()
	viewer.replay.frames = replay.build_frames([
		{"event": "floor_start", "depth": 4, "details": {"map_rows": ["..."]}},
		{"event": "battle_result", "depth": 5, "player_state": {"level": 3, "score": 12},
			"details": {"result": "dungeon_cleared"}},
	])
	viewer.set_frame(1)
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

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append("FAIL: " + message)
