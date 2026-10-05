extends SceneTree

const MainGame := preload("res://scripts/main.gd")
const DEFAULT_STRATEGY := "aggressive"
const DEFAULT_SEED := 424242
const DEFAULT_MAX_TURNS := 5000
const DEFAULT_OUTPUT := "user://anarogue-headless.jsonl"
const MAX_SCENARIO_SEED := 4294967295

var strategy_name := DEFAULT_STRATEGY
var scenario_seed := DEFAULT_SEED
var max_turns := DEFAULT_MAX_TURNS
var output_path := DEFAULT_OUTPUT
var should_run := true
var goal_overrides: Dictionary = {}


func _init() -> void:
	call_deferred("run")


func run() -> void:
	var parse_result := parse_arguments(collect_runner_arguments())
	if parse_result != OK:
		quit(parse_result)
		return
	if not should_run:
		quit(0)
		return

	var resolved_output := resolve_output_path(output_path)
	if not ensure_output_directory(resolved_output):
		quit(2)
		return

	var strategy: int = (
		MainGame.StrategyType.CAUTIOUS
		if strategy_name == "cautious"
		else MainGame.StrategyType.AGGRESSIVE
	)
	var game := MainGame.new()
	game.configure_headless(scenario_seed, strategy, resolved_output)
	if not game.configure_goal_policy(goal_overrides):
		printerr("Invalid goal policy: weights 0..1000, at least one positive; temperature 1..100")
		game.free()
		quit(2)
		return
	root.add_child(game)
	if game.log_file == null:
		printerr("Could not open log output: %s" % resolved_output)
		game.free()
		quit(2)
		return
	game.start_automatic_run()

	while not game.game_over and game.turn_count < max_turns:
		game.run_auto_player_turn()

	var outcome: String = game.run_outcome if game.game_over else "turn_limit"
	var summary := {
		"outcome": outcome,
		"scenario_seed": scenario_seed,
		"strategy_id": game.strategy_id(strategy),
		"turns": game.turn_count,
		"depth": game.player["depth"],
		"hp": game.player["hp"],
		"gold": game.player["gold"],
		"score": game.player["score"],
		"potions": game.player["inventory"]["health_potion"],
		"log_file": resolved_output,
	}
	game.close_log_file()
	print("HEADLESS_RUN_SUMMARY=%s" % JSON.stringify(summary))
	game.free()
	quit(0)


func parse_arguments(args: PackedStringArray) -> int:
	var index := 0
	while index < args.size():
		var argument := args[index]
		var inline_value := ""
		var has_inline_value := false
		if "=" in argument:
			var parts := argument.split("=", true, 1)
			argument = parts[0]
			inline_value = parts[1]
			has_inline_value = true
		if argument == "--help":
			print_usage()
			should_run = false
			return OK
		if argument not in ["--strategy", "--seed", "--max-turns", "--output", "--enemy-weight", "--item-weight", "--stairs-weight", "--temperature"]:
			printerr("Unknown argument: %s" % argument)
			print_usage()
			return 2
		if not has_inline_value and index + 1 >= args.size():
			printerr("Missing value for %s" % argument)
			print_usage()
			return 2

		var value := inline_value if has_inline_value else args[index + 1]
		match argument:
			"--enemy-weight", "--item-weight", "--stairs-weight", "--temperature":
				if not value.is_valid_int():
					printerr("%s requires an integer" % argument)
					return 2
				goal_overrides[argument.trim_prefix("--").replace("-", "_")] = value.to_int()
			"--strategy":
				if value not in ["aggressive", "cautious"]:
					printerr("--strategy must be aggressive or cautious")
					return 2
				strategy_name = value
			"--seed":
				if (
					not value.is_valid_int()
					or value.to_int() < 0
					or value.to_int() > MAX_SCENARIO_SEED
				):
					printerr("--seed must be an integer from 0 through %d" % MAX_SCENARIO_SEED)
					return 2
				scenario_seed = value.to_int()
			"--max-turns":
				if not value.is_valid_int() or value.to_int() <= 0:
					printerr("--max-turns must be a positive integer")
					return 2
				max_turns = value.to_int()
			"--output":
				if value.is_empty():
					printerr("--output must not be empty")
					return 2
				output_path = value
		index += 1 if has_inline_value else 2
	return OK


func collect_runner_arguments() -> PackedStringArray:
	var result := PackedStringArray()
	var engine_args := OS.get_cmdline_args()
	var runner_options := ["--strategy", "--seed", "--max-turns", "--output", "--enemy-weight", "--item-weight", "--stairs-weight", "--temperature", "--help"]
	var index := 0
	var found_before_separator := false
	while index < engine_args.size():
		var argument := engine_args[index]
		var option := argument.split("=", true, 1)[0]
		if option in runner_options:
			found_before_separator = true
			result.append(argument)
			if "=" not in argument and option != "--help" and index + 1 < engine_args.size():
				result.append(engine_args[index + 1])
				index += 1
		index += 1

	if found_before_separator:
		push_warning("Runner arguments should follow the standalone -- separator; accepting them for compatibility.")
	result.append_array(OS.get_cmdline_user_args())
	return result


func resolve_output_path(path: String) -> String:
	if path.begins_with("user://") or path.begins_with("res://") or path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path("res://").path_join(path).simplify_path()


func ensure_output_directory(path: String) -> bool:
	var absolute_path := ProjectSettings.globalize_path(path)
	var directory := absolute_path.get_base_dir()
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error == OK or error == ERR_ALREADY_EXISTS:
		return true
	printerr("Could not create output directory %s (error %d)" % [directory, error])
	return false


func print_usage() -> void:
	print(
		"Usage: godot --headless --path game --script res://tools/headless_run.gd -- "
		+ "[--strategy aggressive|cautious] [--seed INTEGER] "
		+ "[--max-turns INTEGER] [--output PATH] [--enemy-weight N] [--item-weight N] [--stairs-weight N] [--temperature N]\n"
		+ "Runner arguments normally belong after the standalone -- separator. "
		+ "Both --output PATH and --output=PATH are accepted."
	)
