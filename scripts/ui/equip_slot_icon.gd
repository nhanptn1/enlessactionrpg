extends Control
class_name EquipSlotIcon
## HUD equipment-slot glyph -- same bow/shield/gem silhouettes as the world
## pickup's ItemIcon (item_icon.gd), redrawn against a Control's `size`
## instead of Node2D's fixed radii so it fits this Control-based HUD layout
## directly, matching the existing book_icon.gd precedent for HUD icons.

const EMPTY_COLOR := Color(1, 1, 1, 0.25)

@export var category: String = "":  # "weapon" | "armor" | "accessory"
	set(v):
		if v == category:
			return
		category = v
		queue_redraw()

var rarity_color: Color = EMPTY_COLOR:
	set(v):
		if v == rarity_color:
			return
		rarity_color = v
		queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var c := Vector2(w * 0.5, h * 0.5)
	var r := minf(w, h) * 0.42
	match category:
		"weapon":
			_draw_bow(c, r)
		"armor":
			_draw_shield(c, r)
		"accessory":
			_draw_gem(c, r)
		_:
			draw_arc(c, r, 0, TAU, 20, EMPTY_COLOR, 1.5, true)


func _draw_bow(c: Vector2, r: float) -> void:
	draw_arc(c, r, -PI * 0.35, PI * 0.35, 16, rarity_color, 2.5, true)
	var top := c + Vector2(r * cos(-PI * 0.35), r * sin(-PI * 0.35))
	var bottom := c + Vector2(r * cos(PI * 0.35), r * sin(PI * 0.35))
	draw_line(top, bottom, rarity_color, 1.2, true)


func _draw_shield(c: Vector2, r: float) -> void:
	var pts := PackedVector2Array([
		c + Vector2(0, -r), c + Vector2(r * 0.8, -r * 0.6), c + Vector2(r * 0.8, r * 0.3),
		c + Vector2(0, r * 1.1), c + Vector2(-r * 0.8, r * 0.3), c + Vector2(-r * 0.8, -r * 0.6),
	])
	draw_colored_polygon(pts, rarity_color)


func _draw_gem(c: Vector2, r: float) -> void:
	var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.78, 0), c + Vector2(0, r), c + Vector2(-r * 0.78, 0)])
	draw_colored_polygon(pts, rarity_color)
