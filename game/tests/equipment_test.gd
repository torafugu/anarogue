extends SceneTree

const MainGame := preload("res://scripts/main.gd")
const ReplayData := preload("res://scripts/replay_log.gd")
var failures: Array[String] = []

func _init() -> void:
	call_deferred("run_tests")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func create_game():
	var game := MainGame.new()
	game.configure_headless(1, MainGame.StrategyType.AGGRESSIVE, "/tmp/anarogue-equipment-test.jsonl")
	game.configure_headless_map(24, 18)
	root.add_child(game)
	game.enemies.clear()
	game.items.clear()
	for y in range(18):
		for x in range(24):
			game.map[y][x] = game.TILE_FLOOR
	game.player["pos"] = Vector2i(2, 2)
	game.stairs_pos = Vector2i(20, 15)
	return game

func gear(kind: String, id: String, pos: Vector2i, bonus: int) -> Dictionary:
	return {"id": id, "type": kind, "pos": pos, "attack_bonus": bonus if kind == "weapon" else 0, "defense_bonus": bonus if kind == "armor" else 0}

func run_tests() -> void:
	test_pickup_and_replay()
	test_combat_growth_and_policy()
	if failures.is_empty():
		print("Equipment tests passed: upgrades, drops, persistence, base stats, damage, policy and replay.")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: %s" % failure)
		quit(1)

func test_pickup_and_replay() -> void:
	var game = create_game()
	game.player["inventory"]["health_potion"] = 3
	game.items.append(gear("weapon", "sword", Vector2i(3, 2), 2))
	game.items.append(gear("armor", "vest", Vector2i(3, 2), 1))
	game.player_act(Vector2i.RIGHT, "equip")
	check(game.turn_count == 1 and game.items.is_empty(), "equip uses only the movement turn")
	check(game.effective_attack() == 7 and game.effective_defense() == 1, "equipment modifies effective stats")
	check(game.player["inventory"]["health_potion"] == 3, "gear is independent of potion capacity")
	game.items.append(gear("weapon", "better-sword", Vector2i(3, 2), 4))
	game.pick_up_items("upgrade")
	check(game.effective_attack() == 9 and game.items[0]["id"] == "sword", "stronger weapon replaces and drops previous")
	game.items.append(gear("weapon", "equal-sword", Vector2i(3, 2), 4))
	game.pick_up_items("same")
	check(game.items.size() == 2 and game.player["equipment"]["weapon"]["id"] == "better-sword", "equal and weaker equipment remain on floor")
	game.close_log_file()
	var replay := ReplayData.new()
	check(replay.load_file("/tmp/anarogue-equipment-test.jsonl") == OK, "equipment log replays")
	var upgrade_frame: Dictionary = {}
	for frame in replay.frames:
		if frame["kind"] == "item_result" and frame["player_state"].get("equipment", {}).get("weapon") != null:
			if frame["player_state"]["equipment"]["weapon"]["id"] == "better-sword":
				upgrade_frame = frame
	check(not upgrade_frame.is_empty(), "upgrade has its own replay frame")
	if not upgrade_frame.is_empty():
		check(upgrade_frame["items"].size() == 1 and upgrade_frame["items"][0]["id"] == "sword", "replay immediately restores dropped gear and removes equipped gear")
	game.new_floor()
	check(game.attack_bonus() == 4 and game.defense_bonus() == 1, "equipment persists between floors")
	game.restart_game(true)
	check(game.attack_bonus() == 0 and game.defense_bonus() == 0, "new run clears equipment")
	game.close_log_file()
	game.free()

func test_combat_growth_and_policy() -> void:
	var game = create_game()
	game.items.append(gear("weapon", "sword", Vector2i(2, 2), 2))
	game.items.append(gear("armor", "vest", Vector2i(2, 2), 2))
	game.pick_up_items("equip")
	game.player["xp"] = 8
	game.check_level_up()
	check(game.player["base_attack"] == 6 and game.attack_bonus() == 2 and game.effective_attack() == 8, "level growth changes base attack only")
	check(game.player["base_defense"] == 0 and game.effective_defense() == 2, "defense remains a separate base plus bonus")
	var enemy := {"id": "target", "type": "melee", "pos": Vector2i(3, 2), "hp": 20, "attack": 5}
	game.enemies.append(enemy)
	game.attack_enemy(0)
	check(game.enemies[0]["hp"] == 12, "weapon increases outgoing damage")
	enemy["defense"] = 20
	game.attack_enemy(0)
	check(game.enemies[0]["hp"] == 11, "enemy defense uses the same minimum-damage rule")
	var hp: int = game.player["hp"]
	game.run_melee_turn(0, enemy, enemy["pos"], Vector2i(-1, 0))
	check(game.player["hp"] == hp - 3, "armor reduces melee damage")
	enemy["type"] = "archer"
	enemy["pos"] = Vector2i(6, 2)
	game.run_archer_turn(0, enemy, enemy["pos"])
	check(game.player["hp"] == hp - 6, "armor reduces ranged damage")
	check(game.calculate_damage(3, 20) == 1, "minimum damage is one")
	game.player["hp"] = 14
	game.player["inventory"]["health_potion"] = 3
	enemy["attack"] = 14
	game.enemies[0] = enemy
	check(game.choose_item_decision("armored").is_empty(), "armor is included in lethal-hit prediction")
	game.player["equipment"]["armor"] = null
	check(game.choose_item_decision("unarmored")["rule_id"] == "use_health_potion", "unarmored lethal shot triggers healing")
	game.enemies.clear()
	game.player["hp"] = game.player["max_hp"]
	game.items.append(gear("armor", "vest-2", Vector2i(3, 2), 2))
	check(game.choose_item_decision("gear")["rule_id"] == "collect_nearby_equipment", "full potion inventory does not suppress gear detour")
	game.close_log_file()
	game.free()
