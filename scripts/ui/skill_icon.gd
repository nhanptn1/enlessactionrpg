extends Control
class_name SkillIcon
## Shows a real per-skill icon (art/ui/icons/icon_*.png, cropped from a
## supplied reference sheet) when `texture` is set. Falls back to a procedural
## per-element glyph (flame / snowflake / bolt) for cards that don't map to
## one specific named skill (the repeatable +damage/-cooldown cards) --
## mirrors this project's established no-art-yet fallback
## (scripts/systems/item_icon.gd draws category silhouettes the same way).
## Sized to whatever rect it's given; redraw after changing `texture`/`element`.

@export var texture: Texture2D = null
@export var element: int = 0  # UpgradeResource.ElementType, used only when texture is null

const FIRE_OUTER := Color(1.0, 0.5, 0.12, 1.0)
const FIRE_INNER := Color(1.0, 0.85, 0.3, 1.0)
const FROST_COLOR := Color(0.65, 0.9, 1.0, 1.0)
const FROST_CORE := Color(1.0, 1.0, 1.0, 1.0)
const LIGHTNING_FILL := Color(1.0, 0.92, 0.35, 1.0)
const LIGHTNING_OUTLINE := Color(0.7, 0.42, 1.0, 1.0)
const PHYSICAL_SHAFT := Color(0.75, 0.6, 0.42, 1.0)
const PHYSICAL_HEAD := Color(0.85, 0.85, 0.85, 1.0)


func _draw() -> void:
	if texture != null:
		draw_texture_rect(texture, Rect2(Vector2.ZERO, size), false)
		return
	match element:
		0:
			_draw_flame()
		1:
			_draw_snowflake()
		2:
			_draw_bolt()
		3:
			_draw_arrow()
		_:
			_draw_arrow()  # CLASS (4) and anything future: class skills are untyped/physical, the arrow glyph fits


func _draw_flame() -> void:
	var w := size.x
	var h := size.y
	var outer := PackedVector2Array([
		Vector2(w * 0.5, h * 0.04),
		Vector2(w * 0.78, h * 0.42),
		Vector2(w * 0.66, h * 0.56),
		Vector2(w * 0.86, h * 0.78),
		Vector2(w * 0.5, h * 0.97),
		Vector2(w * 0.14, h * 0.78),
		Vector2(w * 0.34, h * 0.56),
		Vector2(w * 0.22, h * 0.42),
	])
	draw_colored_polygon(outer, FIRE_OUTER)
	var inner := PackedVector2Array([
		Vector2(w * 0.5, h * 0.32),
		Vector2(w * 0.66, h * 0.58),
		Vector2(w * 0.5, h * 0.88),
		Vector2(w * 0.34, h * 0.58),
	])
	draw_colored_polygon(inner, FIRE_INNER)


func _draw_snowflake() -> void:
	var center := size / 2.0
	var r := minf(size.x, size.y) * 0.44
	for i in 6:
		var angle := TAU * i / 6.0
		var dir := Vector2(cos(angle), sin(angle))
		var tip := center + dir * r
		draw_line(center, tip, FROST_COLOR, 3.0)
		var branch_base := center + dir * r * 0.62
		var perp := dir.rotated(PI / 2.0)
		draw_line(branch_base, branch_base + (dir + perp).normalized() * r * 0.3, FROST_COLOR, 2.0)
		draw_line(branch_base, branch_base + (dir - perp).normalized() * r * 0.3, FROST_COLOR, 2.0)
	draw_circle(center, r * 0.14, FROST_CORE)


func _draw_bolt() -> void:
	var w := size.x
	var h := size.y
	var points := PackedVector2Array([
		Vector2(w * 0.58, h * 0.03),
		Vector2(w * 0.24, h * 0.56),
		Vector2(w * 0.46, h * 0.56),
		Vector2(w * 0.4, h * 0.97),
		Vector2(w * 0.78, h * 0.4),
		Vector2(w * 0.56, h * 0.4),
	])
	draw_colored_polygon(points, LIGHTNING_FILL)
	for i in points.size():
		draw_line(points[i], points[(i + 1) % points.size()], LIGHTNING_OUTLINE, 1.5)


func _draw_arrow() -> void:
	var w := size.x
	var h := size.y
	draw_line(Vector2(w * 0.2, h * 0.8), Vector2(w * 0.75, h * 0.25), PHYSICAL_SHAFT, maxf(w, h) * 0.06)
	var head := PackedVector2Array([
		Vector2(w * 0.75, h * 0.25),
		Vector2(w * 0.9, h * 0.42),
		Vector2(w * 0.58, h * 0.42),
	])
	draw_colored_polygon(head, PHYSICAL_HEAD)
	var fletch := PackedVector2Array([
		Vector2(w * 0.2, h * 0.8),
		Vector2(w * 0.1, h * 0.62),
		Vector2(w * 0.32, h * 0.7),
	])
	draw_colored_polygon(fletch, PHYSICAL_HEAD)
