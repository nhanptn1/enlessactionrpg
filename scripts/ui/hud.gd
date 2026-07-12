extends CanvasLayer
class_name HUD

@onready var hp_bar: ProgressBar = $Margin/VBox/HPBar
@onready var xp_bar: ProgressBar = $Margin/VBox/XPBar
@onready var level_label: Label = $Margin/VBox/LevelLabel
@onready var wave_label: Label = $Margin/VBox/WaveLabel
@onready var skill_label: Label = $Margin/VBox/SkillRow/SkillLabel
@onready var skill_cooldown: RadialCooldown = $Margin/VBox/SkillRow/SkillCooldown
@onready var pause_button: Button = $PauseButton
@onready var boss_hp_bar_container: MarginContainer = $BossHPBarContainer
@onready var boss_hp_bar: ProgressBar = $BossHPBarContainer/BossVBox/BossHPBar

var _player: Node


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	if _player:
		_player.hp_changed.connect(_on_player_hp_changed)
		_player.xp_changed.connect(_on_player_xp_changed)
		_player.level_up.connect(_on_player_level_up)
		_player.skill_unlocked.connect(_on_skill_unlocked)
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
	if timer.wait_time <= 0.0:
		return
	skill_cooldown.value = 1.0 - (timer.time_left / timer.wait_time)


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


func _on_skill_unlocked(skill_name: String) -> void:
	skill_label.text = skill_name


func _on_wave_started(wave_number: int) -> void:
	wave_label.text = "Wave %d" % wave_number


func _on_signal_bus_wave_started(_wave_number: int, is_boss: bool) -> void:
	boss_hp_bar_container.visible = is_boss


func _on_boss_hp_changed(current: float, max_hp: float) -> void:
	boss_hp_bar.max_value = max_hp
	boss_hp_bar.value = current
