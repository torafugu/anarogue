extends SceneTree

const MainGame := preload("res://scripts/main.gd")

var failures: Array[String] = []


func _init() -> void:
	test_every_playable_floor_has_an_enemy()
	test_reaching_depth_five_clears_the_dungeon()
	if failures.is_empty():
		print("Simulation v2 tests passed.")
		quit(0)
	else:
		for failure in failures:
			printerr(failure)
		quit(1)


func test_every_playable_floor_has_an_enemy() -> void:
	for seed in [1, 424242]:
		var game = MainGame.new()
		game.configure_headless(seed, MainGame.StrategyType.AGGRESSIVE, "/tmp/anarogue-simulation-v2-test.jsonl")
		game.configure_headless_map(24, 18)
		root.add_child(game)
		for depth in range(1, MainGame.MAX_DEPTH):
			game.player["depth"] = depth
			game.new_floor()
			assert_true(not game.enemies.is_empty(), "seed %d depth %d has an enemy" % [seed, depth])
			assert_true(game.player["pos"] != game.stairs_pos, "seed %d depth %d separates stairs" % [seed, depth])
		game.close_log_file()
		game.free()


func test_reaching_depth_five_clears_the_dungeon() -> void:
	var game = MainGame.new()
	game.configure_headless(1, MainGame.StrategyType.AGGRESSIVE, "/tmp/anarogue-simulation-v2-terminal.jsonl")
	game.configure_headless_map(24, 18)
	root.add_child(game)
	game.player["depth"] = MainGame.MAX_DEPTH - 1
	game.new_floor()
	game.enemies.clear()
	var direction := adjacent_walkable_direction(game, game.stairs_pos)
	assert_true(direction != Vector2i.ZERO, "final stairs have an adjacent walkable tile")
	if direction == Vector2i.ZERO:
		game.close_log_file()
		game.free()
		return
	game.player["pos"] = game.stairs_pos - direction
	game.player_act(direction)
	assert_true(game.game_over, "reaching depth five ends the run")
	assert_true(game.run_outcome == "dungeon_cleared", "the terminal outcome is dungeon_cleared")
	assert_true(game.player["depth"] == MainGame.MAX_DEPTH, "the final depth is five")
	game.close_log_file()
	game.free()


func adjacent_walkable_direction(game, destination: Vector2i) -> Vector2i:
	for direction in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		if game.is_walkable(destination - direction):
			return direction
	return Vector2i.ZERO


func assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append("Assertion failed: %s" % message)
