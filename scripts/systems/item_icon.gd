extends Node2D
class_name ItemIcon
## Procedurally-drawn category silhouette for world item pickups. No icon art
## exists yet, so shape (not just rarity tint) is what makes gear read as
## different from consumables at a glance, per the art bible's item rules.

var category: String = "":
	set(v):
		if v == category:
			return
		category = v
		queue_redraw()

var rarity_color: Color = Color.WHITE:
	set(v):
		if v == rarity_color:
			return
		rarity_color = v
		queue_redraw()


func _draw() -> void:
	match category:
		"weapon":
			_draw_bow()
		"armor":
			_draw_shield()
		"accessory":
			_draw_gem()
		"consumable":
			_draw_potion()
		_:
			draw_circle(Vector2.ZERO, 8.0, rarity_color)


func _draw_bow() -> void:
	# Bow stave as an arc, string as a straight chord -- reads as "bow" even
	# at ~20px.
	draw_arc(Vector2.ZERO, 9.0, -PI * 0.35, PI * 0.35, 16, rarity_color, 2.5, true)
	var top := Vector2(9.0 * cos(-PI * 0.35), 9.0 * sin(-PI * 0.35))
	var bottom := Vector2(9.0 * cos(PI * 0.35), 9.0 * sin(PI * 0.35))
	draw_line(top, bottom, rarity_color, 1.2, true)


func _draw_shield() -> void:
	var pts := PackedVector2Array([
		Vector2(0, -10), Vector2(8, -6), Vector2(8, 3), Vector2(0, 11), Vector2(-8, 3), Vector2(-8, -6),
	])
	draw_colored_polygon(pts, rarity_color)


func _draw_gem() -> void:
	var pts := PackedVector2Array([Vector2(0, -9), Vector2(7, 0), Vector2(0, 9), Vector2(-7, 0)])
	draw_colored_polygon(pts, rarity_color)


func _draw_potion() -> void:
	draw_rect(Rect2(-5, -3, 10, 12), rarity_color, true)
	draw_rect(Rect2(-2, -9, 4, 7), rarity_color, true)
