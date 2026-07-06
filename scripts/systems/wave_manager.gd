extends Node
class_name WaveManager

signal wave_started(wave_number: int)
signal wave_cleared(wave_number: int)

@export var waves: Array[WaveData] = []

@onready var spawner: EnemySpawner = get_parent().get_node("EnemySpawner")

var current_wave_index := -1
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
	if current_wave_index >= waves.size():
		return  # Milestone 1 stops after authored waves; MVP adds procedural generation
	var wave: WaveData = waves[current_wave_index]
	wave_started.emit(wave.wave_number)
	_spawn_queue.clear()
	for i in wave.enemy_pool.size():
		for _n in wave.spawn_counts[i]:
			_spawn_queue.append(wave.enemy_pool[i])
	_spawn_queue.shuffle()
	_alive_count = _spawn_queue.size()
	_spawn_timer.wait_time = wave.spawn_interval
	_spawn_timer.start()


func _on_spawn_tick() -> void:
	if _spawn_queue.is_empty():
		_spawn_timer.stop()
		return
	spawner.spawn(_spawn_queue.pop_back())


func notify_enemy_died() -> void:
	_alive_count -= 1
	if _alive_count <= 0 and _spawn_queue.is_empty():
		wave_cleared.emit(waves[current_wave_index].wave_number)
		_start_next_wave()
