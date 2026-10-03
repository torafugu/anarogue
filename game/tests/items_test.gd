extends SceneTree

const MainGame := preload("res://scripts/main.gd")
const ReplayData := preload("res://scripts/replay_log.gd")

var failures: Array[String] = []

func _init() -> void:
	call_deferred("run_tests")

func run_tests() -> void:
	test_pickup_and_capacity()
	test_healing_turn_and_policy()
	test_deterministic_spawns()
	test_item_replay()
	if failures.is_empty():
		print("Item tests passed: pickup, capacity, persistence, healing, policies, determinism and replay.")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: %s" % failure)
		quit(1)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func game_for_test():
	var game := MainGame.new()
	game.configure_headless(1, MainGame.StrategyType.AGGRESSIVE, "/tmp/anarogue-items-test.jsonl")
	game.configure_headless_map(24, 18)
	root.add_child(game)
	game.enemies.clear()
	game.items.clear()
	for y in range(game.map_height):
		for x in range(game.map_width):
			game.map[y][x] = game.TILE_FLOOR
	game.player["pos"] = Vector2i(2, 2)
	game.stairs_pos = Vector2i(20, 15)
	return game

func test_pickup_and_capacity() -> void:
	var game = game_for_test()
	var pos := Vector2i(3, 2)
	game.items.append({"id": "potion", "type": "health_potion", "pos": pos})
	game.player_act(Vector2i.RIGHT, "pickup")
	check(game.turn_count == 1, "pickup adds no extra turn")
	check(game.items.is_empty() and game.player["inventory"]["health_potion"] == 1, "pickup transfers item into inventory")
	game.player["inventory"]["health_potion"] = 3
	game.items.append({"id": "overflow", "type": "health_potion", "pos": pos})
	game.pick_up_items("full")
	check(game.items.size() == 1, "full inventory leaves item on floor")
	game.player["depth"] += 1
	game.new_floor()
	check(game.player["inventory"]["health_potion"] == 3, "inventory persists across floors")
	game.restart_game(true)
	check(game.player["inventory"]["health_potion"] == 0, "restart clears inventory")
	game.close_log_file()
	game.free()

func test_healing_turn_and_policy() -> void:
	var game = game_for_test()
	game.player["inventory"]["health_potion"] = 2
	game.use_health_potion("full-hp")
	check(game.turn_count == 0 and game.player["inventory"]["health_potion"] == 2, "full HP use consumes nothing")
	game.player["hp"] = 15
	game.enemies.append({"id": "attacker", "type": "melee", "pos": Vector2i(3, 2), "hp": 10, "attack": 3})
	game.use_health_potion("heal")
	check(game.turn_count == 1 and game.player["hp"] == 15, "heal is capped then enemy attacks: 15 -> 18 -> 15")
	check(game.player["inventory"]["health_potion"] == 1, "use removes one potion")
	game.player["inventory"]["health_potion"] = 0
	game.use_health_potion("empty")
	check(game.turn_count == 1, "empty inventory use consumes nothing")
	game.enemies.clear()
	game.items.append({"id": "safe", "type": "health_potion", "pos": Vector2i(3, 2)})
	game.player["hp"] = game.player["max_hp"]
	game.active_strategy = MainGame.StrategyType.CAUTIOUS
	check(game.choose_item_decision("safe").get("rule_id") == "cautious_collect_potion", "cautious collects nearby safe potion")
	game.enemies.append({"id": "guard", "type": "melee", "pos": Vector2i(5, 2), "hp": 10, "attack": 3})
	check(game.choose_item_decision("guard").is_empty(), "cautious rejects dangerous target even from safe start")
	game.active_strategy = MainGame.StrategyType.AGGRESSIVE
	check(game.choose_item_decision("gather").get("rule_id") == "collect_nearby_potion", "aggressive accepts threatened target")
	game.stairs_pos = Vector2i(3, 2)
	check(game.choose_item_decision("stairs").is_empty(), "item detour cannot use stairs")
	game.stairs_pos = Vector2i(20, 15)
	game.player["inventory"]["health_potion"] = 1
	game.player["hp"] = 9
	check(game.choose_item_decision("low").get("action_type") == "use_item", "healing takes priority")
	game.game_over = true
	game.use_health_potion("dead")
	check(game.turn_count == 1, "cannot use items after game ends")
	game.close_log_file()
	game.free()

func test_deterministic_spawns() -> void:
	var game = game_for_test()
	var baseline_file := FileAccess.open("res://tests/fixtures/fixed-seed-v2.json", FileAccess.READ)
	var baseline: Dictionary = JSON.parse_string(baseline_file.get_as_text())
	baseline_file.close()
	for old in baseline["cases"]:
		game.scenario_seed = old["scenario_seed"]
		game.configure_headless_map(old["map_size"]["width"], old["map_size"]["height"])
		game.player["depth"] = int(old["depth"])
		game.next_enemy_id = 1
		game.new_floor()
		check(game.map_rows_to_log() == old["tiles"], "item stream preserves v2 terrain")
		for index in range(game.enemies.size()):
			check(game.enemies[index]["id"] == old["enemies"][index]["id"], "item stream preserves enemy IDs")
			check(game.enemies[index]["pos"] == Vector2i(int(old["enemies"][index]["pos"]["x"]), int(old["enemies"][index]["pos"]["y"])), "item stream preserves enemy positions")
		var first := game.items_to_log()
		game.active_strategy = MainGame.StrategyType.CAUTIOUS
		game.next_enemy_id = 1
		game.new_floor()
		check(first == game.items_to_log(), "items reproduce across strategies")
		check(not game.items.is_empty(), "each playable floor contains a potion")
		for item in game.items:
			check(game.is_walkable(item["pos"]) and game.enemy_at(item["pos"]) == -1, "items spawn on free floor tiles")
			check(item["pos"] != game.player["pos"] and item["pos"] != game.stairs_pos, "items avoid start and stairs")
	game.close_log_file()
	game.free()

func test_item_replay() -> void:
	var replay := ReplayData.new()
	check(replay.load_file("res://../examples/reference-v3/aggressive-seed-1.jsonl") == OK, "v3 replay loads")
	var saw_pickup := false
	var saw_use := false
	for frame in replay.frames:
		if frame["kind"] != "item_result":
			continue
		if frame["reason"] == "Picked up a health potion.":
			saw_pickup = true
			var player_pos: Dictionary = frame["player_state"]["pos"]
			for item in frame["items"]:
				check(item["pos"] != player_pos, "picked-up potion disappears immediately")
		else:
			saw_use = true
	check(saw_pickup and saw_use, "replay includes both pickup and healing frames")
	check(replay.frames[0]["items"].size() > 0, "later pickup does not mutate first frame")
	check(replay.load_file("res://../examples/reference-v2/aggressive-seed-1.jsonl") == OK, "old v2 replay remains supported")
	check(replay.frames[0]["items"].is_empty(), "old replay defaults to no items")
