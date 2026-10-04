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
	game.configure_headless(1, MainGame.StrategyType.AGGRESSIVE, "/tmp/anarogue-goals-test.jsonl")
	game.configure_headless_map(24, 18)
	root.add_child(game)
	game.items.clear()
	game.enemies.clear()
	for row in game.map:
		row.fill(game.TILE_FLOOR)
	game.player["pos"] = Vector2i(2, 2)
	game.stairs_pos = Vector2i(20, 15)
	game.enemies.append({"id":"goal", "type":"melee", "pos":Vector2i(5, 2), "hp":5,"attack":1,"defense":0,"windup_target":null})
	var policy := game.goal_policy()
	check(not game.configure_goal_policy({"enemy_weight":0,"item_weight":0,"stairs_weight":0}), "all-zero policy is rejected")
	check(not game.configure_goal_policy({"temperature":0}), "invalid temperature is rejected")
	check(game.goal_policy() == policy, "invalid input preserves the existing policy")
	check(game.goal_mass(4, 0, 8) == 4000 and game.goal_mass(1, 8, 8) == 368 and game.goal_mass(0, 0, 8) == 0, "portable probability masses")
	var rng_before := game.policy_rng.state
	var preview := game.choose_goal_decision("preview")
	check(game.policy_rng.state == rng_before and game.selected_goal.is_empty(), "preview is pure")
	var executed := game.choose_goal_decision("commit", true)
	check(preview["goal_selection"] == executed["goal_selection"], "preview predicts the exact next draw")
	rng_before = game.policy_rng.state
	var retained := game.choose_goal_decision("retain", true)
	check(retained["goal_selection"]["target_retained"] and retained["goal_selection"]["draw"] == null and game.policy_rng.state == rng_before, "retention consumes no randomness")
	game.player["hp"] -= 4
	check(not game.choose_goal_decision("hp", true)["goal_selection"]["target_retained"], "material HP change triggers a new draw")
	game.configure_goal_policy({"enemy_weight":1,"item_weight":0,"stairs_weight":0})
	check(game.choose_goal_decision("enemy", true)["target"]["id"] == "goal", "zero weights exclude other categories")
	game.enemies.append({"id":"closer", "type":"melee", "pos":Vector2i(2, 4), "hp":5,"attack":1,"defense":0,"windup_target":null})
	check(game.choose_goal_decision("closer", true)["target"]["id"] == "goal", "a closer candidate does not reverse a retained goal")
	game.enemies.remove_at(0)
	check(game.choose_goal_decision("dead", true)["target"]["id"] == "closer", "completed goal is replaced")
	game.new_floor()
	check(game.selected_goal.is_empty(), "new floor clears goal memory")
	# A melee Brute goal must make progress after evasion, rather than endlessly re-entering its windup tile.
	for row in game.map:
		row.fill(game.TILE_FLOOR)
	game.enemies.clear()
	game.items.clear()
	game.player["pos"] = Vector2i(2, 2)
	game.player["hp"] = 18
	game.player["equipment"] = {"weapon":null,"armor":null}
	game.stairs_pos = Vector2i(20, 15)
	game.active_strategy = MainGame.StrategyType.CAUTIOUS
	game.enemies.append({"id":"brute", "type":"brute", "pos":Vector2i(4, 2), "hp":14,"attack":5,"defense":0,"windup_target":null})
	for _turn in range(30):
		if game.enemies.is_empty():
			break
		game.run_auto_player_turn()
	check(game.enemies.is_empty() and game.player["hp"] == 18, "Brute goal completes without a dodge / approach loop")
	game.close_log_file()
	game.free()
	if failures.is_empty():
		print("Weighted goal tests passed.")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: %s" % failure)
		quit(1)
