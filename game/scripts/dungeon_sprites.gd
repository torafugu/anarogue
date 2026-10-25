extends RefCounted

# Draw-only mapping; symbols remain compatible with the existing simulation and logs.
# Kenney Tiny Dungeon, CC0. The bow is an original AnaRogue SVG.
const TEXTURES := {
	"@": preload("res://assets/tiny-dungeon/Tiles/tile_0096.png"),
	"E": preload("res://assets/tiny-dungeon/Tiles/tile_0121.png"),
	"A": preload("res://assets/tiny-dungeon/Tiles/tile_0112.png"),
	"O": preload("res://assets/tiny-dungeon/Tiles/tile_0110.png"),
	"+": preload("res://assets/tiny-dungeon/Tiles/tile_0115.png"),
	"W": preload("res://assets/tiny-dungeon/Tiles/tile_0104.png"),
	"D": preload("res://assets/tiny-dungeon/Tiles/tile_0101.png"),
	"B": preload("res://assets/anarogue/bow.svg"),
}

static func draw(canvas: CanvasItem, center: Vector2, tile_size: float, symbol: String, color: Color) -> void:
	var texture: Texture2D = TEXTURES.get(symbol, TEXTURES["E"])
	canvas.draw_circle(center, tile_size * 0.43, Color(color, 0.18))
	# Integer scaling keeps 16px sprites sharp on the 40px game tiles.
	var side := maxf(16.0, floorf(tile_size / 16.0) * 16.0)
	canvas.draw_texture_rect(texture, Rect2(center - Vector2.ONE * side * 0.5, Vector2.ONE * side), false)
	if symbol == "A":
		canvas.draw_texture_rect(TEXTURES["B"], Rect2(center + Vector2(side * 0.05, -side * 0.05), Vector2.ONE * side * 0.5), false)
