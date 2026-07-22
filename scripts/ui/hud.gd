extends CanvasLayer
class_name HUD

@onready var heart_hp: HeartHPDisplay = $HeartHP
@onready var hp_bar: ProgressBar = $HPBar
@onready var xp_bar: ProgressBar = $Margin/VBox/XPBar
@onready var level_label: Label = $Margin/VBox/LevelLabel
@onready var wave_label: Label = $Margin/VBox/WaveLabel
@onready var modifier_label: Label = $Margin/VBox/ModifierLabel
@onready var ultimate_label: Label = $Margin/VBox/UltimateLabel
@onready var element_cycle_diagram: ElementCycleDiagram = $ElementCycleDiagram
@onready var hint_banner: Button = $HintBanner
@onready var hint_text_label: Label = $HintBanner/HintText
@onready var dash_button: Button = $ActionButtons/DashCell/DashButton
@onready var ultimate_cell: VBoxContainer = $ActionButtons/UltimateCell
@onready var ultimate_button: Button = $ActionButtons/UltimateCell/UltimateButton
@onready var ultimate_button_icon: TextureRect = $ActionButtons/UltimateCell/UltimateButton/Icon
@onready var skill_label: Label = $Margin/VBox/SkillRow/SkillLabel
@onready var skill_icon: TextureRect = $Margin/VBox/SkillRow/SkillIconStack/Icon
@onready var skill_cooldown: RadialCooldown = $Margin/VBox/SkillRow/SkillIconStack/SkillCooldown
@onready var elemental_rows_container: VBoxContainer = $Margin/VBox/ElementalSkillRows
@onready var class_skill_row: HBoxContainer = $Margin/VBox/ClassSkillRow
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
# Populated once the class skill line unlocks its first tier -- {ring, icon,
# label}. Never tappable (the class skill always auto-fires; there's no
# "select active" for it, unlike the elemental rows above).
var _class_row: Dictionary = {}
# One-time onboarding hints, shown once ever (persisted via SaveManager).
# Queued as they trigger and shown one at a time; see _queue_hint().
var _hint_queue: Array[String] = []
var _hint_showing := false
var _hint_token := 0  # bumped on every show/dismiss so a stale auto-dismiss timer no-ops
var _ultimate_was_ready := false  # edge-detect for the "ultimate charged" hint


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	if _player:
		_player.hp_changed.connect(_on_player_hp_changed)
		_player.xp_changed.connect(_on_player_xp_changed)
		_player.level_up.connect(_on_player_level_up)
		_player.skill_unlocked.connect(_on_skill_unlocked)
		_player.elemental_skill_changed.connect(_on_elemental_skill_changed)
		_player.active_element_switched.connect(_on_active_element_switched)
		_player.class_skill_changed.connect(_on_class_skill_changed)
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
	hint_banner.pressed.connect(_dismiss_current_hint)
	# Very first thing a new player sees, once ever: how to move + auto-fire,
	# then how to dash. Queued right at HUD start (after the class picker).
	_queue_hint("move")
	_queue_hint("dash")


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
	if not _class_row.is_empty():
		var class_timer: Timer = _player.class_skill_timer
		if is_instance_valid(class_timer) and class_timer.wait_time > 0.0:
			_class_row.ring.value = 1.0 - (class_timer.time_left / class_timer.wait_time)
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
		if ready and not _ultimate_was_ready:
			_queue_hint("ultimate")  # first time it's usable
		_ultimate_was_ready = ready
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
	# Switching only matters once a 2nd element is unlocked (the 1st auto-
	# activates) -- teach it the moment that happens.
	if _elemental_rows.size() >= 2:
		_queue_hint("switch_element")


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


func _on_class_skill_changed(skill: SkillData) -> void:
	# The class skill line's own top-left row, built once on first unlock and
	# refreshed on every tier swap. Mirrors an elemental row (icon + cooldown
	# ring stacked, name label) but as a plain Control -- the class skill
	# always auto-fires, so there's nothing to tap to "activate."
	if _class_row.is_empty():
		var icon_stack := Control.new()
		icon_stack.custom_minimum_size = Vector2(38, 38)
		icon_stack.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon := TextureRect.new()
		icon.anchor_right = 1.0
		icon.anchor_bottom = 1.0
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ring := RadialCooldown.new()
		ring.anchor_right = 1.0
		ring.anchor_bottom = 1.0
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_stack.add_child(icon)
		icon_stack.add_child(ring)
		var label := Label.new()
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		label.add_theme_font_size_override("font_size", 18)
		# A class-identity tint distinct from the gold basic/elemental labels.
		var col: Color = CharacterClasses.get_color(_player.active_class_id)
		label.add_theme_color_override("font_color", Color(col.r * 0.8, col.g * 0.85, col.b * 0.95, 1.0))
		class_skill_row.add_child(icon_stack)
		class_skill_row.add_child(label)
		_class_row = {"ring": ring, "icon": icon, "label": label}
	_class_row.icon.texture = skill.icon
	_class_row.label.text = skill.display_name
	class_skill_row.visible = true


func _on_wave_started(wave_number: int) -> void:
	wave_label.text = "Wave %d" % wave_number


func _on_signal_bus_wave_started(_wave_number: int, is_boss: bool) -> void:
	boss_hp_bar_container.visible = is_boss
	# The counter-cycle diagram is a persistent always-on reference; a new wave
	# just clears any previous boss's affinity highlight (it belongs to that
	# specific fight, not the wave after it).
	element_cycle_diagram.active_affinity = ""
	element_cycle_diagram.queue_redraw()
	if is_boss:
		# (2026-07-17) Reset immediately rather than waiting for
		# boss_mutation_announced -- that only fires once the boss itself
		# spawns, which is seconds after the bar becomes visible (the wave's
		# regular monster queue drains first). Without this, a mutated boss's
		# label could linger visibly into the next boss wave's opening seconds
		# even if that one rolls no mutation or a different one.
		boss_label.text = "BOSS"
		_queue_hint("boss")


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
	# The diagram is always on; this just sets which node to highlight (the
	# boss's affinity) so the player sees which element resists them (red) and
	# which counters it (green). "" clears back to the plain reference cycle.
	element_cycle_diagram.active_affinity = affinity_id
	element_cycle_diagram.queue_redraw()
	if affinity_id != "":
		_queue_hint("affinity")


# --- One-time onboarding hints -------------------------------------------------

func _queue_hint(id: String) -> void:
	# Show once ever: mark seen immediately so it can never re-queue, even across
	# runs. A non-blocking toast, shown one at a time.
	if SaveManager.has_seen_hint(id) or id in _hint_queue:
		return
	if not TutorialHints.HINTS.has(id):
		return
	SaveManager.mark_hint_seen(id)
	_hint_queue.append(id)
	if not _hint_showing:
		_show_next_hint()


func _show_next_hint() -> void:
	if _hint_queue.is_empty():
		_hint_showing = false
		hint_banner.visible = false
		return
	_hint_showing = true
	_hint_token += 1
	var my_token := _hint_token
	var id: String = _hint_queue.pop_front()
	hint_text_label.text = TutorialHints.HINTS[id]
	hint_banner.visible = true
	# Auto-dismiss after a read window; a tap dismisses early. The token guard
	# makes a stale timer (fired after a tap already advanced) a no-op.
	# process_always=false: the read window only counts down during live play,
	# so the very first move/dash hints (queued while the class picker still
	# pauses the game) don't silently expire behind that popup before play.
	get_tree().create_timer(6.0, false).timeout.connect(func():
		if my_token == _hint_token:
			_show_next_hint()
	)


func _dismiss_current_hint() -> void:
	if not _hint_showing:
		return
	AudioManager.play_ui("ui_click")
	_hint_token += 1  # invalidate the current hint's pending auto-dismiss timer
	_show_next_hint()


func _on_equipment_changed(slot: String, item: ItemData) -> void:
	var icon: EquipSlotIcon = equip_slots[slot]
	icon.rarity_color = ItemPickup.RARITY_COLORS.get(item.rarity, ItemPickup.RARITY_COLORS["common"])
	icon.tooltip_text = item.display_name
