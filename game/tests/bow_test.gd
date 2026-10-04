extends SceneTree

const MainGame := preload("res://scripts/main.gd")
const ReplayData := preload("res://scripts/replay_log.gd")
var failures: Array[String] = []

func _init() -> void:
	run_tests.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func weapon(style: String, bonus: int, id: String) -> Dictionary:
	return {"id": id, "type": "weapon", "weapon_kind": style, "attack_bonus": bonus, "defense_bonus": 0}

func run_tests() -> void:
	var game := MainGame.new()
	game.configure_headless(1, MainGame.StrategyType.CAUTIOUS, "/tmp/anarogue-bow-test.jsonl")
	game.configure_headless_map(24, 18)
	root.add_child(game)
	game.items.clear()
	game.enemies.clear()
	game.navigation_visits.clear()
	for row in game.map:
		row.fill(game.TILE_FLOOR)
	game.player["pos"] = Vector2i(2, 2)
	game.stairs_pos = Vector2i(20, 15)
	game.player["equipment"]["weapon"] = weapon("melee", 2, "sword")
	check(game.effective_attack() == 7 and game.attack_range() == 1, "melee remains high damage and range one")
	game.player["equipment"]["weapon"] = weapon("bow", 2, "bow")
	check(game.effective_attack() == 3 and game.attack_range() == 5, "bow halves total attack, rounded down, with range five")
	check(game.wants_weapon(weapon("bow", 3, "upgrade")), "stronger bow is accepted")
	check(not game.wants_weapon(weapon("bow", 2, "equal")), "equal bow is ignored")
	check(not game.wants_weapon(weapon("melee", 99, "powerful-sword")), "Cautious retains preferred bow over nonpreferred melee")
	game.active_strategy = MainGame.StrategyType.AGGRESSIVE
	check(game.wants_weapon(weapon("melee", 1, "weak-sword")), "Aggressive prefers melee even at lower bonus")
	game.player["equipment"]["weapon"] = weapon("melee", 2, "sword")
	check(not game.wants_weapon(weapon("bow", 99, "powerful-bow")), "Aggressive does not oscillate back to bow")
	game.active_strategy = MainGame.StrategyType.CAUTIOUS
	var bow_item := weapon("bow", 2, "new-bow")
	bow_item["pos"] = game.player["pos"]
	game.items.append(bow_item)
	game.pick_up_items()
	game.pick_up_items()
	check(game.weapon_kind() == "bow" and game.items.size() == 1 and game.items[0]["weapon_kind"] == "melee", "dropped nonpreferred weapon is not picked up again")
	game.items.clear()
	# Healthy collection chooses preferred weapon before a closer fallback.
	game.player["equipment"]["weapon"] = null
	var near_sword := weapon("melee", 2, "near-sword")
	near_sword["pos"] = Vector2i(3, 2)
	bow_item["pos"] = Vector2i(5, 2)
	game.items.assign([near_sword, bow_item])
	check(game.choose_item_decision("preference")["target"]["id"] == "new-bow", "short detours prioritize the preferred weapon")
	game.items.clear()
	game.player["equipment"]["weapon"] = weapon("bow", 2, "bow")
	game.enemies.assign([{"id": "target", "type": "melee", "pos": Vector2i(7, 2), "hp": 10, "attack": 3, "defense": 0}])
	check(game.can_player_shoot_from(Vector2i(2, 2), Vector2i(7, 2)), "exact range boundary is allowed")
	check(game.can_player_shoot_from(Vector2i(2, 2), Vector2i(5, 6)), "3-4-5 diagonal range is allowed")
	check(not game.can_player_shoot_from(Vector2i(2, 2), Vector2i(8, 2)), "range six is blocked")
	var turn_before := game.turn_count
	game.map[2][4] = game.TILE_WALL
	check(not game.player_shoot("target") and game.turn_count == turn_before, "blocked shot consumes no turn")
	game.map[2][4] = game.TILE_FLOOR
	game.map[2][3] = game.TILE_WALL
	check(not game.can_player_shoot_from(Vector2i(2, 2), Vector2i(3, 3)), "diagonal corner blocks player arrows")
	game.map[2][3] = game.TILE_FLOOR
	check(not game.player_shoot("missing") and game.turn_count == turn_before, "missing target consumes no turn")
	var decision := game.choose_auto_player_decision("bow")
	check(decision["rule_id"] == "shoot_in_range" and decision["action_type"] == "ranged_attack", "automatic bow decision fires in place")
	check(game.player_shoot("target", "test-shot"), "valid shot fires")
	check(game.turn_count == turn_before + 1 and game.player["pos"] == Vector2i(2, 2), "shot costs one turn without moving")
	check(game.enemies[0]["hp"] == 7 and game.enemies[0]["pos"] == Vector2i(6, 2), "lower bow damage applies before enemy movement")
	# Growth route stops at a firing tile, rather than planning a melee approach.
	decision = game.choose_progression_decision("estimate")
	var candidate: Dictionary = decision["progression"]["candidates"][0]
	check(candidate["steps"] == 0 and candidate["estimated_damage"] == 0, "growth estimate accounts for free shots before melee enemy closes")
	game.enemies[0]["hp"] = 1
	game.enemies[0]["defense"] = 20
	game.player["xp"] = 5
	check(game.player_shoot("target", "kill"), "minimum-damage shot kills")
	check(game.enemies.is_empty() and game.player["level"] == 2 and game.player["xp"] == 0, "ranged kill grants normal XP and level growth")
	check(game.effective_attack() == 4 and game.player["base_attack"] == 6, "level growth and bow scaling remain separate")
	game.enemies.assign([{"id": "archer", "type": "archer", "pos": Vector2i(7, 2), "hp": 20, "attack": 3, "defense": 0}])
	game.player["equipment"]["armor"] = {"id": "armor", "type": "armor", "attack_bonus": 0, "defense_bonus": 1}
	var hp_before: int = game.player["hp"]
	check(game.player_shoot("archer", "counterfire") and game.player["hp"] == hp_before - 2, "enemy phase follows the shot and armor mitigates counterfire")
	game.player["inventory"]["health_potion"] = 1
	game.player["hp"] = 8
	check(game.choose_auto_player_decision("heal")["action_type"] == "use_item", "healing takes priority over shooting")
	game.player["inventory"]["health_potion"] = 0
	game.player["hp"] = 1
	check(game.choose_bow_decision("lethal").is_empty(), "automatic shooting avoids lethal counterfire")
	game.stairs_pos = Vector2i(3, 2)
	check(game.choose_auto_player_decision("escape")["target"]["kind"] == "stairs", "Cautious descends when stairs are adjacent")
	game.stairs_pos = Vector2i(20, 15)
	game.player["hp"] = 18
	game.player["equipment"]["weapon"] = weapon("melee", 2, "sword")
	turn_before = game.turn_count
	check(not game.player_shoot("archer") and game.turn_count == turn_before, "melee weapon cannot fire arrows")
	game.close_log_file()
	var replay := ReplayData.new()
	check(replay.load_file("/tmp/anarogue-bow-test.jsonl") == OK, "player shots replay")
	var shots := 0
	for frame in replay.frames:
		if frame["kind"] == "player_ranged_hit":
			shots += 1
			check(frame["arrow"]["from"]["x"] == 2 and frame["arrow"]["from"]["y"] == 2 and frame["arrow"]["player_shot"], "replay arrow starts at Player")
	check(shots == 3, "every successful player shot has a replay frame")
	var frames := replay.build_frames([
		{"event": "floor_start", "depth": 1, "details": {"map_rows": ["........"], "enemies": [{"id": "target", "hp": 10, "pos": {"x": 7, "y": 0}}]}},
		{"event": "battle_result", "depth": 1, "details": {"result": "enemy_hit", "ranged": true, "enemy_id": "target", "enemy_hp_after": 7, "enemy_pos": {"x": 7, "y": 0}, "attacker_pos": {"x": 2, "y": 0}}},
		{"event": "battle_result", "depth": 1, "details": {"result": "enemy_defeated", "ranged": true, "enemy_id": "target", "enemy_pos": {"x": 7, "y": 0}, "attacker_pos": {"x": 2, "y": 0}}},
	])
	check(frames[1]["enemies"][0]["hp"] == 7 and frames[0]["enemies"][0]["hp"] == 10, "shot replay updates HP without mutating prior frames")
	check(frames[2]["enemies"].is_empty() and not frames[2]["arrow"].is_empty(), "killing arrow remains visible after enemy disappears")
	game.new_floor()
	game.close_log_file()
	game.free()
	if failures.is_empty():
		print("Player bow tests passed.")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)
