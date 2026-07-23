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
const CLASS_TIER_MAX := 3  # per-class active skill line, see CharacterClasses.CLASSES "skills"
const ROW_NAME_FONT_SIZE := 26
const ROW_STAT_FONT_SIZE := 20
const ROW_ICON_SIZE := 42

@onready var panel: Control = $Panel
@onready var resume_button: Button = $Panel/VBox/ResumeButton
@onready var restart_button: Button = $Panel/VBox/RestartButton
@onready var skills_button: Button = $Panel/VBox/SkillsButton
@onready var best_label: Label = $Panel/VBox/BestLabel
# (2026-07-16) One merged panel, not two -- the tree and the per-line skill
# detail used to be separate screens reached via a "View Tree" button; user
# asked for them combined. (2026-07-22) They now share the panel as two TABS
# rather than one long scroll: the tree got tall enough that the stat rows sat
# far below the fold, so switching between them beats scrolling past one to
# reach the other.
@onready var skill_panel: Control = $SkillPanel
@onready var tree_view: SkillTreeView = $SkillPanel/Margin/VBox/Scroll/ScrollVBox/TreeView
@onready var skill_rows_container: VBoxContainer = $SkillPanel/Margin/VBox/Scroll/ScrollVBox/RowsContainer
@onready var skill_back_button: Button = $SkillPanel/Margin/VBox/BackButton
@onready var skill_scroll: ScrollContainer = $SkillPanel/Margin/VBox/Scroll
@onready var tree_tab: Button = $SkillPanel/Margin/VBox/Tabs/TreeTab
@onready var stats_tab: Button = $SkillPanel/Margin/VBox/Tabs/StatsTab
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
	tree_tab.pressed.connect(_on_skill_tab_pressed.bind(true))
	stats_tab.pressed.connect(_on_skill_tab_pressed.bind(false))
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
	# Always open on the tree tab, so the panel doesn't remember a tab from a
	# previous pause and surprise the player with the wrong view.
	_show_skill_tab(true)


func _on_skill_tab_pressed(show_tree: bool) -> void:
	AudioManager.play_ui("ui_click")
	_show_skill_tab(show_tree)


func _show_skill_tab(show_tree: bool) -> void:
	# Two views sharing one ScrollContainer -- only one is ever visible, and the
	# scroll resets so the newly-shown tab always starts at the top rather than
	# inheriting the other tab's scroll offset.
	tree_view.visible = show_tree
	skill_rows_container.visible = not show_tree
	tree_tab.button_pressed = show_tree
	stats_tab.button_pressed = not show_tree
	skill_scroll.scroll_vertical = 0


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
	var c: Dictionary = CharacterClasses.CLASSES.get(player.active_class_id, {})
	var lines: Array[String] = ["Class: %s (%s)" % [c.get("display_name", "?"), c.get("description", "")]]
	lines.append(m.get("display_name", ""))
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
	skill_rows_container.add_child(_build_class_row(player))
	# (2026-07-23) Fusions were a plain text section; now that each one has real
	# art they get proper icon rows like every other line, so a fusion reads as
	# a skill the player owns rather than a footnote.
	var fusion_header := Label.new()
	fusion_header.add_theme_font_size_override("font_size", ROW_NAME_FONT_SIZE)
	fusion_header.add_theme_color_override("font_color", ElementFusions.FUSION_COLOR)
	fusion_header.text = "Elemental Fusions"
	skill_rows_container.add_child(fusion_header)
	for pid in ElementFusions.FUSIONS:
		skill_rows_container.add_child(_build_fusion_row(player, pid))


func _build_fusion_row(player: Node, pair_id: String) -> Control:
	# Mirrors _build_row()'s icon + name + detail shape, but a fusion has no
	# tiers and no SkillData -- it's on or off -- so it's built directly.
	var unlocked: bool = pair_id in player.active_fusions
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(ROW_ICON_SIZE, ROW_ICON_SIZE)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var ipath := ElementFusions.icon_path(pair_id)
	if ipath != "":
		icon.texture = load(ipath)
	# Locked fusions show their art dimmed, so the player can see what they're
	# working toward instead of a blank slot.
	icon.modulate = Color(1, 1, 1, 1) if unlocked else Color(0.4, 0.4, 0.45, 0.6)
	header.add_child(icon)

	var name_label := Label.new()
	name_label.add_theme_font_size_override("font_size", ROW_NAME_FONT_SIZE)
	name_label.text = "%s%s" % [ElementFusions.display_name(pair_id), "  (Active)" if unlocked else ""]
	name_label.add_theme_color_override("font_color", ElementFusions.FUSION_COLOR if unlocked else LOCKED_ROW_COLOR)
	header.add_child(name_label)
	row.add_child(header)

	var detail := Label.new()
	detail.add_theme_font_size_override("font_size", ROW_STAT_FONT_SIZE)
	detail.add_theme_color_override("font_color", STAT_LABEL_COLOR)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD
	if unlocked:
		detail.text = ElementFusions.description(pair_id)
	else:
		# The locked line is the only place the game explains how fusions are
		# earned, so it names both required lines and the exact tier.
		var els: Array = ElementFusions.FUSIONS[pair_id]["elements"]
		detail.text = "Locked — raise %s and %s to tier %d" % [str(els[0]).capitalize(), str(els[1]).capitalize(), player.FUSION_UNLOCK_TIER]
	row.add_child(detail)
	return row


func _build_physical_row(player: Node) -> Control:
	var skill: SkillData = player.get_current_physical_skill()
	var tier: int = player.get_physical_tier()
	return _build_row("Physical", skill, tier, PHYSICAL_TIER_MAX, 3, true, false, player)


func _build_element_row(player: Node, element: int) -> Control:
	var tier: int = player.get_element_tier(element)
	var skill: SkillData = player.get_current_skill_for_element(element) if tier > 0 else null
	var is_active: bool = tier > 0 and player.active_element == element
	return _build_row(ELEMENT_NAMES[element], skill, tier, ELEMENT_TIER_MAX, element, tier > 0, is_active, player)


func _build_class_row(player: Node) -> Control:
	# The per-class active skill line -- labeled by the player's class name
	# (e.g. "Sniper: Railshot") rather than a fixed element name. Never shows
	# "(Active)" since the class skill always auto-fires; there's no toggle.
	var tier: int = player.class_skill_level
	var skill: SkillData = player.get_current_class_skill() if tier > 0 else null
	var class_name_str: String = CharacterClasses.CLASSES.get(player.active_class_id, {}).get("display_name", "Class")
	return _build_row(class_name_str, skill, tier, CLASS_TIER_MAX, UpgradeResource.ElementType.CLASS, tier > 0, false, player)


func _build_row(line_name: String, skill: SkillData, tier: int, tier_max: int, icon_element: int, unlocked: bool, is_active: bool, player: Node) -> Control:
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
		stat_label.text = "Tier %d/%d  •  %s" % [tier, tier_max, _format_skill_stats(skill, player, icon_element)]
	else:
		stat_label.text = "Not yet unlocked"
	row.add_child(stat_label)

	return row


func _line_multipliers(player: Node, icon_element: int) -> Dictionary:
	# (2026-07-22) The EFFECTIVE multipliers each line fires with, mirroring
	# player.gd's own fire-time math -- see _refresh_elemental_timer()'s
	# `cooldown * maxf(*_skill_cd_mult, 0.3)`, _refresh_timer_cooldowns()'s
	# `cooldown * cooldown_mult`, and the `base_damage * <mult>` lines in the
	# fire paths. Class skills deal untyped physical damage, so they ride the
	# basic line's damage_mult/cooldown_mult.
	match icon_element:
		UpgradeResource.ElementType.FIRE:
			return {"dmg": player.fire_skill_dmg_mult, "cd": maxf(player.fire_skill_cd_mult, 0.3), "arrows": 0}
		UpgradeResource.ElementType.FROST:
			return {"dmg": player.frost_skill_dmg_mult, "cd": maxf(player.frost_skill_cd_mult, 0.3), "arrows": 0}
		UpgradeResource.ElementType.LIGHTNING:
			return {"dmg": player.lightning_skill_dmg_mult, "cd": maxf(player.lightning_skill_cd_mult, 0.3), "arrows": 0}
		UpgradeResource.ElementType.CLASS:
			return {"dmg": player.damage_mult, "cd": player.cooldown_mult, "arrows": 0}
	# PHYSICAL / basic line -- the only one "+1 Arrow" applies to.
	return {"dmg": player.damage_mult, "cd": player.cooldown_mult, "arrows": player.bonus_projectile_count}


func _format_skill_stats(skill: SkillData, player: Node, icon_element: int) -> String:
	# (2026-07-22) Shows what the skill ACTUALLY does right now, not the .tres
	# base values -- user report: "skill panel stats don't update when you take
	# a damage/cooldown upgrade." Upgrades never touch the shared SkillData
	# resources, they accumulate into the player's multipliers, so those have to
	# be folded in here or the panel reads as frozen for the whole run.
	var mults := _line_multipliers(player, icon_element)
	var dmg := roundi(skill.base_damage * float(mults["dmg"]))
	var cd := "%.1f" % (skill.cooldown * float(mults["cd"]))
	match skill.fire_mode:
		SkillData.FireMode.ARROW_RAIN:
			return "Damage %d  •  Cooldown %ss  •  %d zones" % [dmg, cd, skill.rain_arrow_count]
		SkillData.FireMode.TRAP_SHOT:
			return "Damage %d  •  Cooldown %ss  •  Lasts %.1fs" % [dmg, cd, skill.trap_duration]
		SkillData.FireMode.SELF_BURST:
			var s := "Damage %d  •  Cooldown %ss  •  Radius %d" % [dmg, cd, roundi(skill.trap_radius)]
			if skill.heal_on_cast > 0.0:
				s += "  •  Heals %d" % roundi(skill.heal_on_cast)
			return s
	var parts := "Damage %d  •  Cooldown %ss" % [dmg, cd]
	if skill.pierce_count > 0:
		parts += "  •  Pierce %d" % skill.pierce_count
	# Effective shot count, matching the fire path's own
	# mini(projectile_count + bonus_projectile_count, MAX_SHOT_COUNT) clamp so a
	# capped-out "+1 Arrow" stack never reads as more arrows than actually fire.
	var shots: int = mini(skill.projectile_count + int(mults["arrows"]), player.MAX_SHOT_COUNT)
	if shots > 1:
		parts += "  •  %d arrows" % shots
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
