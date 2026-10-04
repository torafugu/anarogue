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
	game.configure_headless(27, MainGame.StrategyType.CAUTIOUS, "/tmp/anarogue-brute-test.jsonl")
	game.configure_headless_map(44, 28)
	root.add_child(game)
	check(game.enemies.any(func(e): return e["type"] == "brute"), "fixed seed spawns Brute")
	game.items.clear()
	game.enemies.clear()
	for row in game.map:
		row.fill(game.TILE_FLOOR)
	game.player["pos"] = Vector2i(2, 2)
	game.stairs_pos = Vector2i(20, 15)
	var brute := {"id": "test-brute", "type": "brute", "pos": Vector2i(4, 2), "hp": 17, "attack": 5, "defense": 0, "windup_target": null}
	game.enemies.append(brute)
	game.turn_count = 1
	game.run_enemy_turn()
	check(game.enemies[0]["pos"] == Vector2i(4, 2), "Brute rests on odd movement turns")
	game.turn_count = 2
	game.run_enemy_turn()
	check(game.enemies[0]["pos"] == Vector2i(3, 2), "Brute moves one tile on even turns")
	game.turn_count = 3
	game.run_enemy_turn()
	check(game.player["hp"] == 18 and game.enemies[0]["windup_target"] == Vector2i(2, 2), "windup marks a tile without dealing damage")
	check(game.incoming_damage_at(Vector2i(2, 2)) == 5 and game.incoming_damage_at(Vector2i(3, 3)) == 0, "prediction only threatens the marked tile")
	check(game.danger_cost(Vector2i(2, 2)) == 45, "marked tile carries high path cost")
	var escape := game.choose_auto_player_decision("dodge")
	check(escape["rule_id"] == "evade_windup" and game.incoming_damage_at(game.player["pos"] + escape["direction"]) == 0, "Cautious chooses a safe dodge")
	# Stay adjacent but move off the locked target: Brute must not retarget.
	game.player["pos"] = Vector2i(3, 3)
	game.turn_count = 4
	game.run_enemy_turn()
	check(game.player["hp"] == 18 and game.enemies[0]["windup_target"] == null, "strike misses the old tile and resets")
	game.turn_count = 5
	game.run_enemy_turn()
	game.player["equipment"]["armor"] = {"id": "armor", "type": "armor", "attack_bonus": 0, "defense_bonus": 2}
	game.turn_count = 6
	game.run_enemy_turn()
	check(game.player["hp"] == 15 and game.enemies[0]["windup_target"] == null, "heavy strike hits after one windup and uses armor")
	game.player["equipment"]["armor"] = null
	game.player["hp"] = 18
	game.player["pos"] = Vector2i(2, 2)
	var progression := game.choose_progression_decision("growth")
	check(progression["progression"]["candidates"][0]["xp_gain"] == 5 and progression["progression"]["candidates"][0]["estimated_damage"] == 5, "growth estimate counts alternating heavy strikes")
	game.enemies[0]["windup_target"] = game.player["pos"]
	progression = game.choose_progression_decision("ready-growth")
	check(progression["progression"]["candidates"][0]["estimated_damage"] == 10, "ready windup changes estimated retaliation")
	game.active_strategy = MainGame.StrategyType.AGGRESSIVE
	check(game.choose_auto_player_decision("strong")["action_type"] == "attack", "Aggressive keeps attacking a winding Brute")
	game.active_strategy = MainGame.StrategyType.CAUTIOUS
	game.enemies[0]["hp"] = 1
	game.player["xp"] = 3
	check(game.choose_windup_response("kill")["rule_id"] == "interrupt_windup", "Cautious targets the killable marked Brute")
	game.enemies.append({"id": "other", "type": "melee", "pos": Vector2i(2, 1), "hp": 17, "attack": 1, "defense": 0})
	game.run_auto_player_turn()
	check(game.enemies.size() == 1 and game.enemies[0]["id"] == "other" and game.player["level"] == 2 and game.player["xp"] == 0 and game.player["score"] == 2, "Brute kill gives five XP and two score without receiving the strike")
	game.enemies.clear()
	game.enemies.append({"id": "trapped", "type": "brute", "pos": Vector2i(3, 2), "hp": 20, "attack": 5, "defense": 0, "windup_target": game.player["pos"]})
	for pos in [Vector2i(2, 1), Vector2i(2, 3), Vector2i(1, 2)]:
		game.map[pos.y][pos.x] = game.TILE_WALL
	check(game.choose_windup_response("trapped").is_empty(), "blocked dodge returns to existing combat rather than walking through walls")
	game.close_log_file()
	var replay := ReplayData.new()
	var frames := replay.build_frames([
		{"event": "floor_start", "depth": 1, "details": {"map_rows": ["...."], "enemies": [{"id": "b", "type": "brute", "hp": 17, "pos": {"x": 2, "y": 0}, "windup_target": null}]}},
		{"event": "battle_result", "depth": 1, "details": {"result": "enemy_windup", "enemy_id": "b", "enemy_type": "brute", "enemy_pos": {"x": 2, "y": 0}, "target": {"x": 1, "y": 0}, "windup_target": {"x": 1, "y": 0}}},
		{"event": "battle_result", "depth": 1, "details": {"result": "enemy_strike_missed", "enemy_id": "b", "enemy_type": "brute", "enemy_pos": {"x": 2, "y": 0}, "target": {"x": 1, "y": 0}, "windup_target": null}},
	])
	check(frames.size() == 3 and frames[1]["enemies"][0]["windup_target"]["x"] == 1, "replay preserves the windup target")
	check(frames[0]["enemies"][0]["windup_target"] == null and frames[2]["enemies"][0]["windup_target"] == null, "replay clears target without mutating history")
	game.free()
	if failures.is_empty():
		print("Brute tests passed.")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)
