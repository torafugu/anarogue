extends SceneTree

const MainGame := preload("res://scripts/main.gd")
const PortableRandom := preload("res://scripts/portable_rng.gd")
const FIXTURE_PATH := "res://tests/fixtures/fixed-seed-v1.json"
const CASES := [
	{
		"name": "comparison_seed_depth_1",
		"scenario_seed": 424242,
		"depth": 1,
		"map_width": 24,
		"map_height": 18,
	},
	{
		"name": "comparison_seed_depth_2",
		"scenario_seed": 424242,
		"depth": 2,
		"map_width": 24,
		"map_height": 18,
	},
	{
		"name": "alternate_seed_wide_map",
		"scenario_seed": 20260928,
		"depth": 1,
		"map_width": 30,
		"map_height": 20,
	},
	{
		"name": "portable_seed_with_enemy",
		"scenario_seed": 1,
		"depth": 1,
		"map_width": 24,
		"map_height": 18,
	},
]

var failures: Array[String] = []


func _init() -> void:
	var actual := build_suite_snapshot()
	var repeated := build_suite_snapshot()
	assert_equal(actual, repeated, "A fixed seed must reproduce the same suite")

	if "--write-fixture" in OS.get_cmdline_user_args():
		write_fixture(actual)
		finish()
		return

	if not FileAccess.file_exists(FIXTURE_PATH):
		failures.append("Missing fixture: %s" % FIXTURE_PATH)
		print("FIXED_SEED_SNAPSHOT=%s" % JSON.stringify(actual))
		finish()
		return

	var fixture_file := FileAccess.open(FIXTURE_PATH, FileAccess.READ)
	if fixture_file == null:
		failures.append("Could not read fixture: %s" % FIXTURE_PATH)
		finish()
		return

	var expected_json := fixture_file.get_as_text().strip_edges()
	var actual_json := JSON.stringify(actual)
	assert_equal(actual_json, expected_json, "Generated state must match the v1 fixture")

	finish()


func build_suite_snapshot() -> Dictionary:
	var snapshots: Array[Dictionary] = []
	for test_case in CASES:
		snapshots.append(build_case_snapshot(test_case))
	return {
		"fixture_version": 1,
		"cases": snapshots,
	}


func build_case_snapshot(test_case: Dictionary) -> Dictionary:
	var game = MainGame.new()
	game.scenario_seed = test_case["scenario_seed"]
	game.map_width = test_case["map_width"]
	game.map_height = test_case["map_height"]
	game.player["depth"] = test_case["depth"]
	game.next_enemy_id = 1
	game.map.clear()
	game.rooms.clear()
	game.enemies.clear()

	for y in range(game.map_height):
		var row: Array[int] = []
		for x in range(game.map_width):
			row.append(game.TILE_WALL)
		game.map.append(row)

	var floor_seed: int = game.derived_seed("floor", game.player["depth"])
	var spawn_seed: int = game.derived_seed("spawn", game.player["depth"])
	var floor_rng := PortableRandom.new(floor_seed)
	var spawn_rng := PortableRandom.new(spawn_seed)

	game.generate_dungeon(floor_rng)
	game.player["pos"] = game.rooms[0].get_center()
	game.stairs_pos = game.rooms[game.rooms.size() - 1].get_center()
	game.spawn_enemies(spawn_rng)

	game.active_strategy = MainGame.StrategyType.AGGRESSIVE
	var aggressive_decision: Dictionary = game.choose_auto_player_decision("regression-aggressive")
	game.active_strategy = MainGame.StrategyType.CAUTIOUS
	var cautious_decision: Dictionary = game.choose_auto_player_decision("regression-cautious")

	var snapshot := {
		"name": test_case["name"],
		"scenario_seed": game.scenario_seed,
		"depth": game.player["depth"],
		"map_size": {
			"width": game.map_width,
			"height": game.map_height,
		},
		"floor_seed": floor_seed,
		"spawn_seed": spawn_seed,
		"tiles": map_rows(game),
		"rooms": room_snapshots(game.rooms),
		"player_pos": vector_snapshot(game.player["pos"]),
		"stairs_pos": vector_snapshot(game.stairs_pos),
		"enemies": enemy_snapshots(game),
		"decisions": {
			"aggressive": decision_snapshot(aggressive_decision),
			"cautious": decision_snapshot(cautious_decision),
		},
	}
	game.free()
	return snapshot


func map_rows(game) -> Array[String]:
	var rows: Array[String] = []
	for y in range(game.map_height):
		var row := ""
		for x in range(game.map_width):
			row += "." if game.map[y][x] == game.TILE_FLOOR else "#"
		rows.append(row)
	return rows


func room_snapshots(rooms: Array[Rect2i]) -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for room in rooms:
		snapshots.append({
			"x": room.position.x,
			"y": room.position.y,
			"width": room.size.x,
			"height": room.size.y,
		})
	return snapshots


func enemy_snapshots(game) -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for enemy in game.enemies:
		snapshots.append({
			"id": enemy["id"],
			"type": enemy["type"],
			"pos": vector_snapshot(enemy["pos"]),
			"hp": enemy["hp"],
			"attack": enemy["attack"],
			"gold_reward": game.gold_reward_for_enemy(enemy),
		})
	return snapshots


func decision_snapshot(decision: Dictionary) -> Dictionary:
	var snapshot := {
		"rule_id": decision["rule_id"],
		"action_type": decision["action_type"],
		"direction": vector_snapshot(decision["direction"]),
		"target": decision["target"],
	}
	if decision.has("selected_step_danger"):
		snapshot["selected_step_danger"] = decision["selected_step_danger"]
	return snapshot


func vector_snapshot(value: Vector2i) -> Dictionary:
	return {
		"x": value.x,
		"y": value.y,
	}


func write_fixture(snapshot: Dictionary) -> void:
	var fixture_file := FileAccess.open(FIXTURE_PATH, FileAccess.WRITE)
	if fixture_file == null:
		failures.append("Could not write fixture: %s" % FIXTURE_PATH)
		return
	fixture_file.store_string(JSON.stringify(snapshot) + "\n")
	print("Updated %s" % FIXTURE_PATH)


func assert_equal(actual, expected, message: String) -> void:
	if actual == expected:
		return
	failures.append(message)
	print("EXPECTED=%s" % JSON.stringify(expected))
	print("ACTUAL=%s" % JSON.stringify(actual))


func finish() -> void:
	if failures.is_empty():
		print("Fixed-seed regression tests passed (%d cases)." % CASES.size())
		quit(0)
		return

	for failure in failures:
		printerr("FAIL: %s" % failure)
	quit(1)
