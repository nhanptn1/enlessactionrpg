extends CanvasLayer
class_name PauseMenu

const ACTIVE_ROW_COLOR := Color(1, 0.85, 0.4, 1)
const LOCKED_ROW_COLOR := Color(0.55, 0.55, 0.55, 1)
const STAT_LABEL_COLOR := Color(0.85, 0.85, 0.85, 1)
const ELEMENT_NAMES := {
	UpgradeResource.ElementType.FIRE: "Fire",
	UpgradeResource.ElementType.FROST: "Frost",
	UpgradeResource.ElementType.LIGHTNING: "Lightning",
}
const PHYSICAL_TIER_MAX := 4
const ELEMENT_TIER_MAX := 4
const ROW_NAME_FONT_SIZE := 22
const ROW_STAT_FONT_SIZE := 17
const ROW_ICON_SIZE := 38

@onready var panel: Control = $Panel
@onready var resume_button: Button = $Panel/VBox/ResumeButton
@onready var restart_button: Button = $Panel/VBox/RestartButton
@onready var skills_button: Button = $Panel/VBox/SkillsButton
@onready var best_label: Label = $Panel/VBox/BestLabel
# (2026-07-16) One merged panel now, not two -- the tree (top) and the
# per-line skill detail (bottom) used to be separate screens reached via a
# "View Tree" button; user asked for them combined into a single scrollable
# view instead.
@onready var skill_panel: Control = $SkillPanel
@onready var tree_view: SkillTreeView = $SkillPanel/Margin/VBox/Scroll/ScrollVBox/TreeView
@onready var skill_rows_container: VBoxContainer = $SkillPanel/Margin/VBox/Scroll/ScrollVBox/RowsContainer
@onready var skill_back_button: Button = $SkillPanel/Margin/VBox/BackButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("pause_menu")  # lets the HUD's Skill button jump straight to the skill panel, see open_skills_panel()
	panel.visible = false
	skill_panel.visible = false
	resume_button.pressed.connect(_on_resume_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	skills_button.pressed.connect(_on_skills_pressed)
	skill_back_button.pressed.connect(_on_skill_back_pressed)
	SignalBus.game_paused.connect(_on_game_paused)
	SignalBus.game_unpaused.connect(_on_game_unpaused)
	_update_best_label()


func _on_game_paused(source: String) -> void:
	if source != "pause_menu":
		return
	panel.visible = true
	_update_best_label()


func _on_game_unpaused(_source: String) -> void:
	panel.visible = false
	skill_panel.visible = false


func _on_skills_pressed() -> void:
	AudioManager.play_ui("ui_click")
	open_skills_panel()


# (2026-07-16) Public entry point so the HUD's own Skill button can jump
# straight to this panel without going through the main pause menu first --
# the HUD button still pauses via the same "pause_menu" source (see
# hud.gd::_on_skill_button_pressed()), which makes _on_game_paused() show
# `panel` first; always forcing it back to hidden here (not just when called
# from _on_skills_pressed(), which already had it hidden) keeps this correct
# regardless of caller.
func open_skills_panel() -> void:
	panel.visible = false
	skill_panel.visible = true
	var player := get_tree().get_first_node_in_group("player")
	var wave_popup := get_tree().get_first_node_in_group("wave_upgrade_popup")
	if is_instance_valid(player) and is_instance_valid(wave_popup):
		tree_view.setup(player, wave_popup.upgrade_pool)
		tree_view.show_all()
	_build_skill_rows()


func _on_skill_back_pressed() -> void:
	AudioManager.play_ui("ui_click")
	skill_panel.visible = false
	panel.visible = true


func _build_skill_rows() -> void:
	for child in skill_rows_container.get_children():
		child.queue_free()
	var player := get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player):
		return
	skill_rows_container.add_child(_build_physical_row(player))
	for element in [UpgradeResource.ElementType.FIRE, UpgradeResource.ElementType.FROST, UpgradeResource.ElementType.LIGHTNING]:
		skill_rows_container.add_child(_build_element_row(player, element))


func _build_physical_row(player: Node) -> Control:
	var skill: SkillData = player.get_current_physical_skill()
	var tier: int = player.get_physical_tier()
	return _build_row("Physical", skill, tier, PHYSICAL_TIER_MAX, 3, true, false)


func _build_element_row(player: Node, element: int) -> Control:
	var tier: int = player.get_element_tier(element)
	var skill: SkillData = player.get_current_skill_for_element(element) if tier > 0 else null
	var is_active: bool = tier > 0 and player.active_element == element
	return _build_row(ELEMENT_NAMES[element], skill, tier, ELEMENT_TIER_MAX, element, tier > 0, is_active)


func _build_row(line_name: String, skill: SkillData, tier: int, tier_max: int, icon_element: int, unlocked: bool, is_active: bool) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	var icon := SkillIcon.new()
	icon.custom_minimum_size = Vector2(ROW_ICON_SIZE, ROW_ICON_SIZE)
	icon.element = icon_element
	if unlocked and skill != null:
		icon.texture = skill.icon
	header.add_child(icon)

	var name_label := Label.new()
	name_label.add_theme_font_size_override("font_size", ROW_NAME_FONT_SIZE)
	if unlocked and skill != null:
		name_label.text = "%s: %s" % [line_name, skill.display_name]
		name_label.add_theme_color_override("font_color", ACTIVE_ROW_COLOR if is_active else Color(1, 1, 1, 1))
		if is_active:
			name_label.text += "  (Active)"
	else:
		name_label.text = "%s: Locked" % line_name
		name_label.add_theme_color_override("font_color", LOCKED_ROW_COLOR)
	header.add_child(name_label)
	row.add_child(header)

	var stat_label := Label.new()
	stat_label.add_theme_font_size_override("font_size", ROW_STAT_FONT_SIZE)
	stat_label.add_theme_color_override("font_color", STAT_LABEL_COLOR)
	if unlocked and skill != null:
		stat_label.text = "Tier %d/%d  •  %s" % [tier, tier_max, _format_skill_stats(skill)]
	else:
		stat_label.text = "Not yet unlocked"
	row.add_child(stat_label)

	return row


func _format_skill_stats(skill: SkillData) -> String:
	var dmg := roundi(skill.base_damage)
	var cd := "%.1f" % skill.cooldown
	match skill.fire_mode:
		SkillData.FireMode.ARROW_RAIN:
			return "Damage %d  •  Cooldown %ss  •  %d zones" % [dmg, cd, skill.rain_arrow_count]
		SkillData.FireMode.TRAP_SHOT:
			return "Damage %d  •  Cooldown %ss  •  Lasts %.1fs" % [dmg, cd, skill.trap_duration]
	var parts := "Damage %d  •  Cooldown %ss" % [dmg, cd]
	if skill.pierce_count > 0:
		parts += "  •  Pierce %d" % skill.pierce_count
	if skill.projectile_count > 1:
		parts += "  •  %d arrows" % skill.projectile_count
	if skill.burst_radius > 0.0:
		parts += "  •  Splash %d" % roundi(skill.burst_radius)
	if skill.chain_count > 0:
		parts += "  •  Chains %d" % skill.chain_count
	return parts


func _on_resume_pressed() -> void:
	AudioManager.play_ui("ui_click")
	GameManager.request_unpause("pause_menu")


func _on_restart_pressed() -> void:
	AudioManager.play_ui("ui_click")
	GameManager.reset_state()
	get_tree().reload_current_scene()


func _update_best_label() -> void:
	best_label.text = "Best: Wave %d — Level %d" % [SaveManager.best_wave, SaveManager.best_level]
