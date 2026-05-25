extends Node

# Player data and actions
var pos := Vector2i.ZERO
var hp := 18
var max_hp := 18
var attack := 5
var gold := 0
var depth := 1

func init_player(start_pos: Vector2i) -> void:
	pos = start_pos
	hp = max_hp
	gold = 0
	depth = 1

func act(direction: Vector2i, game_manager) -> void:
	var target: Vector2i = pos + direction
	if not game_manager.is_walkable(target):
		game_manager.log_user_action("move", "blocked_wall", {
			"direction": vector_to_log(direction),
			"from": vector_to_log(pos),
			"target": vector_to_log(target),
		})
		return

	game_manager.turn_count += 1
	var enemy_index := game_manager.enemy_at(target)
	if enemy_index != -1:
		game_manager.log_user_action("attack", "enemy_targeted", {
			"direction": vector_to_log(direction),
			"from": vector_to_log(pos),
			"target": vector_to_log(target),
		})
		game_manager.attack_enemy(enemy_index)
	else:
		var from_pos: Vector2i = pos
		pos = target
		game_manager.log_user_action("move", "moved", {
			"direction": vector_to_log(direction),
			"from": vector_to_log(from_pos),
			"target": vector_to_log(target),
		})
		if pos == game_manager.stairs_pos:
			game_manager.log_user_action("descend", "stairs_used", {
				"from_depth": depth,
				"hp_before": hp,
			})
			depth = depth + 1
			hp = min(max_hp, hp + 4)
			game_manager.log_event("floor_descend", {
				"to_depth": depth,
				"hp_after": hp,
			})
			game_manager.new_floor()
			return

	game_manager.run_enemy_turn()
	game_manager.queue_redraw()

func vector_to_log(value: Vector2i) -> Dictionary:
	return {
		"x": value.x,
		"y": value.y,
	}