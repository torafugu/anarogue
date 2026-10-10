extends SceneTree

const ReplayData := preload("res://scripts/replay_log.gd")
const REFERENCE_PATH := "res://../examples/reference-v2/aggressive-seed-1.jsonl"
const ARCHER_REFERENCE_PATH := "res://../examples/reference-v2/cautious-seed-1.jsonl"


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
	var archer_replay := ReplayData.new()
	if archer_replay.load_file(ARCHER_REFERENCE_PATH) != OK:
		printerr("FAIL: Could not load Archer reference replay.")
		quit(1)
		return
	var has_ranged_hit := false
	for frame in archer_replay.frames:
		if frame["kind"] == "ranged_hit" and not frame["arrow"].is_empty():
			has_ranged_hit = true
			break
	if not has_ranged_hit:
		printerr("FAIL: Replay must preserve Archer ranged attacks.")
		quit(1)
		return
	check_turns()
	print("Replay log test passed (%d frames)." % replay.frames.size())
	quit(0)


func check_turns() -> void:
	var replay := ReplayData.new()
	var events := [
		{"event": "floor_start", "turn": 0, "depth": 1, "player_state": {"pos": {"x": 0, "y": 0}, "hp": 18}, "details": {"map_rows": ["..."], "enemies": [{"id": "e", "hp": 10, "pos": {"x": 2, "y": 0}}]}},
		{"event": "decision", "turn": 0, "depth": 1, "details": {"action_turn": 1, "action": {"type": "move"}}},
		{"event": "user_action", "turn": 1, "depth": 1, "player_state": {"pos": {"x": 1, "y": 0}, "hp": 18}, "details": {"result": "moved"}},
		{"event": "battle_result", "turn": 1, "depth": 1, "player_state": {"pos": {"x": 1, "y": 0}, "hp": 15}, "details": {"result": "enemy_hit", "enemy_id": "e", "enemy_hp_after": 7}},
		{"event": "decision", "turn": 1, "depth": 1, "player_state": {"pos": {"x": 1, "y": 0}, "hp": 15}, "details": {"action_turn": 2, "observation": {"enemies": [{"id": "e", "hp": 7, "pos": {"x": 1, "y": 1}}]}}},
		{"event": "floor_descend", "turn": 2, "depth": 2, "details": {}},
		{"event": "floor_start", "turn": 2, "depth": 2, "player_state": {"hp": 18}, "details": {"map_rows": ["...."], "enemies": []}},
		{"event": "battle_result", "turn": 3, "depth": 2, "player_state": {"hp": 0}, "details": {"result": "player_defeated"}},
		{"event": "run_end", "turn": 3, "depth": 2, "player_state": {"hp": 0}, "details": {}},
	]
	var turns := replay.build_turns(events)
	assert(turns.size() == 4, "one snapshot per Turn, including initialization")
	assert(turns[0]["log_frames"].size() == 1, "executed decisions leave initialization")
	assert(turns[1]["log_frames"].size() == 3, "decision, movement and melee result share a Turn")
	assert(turns[1]["log_frames"][0]["action_turn"] == 1, "decision attaches to executed Turn")
	assert(turns[1]["player_state"]["pos"]["x"] == 1 and turns[1]["player_state"]["hp"] == 15, "final player state includes movement and damage")
	assert(turns[1]["enemies"][0]["pos"]["y"] == 1, "next decision completes enemy movement state")
	assert(turns[2]["depth"] == 2 and turns[2]["map_rows"] == ["...."], "floor transition displays destination in one Turn")
	assert(turns[2]["log_frames"].size() == 3, "transition preserves decision, descent and floor-start logs")
	assert(turns[3]["kind"] == "terminal" and turns[3]["outcome"] == "player_defeated", "run-end event preserves terminal result")
	var truncated := replay.build_turns(events.slice(0, 5))
	assert(truncated.size() == 2 and truncated[1]["log_frames"].size() == 4, "unexecuted decision stays visible without a phantom Turn")
	var melee := replay.build_turns(events.slice(0, 4))
	assert(melee[1]["enemies"][0]["hp"] == 7, "melee updates HP even without a following decision")
	assert(melee[0]["enemies"][0]["hp"] == 10, "earlier states remain immutable")
	assert(replay.load_file("res://../examples/reference-v8/aggressive-seed-424242.jsonl") == OK)
	assert(replay.turns.size() == 109 and replay.turns.back()["turn"] == 108, "v8 has 108 executed Turns plus initialization")
	var event_count := 0
	for i in range(replay.turns.size()):
		assert(replay.turns[i]["turn"] == i, "no duplicate or skipped Turn in reference")
		event_count += replay.turns[i]["log_frames"].size()
	assert(event_count == replay.events_by_run[replay.selected_run_id].size(), "all recorded events appear exactly once")
