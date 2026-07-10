extends CanvasLayer
class_name GameOverScreen

@onready var panel: Control = $Panel
@onready var info_label: Label = $Panel/VBox/InfoLabel
@onready var restart_button: Button = $Panel/VBox/RestartButton

var player: Node
var _last_wave := 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel.visible = false
	player = get_tree().get_first_node_in_group("player")
	if player:
		player.died.connect(_on_player_died)
	var wave_manager := get_tree().get_first_node_in_group("wave_manager")
	if wave_manager:
		wave_manager.wave_started.connect(_on_wave_started)
	restart_button.pressed.connect(_on_restart_pressed)


func _on_wave_started(wave_number: int) -> void:
	_last_wave = wave_number


func _on_player_died() -> void:
	var level: int = player.level if player else 1
	SaveManager.record_run(_last_wave, level)
	info_label.text = "Reached Wave %d — Level %d\nBest: Wave %d — Level %d" % [
		_last_wave, level, SaveManager.best_wave, SaveManager.best_level,
	]
	panel.visible = true
	GameManager.request_pause("game_over")


func _on_restart_pressed() -> void:
	AudioManager.play_ui("ui_click")
	GameManager.reset_state()
	get_tree().reload_current_scene()
