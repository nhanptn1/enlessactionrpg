extends Node2D
class_name ItemIcon
## Procedurally-drawn category silhouette for world item pickups. No icon art
## exists yet, so shape (not just rarity tint) is what makes gear read as
## different from consumables at a glance, per the art bible's item rules.
##
## (2026-07-23) Production-polish pass. These used to be flat single-colour
## polygons -- one solid rarity-tinted shape with no outline, no shading and no
## rarity signal beyond the fill colour, which read as placeholder art. Each
## icon is now built in consistent layers, so they look authored rather than
## sketched, while staying 100% procedural (still zero icon assets):
##   1. a rarity glow halo behind, so rare drops catch the eye on a busy screen
##   2. a dark outline, which is what actually makes a small icon read against
##      the arena background
##   3. the fill, shaded light-to-dark top-to-bottom for volume
##   4. a bright highlight on the upper-left, the standard cheap "lit from
##      above" read
## Shared by EquipSlotIcon's HUD glyphs by convention (see equip_slot_icon.gd).

const OUTLINE_COLOR := Color(0.06, 0.05, 0.09, 0.95)
const OUTLINE_WIDTH := 2.4
const HIGHLIGHT_ALPHA := 0.55
const SHADE_DARKEN := 0.45      # bottom of the fill is this fraction of the top's brightness
const GLOW_RINGS := 3
const GLOW_MAX_RADIUS := 15.0
const GLOW_ALPHA := 0.13

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
	_draw_glow()
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
			_draw_shaded_polygon(_circle_points(8.0, 14))


# --- Shared layer helpers ------------------------------------------------------

func _draw_glow() -> void:
	# Concentric fading rings instead of a gradient texture -- same trick the
	# boss/player auras use, keeps this asset-free.
	for i in GLOW_RINGS:
		var f := float(GLOW_RINGS - i) / float(GLOW_RINGS)
		draw_circle(Vector2.ZERO, GLOW_MAX_RADIUS * f, Color(rarity_color.r, rarity_color.g, rarity_color.b, GLOW_ALPHA * (1.0 - f) + 0.03))


func _shade_top() -> Color:
	return rarity_color.lightened(0.22)


func _shade_bottom() -> Color:
	return Color(rarity_color.r * SHADE_DARKEN, rarity_color.g * SHADE_DARKEN, rarity_color.b * SHADE_DARKEN, rarity_color.a)


func _draw_shaded_polygon(pts: PackedVector2Array) -> void:
	# Vertical light->dark ramp across the shape, then a dark outline over the
	# seam so the two halves never show a hard edge.
	if pts.size() < 3:
		return
	var min_y := pts[0].y
	var max_y := pts[0].y
	for p in pts:
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
	var span: float = maxf(max_y - min_y, 0.001)
	var top := _shade_top()
	var bottom := _shade_bottom()
	var colors := PackedColorArray()
	for p in pts:
		colors.append(top.lerp(bottom, (p.y - min_y) / span))
	draw_polygon(pts, colors)
	_draw_outline(pts)


func _draw_outline(pts: PackedVector2Array) -> void:
	for i in pts.size():
		draw_line(pts[i], pts[(i + 1) % pts.size()], OUTLINE_COLOR, OUTLINE_WIDTH, true)


func _draw_highlight(from_p: Vector2, to_p: Vector2, width: float = 1.6) -> void:
	draw_line(from_p, to_p, Color(1, 1, 1, HIGHLIGHT_ALPHA), width, true)


func _circle_points(radius: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * float(i) / float(segments)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts


# --- Category silhouettes ------------------------------------------------------

func _draw_bow() -> void:
	# Bow stave as an arc, string as a chord -- reads as "bow" even at ~20px.
	# Outline pass first (thicker, dark) then the coloured stave on top, which
	# is how the flat version failed to separate from the background.
	var top := Vector2(9.0 * cos(-PI * 0.35), 9.0 * sin(-PI * 0.35))
	var bottom := Vector2(9.0 * cos(PI * 0.35), 9.0 * sin(PI * 0.35))
	draw_arc(Vector2.ZERO, 9.0, -PI * 0.35, PI * 0.35, 16, OUTLINE_COLOR, 4.6, true)
	draw_arc(Vector2.ZERO, 9.0, -PI * 0.35, PI * 0.35, 16, _shade_top(), 2.5, true)
	draw_line(top, bottom, OUTLINE_COLOR, 2.4, true)
	draw_line(top, bottom, rarity_color.lightened(0.35), 1.1, true)
	# Nocked arrow -- distinguishes a weapon pickup from the shield at a glance.
	draw_line(Vector2(-6, 0), Vector2(7, 0), OUTLINE_COLOR, 3.0, true)
	draw_line(Vector2(-6, 0), Vector2(7, 0), _shade_top(), 1.4, true)


func _draw_shield() -> void:
	var pts := PackedVector2Array([
		Vector2(0, -10), Vector2(8, -6), Vector2(8, 3), Vector2(0, 11), Vector2(-8, 3), Vector2(-8, -6),
	])
	_draw_shaded_polygon(pts)
	_draw_highlight(Vector2(-4.5, -6.5), Vector2(-4.5, 1.5), 1.8)


func _draw_gem() -> void:
	var pts := PackedVector2Array([Vector2(0, -9), Vector2(7, 0), Vector2(0, 9), Vector2(-7, 0)])
	_draw_shaded_polygon(pts)
	# A facet line plus a glint sells "gem" rather than "diamond shape".
	_draw_highlight(Vector2(0, -7.5), Vector2(-4.5, 0.0), 1.5)
	_draw_highlight(Vector2(-4.5, 0.0), Vector2(0, 6.0), 1.1)


func _draw_potion() -> void:
	var body := PackedVector2Array([
		Vector2(-5, -3), Vector2(5, -3), Vector2(5, 7), Vector2(3, 9), Vector2(-3, 9), Vector2(-5, 7),
	])
	_draw_shaded_polygon(body)
	# Neck + stopper, drawn after the body so the outline reads as one object.
	var neck := PackedVector2Array([Vector2(-2, -9), Vector2(2, -9), Vector2(2, -3), Vector2(-2, -3)])
	_draw_shaded_polygon(neck)
	# Liquid line + glint.
	draw_line(Vector2(-4, 1), Vector2(4, 1), Color(1, 1, 1, 0.35), 1.4, true)
	_draw_highlight(Vector2(-3, 3), Vector2(-3, 6), 1.6)
