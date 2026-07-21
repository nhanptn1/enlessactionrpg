extends CanvasLayer
class_name HUD

@onready var heart_hp: HeartHPDisplay = $HeartHP
@onready var hp_bar: ProgressBar = $HPBar
@onready var xp_bar: ProgressBar = $Margin/VBox/XPBar
@onready var level_label: Label = $Margin/VBox/LevelLabel
@onready var wave_label: Label = $Margin/VBox/WaveLabel
@onready var modifier_label: Label = $Margin/VBox/ModifierLabel
@onready var ultimate_label: Label = $Margin/VBox/UltimateLabel
# Matches the element colors used across the HUD/skill tree (fire orange,
# frost blue, lightning purple), as bbcode hex for ElementCycleLabel.
const ELEMENT_BBCODE_COLORS := {
	"fire": "#ff8c33",
	"frost": "#80ccff",
	"lightning": "#bf73ff",
}

@onready var element_cycle_label: RichTextLabel = $ElementCycleLabel
@onready var dash_button: Button = $ActionButtons/DashCell/DashButton
@onready var ultimate_cell: VBoxContainer = $ActionButtons/UltimateCell
@onready var ultimate_button: Button = $ActionButtons/UltimateCell/UltimateButton
@onready var ultimate_button_icon: TextureRect = $ActionButtons/UltimateCell/UltimateButton/Icon
@onready var skill_label: Label = $Margin/VBox/SkillRow/SkillLabel
@onready var skill_icon: TextureRect = $Margin/VBox/SkillRow/SkillIconStack/Icon
@onready var skill_cooldown: RadialCooldown = $Margin/VBox/SkillRow/SkillIconStack/SkillCooldown
@onready var elemental_rows_container: VBoxContainer = $Margin/VBox/ElementalSkillRows
@onready var pause_button: Button = $PauseButton
@onready var skill_button: Button = $SkillButton
@onready var boss_hp_bar_container: MarginContainer = $Margin/VBox/BossHPBarContainer
@onready var boss_hp_bar: ProgressBar = $Margin/VBox/BossHPBarContainer/BossVBox/BossHPBar
@onready var boss_label: Label = $Margin/VBox/BossHPBarContainer/BossVBox/BossLabel
@onready var equip_slots: Dictionary = {
	"weapon": $Margin/VBox/EquipmentRow/WeaponSlot,
	"armor": $Margin/VBox/EquipmentRow/ArmorSlot,
	"accessory": $Margin/VBox/EquipmentRow/AccessorySlot,
}

const ACTIVE_ROW_MODULATE := Color(1, 1, 1, 1)
const INACTIVE_ROW_MODULATE := Color(1, 1, 1, 0.45)  # dim, but still tappable -- read as "unlocked, not active"

var _player: Node
# One row per unlocked element (int -> {ring, label, icon, row}) -- each is
# independently tappable to make that element the active one (see
# Player.select_active_element()). The active element's row is full
# brightness with a live cooldown ring; the others are dimmed and static.
var _elemental_rows: Dictionary = {}


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	if _player:
		_player.hp_changed.connect(_on_player_hp_changed)
		_player.xp_changed.connect(_on_player_xp_changed)
		_player.level_up.connect(_on_player_level_up)
		_player.skill_unlocked.connect(_on_skill_unlocked)
		_player.elemental_skill_changed.connect(_on_elemental_skill_changed)
		_player.active_element_switched.connect(_on_active_element_switched)
		_player.equipment_changed.connect(_on_equipment_changed)
		for slot in _player.equipped:
			if _player.equipped[slot] != null:
				_on_equipment_changed(slot, _player.equipped[slot])
		heart_hp.current_hp = roundi(_player.current_hp)
		hp_bar.max_value = _player.max_hp
		hp_bar.value = _player.current_hp
		xp_bar.max_value = _player.xp_to_next_level()
		xp_bar.value = _player.xp
		level_label.text = "Lv. %d" % _player.level
		if _player.active_run_modifier_id != "":
			var m: Dictionary = RunModifiers.MODIFIERS.get(_player.active_run_modifier_id, {})
			modifier_label.text = m.get("display_name", "")
			modifier_label.tooltip_text = m.get("description", "")
		if _player.basic_shot:
			skill_label.text = _player.basic_shot.display_name
			skill_icon.texture = _player.basic_shot.icon
	# Icon and cooldown ring stacked in the same 32x32 rect, same pattern as
	# the elemental rows (icon_stack in _build_elemental_row()) -- set here
	# in code rather than the .tscn since expand_mode matters: TextureRect
	# defaults to EXPAND_KEEP_SIZE, which reports the source icon's full
	# native pixel size as its own minimum size and blows up the whole row.
	skill_icon.anchor_right = 1.0
	skill_icon.anchor_bottom = 1.0
	skill_icon.stretch_mode = TextureRect.STRETCH_SCALE
	skill_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	skill_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skill_cooldown.anchor_right = 1.0
	skill_cooldown.anchor_bottom = 1.0
	skill_cooldown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wave_manager := get_tree().get_first_node_in_group("wave_manager")
	if wave_manager:
		wave_manager.wave_started.connect(_on_wave_started)
	SignalBus.wave_started.connect(_on_signal_bus_wave_started)
	SignalBus.boss_hp_changed.connect(_on_boss_hp_changed)
	SignalBus.boss_mutation_announced.connect(_on_boss_mutation_announced)
	SignalBus.boss_affinity_announced.connect(_on_boss_affinity_announced)
	# Touch/mobile-friendly entry point for pausing -- the "pause" input
	# action (Escape) still works too, this is the on-screen equivalent.
	# No unpause branch needed here: while paused, HUD is frozen along with
	# every other default-process_mode gameplay node, so this button simply
	# can't be pressed again until PauseMenu's own Resume button unpauses.
	pause_button.pressed.connect(_on_pause_pressed)
	skill_button.pressed.connect(_on_skill_button_pressed)
	ultimate_button.pressed.connect(_on_ultimate_button_pressed)
	dash_button.pressed.connect(_on_dash_button_pressed)


func _process(_delta: float) -> void:
	# Polled rather than signal-driven -- BasicShotTimer has no per-tick
	# signal, and this naturally freezes along with every other
	# default-process_mode node while the game is paused.
	if not is_instance_valid(_player):
		return
	var timer: Timer = _player.attack_timer
	if timer.wait_time > 0.0:
		skill_cooldown.value = 1.0 - (timer.time_left / timer.wait_time)
	if _player.active_element != -1 and _elemental_rows.has(_player.active_element):
		var elemental_timer: Timer = _player.get_elemental_timer_by_element(_player.active_element)
		if is_instance_valid(elemental_timer) and elemental_timer.wait_time > 0.0:
			_elemental_rows[_player.active_element].ring.value = 1.0 - (elemental_timer.time_left / elemental_timer.wait_time)
	# Ultimate charge readout + on-screen cast button -- polled like the
	# cooldown rings above (charge changes on every kill; a per-kill
	# signal-driven update would fire far more often than once a frame
	# anyway). Everything stays hidden until the active element's capstone
	# actually unlocks the ultimate, so early runs see nothing new. The
	# button is the touch/mobile trigger (Q still works on keyboard); its
	# icon is the active element's own capstone skill art, dimmed while
	# charging and full-bright once ready.
	# Dash button dims while the cooldown runs -- same poll-driven state as
	# everything else here. Always visible (dash needs no unlock).
	var dash_ready: bool = _player._dash_cooldown_remaining <= 0.0 and not _player._is_dashing
	dash_button.disabled = not dash_ready
	dash_button.modulate = Color(1, 1, 1, 1) if dash_ready else Color(0.6, 0.6, 0.6, 0.75)
	var ult_unlocked: bool = _player.is_ultimate_unlocked()
	ultimate_label.visible = ult_unlocked
	# Toggle the whole cell (button + its caption) as one unit -- the
	# VBoxContainer packs the dash cell to the bottom either way, so the dash
	# button never shifts when the ultimate appears/disappears.
	ultimate_cell.visible = ult_unlocked
	if ult_unlocked:
		var ready: bool = _player.can_use_ultimate()
		if ready:
			ultimate_label.text = "ULTIMATE READY — press Q"
		else:
			ultimate_label.text = "Ultimate: %d/%d kills" % [_player.ultimate_charge, _player.ULTIMATE_KILLS_REQUIRED]
		ultimate_button.disabled = not ready
		ultimate_button.modulate = Color(1, 1, 1, 1) if ready else Color(0.6, 0.6, 0.6, 0.75)
		var skill: SkillData = _player.get_current_skill_for_element(_player.active_element)
		var icon_texture: Texture2D = skill.icon if skill != null else null
		if ultimate_button_icon.texture != icon_texture:
			ultimate_button_icon.texture = icon_texture


func _on_ultimate_button_pressed() -> void:
	if is_instance_valid(_player) and _player.try_use_ultimate():
		AudioManager.play_ui("ui_click")


func _on_dash_button_pressed() -> void:
	if is_instance_valid(_player):
		_player.try_dash()  # no ui_click on top -- the dash's own whoosh SFX is the feedback


func _on_pause_pressed() -> void:
	AudioManager.play_ui("ui_click")
	GameManager.request_pause("pause_menu")


func _on_skill_button_pressed() -> void:
	# Pauses via the exact same "pause_menu" source PauseButton/Esc use (so
	# state tracking and Esc-to-resume both stay correct), then jumps straight
	# to the skill panel instead of showing the main pause menu first.
	AudioManager.play_ui("ui_click")
	GameManager.request_pause("pause_menu")
	var pause_menu := get_tree().get_first_node_in_group("pause_menu")
	if is_instance_valid(pause_menu):
		pause_menu.open_skills_panel()


func _on_player_hp_changed(current: float, max_hp: float) -> void:
	heart_hp.current_hp = roundi(current)
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
	skill_icon.texture = skill.icon


func _on_elemental_skill_changed(element: int, skill: SkillData) -> void:
	# Fires on every tier pick for whichever element was just picked,
	# regardless of whether it's the active one -- all unlocked elements get
	# their own row now, so this always refreshes that element's row content.
	if _elemental_rows.has(element):
		_elemental_rows[element].label.text = skill.display_name
		_elemental_rows[element].icon.texture = skill.icon
	else:
		_build_elemental_row(element, skill)


func _on_active_element_switched(element: int, _skill: SkillData) -> void:
	# Only the active row's own content already reflects the right skill
	# (kept current by _on_elemental_skill_changed) -- this just re-styles
	# every row so exactly one reads as "active."
	for row_element in _elemental_rows:
		_elemental_rows[row_element].row.modulate = ACTIVE_ROW_MODULATE if row_element == element else INACTIVE_ROW_MODULATE


func _build_elemental_row(element: int, skill: SkillData) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.modulate = ACTIVE_ROW_MODULATE if element == _player.active_element else INACTIVE_ROW_MODULATE
	# Icon and cooldown ring are stacked in the same 32x32 rect (icon behind,
	# ring drawn on top) rather than placed side by side, matching a typical
	# "ability icon with a cooldown sweep" UI convention. It's a flat/borderless
	# Button (not a plain Control) so tapping it makes this exact element
	# active via select_active_element() -- direct per-icon selection, not a
	# cycle, since a blind "switch to next unlocked element" button was
	# confusing once 3 elements could be unlocked at once (tapping it didn't
	# reliably return to the element the player expected).
	var icon_stack := Button.new()
	icon_stack.flat = true
	icon_stack.focus_mode = Control.FOCUS_NONE
	icon_stack.custom_minimum_size = Vector2(38, 38)
	icon_stack.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_stack.pressed.connect(func(): _player.select_active_element(element))
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
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1, 0.85, 0.4, 1))
	row.add_child(icon_stack)
	row.add_child(label)
	elemental_rows_container.add_child(row)
	_elemental_rows[element] = {"ring": ring, "label": label, "icon": icon, "row": row}


func _on_wave_started(wave_number: int) -> void:
	wave_label.text = "Wave %d" % wave_number


func _on_signal_bus_wave_started(_wave_number: int, is_boss: bool) -> void:
	boss_hp_bar_container.visible = is_boss
	# Same reset logic as the boss label below -- the cycle reference belongs
	# to a specific affinity boss's fight, never to the wave that follows it.
	element_cycle_label.visible = false
	if is_boss:
		# (2026-07-17) Reset immediately rather than waiting for
		# boss_mutation_announced -- that only fires once the boss itself
		# spawns, which is seconds after the bar becomes visible (the wave's
		# regular monster queue drains first). Without this, a mutated boss's
		# label could linger visibly into the next boss wave's opening seconds
		# even if that one rolls no mutation or a different one.
		boss_label.text = "BOSS"


func _on_boss_hp_changed(current: float, max_hp: float) -> void:
	boss_hp_bar.max_value = max_hp
	boss_hp_bar.value = current


func _on_boss_mutation_announced(mutation_name: String) -> void:
	# Emitted once per boss spawn regardless of whether it rolled a mutation
	# (mutation_name == ""), so this always resets the label -- a mutated
	# boss's name from an earlier cycle can never linger onto a later
	# unmutated one.
	boss_label.text = "BOSS" if mutation_name == "" else "BOSS — %s" % mutation_name.to_upper()


func _on_boss_affinity_announced(affinity_id: String) -> void:
	# Shows the full counter rotation (top-right, under the pause button)
	# whenever an affinity boss is on the field, with the line that answers
	# THIS boss bolded and arrowed. Teaching the whole cycle (not just the one
	# matchup) is deliberate -- it's the same reference every affinity fight,
	# so the player only has to internalize it once.
	element_cycle_label.visible = affinity_id != ""
	if affinity_id == "":
		return
	var lines: Array[String] = []
	for line in [
		["frost", "fire"],      # Frost counters a fire-affinity boss
		["lightning", "frost"],
		["fire", "lightning"],
	]:
		var counter_name: String = line[0]
		var boss_element: String = line[1]
		var text := "[color=%s]%s[/color] beats [color=%s]%s[/color]" % [
			ELEMENT_BBCODE_COLORS[counter_name], counter_name.capitalize(),
			ELEMENT_BBCODE_COLORS[boss_element], boss_element.capitalize(),
		]
		if boss_element == affinity_id:
			text = "> [b]%s[/b]" % text
		else:
			text = "   %s" % text
		lines.append(text)
	element_cycle_label.text = "\n".join(lines)


func _on_equipment_changed(slot: String, item: ItemData) -> void:
	var icon: EquipSlotIcon = equip_slots[slot]
	icon.rarity_color = ItemPickup.RARITY_COLORS.get(item.rarity, ItemPickup.RARITY_COLORS["common"])
	icon.tooltip_text = item.display_name
