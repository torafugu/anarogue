extends SceneTree

const MainGame := preload("res://scripts/main.gd")
const OUTPUT_DIRECTORY := "res://../examples/reference"
const DISPLAY_DIRECTORY := "examples/reference"
const FIXED_EVENT_TIME := "2000-01-01 00:00:00"
const MAP_WIDTH := 24
const MAP_HEIGHT := 18
const CASES := [
	{
		"name": "aggressive-seed-1",
		"strategy": MainGame.StrategyType.AGGRESSIVE,
		"seed": 1,
		"max_turns": 120,
		"expected": {
			"outcome": "turn_limit", "turns": 120, "final_depth": 5,
			"final_hp": 18, "final_gold": 4, "final_score": 14,
		},
	},
	{
		"name": "cautious-seed-1",
		"strategy": MainGame.StrategyType.CAUTIOUS,
		"seed": 1,
		"max_turns": 120,
		"expected": {
			"outcome": "player_defeated", "turns": 19, "final_depth": 1,
			"final_hp": 0, "final_gold": 0, "final_score": 0,
		},
	},
	{
		"name": "aggressive-seed-424242",
		"strategy": MainGame.StrategyType.AGGRESSIVE,
		"seed": 424242,
		"max_turns": 120,
		"expected": {
			"outcome": "player_defeated", "turns": 70, "final_depth": 6,
			"final_hp": 0, "final_gold": 0, "final_score": 15,
		},
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
		"format_version": 1,
		"simulation_spec": "v1",
		"randomness_spec": "v1",
		"event_schema": "v1",
		"fixed_event_time": FIXED_EVENT_TIME,
		"map_size": {"width": MAP_WIDTH, "height": MAP_HEIGHT},
		"cases": manifest_cases,
	}
	var manifest_path := OUTPUT_DIRECTORY.path_join("manifest-v1.json")
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
	game.configure_headless_map(MAP_WIDTH, MAP_HEIGHT)
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

	var outcome := "player_defeated" if game.game_over else "turn_limit"
	var result := {
		"name": case_name,
		"file": display_path,
		"run_id": game.run_id,
		"strategy_id": game.strategy_id(strategy),
		"scenario_seed": test_case["seed"],
		"max_turns": test_case["max_turns"],
		"outcome": outcome,
		"turns": game.turn_count,
		"final_depth": game.player["depth"],
		"final_hp": game.player["hp"],
		"final_gold": game.player["gold"],
		"final_score": game.player["score"],
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
