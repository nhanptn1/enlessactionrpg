extends Node
class_name WaveManager

const ITEM_PICKUP_SCENE := preload("res://scenes/effects/ItemPickup.tscn")
const BOSS_WAVE_INTERVAL := 10
const HP_SCALING_PER_WAVE := 0.15
const HP_MULT_CEILING := 6.0
const SPEED_SCALING_PER_WAVE := 0.05
const COUNT_SCALING_PER_WAVE := 1
const SPAWN_INTERVAL_DECAY := 0.03
const SPAWN_INTERVAL_FLOOR := 0.35
const BOSS_HP_MULT_BASE := 15.0
const BOSS_HP_MULT_GROWTH_PER_CYCLE := 0.2
const BOSS_DAMAGE_MULT := 2.0
const BOSS_XP_REWARD := 200
const BOSS_VISUAL_SCALE := 1.5
const RARITY_WEIGHTS := {"common": 0.55, "rare": 0.30, "epic": 0.15}
# Elite rolls only apply to normal (non-boss) waves -- the boss already has
# its own cycle-based scaling in _boss_hp_mult(), stacking elite on top of
# that would be redundant. 5% matches the ratio the (deferred) big-wave plan
# docs called for, borrowed here since it's a reasonable rarity regardless of
# wave scale.
const ELITE_CHANCE := 0.05
const ELITE_HP_MULT := 2.0
const ELITE_SPEED_MULT := 1.1
const ELITE_DAMAGE_MULT := 1.4
const ELITE_XP_MULT := 3.0

signal wave_started(wave_number: int)
signal wave_cleared(wave_number: int)

@export var waves: Array[WaveData] = []
@export var procedural_enemy_pool: Array[EnemyData] = []  # assign [slime_scout, goblin_runner, bat_swarm] in Main.tscn
@export var boss_pool: Array[EnemyData] = []  # bosses rotate by cycle: boss_pool[(cycle - 1) % boss_pool.size()]
@export var item_pool: Array[ItemData] = []  # assign all ItemData resources in Main.tscn

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


func is_boss_wave_active() -> bool:
	return _is_boss_wave


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
	SignalBus.wave_started.emit(wave_number, _is_boss_wave)
	GameManager.set_play_state(_is_boss_wave)
	_spawn_queue.clear()

	if _is_boss_wave:
		var cycle := wave_number / BOSS_WAVE_INTERVAL
		_spawn_queue.append(boss_pool[(cycle - 1) % boss_pool.size()])
		_current_hp_mult = _boss_hp_mult(cycle)
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
	wave.enemy_pool = [procedural_enemy_pool[randi() % procedural_enemy_pool.size()]]
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


func _boss_hp_mult(cycle: int) -> float:
	return BOSS_HP_MULT_BASE * (1.0 + BOSS_HP_MULT_GROWTH_PER_CYCLE * (cycle - 1))


func roll_item_drop() -> ItemData:
	if item_pool.is_empty():
		return null
	var roll := randf()
	var rarity := "common"
	if roll < RARITY_WEIGHTS["epic"]:
		rarity = "epic"
	elif roll < RARITY_WEIGHTS["epic"] + RARITY_WEIGHTS["rare"]:
		rarity = "rare"
	var matches: Array[ItemData] = []
	for item in item_pool:
		if item.rarity == rarity:
			matches.append(item)
	if matches.is_empty():
		# authoring gap (e.g. no items of this rarity yet, or a typo'd
		# rarity string) — fall back to the full pool rather than
		# silently never dropping anything for this tier
		matches = item_pool
	return matches[randi() % matches.size()]


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
	var enemy_data: EnemyData = _spawn_queue.pop_back()
	var cluster_size: int = maxi(enemy_data.cluster_size, 1)
	if cluster_size == 1:
		_spawn_one(enemy_data, -1.0)
	else:
		_alive_count += cluster_size - 1  # this entry only counted as 1 in the initial _alive_count
		var cluster_center_x := randf_range(-spawner.spawn_width / 2.0, spawner.spawn_width / 2.0) + spawner.center_x
		for _n in cluster_size:
			_spawn_one(enemy_data, cluster_center_x + randf_range(-30.0, 30.0))


func _spawn_one(enemy_data: EnemyData, x_override: float) -> void:
	var is_elite := not _is_boss_wave and randf() < ELITE_CHANCE
	var hp_mult := _current_hp_mult * (ELITE_HP_MULT if is_elite else 1.0)
	var speed_mult := _current_speed_mult * (ELITE_SPEED_MULT if is_elite else 1.0)
	var damage_mult := _current_damage_mult * (ELITE_DAMAGE_MULT if is_elite else 1.0)
	var xp_override := roundi(enemy_data.xp_reward * ELITE_XP_MULT) if is_elite else _current_xp_override
	spawner.spawn(enemy_data, hp_mult, speed_mult, damage_mult, xp_override, _current_visual_scale, x_override, is_elite)


func notify_enemy_died() -> void:
	_alive_count -= 1
	if _alive_count <= 0 and _spawn_queue.is_empty():
		var was_boss := _is_boss_wave
		wave_cleared.emit(_current_wave.wave_number)
		SignalBus.wave_cleared.emit(_current_wave.wave_number, was_boss)
		_start_next_wave()


func _on_enemy_died(xp_reward: int, drop_chance: float, death_position: Vector2) -> void:
	_grant_death_rewards(xp_reward, drop_chance, death_position)
	notify_enemy_died()


func _on_minion_died(xp_reward: int, drop_chance: float, death_position: Vector2) -> void:
	# Boss-summoned adds (e.g. saplings) still reward the player, but must
	# NOT touch _alive_count -- they were never part of the wave's own spawn
	# queue, so counting them would let the wave clear while the boss (the
	# queue's actual sole entry) is still alive and fighting.
	_grant_death_rewards(xp_reward, drop_chance, death_position)


func _grant_death_rewards(xp_reward: int, drop_chance: float, death_position: Vector2) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and player.has_method("gain_xp"):
		player.gain_xp(xp_reward)
	if randf() < drop_chance:
		var item: ItemData = roll_item_drop()
		if item != null:
			var pickup = ITEM_PICKUP_SCENE.instantiate()
			pickup.item_data = item  # BEFORE add_child — _ready() reads it synchronously
			pickup.global_position = death_position
			get_tree().current_scene.add_child(pickup)
