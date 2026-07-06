extends Node
class_name WaveManager

const BOSS_WAVE_INTERVAL := 10
const HP_SCALING_PER_WAVE := 0.15
const HP_MULT_CEILING := 6.0
const SPEED_SCALING_PER_WAVE := 0.05
const COUNT_SCALING_PER_WAVE := 1
const SPAWN_INTERVAL_DECAY := 0.03
const SPAWN_INTERVAL_FLOOR := 0.35
const BOSS_HP_MULT := 15.0
const BOSS_DAMAGE_MULT := 2.0
const BOSS_XP_REWARD := 200
const BOSS_VISUAL_SCALE := 3.0

signal wave_started(wave_number: int)
signal wave_cleared(wave_number: int)

@export var waves: Array[WaveData] = []
@export var procedural_enemy_data: EnemyData  # assign slime_scout.tres in Main.tscn

@onready var spawner: EnemySpawner = get_parent().get_node("EnemySpawner")

var current_wave_index := -1
var _current_wave: WaveData
var _current_hp_mult := 1.0
var _current_speed_mult := 1.0
var _current_damage_mult := 1.0
var _current_xp_override := -1
var _current_visual_scale := 1.0
var _is_boss_wave := false
var _alive_count := 0
var _spawn_queue: Array[EnemyData] = []
var _spawn_timer: Timer


func _ready() -> void:
	add_to_group("wave_manager")
	_spawn_timer = Timer.new()
	_spawn_timer.one_shot = false
	add_child(_spawn_timer)
	_spawn_timer.timeout.connect(_on_spawn_tick)
	_start_next_wave()


func _start_next_wave() -> void:
	current_wave_index += 1
	var wave_number := current_wave_index + 1
	_is_boss_wave = wave_number % BOSS_WAVE_INTERVAL == 0

	if current_wave_index < waves.size():
		_current_wave = waves[current_wave_index]
		_current_hp_mult = 1.0
		_current_speed_mult = 1.0
		_current_damage_mult = 1.0
		_current_xp_override = -1
		_current_visual_scale = 1.0
	else:
		_current_wave = _generate_wave(wave_number)

	_refill_player_shield()
	wave_started.emit(wave_number)
	_spawn_queue.clear()

	if _is_boss_wave:
		_spawn_queue.append(procedural_enemy_data)
		_current_hp_mult = BOSS_HP_MULT
		_current_damage_mult = BOSS_DAMAGE_MULT
		_current_xp_override = BOSS_XP_REWARD
		_current_visual_scale = BOSS_VISUAL_SCALE
	else:
		for i in _current_wave.enemy_pool.size():
			for _n in _current_wave.spawn_counts[i]:
				_spawn_queue.append(_current_wave.enemy_pool[i])
		_spawn_queue.shuffle()

	_alive_count = _spawn_queue.size()
	_spawn_timer.wait_time = _current_wave.spawn_interval
	_spawn_timer.start()


func _generate_wave(wave_number: int) -> WaveData:
	var wave := WaveData.new()
	wave.wave_number = wave_number
	wave.enemy_pool = [procedural_enemy_data]
	var extra_waves := wave_number - waves.size()
	var count: int = _last_authored_count() + COUNT_SCALING_PER_WAVE * extra_waves
	wave.spawn_counts = [count]
	wave.spawn_interval = maxf(SPAWN_INTERVAL_FLOOR, _last_authored_interval() - SPAWN_INTERVAL_DECAY * extra_waves)
	wave.is_boss_wave = wave_number % BOSS_WAVE_INTERVAL == 0

	_current_hp_mult = minf(1.0 + HP_SCALING_PER_WAVE * (wave_number - 1), HP_MULT_CEILING)
	_current_speed_mult = 1.0 + SPEED_SCALING_PER_WAVE * (wave_number - 1)
	_current_damage_mult = 1.0
	_current_xp_override = -1
	_current_visual_scale = 1.0
	return wave


func _last_authored_count() -> int:
	var last: WaveData = waves[waves.size() - 1]
	var total := 0
	for c in last.spawn_counts:
		total += c
	return total


func _last_authored_interval() -> float:
	return waves[waves.size() - 1].spawn_interval


func _refill_player_shield() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and player.has_method("refill_shield"):
		player.refill_shield()


func _on_spawn_tick() -> void:
	if _spawn_queue.is_empty():
		_spawn_timer.stop()
		return
	spawner.spawn(_spawn_queue.pop_back(), _current_hp_mult, _current_speed_mult, _current_damage_mult, _current_xp_override, _current_visual_scale)


func notify_enemy_died() -> void:
	_alive_count -= 1
	if _alive_count <= 0 and _spawn_queue.is_empty():
		wave_cleared.emit(_current_wave.wave_number)
		_start_next_wave()
