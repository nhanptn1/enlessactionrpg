extends Node
## Central game-state and pause orchestration.

enum State { BOOT, PLAYING, BOSS, LEVEL_UP, PAUSED, GAME_OVER }

var state := State.BOOT
var _pause_sources: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if not can_toggle_pause():
		return
	if is_paused_by("pause_menu"):
		request_unpause("pause_menu")
	else:
		request_pause("pause_menu")


func reset_state() -> void:
	# SceneTree has no "scene changed" signal to hook this off of automatically
	# -- call this explicitly right before get_tree().reload_current_scene(),
	# the only way this game ever changes scenes (both Restart buttons).
	_pause_sources.clear()
	state = State.PLAYING
	get_tree().paused = false


func request_pause(source: String) -> void:
	if source in _pause_sources:
		return
	_pause_sources.append(source)
	get_tree().paused = true
	if source == "pause_menu":
		state = State.PAUSED
	elif source == "level_up":
		state = State.LEVEL_UP
	elif source == "game_over":
		state = State.GAME_OVER
	SignalBus.game_paused.emit(source)


func request_unpause(source: String) -> void:
	_pause_sources.erase(source)
	if _pause_sources.is_empty():
		get_tree().paused = false
		if state in [State.PAUSED, State.LEVEL_UP]:
			state = State.BOSS if _is_boss_wave_active() else State.PLAYING
		SignalBus.game_unpaused.emit(source)


func is_paused_by(source: String) -> bool:
	return source in _pause_sources


func can_toggle_pause() -> bool:
	if state == State.GAME_OVER:
		return false
	if is_paused_by("level_up") or is_paused_by("game_over"):
		return false
	return state in [State.PLAYING, State.BOSS, State.PAUSED]


func set_play_state(is_boss: bool) -> void:
	if state in [State.LEVEL_UP, State.PAUSED, State.GAME_OVER]:
		return
	state = State.BOSS if is_boss else State.PLAYING


func _is_boss_wave_active() -> bool:
	var wm := get_tree().get_first_node_in_group("wave_manager")
	if not is_instance_valid(wm):
		return false
	return wm.is_boss_wave_active() if wm.has_method("is_boss_wave_active") else false
