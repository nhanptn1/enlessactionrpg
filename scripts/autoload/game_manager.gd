extends Node
## Central game-state and pause orchestration.

enum State { BOOT, PLAYING, BOSS, LEVEL_UP, WAVE_UPGRADE, PAUSED, GAME_OVER }

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
	_end_hitstop()  # a restart mid-hitstop must never leave the game in slow motion


# --- Hitstop -------------------------------------------------------------------
# (2026-07-23) Combat juice pass: a very brief time dilation on big moments
# (fusion combo procs, boss phase change) so heavy hits land with weight
# instead of passing at the same tempo as chip damage. Guarded by a generation
# token so overlapping calls can't stack or restore early, and restored in
# reset_state() so a restart can never strand the game slowed down.
const HITSTOP_SCALE := 0.35
var _hitstop_token := 0


func hitstop(duration: float = 0.09) -> void:
	if duration <= 0.0:
		return
	_hitstop_token += 1
	var token := _hitstop_token
	Engine.time_scale = HITSTOP_SCALE
	# ignore_time_scale = true (the 4th arg), so this waits `duration` REAL
	# seconds and must NOT be pre-scaled -- an earlier version multiplied by
	# HITSTOP_SCALE on top of that, cutting every hitstop to 35% of its intended
	# length. process_always so a pause can't strand it either.
	await get_tree().create_timer(duration, true, false, true).timeout
	if token == _hitstop_token:
		Engine.time_scale = 1.0


func _end_hitstop() -> void:
	_hitstop_token += 1  # invalidates any in-flight restore
	Engine.time_scale = 1.0


func request_pause(source: String) -> void:
	if source in _pause_sources:
		return
	_pause_sources.append(source)
	get_tree().paused = true
	if source == "pause_menu":
		state = State.PAUSED
	elif source == "level_up":
		state = State.LEVEL_UP
	elif source == "wave_upgrade":
		state = State.WAVE_UPGRADE
	elif source == "game_over":
		state = State.GAME_OVER
	SignalBus.game_paused.emit(source)


func request_unpause(source: String) -> void:
	_pause_sources.erase(source)
	if _pause_sources.is_empty():
		get_tree().paused = false
		if state in [State.PAUSED, State.LEVEL_UP, State.WAVE_UPGRADE]:
			state = State.BOSS if _is_boss_wave_active() else State.PLAYING
		SignalBus.game_unpaused.emit(source)


func is_paused_by(source: String) -> bool:
	return source in _pause_sources


func can_toggle_pause() -> bool:
	if state == State.GAME_OVER:
		return false
	if is_paused_by("level_up") or is_paused_by("wave_upgrade") or is_paused_by("game_over") or is_paused_by("class_select") or is_paused_by("continue"):
		return false
	return state in [State.PLAYING, State.BOSS, State.PAUSED]


func set_play_state(is_boss: bool) -> void:
	if state in [State.LEVEL_UP, State.WAVE_UPGRADE, State.PAUSED, State.GAME_OVER]:
		return
	state = State.BOSS if is_boss else State.PLAYING


func _is_boss_wave_active() -> bool:
	var wm := get_tree().get_first_node_in_group("wave_manager")
	if not is_instance_valid(wm):
		return false
	return wm.is_boss_wave_active() if wm.has_method("is_boss_wave_active") else false
