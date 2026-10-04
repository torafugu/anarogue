extends SceneTree

const MainGame := preload("res://scripts/main.gd")
const OUTPUT_DIRECTORY := "res://../examples/reference-v5"
const DISPLAY_DIRECTORY := "examples/reference-v5"
const FIXED_EVENT_TIME := "2000-01-01 00:00:00"
const MAP_WIDTH := 24
const MAP_HEIGHT := 18
const CASES := [
	{
		"name": "aggressive-seed-301-cycle",
		"strategy": MainGame.StrategyType.AGGRESSIVE,
		"seed": 301, "map_width": 64, "map_height": 40, "max_turns": 500,
		"expected": {"outcome": "player_defeated", "turns": 164, "final_depth": 2, "final_hp": 0, "final_gold": 10, "final_score": 10, "final_potions": 0, "final_level": 2, "final_xp": 12},
	},
	{
		"name": "cautious-seed-27-cycle",
		"strategy": MainGame.StrategyType.CAUTIOUS,
		"seed": 27, "map_width": 44, "map_height": 28, "max_turns": 500,
		"expected": {"outcome": "dungeon_cleared", "turns": 277, "final_depth": 5, "final_hp": 18, "final_gold": 10, "final_score": 15, "final_potions": 1, "final_level": 2, "final_xp": 1},
	},
	{
		"name": "cautious-seed-2",
		"strategy": MainGame.StrategyType.CAUTIOUS,
		"seed": 2, "map_width": 24, "map_height": 18, "max_turns": 120,
		"expected": {"outcome": "dungeon_cleared", "turns": 102, "final_depth": 5, "final_hp": 16, "final_gold": 4, "final_score": 13, "final_potions": 3, "final_level": 1, "final_xp": 3},
	},
	{
		"name": "aggressive-seed-1",
		"strategy": MainGame.StrategyType.AGGRESSIVE,
		"seed": 1, "map_width": 24, "map_height": 18, "max_turns": 120,
		"expected": {"outcome": "dungeon_cleared", "turns": 103, "final_depth": 5, "final_hp": 17, "final_gold": 10, "final_score": 18, "final_potions": 3, "final_level": 2, "final_xp": 8},
	},
	{
		"name": "cautious-seed-1",
		"strategy": MainGame.StrategyType.CAUTIOUS,
		"seed": 1, "map_width": 24, "map_height": 18, "max_turns": 120,
		"expected": {"outcome": "dungeon_cleared", "turns": 107, "final_depth": 5, "final_hp": 17, "final_gold": 3, "final_score": 14, "final_potions": 3, "final_level": 1, "final_xp": 6},
	},
	{
		"name": "aggressive-seed-424242",
		"strategy": MainGame.StrategyType.AGGRESSIVE,
		"seed": 424242, "map_width": 24, "map_height": 18, "max_turns": 120,
		"expected": {"outcome": "dungeon_cleared", "turns": 113, "final_depth": 5, "final_hp": 19, "final_gold": 7, "final_score": 17, "final_potions": 3, "final_level": 2, "final_xp": 6},
	},
]

func _init() -> void:
	call_deferred("generate")


func generate() -> void:
	var output_directory := ProjectSettings.globalize_path(OUTPUT_DIRECTORY)
	var directory_error := DirAccess.make_dir_recursive_absolute(output_directory)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		printerr("Could not create reference output directory: %s" % output_directory)
		quit(1)
		return

	var manifest_cases: Array[Dictionary] = []
	for test_case in CASES:
		var result := generate_case(test_case)
		if result.is_empty():
			quit(1)
			return
		manifest_cases.append(result)

	var manifest := {
		"format_version": 5,
		"simulation_spec": "v5",
		"randomness_spec": "v1",
		"event_schema": "v5",
		"fixed_event_time": FIXED_EVENT_TIME,
		"map_size": {"width": MAP_WIDTH, "height": MAP_HEIGHT},
		"cases": manifest_cases,
	}
	var manifest_path := OUTPUT_DIRECTORY.path_join("manifest-v5.json")
	var manifest_file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if manifest_file == null:
		printerr("Could not write reference manifest: %s" % manifest_path)
		quit(1)
		return
	manifest_file.store_string(JSON.stringify(manifest, "  ") + "\n")
	manifest_file.close()
	print("Generated %d deterministic reference logs." % CASES.size())
	quit(0)


func generate_case(test_case: Dictionary) -> Dictionary:
	var case_name: String = test_case["name"]
	var output_name := "%s.jsonl" % case_name
	var output_path := OUTPUT_DIRECTORY.path_join(output_name)
	var display_path := DISPLAY_DIRECTORY.path_join(output_name)
	var strategy: int = test_case["strategy"]
	var game := MainGame.new()
	game.configure_headless(test_case["seed"], strategy, output_path)
	var width: int = int(test_case.get("map_width", MAP_WIDTH))
	var height: int = int(test_case.get("map_height", MAP_HEIGHT))
	game.configure_headless_map(width, height)
	game.configure_reference_log(
		"reference-%s" % case_name,
		FIXED_EVENT_TIME,
		display_path
	)
	root.add_child(game)
	if game.log_file == null:
		printerr("Could not open reference log: %s" % output_path)
		game.free()
		return {}
	game.start_automatic_run()

	while not game.game_over and game.turn_count < test_case["max_turns"]:
		game.run_auto_player_turn()

	var outcome: String = game.run_outcome if game.game_over else "turn_limit"
	var result := {
		"name": case_name,
		"file": display_path,
		"run_id": game.run_id,
		"strategy_id": game.strategy_id(strategy),
		"scenario_seed": test_case["seed"],
		"max_turns": test_case["max_turns"],
		"map_width": width,
		"map_height": height,
		"outcome": outcome,
		"turns": game.turn_count,
		"final_depth": game.player["depth"],
		"final_hp": game.player["hp"],
		"final_gold": game.player["gold"],
		"final_score": game.player["score"],
		"final_level": game.player["level"],
		"final_xp": game.player["xp"],
		"final_potions": game.player["inventory"]["health_potion"],
	}
	game.close_log_file()
	game.free()
	for field in test_case["expected"]:
		if result[field] != test_case["expected"][field]:
			printerr(
				"Reference case %s changed: %s expected %s, got %s"
				% [case_name, field, test_case["expected"][field], result[field]]
			)
			return {}
	print("REFERENCE_CASE=%s" % JSON.stringify(result))
	return result
