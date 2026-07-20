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
const PHYSICAL_TIER_MAX := 6  # Trap Shot's capstone split into 3 progressive tiers -- see wave_upgrade_popup.gd::_max_tier_for()
const ELEMENT_TIER_MAX := 5  # (2026-07-17) grew by 1 for the tier-5 capstone passive, see wave_upgrade_popup.gd::_max_tier_for()
const ROW_NAME_FONT_SIZE := 26
const ROW_STAT_FONT_SIZE := 20
const ROW_ICON_SIZE := 42

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
@onready var stats_button: Button = $Panel/VBox/StatsButton
@onready var stats_panel: Control = $StatsPanel
@onready var stats_rows_container: VBoxContainer = $StatsPanel/Margin/VBox/Scroll/RowsContainer
@onready var stats_back_button: Button = $StatsPanel/Margin/VBox/BackButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("pause_menu")  # lets the HUD's Skill button jump straight to the skill panel, see open_skills_panel()
	panel.visible = false
	skill_panel.visible = false
	resume_button.pressed.connect(_on_resume_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	skills_button.pressed.connect(_on_skills_pressed)
	skill_back_button.pressed.connect(_on_skill_back_pressed)
	stats_button.pressed.connect(_on_stats_pressed)
	stats_back_button.pressed.connect(_on_stats_back_pressed)
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
	stats_panel.visible = false


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


func _on_stats_pressed() -> void:
	AudioManager.play_ui("ui_click")
	panel.visible = false
	stats_panel.visible = true
	_build_stats_rows()


func _on_stats_back_pressed() -> void:
	AudioManager.play_ui("ui_click")
	stats_panel.visible = false
	panel.visible = true


# Live totals only -- every value here is read straight off the player
# instance, so it already reflects meta upgrades, in-run picks, and equipped
# items combined (they all fold into the same vars; see player.gd), rather
# than trying to re-derive a breakdown per source.
func _build_stats_rows() -> void:
	for child in stats_rows_container.get_children():
		child.queue_free()
	var player := get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player):
		return
	stats_rows_container.add_child(_build_stats_section("Core", _core_stat_lines(player)))
	if player.active_run_modifier_id != "":
		stats_rows_container.add_child(_build_stats_section("Run Modifier", _run_modifier_stat_lines(player)))
	if player.physical_level >= 4:
		stats_rows_container.add_child(_build_stats_section("Physical", _physical_stat_lines(player)))
	for element in [UpgradeResource.ElementType.FIRE, UpgradeResource.ElementType.FROST, UpgradeResource.ElementType.LIGHTNING]:
		var tier: int = player.get_element_tier(element)
		if tier > 0:
			stats_rows_container.add_child(_build_stats_section(ELEMENT_NAMES[element], _element_stat_lines(player, element)))


func _build_stats_section(title: String, lines: Array[String]) -> Control:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 4)

	var header := Label.new()
	header.add_theme_font_size_override("font_size", ROW_NAME_FONT_SIZE)
	header.add_theme_color_override("font_color", ACTIVE_ROW_COLOR)
	header.text = title
	section.add_child(header)

	for line in lines:
		var line_label := Label.new()
		line_label.add_theme_font_size_override("font_size", ROW_STAT_FONT_SIZE)
		line_label.add_theme_color_override("font_color", STAT_LABEL_COLOR)
		line_label.text = line
		section.add_child(line_label)

	return section


func _core_stat_lines(player: Node) -> Array[String]:
	var lines: Array[String] = [
		"HP: %d / %d" % [roundi(player.current_hp), roundi(player.max_hp)],
		"Damage: +%d%%" % roundi((player.damage_mult - 1.0) * 100.0),
		"Attack Speed: +%d%%" % roundi((1.0 / player.cooldown_mult - 1.0) * 100.0),
		"Crit Chance: %d%%" % roundi(player.crit_chance * 100.0),
		"Projectile Speed: +%d%%" % roundi((player.projectile_speed_mult - 1.0) * 100.0),
		"XP Gain: +%d%%" % roundi((player.xp_gain_mult - 1.0) * 100.0),
	]
	if player.bonus_projectile_count > 0:
		lines.append("Bonus Arrows: +%d" % player.bonus_projectile_count)
	return lines


func _run_modifier_stat_lines(player: Node) -> Array[String]:
	var m: Dictionary = RunModifiers.MODIFIERS.get(player.active_run_modifier_id, {})
	var lines: Array[String] = [m.get("display_name", "")]
	if m.has("description"):
		lines.append(m["description"])
	return lines


func _physical_stat_lines(player: Node) -> Array[String]:
	return ["Trap Detonate Bonus: +%d%%" % roundi(player.physical_trap_detonate_mult * 100.0)]


func _element_stat_lines(player: Node, element: int) -> Array[String]:
	var lines: Array[String] = []
	match element:
		UpgradeResource.ElementType.FIRE:
			lines.append("Skill Damage: +%d%%" % roundi((player.fire_skill_dmg_mult - 1.0) * 100.0))
			lines.append("Skill Cooldown: -%d%%" % roundi((1.0 - maxf(player.fire_skill_cd_mult, 0.3)) * 100.0))
			if player.fire_spread_chance > 0.0 and player.fire_level < 5:
				lines.append("Spread Chance: %d%%" % roundi(player.fire_spread_chance * 100.0))
			if player.fire_dps_mult > 1.0:
				lines.append("Burn DPS: +%d%%" % roundi((player.fire_dps_mult - 1.0) * 100.0))
			if player.fire_explode_on_death > 0.0:
				lines.append("Explodes on Death")
			if player.fire_duration_bonus > 0.0:
				lines.append("Burn Duration: +%.1fs" % player.fire_duration_bonus)
			if player.fire_level >= 5:
				lines.append("Capstone: Inferno Heart (guaranteed spread, +50% burn)")
		UpgradeResource.ElementType.FROST:
			lines.append("Skill Damage: +%d%%" % roundi((player.frost_skill_dmg_mult - 1.0) * 100.0))
			lines.append("Skill Cooldown: -%d%%" % roundi((1.0 - maxf(player.frost_skill_cd_mult, 0.3)) * 100.0))
			if player.frost_duration_bonus > 0.0:
				lines.append("Slow Duration: +%.1fs" % player.frost_duration_bonus)
			if player.frost_damage_amp > 0.0:
				lines.append("Damage Amp vs Slowed: +%d%%" % roundi(player.frost_damage_amp * 100.0))
			if player.frost_spread_chance > 0.0 and player.frost_level < 5:
				lines.append("Spread Chance: %d%%" % roundi(player.frost_spread_chance * 100.0))
			if player.frost_combo_bonus_mult > 0.0:
				lines.append("Combo Bonus: +%d%%" % roundi(player.frost_combo_bonus_mult * 100.0))
			if player.frost_level >= 5:
				lines.append("Capstone: Absolute Zero (guaranteed spread, 2x combo damage)")
		UpgradeResource.ElementType.LIGHTNING:
			lines.append("Skill Damage: +%d%%" % roundi((player.lightning_skill_dmg_mult - 1.0) * 100.0))
			lines.append("Skill Cooldown: -%d%%" % roundi((1.0 - maxf(player.lightning_skill_cd_mult, 0.3)) * 100.0))
			if player.lightning_slow_bonus > 0.0:
				lines.append("Slow Bonus: +%d%%" % roundi(player.lightning_slow_bonus * 100.0))
			if player.lightning_dps > 0.0:
				lines.append("Shock DPS: +%d" % roundi(player.lightning_dps))
			if player.lightning_spread_chance > 0.0 and player.lightning_level < 5:
				lines.append("Spread Chance: %d%%" % roundi(player.lightning_spread_chance * 100.0))
			if player.lightning_combo_bonus_mult > 0.0:
				lines.append("Combo Bonus: +%d%%" % roundi(player.lightning_combo_bonus_mult * 100.0))
			if player.lightning_level >= 5:
				lines.append("Capstone: Overcharge (guaranteed spread, 2x Superconductor damage)")
	return lines


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
