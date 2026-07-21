extends CanvasLayer
class_name ClassSelectPopup

# Run-start class picker (Phase 4, final pillar). Shows once per run, before
# wave 1 gets to act: _ready() pauses via the standard GameManager source
# system ("class_select"), so the whole game (spawn timers included) waits
# frozen until a class is picked. Restarts re-show it naturally since both
# Restart buttons reload the whole scene. Rows are built in code from
# CharacterClasses.CLASSES (same dynamic-row pattern as pause_menu.gd's
# stats/skills panels) so adding a class later is a data-only change.

const ARCHER_PREVIEW := preload("res://art/characters/archer_idle_01.png")
const ROW_HEIGHT := 92.0
const PREVIEW_SIZE := 64.0

@onready var panel: Control = $Panel
@onready var rows: VBoxContainer = $Panel/VBox/Rows

var player: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("class_select_popup")
	player = get_tree().get_first_node_in_group("player")
	for class_id in CharacterClasses.CLASSES:
		rows.add_child(_build_row(class_id))
	panel.visible = true
	GameManager.request_pause("class_select")


func _build_row(class_id: String) -> Button:
	var c: Dictionary = CharacterClasses.CLASSES[class_id]
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	btn.pressed.connect(select_class.bind(class_id))

	var hbox := HBoxContainer.new()
	hbox.anchor_right = 1.0
	hbox.anchor_bottom = 1.0
	hbox.offset_left = 12.0
	hbox.offset_right = -12.0
	hbox.add_theme_constant_override("separation", 14)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(hbox)

	var preview := TextureRect.new()
	preview.texture = ARCHER_PREVIEW
	preview.custom_minimum_size = Vector2(PREVIEW_SIZE, PREVIEW_SIZE)
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.modulate = c["color"]
	preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(preview)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(text_box)

	var name_label := Label.new()
	name_label.text = c["display_name"]
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", Color(c["color"].r, c["color"].g, c["color"].b, 1.0))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = c["description"]
	desc_label.add_theme_font_size_override("font_size", 15)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(desc_label)

	return btn


func select_class(class_id: String) -> void:
	if is_instance_valid(player) and player.has_method("apply_class"):
		player.apply_class(class_id)
	AudioManager.play_ui("ui_click")
	panel.visible = false
	GameManager.request_unpause("class_select")
