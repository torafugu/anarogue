extends SceneTree

const ReplayData := preload("res://scripts/replay_log.gd")
const REFERENCE_PATH := "res://../examples/reference/aggressive-seed-1.jsonl"


func _init() -> void:
	var replay := ReplayData.new()
	var error := replay.load_file(REFERENCE_PATH)
	if error != OK:
		printerr("FAIL: Could not load reference replay (error %d)." % error)
		quit(1)
		return
	if replay.run_ids.size() != 1:
		printerr("FAIL: Expected one run, got %d." % replay.run_ids.size())
		quit(1)
		return
	if replay.frames.is_empty():
		printerr("FAIL: Replay produced no frames.")
		quit(1)
		return
	var first: Dictionary = replay.frames[0]
	var rows: Array = first["map_rows"]
	if rows.size() != 18 or str(rows[0]).length() != 24:
		printerr("FAIL: Replay map must be 24x18.")
		quit(1)
		return
	if first["kind"] != "floor_start" or first["depth"] != 1:
		printerr("FAIL: First replay frame must start depth 1.")
		quit(1)
		return
	var has_decision := false
	for frame in replay.frames:
		if frame["kind"] == "decision":
			has_decision = true
			break
	if not has_decision:
		printerr("FAIL: Replay must include decision frames.")
		quit(1)
		return
	print("Replay log test passed (%d frames)." % replay.frames.size())
	quit(0)
