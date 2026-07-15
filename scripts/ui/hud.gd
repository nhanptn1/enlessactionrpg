extends CanvasLayer
class_name HUD

@onready var hp_bar: ProgressBar = $Margin/VBox/HPBar
@onready var xp_bar: ProgressBar = $Margin/VBox/XPBar
@onready var level_label: Label = $Margin/VBox/LevelLabel
@onready var wave_label: Label = $Margin/VBox/WaveLabel
@onready var skill_label: Label = $Margin/VBox/SkillRow/SkillLabel
@onready var skill_cooldown: RadialCooldown = $Margin/VBox/SkillRow/SkillCooldown
@onready var elemental_rows_container: VBoxContainer = $Margin/VBox/ElementalSkillRows
@onready var pause_button: Button = $PauseButton
@onready var boss_hp_bar_container: MarginContainer = $BossHPBarContainer
@onready var boss_hp_bar: ProgressBar = $BossHPBarContainer/BossVBox/BossHPBar

var _player: Node
# Only one elemental row now (see Player.active_element) -- {ring, label, icon}
# once built, {} until the player's first elemental unlock.
var _elemental_row: Dictionary = {}


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	if _player:
		_player.hp_changed.connect(_on_player_hp_changed)
		_player.xp_changed.connect(_on_player_xp_changed)
		_player.level_up.connect(_on_player_level_up)
		_player.skill_unlocked.connect(_on_skill_unlocked)
		_player.elemental_skill_changed.connect(_on_elemental_skill_changed)
		_player.active_element_switched.connect(_on_active_element_switched)
		hp_bar.max_value = _player.max_hp
		hp_bar.value = _player.current_hp
		xp_bar.max_value = _player.xp_to_next_level()
		xp_bar.value = _player.xp
		level_label.text = "Lv. %d" % _player.level
		if _player.basic_shot:
			skill_label.text = _player.basic_shot.display_name
	var wave_manager := get_tree().get_first_node_in_group("wave_manager")
	if wave_manager:
		wave_manager.wave_started.connect(_on_wave_started)
	SignalBus.wave_started.connect(_on_signal_bus_wave_started)
	SignalBus.boss_hp_changed.connect(_on_boss_hp_changed)
	# Touch/mobile-friendly entry point for pausing -- the "pause" input
	# action (Escape) still works too, this is the on-screen equivalent.
	# No unpause branch needed here: while paused, HUD is frozen along with
	# every other default-process_mode gameplay node, so this button simply
	# can't be pressed again until PauseMenu's own Resume button unpauses.
	pause_button.pressed.connect(_on_pause_pressed)


func _process(_delta: float) -> void:
	# Polled rather than signal-driven -- BasicShotTimer has no per-tick
	# signal, and this naturally freezes along with every other
	# default-process_mode node while the game is paused.
	if not is_instance_valid(_player):
		return
	var timer: Timer = _player.attack_timer
	if timer.wait_time > 0.0:
		skill_cooldown.value = 1.0 - (timer.time_left / timer.wait_time)
	if not _elemental_row.is_empty() and _player.active_element != -1:
		var elemental_timer: Timer = _player.get_elemental_timer_by_element(_player.active_element)
		if is_instance_valid(elemental_timer) and elemental_timer.wait_time > 0.0:
			_elemental_row.ring.value = 1.0 - (elemental_timer.time_left / elemental_timer.wait_time)


func _on_pause_pressed() -> void:
	AudioManager.play_ui("ui_click")
	GameManager.request_pause("pause_menu")


func _on_player_hp_changed(current: float, max_hp: float) -> void:
	hp_bar.max_value = max_hp
	hp_bar.value = current


func _on_player_xp_changed(current: int, needed: int) -> void:
	xp_bar.max_value = needed
	xp_bar.value = current


func _on_player_level_up(new_level: int) -> void:
	level_label.text = "Lv. %d" % new_level


func _on_skill_unlocked(skill: SkillData) -> void:
	# Elemental changes also fire this (for LevelUpPopup's generic "X
	# Unlocked!" banner) but are tracked here via elemental_skill_changed
	# instead, which is keyed by element rather than by SkillData reference --
	# a SkillData reference isn't stable across an element's own tier swaps.
	if skill in _player.fire_skills or skill in _player.frost_skills or skill in _player.lightning_skills:
		return
	skill_label.text = skill.display_name


func _on_elemental_skill_changed(element: int, skill: SkillData) -> void:
	# Fires on every tier pick regardless of which element is active (see
	# Player.elemental_skill_changed) -- only refresh the row if it's showing
	# this element right now. A switch to a different element is handled by
	# _on_active_element_switched instead.
	if element != _player.active_element:
		return
	_show_elemental_skill(skill)


func _on_active_element_switched(_element: int, skill: SkillData) -> void:
	_show_elemental_skill(skill)


func _show_elemental_skill(skill: SkillData) -> void:
	if _elemental_row.is_empty():
		_build_elemental_row(skill)
	else:
		_elemental_row.label.text = skill.display_name
		_elemental_row.icon.texture = skill.icon


func _build_elemental_row(skill: SkillData) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	# Icon and cooldown ring are stacked in the same 32x32 rect (icon behind,
	# ring drawn on top) rather than placed side by side, matching a typical
	# "ability icon with a cooldown sweep" UI convention. It's a flat/borderless
	# Button (not a plain Control) so tapping it cycles the active element via
	# switch_active_element() -- the only way to swap once >1 element is
	# unlocked, since all 3 trees can be invested in simultaneously now.
	var icon_stack := Button.new()
	icon_stack.flat = true
	icon_stack.focus_mode = Control.FOCUS_NONE
	icon_stack.custom_minimum_size = Vector2(32, 32)
	icon_stack.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_stack.pressed.connect(func(): _player.switch_active_element())
	var icon := TextureRect.new()
	icon.texture = skill.icon
	icon.anchor_right = 1.0
	icon.anchor_bottom = 1.0
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	# Without this, TextureRect defaults to EXPAND_KEEP_SIZE and reports the
	# source texture's full native pixel size (~260x260) as its own minimum
	# size, which blows the whole row up to that size regardless of the
	# anchors set above -- this is what caused the giant icon.
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ring := RadialCooldown.new()
	ring.anchor_right = 1.0
	ring.anchor_bottom = 1.0
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_stack.add_child(icon)
	icon_stack.add_child(ring)
	var label := Label.new()
	label.text = skill.display_name
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(1, 0.85, 0.4, 1))
	row.add_child(icon_stack)
	row.add_child(label)
	elemental_rows_container.add_child(row)
	_elemental_row = {"ring": ring, "label": label, "icon": icon}


func _on_wave_started(wave_number: int) -> void:
	wave_label.text = "Wave %d" % wave_number


func _on_signal_bus_wave_started(_wave_number: int, is_boss: bool) -> void:
	boss_hp_bar_container.visible = is_boss


func _on_boss_hp_changed(current: float, max_hp: float) -> void:
	boss_hp_bar.max_value = max_hp
	boss_hp_bar.value = current
