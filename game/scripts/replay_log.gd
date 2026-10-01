class_name ReplayLog
extends RefCounted

var events_by_run: Dictionary = {}
var run_ids: Array[String] = []
var frames: Array[Dictionary] = []
var warnings: Array[String] = []
var selected_run_id := ""
var source_path := ""


func load_file(path: String) -> Error:
	events_by_run.clear()
	run_ids.clear()
	frames.clear()
	warnings.clear()
	selected_run_id = ""
	source_path = path

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()

	var line_number := 0
	while not file.eof_reached():
		var line := file.get_line()
		line_number += 1
		if line.strip_edges().is_empty():
			continue
		var value = JSON.parse_string(line)
		if typeof(value) != TYPE_DICTIONARY:
			warnings.append("Line %d is not a JSON object." % line_number)
			continue
		var event: Dictionary = value
		var run_id: String = str(event.get("run_id", ""))
		if run_id.is_empty():
			warnings.append("Line %d has no run_id." % line_number)
			continue
		if not events_by_run.has(run_id):
			events_by_run[run_id] = []
			run_ids.append(run_id)
		var run_events: Array = events_by_run[run_id]
		run_events.append(event)
		events_by_run[run_id] = run_events
	file.close()

	if run_ids.is_empty():
		return ERR_FILE_CORRUPT
	select_run(run_ids.back())
	return OK


func select_run(run_id: String) -> bool:
	if not events_by_run.has(run_id):
		return false
	selected_run_id = run_id
	frames = build_frames(events_by_run[run_id])
	return not frames.is_empty()


func build_frames(events: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var floors: Dictionary = {}
	var last_enemies: Array = []
	var last_stairs := {"x": 0, "y": 0}

	for event_value in events:
		if typeof(event_value) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = event_value
		var event_name: String = str(event.get("event", ""))
		var depth: int = int(event.get("depth", 1))
		var details: Dictionary = event.get("details", {})
		if event_name == "floor_start":
			var map_rows: Array = details.get("map_rows", [])
			if map_rows.is_empty():
				warnings.append(
					"Run %s depth %d has no map_rows; use a schema v2 log for terrain replay."
					% [selected_run_id, depth]
				)
			floors[depth] = map_rows.duplicate()
			last_enemies = details.get("enemies", []).duplicate(true)
			last_stairs = details.get("stairs_pos", last_stairs).duplicate(true)
			result.append(make_frame(event, floors, last_enemies, last_stairs, "floor_start"))
		elif event_name == "decision":
			var observation: Dictionary = details.get("observation", {})
			last_enemies = observation.get("enemies", last_enemies).duplicate(true)
			last_stairs = observation.get("stairs_pos", last_stairs).duplicate(true)
			result.append(make_frame(event, floors, last_enemies, last_stairs, "decision"))
		elif (
			event_name == "battle_result"
			and details.get("result", "") == "player_hit"
			and details.get("ranged", false)
		):
			var ranged_frame := make_frame(
				event, floors, last_enemies, last_stairs, "ranged_hit"
			)
			var player_state: Dictionary = event.get("player_state", {})
			ranged_frame["arrow"] = {
				"from": details.get("enemy_pos", {}).duplicate(true),
				"to": player_state.get("pos", {}).duplicate(true),
			}
			result.append(ranged_frame)
		elif (
			event_name == "battle_result"
			and details.get("result", "") in ["player_defeated", "dungeon_cleared"]
		):
			result.append(make_frame(event, floors, last_enemies, last_stairs, "terminal"))
	return result


func make_frame(
	event: Dictionary,
	floors: Dictionary,
	enemies: Array,
	stairs: Dictionary,
	kind: String
) -> Dictionary:
	var depth: int = int(event.get("depth", 1))
	var details: Dictionary = event.get("details", {})
	var map_rows: Array = floors.get(depth, [])
	if map_rows.is_empty():
		var nearest_depth := -1
		for floor_depth in floors:
			if int(floor_depth) <= depth and int(floor_depth) > nearest_depth:
				nearest_depth = int(floor_depth)
		if nearest_depth != -1:
			map_rows = floors[nearest_depth]
	return {
		"kind": kind,
		"sequence": int(event.get("sequence", 0)),
		"turn": int(event.get("turn", 0)),
		"depth": depth,
		"strategy_id": str(event.get("strategy_id", "unknown")),
		"player_state": event.get("player_state", {}).duplicate(true),
		"enemies": enemies.duplicate(true),
		"stairs_pos": stairs.duplicate(true),
		"map_rows": map_rows.duplicate(),
		"rule_id": str(details.get("rule_id", "")),
		"reason": str(details.get("reason", "")),
		"arrow": {},
	}
