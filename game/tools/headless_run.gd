extends SceneTree

const MainGame := preload("res://scripts/main.gd")
const DEFAULT_STRATEGY := "aggressive"
const DEFAULT_SEED := 424242
const DEFAULT_MAX_TURNS := 5000
const DEFAULT_OUTPUT := "user://anarogue-headless.jsonl"

var strategy_name := DEFAULT_STRATEGY
var scenario_seed := DEFAULT_SEED
var max_turns := DEFAULT_MAX_TURNS
var output_path := DEFAULT_OUTPUT
var should_run := true


func _init() -> void:
	call_deferred("run")


func run() -> void:
	var parse_result := parse_arguments(OS.get_cmdline_user_args())
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
	root.add_child(game)
	if game.log_file == null:
		printerr("Could not open log output: %s" % resolved_output)
		game.free()
		quit(2)
		return
	game.start_automatic_run()

	while not game.game_over and game.turn_count < max_turns:
		game.run_auto_player_turn()

	var outcome := "player_defeated" if game.game_over else "turn_limit"
	var summary := {
		"outcome": outcome,
		"scenario_seed": scenario_seed,
		"strategy_id": game.strategy_id(strategy),
		"turns": game.turn_count,
		"depth": game.player["depth"],
		"hp": game.player["hp"],
		"gold": game.player["gold"],
		"score": game.player["score"],
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
		if argument == "--help":
			print_usage()
			should_run = false
			return OK
		if argument not in ["--strategy", "--seed", "--max-turns", "--output"]:
			printerr("Unknown argument: %s" % argument)
			print_usage()
			return 2
		if index + 1 >= args.size():
			printerr("Missing value for %s" % argument)
			print_usage()
			return 2

		var value := args[index + 1]
		match argument:
			"--strategy":
				if value not in ["aggressive", "cautious"]:
					printerr("--strategy must be aggressive or cautious")
					return 2
				strategy_name = value
			"--seed":
				if not value.is_valid_int():
					printerr("--seed must be an integer")
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
		index += 2
	return OK


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
		+ "[--max-turns INTEGER] [--output PATH]"
	)
