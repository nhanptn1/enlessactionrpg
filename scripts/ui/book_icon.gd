extends Control
class_name BookIcon
## Procedural open-book glyph for the HUD's Skill button -- no book art
## exists yet, matches this project's established no-art-yet fallback
## pattern (skill_icon.gd/item_icon.gd draw their own art the same way).

const COVER_COLOR := Color(0.55, 0.35, 0.15, 1.0)
const PAGE_COLOR := Color(0.95, 0.9, 0.75, 1.0)
const SPINE_COLOR := Color(0.35, 0.2, 0.08, 1.0)


func _draw() -> void:
	var w := size.x
	var h := size.y
	var cover := PackedVector2Array([
		Vector2(w * 0.08, h * 0.22), Vector2(w * 0.5, h * 0.12), Vector2(w * 0.92, h * 0.22),
		Vector2(w * 0.92, h * 0.85), Vector2(w * 0.5, h * 0.95), Vector2(w * 0.08, h * 0.85),
	])
	draw_colored_polygon(cover, COVER_COLOR)
	var left_page := PackedVector2Array([
		Vector2(w * 0.13, h * 0.28), Vector2(w * 0.48, h * 0.2), Vector2(w * 0.48, h * 0.86), Vector2(w * 0.13, h * 0.78),
	])
	draw_colored_polygon(left_page, PAGE_COLOR)
	var right_page := PackedVector2Array([
		Vector2(w * 0.87, h * 0.28), Vector2(w * 0.52, h * 0.2), Vector2(w * 0.52, h * 0.86), Vector2(w * 0.87, h * 0.78),
	])
	draw_colored_polygon(right_page, PAGE_COLOR)
	draw_line(Vector2(w * 0.5, h * 0.14), Vector2(w * 0.5, h * 0.92), SPINE_COLOR, maxf(w, h) * 0.05)
	for i in 3:
		var t := 0.35 + i * 0.15
		draw_line(Vector2(w * 0.18, h * t), Vector2(w * 0.44, h * (t + 0.02)), SPINE_COLOR, 1.5)
		draw_line(Vector2(w * 0.56, h * (t + 0.02)), Vector2(w * 0.82, h * t), SPINE_COLOR, 1.5)
