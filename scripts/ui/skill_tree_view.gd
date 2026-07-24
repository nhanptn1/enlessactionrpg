extends Control
class_name SkillTreeView
## Draws all 4 skill lines (Physical/Fire/Frost/Lightning) as 4 side-by-side
## columns, each a single straight vertical chain of nodes -- matches the
## user-supplied reference image (image/skills/skill-trees.png): one line per
## column, no branching. Originally 4 tiers each; Physical since grew to 6
## (Trap Shot's capstone split into 3 progressive tiers), so column height is
## driven by however many tiers that column's own data actually has, not a
## shared constant. (2026-07-16) Now the top half
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
# (2026-07-16) No longer a fixed tier number -- Physical grew to 6 tiers while
# Fire/Frost/Lightning stayed at 4, so "capstone" is now whichever tier is
# highest for that specific column (see show_all()), not a shared constant.
const FUSION_BAND_TOP_GAP := 18.0  # breathing room between the last tier row and the fusion band
const FUSION_LABEL_HEIGHT := 40.0  # two lines of wrapped name under each fusion node
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

	# (2026-07-21) 5th column: the player's own class-skill tree. Only the
	# active class's column ever shows (its upgrades are class-gated in
	# _tier_sorted_upgrades below), headed by the class's name/color instead
	# of a fixed element label.
	var columns: Array = COLUMN_ORDER.duplicate()
	columns.append(UpgradeResource.ElementType.CLASS)
	var col_width: float = AREA_WIDTH / columns.size()
	custom_minimum_size.x = AREA_WIDTH
	var max_row_count := 0

	for col_index in columns.size():
		var element: int = columns[col_index]
		var center_x: float = col_index * col_width + col_width / 2.0
		var upgrades := _tier_sorted_upgrades(element)
		max_row_count = maxi(max_row_count, upgrades.size())
		_build_header(element, center_x)
		var current_tier: int = _current_tier_for(element)
		var column_max_tier: int = upgrades[-1].tier if not upgrades.is_empty() else 0
		var prev_center: Vector2 = Vector2.ZERO
		var has_prev := false
		for upgrade in upgrades:
			var y: float = TOP_PADDING + HEADER_HEIGHT + (upgrade.tier - 1) * ROW_HEIGHT
			var center := Vector2(center_x, y)
			var state := _classify(upgrade, current_tier)
			_build_node(upgrade, state, center, upgrade.tier == column_max_tier)
			if has_prev:
				_line_segments.append([prev_center, center])
			prev_center = center
			has_prev = true

	var columns_bottom: float = TOP_PADDING + HEADER_HEIGHT + max_row_count * ROW_HEIGHT
	custom_minimum_size.y = columns_bottom + _build_fusion_band(columns_bottom)
	queue_redraw()


# (2026-07-24) Fusions had no representation here at all. The Skills panel
# always opens on this tree (see PauseMenu.open_skills_panel), the tree drew
# only Physical/Fire/Frost/Lightning/class, and the fusion rows built in entry
# 87 live on the OTHER tab -- which is hidden by default. So a player who
# opened the panel saw no fusions anywhere and reasonably concluded the game
# wasn't showing them ("the skill panel still not display the fusion skill").
# The rows were never broken, just unreachable without knowing to tap a tab.
#
# Drawn as a horizontal BAND rather than a 6th column because a fusion has no
# tiers to stack -- it is unlocked or not, then equipped or not, so a
# column-of-nodes shape would misrepresent it as a progression.
func _build_fusion_band(top_y: float) -> float:
	var ids: Array = ElementFusions.FUSIONS.keys()
	if ids.is_empty():
		return 0.0
	var header := Label.new()
	header.text = "Elemental Fusions"
	header.add_theme_font_size_override("font_size", 22)
	header.add_theme_color_override("font_color", ElementFusions.FUSION_COLOR)
	header.position = Vector2(0.0, top_y + FUSION_BAND_TOP_GAP)
	header.size = Vector2(AREA_WIDTH, HEADER_HEIGHT)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(header)

	var slot_width: float = AREA_WIDTH / ids.size()
	var node_y: float = top_y + FUSION_BAND_TOP_GAP + HEADER_HEIGHT + NODE_SIZE / 2.0
	for i in ids.size():
		var pid: String = ids[i]
		var unlocked: bool = pid in _player.active_fusions
		var active: bool = _player.active_fusion_id == pid
		var center := Vector2(i * slot_width + slot_width / 2.0, node_y)
		_build_fusion_node(pid, center, unlocked, active)
	return FUSION_BAND_TOP_GAP + HEADER_HEIGHT + NODE_SIZE + FUSION_LABEL_HEIGHT


func _build_fusion_node(pair_id: String, center: Vector2, unlocked: bool, active: bool) -> void:
	var node := Panel.new()
	var style := StyleBoxFlat.new()
	# Same three-state language the tier nodes use: green = yours, gold =
	# available/equipped, grey = locked.
	style.bg_color = (COLOR_AVAILABLE if active else COLOR_PICKED) if unlocked else COLOR_LOCKED
	style.corner_radius_top_left = int(NODE_SIZE / 2.0)
	style.corner_radius_top_right = int(NODE_SIZE / 2.0)
	style.corner_radius_bottom_left = int(NODE_SIZE / 2.0)
	style.corner_radius_bottom_right = int(NODE_SIZE / 2.0)
	node.add_theme_stylebox_override("panel", style)
	node.size = Vector2(NODE_SIZE, NODE_SIZE)
	node.position = center - Vector2(NODE_SIZE, NODE_SIZE) / 2.0
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(node)

	var icon := TextureRect.new()
	icon.texture = load(ElementFusions.icon_path(pair_id))
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size = Vector2(NODE_SIZE, NODE_SIZE) * 0.78
	icon.position = center - icon.size / 2.0
	# Locked fusions show their art dimmed, so the player can see what they are
	# working toward rather than a blank slot -- same treatment the stats tab uses.
	icon.modulate = Color(1, 1, 1, 1) if unlocked else Color(1, 1, 1, 0.35)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(icon)

	var label := Label.new()
	label.text = ElementFusions.display_name(pair_id)
	if active:
		label.text += " (Active)"
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", ElementFusions.FUSION_COLOR if unlocked else COLOR_LOCKED)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.size = Vector2(AREA_WIDTH / float(ElementFusions.FUSIONS.size()), FUSION_LABEL_HEIGHT)
	label.position = Vector2(center.x - label.size.x / 2.0, center.y + NODE_SIZE / 2.0 + 4.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)


func _tier_sorted_upgrades(element: int) -> Array[UpgradeResource]:
	var result: Array[UpgradeResource] = []
	for upgrade in _upgrade_pool:
		if upgrade.element != element or upgrade.tier < 1:
			continue
		# The CLASS column shows only the player's own class's tree.
		if element == UpgradeResource.ElementType.CLASS and upgrade.required_class != _player.active_class_id:
			continue
		result.append(upgrade)
	result.sort_custom(func(a, b): return a.tier < b.tier)
	return result


func _build_header(element: int, center_x: float) -> void:
	var label := Label.new()
	if element == UpgradeResource.ElementType.CLASS:
		var c: Dictionary = CharacterClasses.CLASSES.get(_player.active_class_id, {})
		label.text = c.get("display_name", "Class")
		var col: Color = c.get("color", Color.WHITE)
		label.add_theme_color_override("font_color", Color(col.r, col.g, col.b, 1.0))
	else:
		label.text = COLUMN_NAMES[element]
		label.add_theme_color_override("font_color", COLUMN_COLORS[element])
	label.add_theme_font_size_override("font_size", 22)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(center_x - 70.0, TOP_PADDING - HEADER_HEIGHT)
	label.size = Vector2(140.0, HEADER_HEIGHT)
	add_child(label)


func _current_tier_for(element: int) -> int:
	if element == UpgradeResource.ElementType.PHYSICAL:
		return _player.get_physical_tier()
	if element == UpgradeResource.ElementType.CLASS:
		return _player.class_skill_level
	return _player.get_element_tier(element)


func _classify(upgrade: UpgradeResource, current_tier: int) -> String:
	if upgrade.tier <= current_tier:
		return "picked"
	if upgrade.tier == current_tier + 1:
		return "available"
	return "locked"


func _build_node(upgrade: UpgradeResource, state: String, center: Vector2, is_capstone: bool) -> void:
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
