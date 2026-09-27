extends Node

# Enemy data and actions
var pos := Vector2i.ZERO
var hp := 8
var attack := 2

func init_enemy(start_pos: Vector2i, player_depth: int) -> void:
	pos = start_pos
	hp = 8 + player_depth * 2
	attack = 2 + player_depth

func take_damage(damage: int) -> bool:
	hp -= damage
	return hp <= 0