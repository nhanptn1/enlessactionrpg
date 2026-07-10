extends CanvasLayer
class_name HUD

@onready var hp_bar: ProgressBar = $Margin/VBox/HPBar
@onready var xp_bar: ProgressBar = $Margin/VBox/XPBar
@onready var level_label: Label = $Margin/VBox/LevelLabel
@onready var wave_label: Label = $Margin/VBox/WaveLabel
@onready var pause_button: Button = $PauseButton


func _ready() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player:
		player.hp_changed.connect(_on_player_hp_changed)
		player.xp_changed.connect(_on_player_xp_changed)
		player.level_up.connect(_on_player_level_up)
		hp_bar.max_value = player.max_hp
		hp_bar.value = player.current_hp
		xp_bar.max_value = player.xp_to_next_level()
		xp_bar.value = player.xp
		level_label.text = "Lv. %d" % player.level
	var wave_manager := get_tree().get_first_node_in_group("wave_manager")
	if wave_manager:
		wave_manager.wave_started.connect(_on_wave_started)
	# Touch/mobile-friendly entry point for pausing -- the "pause" input
	# action (Escape) still works too, this is the on-screen equivalent.
	# No unpause branch needed here: while paused, HUD is frozen along with
	# every other default-process_mode gameplay node, so this button simply
	# can't be pressed again until PauseMenu's own Resume button unpauses.
	pause_button.pressed.connect(_on_pause_pressed)


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


func _on_wave_started(wave_number: int) -> void:
	wave_label.text = "Wave %d" % wave_number
