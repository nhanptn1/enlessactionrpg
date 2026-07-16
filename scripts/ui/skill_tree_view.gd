extends Control
class_name SkillTreeView
## Draws all 4 skill lines (Physical/Fire/Frost/Lightning) as 4 side-by-side
## columns, each a single straight vertical chain of nodes -- matches the
## user-supplied reference image (image/skills/skill-trees.png) exactly: one
## line per column, no branching, 4 tiers each. (2026-07-16) Now the top half
## of one merged Skills panel (was its own separate "Skill Tree" screen) --
## the always-visible per-line detail list below it already covers "what do
## I have right now" in full sentence form, so tap-to-inspect on individual
## nodes was dropped as redundant; nodes are purely visual (Panel, not
## Button) and sized up per user feedback that the tree read too small.

const NODE_SIZE := 60.0
const ROW_HEIGHT := 130.0
const TOP_PADDING := 70.0  # leaves room for the column header label above tier 1
const HEADER_HEIGHT := 34.0
const LINE_COLOR := Color(0.5, 0.5, 0.55, 0.6)
const LINE_WIDTH := 3.0

const COLOR_PICKED := Color(0.25, 0.85, 0.35, 1.0)
const COLOR_AVAILABLE := Color(1.0, 0.85, 0.3, 1.0)
const COLOR_LOCKED := Color(0.3, 0.3, 0.32, 1.0)

# (2026-07-16) The reference image draws tiers 3 and 4 almost identically for
# every element (confirmed by re-checking the source directly) -- at this
# node's render size that tiny art difference reads as "nothing changed."
# Rather than fight the source art, the capstone tier gets its own visual
# treatment so it's unmistakably the "ultimate" node regardless of how
# similar its icon looks to tier 3's. First pass used a gold border ring --
# user feedback was that the ring looked bad (and read as confusingly close
# to COLOR_AVAILABLE's own gold), so this is now just a size bump plus a
# subtle brightness lift on the node's own state color, no separate ring.
const CAPSTONE_TIER := 4
const CAPSTONE_NODE_SIZE := 74.0
const CAPSTONE_CONTRAST_LIFT := 0.22  # lerp the node's state color toward white by this much

# Column order and header tint matches the reference image left-to-right:
# Physical (gray), Fire (orange), Frost (blue), Lightning (purple).
const COLUMN_ORDER := [
	UpgradeResource.ElementType.PHYSICAL,
	UpgradeResource.ElementType.FIRE,
	UpgradeResource.ElementType.FROST,
	UpgradeResource.ElementType.LIGHTNING,
]
const COLUMN_NAMES := {
	UpgradeResource.ElementType.PHYSICAL: "Physical",
	UpgradeResource.ElementType.FIRE: "Fire",
	UpgradeResource.ElementType.FROST: "Frost",
	UpgradeResource.ElementType.LIGHTNING: "Lightning",
}
const COLUMN_COLORS := {
	UpgradeResource.ElementType.PHYSICAL: Color(0.85, 0.85, 0.85, 1.0),
	UpgradeResource.ElementType.FIRE: Color(1.0, 0.55, 0.2, 1.0),
	UpgradeResource.ElementType.FROST: Color(0.5, 0.8, 1.0, 1.0),
	UpgradeResource.ElementType.LIGHTNING: Color(0.75, 0.45, 1.0, 1.0),
}
const AREA_WIDTH := 660.0  # fixed rather than reading size.x -- this Control lives inside a ScrollContainer, whose child layout isn't settled the first time show_all() runs

var _player: Node
var _upgrade_pool: Array[UpgradeResource] = []
var _line_segments: Array = []  # Array[Array[Vector2]] -- [from, to] pairs for _draw()


func setup(player: Node, upgrade_pool: Array[UpgradeResource]) -> void:
	_player = player
	_upgrade_pool = upgrade_pool


func show_all() -> void:
	for child in get_children():
		child.queue_free()
	_line_segments.clear()
	if not is_instance_valid(_player):
		return

	var col_width: float = AREA_WIDTH / COLUMN_ORDER.size()
	custom_minimum_size.x = AREA_WIDTH
	var max_row_count := 0

	for col_index in COLUMN_ORDER.size():
		var element: int = COLUMN_ORDER[col_index]
		var center_x: float = col_index * col_width + col_width / 2.0
		var upgrades := _tier_sorted_upgrades(element)
		max_row_count = maxi(max_row_count, upgrades.size())
		_build_header(element, center_x)
		var current_tier: int = _current_tier_for(element)
		var prev_center: Vector2 = Vector2.ZERO
		var has_prev := false
		for upgrade in upgrades:
			var y: float = TOP_PADDING + HEADER_HEIGHT + (upgrade.tier - 1) * ROW_HEIGHT
			var center := Vector2(center_x, y)
			var state := _classify(upgrade, current_tier)
			_build_node(upgrade, state, center)
			if has_prev:
				_line_segments.append([prev_center, center])
			prev_center = center
			has_prev = true

	custom_minimum_size.y = TOP_PADDING + HEADER_HEIGHT + max_row_count * ROW_HEIGHT
	queue_redraw()


func _tier_sorted_upgrades(element: int) -> Array[UpgradeResource]:
	var result: Array[UpgradeResource] = []
	for upgrade in _upgrade_pool:
		if upgrade.element == element and upgrade.tier >= 1:
			result.append(upgrade)
	result.sort_custom(func(a, b): return a.tier < b.tier)
	return result


func _build_header(element: int, center_x: float) -> void:
	var label := Label.new()
	label.text = COLUMN_NAMES[element]
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", COLUMN_COLORS[element])
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(center_x - 70.0, TOP_PADDING - HEADER_HEIGHT)
	label.size = Vector2(140.0, HEADER_HEIGHT)
	add_child(label)


func _current_tier_for(element: int) -> int:
	if element == UpgradeResource.ElementType.PHYSICAL:
		return _player.get_physical_tier()
	return _player.get_element_tier(element)


func _classify(upgrade: UpgradeResource, current_tier: int) -> String:
	if upgrade.tier <= current_tier:
		return "picked"
	if upgrade.tier == current_tier + 1:
		return "available"
	return "locked"


func _build_node(upgrade: UpgradeResource, state: String, center: Vector2) -> void:
	var is_capstone: bool = upgrade.tier == CAPSTONE_TIER
	var node_size: float = CAPSTONE_NODE_SIZE if is_capstone else NODE_SIZE
	var node_bg := Panel.new()
	node_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node_bg.custom_minimum_size = Vector2(node_size, node_size)
	node_bg.position = center - Vector2(node_size, node_size) / 2.0
	node_bg.size = Vector2(node_size, node_size)
	var style := StyleBoxFlat.new()
	var base_color := _color_for(state)
	style.bg_color = base_color.lerp(Color.WHITE, CAPSTONE_CONTRAST_LIFT) if is_capstone else base_color
	style.set_corner_radius_all(int(node_size / 2.0))
	node_bg.add_theme_stylebox_override("panel", style)

	var icon := SkillIcon.new()
	icon.anchor_right = 1.0
	icon.anchor_bottom = 1.0
	icon.offset_left = 6.0
	icon.offset_top = 6.0
	icon.offset_right = -6.0
	icon.offset_bottom = -6.0
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = upgrade.icon
	icon.element = upgrade.element
	icon.modulate.a = 1.0 if state in ["picked", "available"] else 0.55
	node_bg.add_child(icon)

	add_child(node_bg)


func _color_for(state: String) -> Color:
	match state:
		"picked":
			return COLOR_PICKED
		"available":
			return COLOR_AVAILABLE
	return COLOR_LOCKED


func _draw() -> void:
	for segment in _line_segments:
		draw_line(segment[0], segment[1], LINE_COLOR, LINE_WIDTH)
