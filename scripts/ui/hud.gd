extends CanvasLayer
class_name HUD

@onready var hp_bar: ProgressBar = $Margin/VBox/HPBar
@onready var xp_bar: ProgressBar = $Margin/VBox/XPBar
@onready var level_label: Label = $Margin/VBox/LevelLabel
@onready var wave_label: Label = $Margin/VBox/WaveLabel


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
