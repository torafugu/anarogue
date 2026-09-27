extends Node

const MAP_WIDTH := 44
const MAP_HEIGHT := 28
const TILE_SIZE := 20
const ROOM_ATTEMPTS := 70
const MAX_ROOMS := 11
const MIN_ROOM_SIZE := 5
const MAX_ROOM_SIZE := 11

const TILE_WALL := 0
const TILE_FLOOR := 1

func generate_dungeon() -> Array:
	var map := []
	var rooms := []
	for y in range(MAP_HEIGHT):
		var row := []
		for x in range(MAP_WIDTH):
			row.append(TILE_WALL)
		map.append(row)
	
	for i in range(ROOM_ATTEMPTS):
		if rooms.size() >= MAX_ROOMS:
			break
		
		var w := rng.randi_range(MIN_ROOM_SIZE, MAX_ROOM_SIZE)
		var h := rng.randi_range(MIN_ROOM_SIZE, MAX_ROOM_SIZE)
		var x := rng.randi_range(1, MAP_WIDTH - w - 2)
		var y := rng.randi_range(1, MAP_HEIGHT - h - 2)
		var room := Rect2i(x, y, w, h)
		
		var overlaps := false
		for existing in rooms:
			if room.grow(1).intersects(existing):
				overlaps = true
				break
		
		if overlaps:
			continue
		
		carve_room(map, room)
		if not rooms.is_empty():
			connect_rooms(map, rooms.back().get_center(), room.get_center())
		rooms.append(room)
	
	if rooms.is_empty():
		var fallback := Rect2i(4, 4, 12, 10)
		carve_room(map, fallback)
		rooms.append(fallback)
	
	return [map, rooms]

func carve_room(map: Array, room: Rect2i) -> void:
	for y in range(room.position.y, room.end.y):
		for x in range(room.position.x, room.end.x):
			map[y][x] = TILE_FLOOR

func connect_rooms(map: Array, a: Vector2i, b: Vector2i) -> void:
	if rng.randf() < 0.5:
		carve_horizontal(map, a.x, b.x, a.y)
		carve_vertical(map, a.y, b.y, b.x)
	else:
		carve_vertical(map, a.y, b.y, a.x)
		carve_horizontal(map, a.x, b.x, b.y)

func carve_horizontal(map: Array, x1: int, x2: int, y: int) -> void:
	for x in range(mini(x1, x2), maxi(x1, x2) + 1):
		map[y][x] = TILE_FLOOR

func carve_vertical(map: Array, y1: int, y2: int, x: int) -> void:
	for y in range(mini(y1, y2), maxi(y1, y2) + 1):
		map[y][x] = TILE_FLOOR