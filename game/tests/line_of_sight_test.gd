extends SceneTree

const MainGame := preload("res://scripts/main.gd")
var failures: Array[String] = []

func _init() -> void:
	call_deferred("run_tests")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func run_tests() -> void:
	var game := MainGame.new()
	game.configure_headless(1, MainGame.StrategyType.CAUTIOUS, "/tmp/anarogue-line-of-sight-test.jsonl")
	game.configure_headless_map(24, 18)
	root.add_child(game)
	game.items.clear()
	game.enemies.clear()
	for y in range(18):
		for x in range(24):
			game.map[y][x] = game.TILE_FLOOR
	var origin := Vector2i(2, 2)
	for target in [Vector2i(8, 2), Vector2i(2, 8), Vector2i(8, 5), Vector2i(5, 8), Vector2i(6, 6)]:
		check(game.has_line_of_sight(origin, target) and game.has_line_of_sight(target, origin), "open rays are symmetric")
	game.map[2][5] = game.TILE_WALL
	check(not game.has_line_of_sight(origin, Vector2i(8, 2)) and not game.has_line_of_sight(Vector2i(8, 2), origin), "horizontal wall blocks both directions")
	game.map[2][5] = game.TILE_FLOOR
	check(game.has_line_of_sight(origin, Vector2i(8, 2)), "open doorway restores sight")
	for wall in [Vector2i(3, 2), Vector2i(2, 3), Vector2i(3, 3)]:
		game.map[wall.y][wall.x] = game.TILE_WALL
		check(not game.has_line_of_sight(origin, Vector2i(6, 6)) and not game.has_line_of_sight(Vector2i(6, 6), origin), "diagonal walls and either corner side block sight")
		game.map[wall.y][wall.x] = game.TILE_FLOOR
	game.map[3][4] = game.TILE_WALL
	check(not game.has_line_of_sight(origin, Vector2i(8, 5)) and not game.has_line_of_sight(Vector2i(8, 5), origin), "shallow ray detects crossed wall")
	game.map[3][4] = game.TILE_FLOOR
	check(game.has_line_of_sight(origin, origin), "same floor tile is visible")
	check(not game.has_line_of_sight(origin, Vector2i(-1, 2)), "out-of-map target is blocked")
	game.player["pos"] = origin
	game.player["hp"] = 14
	game.player["inventory"]["health_potion"] = 1
	var archer := {"id": "covered-archer", "type": "archer", "pos": Vector2i(6, 2), "hp": 6, "attack": 14}
	game.enemies.append(archer)
	game.map[2][4] = game.TILE_WALL
	game.headless_mode = false
	game.run_archer_turn(0, archer, archer["pos"])
	check(game.player["hp"] == 14 and game.arrows.is_empty(), "cover prevents damage and arrow creation")
	check(game.danger_cost(origin) == 0, "covered Archer contributes no danger")
	check(game.choose_item_decision("covered").is_empty(), "covered lethal shot does not trigger emergency healing")
	game.map[2][4] = game.TILE_FLOOR
	check(game.danger_cost(origin) == 12, "visible Archer contributes ranged danger")
	check(game.choose_item_decision("visible")["rule_id"] == "use_health_potion", "visible lethal shot triggers emergency healing")
	archer["attack"] = 2
	game.run_archer_turn(0, archer, archer["pos"])
	check(game.player["hp"] == 12 and game.arrows.size() == 1, "clear in-range ray produces one damaging arrow")
	archer["pos"] = Vector2i(10, 2)
	game.run_archer_turn(0, archer, archer["pos"])
	check(game.player["hp"] == 12 and game.enemies[0]["pos"] != Vector2i(10, 2), "visible out-of-range Archer approaches without shooting")
	archer["pos"] = Vector2i(3, 3)
	game.map[2][3] = game.TILE_WALL
	game.run_archer_turn(0, archer, archer["pos"])
	check(game.player["hp"] == 12 and archer["pos"] == Vector2i(3, 3), "blocked diagonal corner prevents close combat")
	game.close_log_file()
	game.free()
	if failures.is_empty():
		print("Line-of-sight tests passed: walls, corners, open rays, range, damage, arrows and healing policy.")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: %s" % failure)
		quit(1)
