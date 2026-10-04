extends SceneTree

const MainGame := preload("res://scripts/main.gd")
const ReplayData := preload("res://scripts/replay_log.gd")
var failures: Array[String] = []

func _init() -> void:
	run_tests.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func run_tests() -> void:
	var game := MainGame.new()
	game.configure_headless(1, MainGame.StrategyType.CAUTIOUS, "/tmp/anarogue-growth-test.jsonl")
	game.configure_headless_map(24, 18)
	root.add_child(game)
	game.items.clear()
	game.navigation_visits.clear()
	for row in game.map:
		row.fill(game.TILE_FLOOR)
	game.player["pos"] = Vector2i(2, 2)
	game.stairs_pos = Vector2i(20, 15)
	game.enemies.assign([{"id": "growth", "type": "melee", "pos": Vector2i(4, 2), "hp": 5, "attack": 1, "defense": 0}])
	check(game.choose_cautious_decision("far")["rule_id"] == "descend_for_progress", "Cautious skips XP that cannot level up")
	game.player["xp"] = 5
	var decision := game.choose_cautious_decision("near")
	check(decision["rule_id"] == "hunt_for_growth", "Cautious takes a safe level-up fight")
	check(decision["progression"]["candidates"][0]["levels_gained"] == 1, "level threshold is evaluated")
	game.player["level"] = 2
	check(game.choose_cautious_decision("higher")["rule_id"] == "descend_for_progress", "threshold increases with current level")
	game.player["level"] = 1
	game.player["depth"] = 4
	check(game.choose_cautious_decision("finish")["rule_id"] == "descend_for_progress", "completion outweighs late growth")
	game.player["depth"] = 1
	game.player["hp"] = 5
	decision = game.choose_cautious_decision("weak")
	check(decision["progression"]["candidates"][0]["rejection"] == "hp_reserve", "growth never borrows future level-up healing for safety")
	game.player["hp"] = 18
	game.enemies[0]["hp"] = 10
	game.enemies[0]["attack"] = 5
	check(game.choose_cautious_decision("unarmored")["rule_id"] == "descend_for_progress", "costly combat is skipped")
	game.player["equipment"]["armor"] = {"id": "armor", "type": "armor", "attack_bonus": 0, "defense_bonus": 4}
	decision = game.choose_cautious_decision("armored")
	check(decision["rule_id"] == "hunt_for_growth", "armor changes the growth decision")
	check(decision["progression"]["candidates"][0]["estimated_damage"] == 2, "approach and retaliation both use effective defense")
	game.enemies[0]["defense"] = 4
	check(game.choose_cautious_decision("defended")["rule_id"] == "descend_for_progress", "enemy defense increases the cost")
	game.enemies[0]["defense"] = 0
	game.enemies[0]["type"] = "archer"
	check(game.choose_cautious_decision("mobile")["progression"]["candidates"][0]["rejection"] == "mobile_target", "Cautious does not chase retreating Archers for growth")
	game.enemies[0]["type"] = "melee"
	game.enemies[0]["hp"] = 5
	game.enemies[0]["attack"] = 1
	game.player["xp"] = 0
	game.active_strategy = MainGame.StrategyType.AGGRESSIVE
	check(game.choose_aggressive_decision("aggressive")["rule_id"] == "hunt_for_growth", "Aggressive values partial XP progress")
	game.navigation_visits[Vector2i(3, 2)] = 10
	check(game.choose_aggressive_decision("repeated")["rule_id"] == "descend_for_progress", "revisits discourage repeating growth detours")
	game.navigation_visits.clear()
	# A fight cannot be planned through the stairs or another enemy.
	for row in game.map:
		row.fill(game.TILE_WALL)
	for x in range(2, 6):
		game.map[2][x] = game.TILE_FLOOR
	game.stairs_pos = Vector2i(3, 2)
	check(game.progression_route(Vector2i(4, 2), 12).is_empty(), "stairs cannot be crossed to chase an enemy")
	game.map[2][3] = game.TILE_WALL
	check(game.choose_progression_decision("blocked").is_empty(), "blocked stairs keep the existing fallback")
	# Log the actual comparison and carry it into replay frames.
	for row in game.map:
		row.fill(game.TILE_FLOOR)
	game.stairs_pos = Vector2i(20, 15)
	game.player["xp"] = 5
	game.run_auto_player_turn()
	check(game.growth_target_id == "growth", "executing a growth decision records the target")
	game.close_log_file()
	var replay := ReplayData.new()
	check(replay.load_file("/tmp/anarogue-growth-test.jsonl") == OK, "growth log replays")
	var found := false
	for frame in replay.frames:
		if frame["rule_id"] == "hunt_for_growth":
			found = frame["progression"]["selected"] == "combat"
	check(found, "replay preserves growth comparison")
	game.new_floor()
	check(game.growth_target_id.is_empty(), "floor changes clear growth target")
	game.close_log_file()
	game.free()
	if failures.is_empty():
		print("Growth decision tests passed.")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)
