extends SceneTree

const MainGame := preload("res://scripts/main.gd")
var failures: Array[String] = []

func _init() -> void:
	call_deferred("run_tests")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func run_tests() -> void:
	test_soft_penalty_and_reset()
	test_seed_27_oscillation()
	if failures.is_empty():
		print("Navigation tests passed: revisits, required backtracking, history reset and seed-27 pursuit cycle.")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: %s" % failure)
		quit(1)

func create_game(seed_value: int, width: int, height: int):
	var game := MainGame.new()
	game.configure_headless(seed_value, MainGame.StrategyType.CAUTIOUS, "/tmp/anarogue-navigation-test.jsonl")
	game.configure_headless_map(width, height)
	root.add_child(game)
	return game

func test_soft_penalty_and_reset() -> void:
	var game = create_game(1, 24, 18)
	game.enemies.clear()
	game.items.clear()
	game.navigation_visits.clear()
	for y in range(18):
		for x in range(24):
			game.map[y][x] = game.TILE_FLOOR
	game.player["pos"] = Vector2i(2, 2)
	game.stairs_pos = Vector2i(20, 15)
	var repeated := Vector2i(3, 2)
	var destination := Vector2i(6, 2)
	game.navigation_visits[repeated] = 2
	check(game.revisit_cost(repeated) == 0, "a single return is not penalized")
	check(game.find_low_risk_step_toward(destination) == Vector2i.RIGHT, "normal shortest route is retained")
	game.navigation_visits[repeated] = 3
	check(game.revisit_cost(repeated) == 8, "third visit gains a penalty")
	check(game.find_low_risk_step_toward(destination) == Vector2i.UP, "cautious chooses an unvisited detour")
	check(game.find_next_step_toward(destination) == Vector2i.UP, "aggressive pathfinding also avoids repeated tiles")
	for y in range(18):
		for x in range(24):
			game.map[y][x] = game.TILE_WALL
	for x in range(2, 7):
		game.map[2][x] = game.TILE_FLOOR
	check(game.find_low_risk_step_toward(destination) == Vector2i.RIGHT, "required backtracking remains possible")
	game.navigation_visits.clear()
	game.navigation_visits[Vector2i(2, 2)] = 1
	game.player_act(Vector2i.RIGHT)
	game.player_act(Vector2i.LEFT)
	check(game.navigation_visits[Vector2i(2, 2)] == 2, "successful movement records visits")
	game.player_act(Vector2i.RIGHT)
	game.player_act(Vector2i.LEFT)
	check(game.navigation_visits[Vector2i(2, 2)] == 3, "repeated movement is counted")
	game.player["inventory"]["health_potion"] = 1
	game.player["hp"] = 9
	game.use_health_potion()
	game.player_act(Vector2i.UP)
	check(game.navigation_visits.size() == 2 and game.navigation_visits[Vector2i(2, 2)] == 3, "healing and blocked moves do not count as visits")
	game.new_floor()
	check(game.navigation_visits.size() == 1 and game.navigation_visits[game.player["pos"]] == 1, "new floor resets history")
	game.close_log_file()
	game.free()

func test_seed_27_oscillation() -> void:
	var game = create_game(27, 44, 28)
	game.start_automatic_run()
	var positions: Array[Vector2i] = []
	var alternating := 0
	var longest := 0
	var observed_revisit := false
	while not game.game_over and game.turn_count < 500:
		var position: Vector2i = game.player["pos"]
		positions.append(position)
		if int(game.navigation_visits.get(position, 0)) >= 3:
			observed_revisit = true
		var index := positions.size() - 1
		if index >= 2 and positions[index] == positions[index - 2] and positions[index] != positions[index - 1]:
			alternating += 1
		else:
			alternating = 0
		longest = maxi(longest, alternating + 2)
		game.run_auto_player_turn()
	check(game.game_over, "seed 27 no longer spends its entire turn budget oscillating")
	check(longest < 12 and observed_revisit, "pursuit cycle breaks after repeat penalties activate")
	check(game.turn_count == 134, "seed-27 regression remains deterministic")
	game.close_log_file()
	game.free()
