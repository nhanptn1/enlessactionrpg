extends Control
class_name ElementCycleDiagram

## Draws the Fire/Frost/Lightning counter cycle as a triangle of colored
## element nodes with directional "beats" arrows (X -> Y means X beats Y),
## mirroring a Pokemon-style type-advantage wheel. Shown top-right during boss
## waves. When an affinity boss is on the field, its own node is ringed red
## ("this boss resists you") and the element that counters it is ringed green
## with a highlighted arrow ("use this"). Purely procedural -- no art assets.

const NODE_R := 21.0
const FIRE_COL := Color(1.0, 0.55, 0.2, 1.0)
const FROST_COL := Color(0.45, 0.8, 1.0, 1.0)
const LIGHT_COL := Color(0.82, 0.5, 1.0, 1.0)
const ARROW_COL := Color(0.7, 0.82, 0.95, 0.85)
const COUNTER_COL := Color(0.35, 1.0, 0.5, 1.0)  # green -- "your answer"
const BOSS_COL := Color(1.0, 0.32, 0.32, 1.0)    # red -- "resists you"

# X beats Y (arrow X -> Y): Frost beats Fire, Lightning beats Frost, Fire beats Lightning.
const BEATS := [["frost", "fire"], ["lightning", "frost"], ["fire", "lightning"]]
const COUNTER_OF := {"fire": "frost", "frost": "lightning", "lightning": "fire"}

# "" = no affinity boss (plain cycle). Otherwise the boss's affinity id, which
# highlights its node + its counter. Set by HUD; call queue_redraw() after.
var active_affinity: String = ""


func _node_centers() -> Dictionary:
	return {
		"fire": Vector2(size.x * 0.5, size.y * 0.22),
		"frost": Vector2(size.x * 0.22, size.y * 0.7),
		"lightning": Vector2(size.x * 0.78, size.y * 0.7),
	}


func _draw() -> void:
	var n := _node_centers()
	for pair in BEATS:
		# The arrow pointing INTO the boss's node is the counter arrow -- highlight it.
		# Explicit bool: pair[1] indexes an untyped const array (Variant), which
		# blocks `:=` inference (this project's recurring gotcha).
		var is_answer: bool = active_affinity != "" and pair[1] == active_affinity
		_draw_arrow(n[pair[0]], n[pair[1]], is_answer)
	for key in n:
		_draw_node(key, n[key])
	# Bottom hint line when a boss affinity is active.
	if active_affinity != "":
		var font := ThemeDB.fallback_font
		var counter: String = COUNTER_OF[active_affinity]
		var hint := "Use %s" % counter.capitalize()
		var tw := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		_draw_string_outlined(font, Vector2((size.x - tw) * 0.5, size.y - 4.0), hint, 15, COUNTER_COL)


func _draw_arrow(from: Vector2, to: Vector2, highlight: bool) -> void:
	var dir := (to - from).normalized()
	var p0 := from + dir * (NODE_R + 3.0)
	var p1 := to - dir * (NODE_R + 7.0)
	var col := COUNTER_COL if highlight else ARROW_COL
	var w := 4.0 if highlight else 2.5
	draw_line(p0, p1, col, w)
	var perp := Vector2(-dir.y, dir.x)
	var head := 9.0
	draw_colored_polygon(PackedVector2Array([
		p1, p1 - dir * head + perp * head * 0.5, p1 - dir * head - perp * head * 0.5,
	]), col)


func _draw_node(key: String, c: Vector2) -> void:
	var col := _color_for(key)
	var dimmed: bool = active_affinity != "" and key != active_affinity and key != COUNTER_OF.get(active_affinity, "")
	var fill := Color(col.r, col.g, col.b, 0.35 if dimmed else 0.95)
	var diamond := PackedVector2Array([
		c + Vector2(0, -NODE_R), c + Vector2(NODE_R, 0),
		c + Vector2(0, NODE_R), c + Vector2(-NODE_R, 0),
	])
	draw_colored_polygon(diamond, fill)

	var border_col := Color(0.92, 0.92, 0.96, 0.85)
	var border_w := 2.0
	if active_affinity != "":
		if key == active_affinity:
			border_col = BOSS_COL
			border_w = 4.0
		elif key == COUNTER_OF.get(active_affinity, ""):
			border_col = COUNTER_COL
			border_w = 4.0
	var outline := diamond.duplicate()
	outline.append(diamond[0])
	draw_polyline(outline, border_col, border_w)

	_draw_glyph(key, c, dimmed)

	var font := ThemeDB.fallback_font
	var label := key.capitalize()
	var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var lcol := Color(1, 1, 1, 0.4 if dimmed else 0.95)
	_draw_string_outlined(font, c + Vector2(-lw * 0.5, NODE_R + 13.0), label, 12, lcol)


func _draw_glyph(key: String, c: Vector2, dimmed: bool) -> void:
	var col := Color(1, 1, 1, 0.5 if dimmed else 1.0)
	match key:
		"fire":
			# a small flame: filled teardrop-ish triangle
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -9), c + Vector2(6, 5), c + Vector2(0, 9), c + Vector2(-6, 5),
			]), col)
		"frost":
			# snowflake: 3 crossing spokes
			for a in [0.0, PI / 3.0, 2.0 * PI / 3.0]:
				var d := Vector2(cos(a), sin(a)) * 9.0
				draw_line(c - d, c + d, col, 2.0)
		"lightning":
			# zigzag bolt
			draw_polyline(PackedVector2Array([
				c + Vector2(2, -9), c + Vector2(-3, -1), c + Vector2(2, 1),
				c + Vector2(-2, 9), c + Vector2(4, -2), c + Vector2(-1, 0),
			]), col, 2.0)


func _draw_string_outlined(font: Font, pos: Vector2, text: String, font_size: int, col: Color) -> void:
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color(0, 0, 0, 0.9))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


func _color_for(key: String) -> Color:
	match key:
		"fire":
			return FIRE_COL
		"frost":
			return FROST_COL
		"lightning":
			return LIGHT_COL
	return Color.WHITE
