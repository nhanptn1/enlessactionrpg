extends CanvasLayer
class_name PauseMenu

@onready var panel: Control = $Panel
@onready var resume_button: Button = $Panel/VBox/ResumeButton
@onready var restart_button: Button = $Panel/VBox/RestartButton
@onready var best_label: Label = $Panel/VBox/BestLabel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel.visible = false
	resume_button.pressed.connect(_on_resume_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
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


func _on_resume_pressed() -> void:
	AudioManager.play_ui("ui_click")
	GameManager.request_unpause("pause_menu")


func _on_restart_pressed() -> void:
	AudioManager.play_ui("ui_click")
	GameManager.reset_state()
	get_tree().reload_current_scene()


func _update_best_label() -> void:
	best_label.text = "Best: Wave %d — Level %d" % [SaveManager.best_wave, SaveManager.best_level]
