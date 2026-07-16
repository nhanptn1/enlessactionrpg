extends Node
class_name WaveManager

const ITEM_PICKUP_SCENE := preload("res://scenes/effects/ItemPickup.tscn")
const BOSS_WAVE_INTERVAL := 10
# (2026-07-16) Bumped 0.15->0.25 and the ceiling 6.0->12.0 -- user playtest
# feedback was that enemies felt too weak past wave 10 (dying in 1 hit
# instead of the intended 2-3), since the player's damage output compounds
# from multiple simultaneous sources (basic line upgrades, crit, up to 3
# independently-firing elemental skills) while this was the only thing
# scaling enemies back up.
const HP_SCALING_PER_WAVE := 0.25
const HP_MULT_CEILING := 12.0
const SPEED_SCALING_PER_WAVE := 0.03
const COUNT_SCALING_PER_WAVE := 1
const SPAWN_INTERVAL_DECAY := 0.03
const SPAWN_INTERVAL_FLOOR := 0.35
# (2026-07-16) 15.0->75.0 (x5) per direct user request.
const BOSS_HP_MULT_BASE := 75.0
const BOSS_HP_MULT_GROWTH_PER_CYCLE := 0.2
const BOSS_DAMAGE_MULT := 2.0
const BOSS_XP_REWARD := 100  # (2026-07-16) 200->100, halved alongside every regular enemy's xp_reward
const BOSS_VISUAL_SCALE := 1.5
const MONSTER_XP_MULT := 1.25  # (2026-07-16) per-kill XP felt low after the earlier halving -- applied once here at the single death-reward choke point (_grant_death_rewards()), so it covers every enemy.xp_reward, BOSS_XP_REWARD, and elite/minion overrides uniformly rather than needing 12+ separate .tres edits.
const RARITY_WEIGHTS := {"common": 0.55, "rare": 0.30, "epic": 0.15}
# Elite rolls apply to any regular monster, including the ones that now
# spawn alongside a boss wave (see _start_next_wave()) -- only the boss
# itself is excluded, since it already has its own cycle-based scaling in
# _boss_hp_mult() and is spawned via the separate _spawn_boss(), never
# through _spawn_one(). 5% matches the ratio the (deferred) big-wave plan
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
var _pending_boss: EnemyData = null  # set on boss waves, spawned once _spawn_queue empties -- see _spawn_boss()
var _pending_boss_hp_mult := 1.0


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

	# (2026-07-16, revised) Hand-authored waves 1-5 are back to a flat 1.0x --
	# an earlier fix here applied the wave-number scaling formula from wave 1
	# onward to smooth out the wave-6 cliff, but that also pulled waves 2-5's
	# HP up to as much as 2.0x, which is what actually made "wave 1-5 too hard
	# with melee swarms" worse. Waves 1-5 were already hand-tuned assuming a
	# flat 1.0x, so leave them alone; the cliff is fixed differently below.
	_current_damage_mult = 1.0
	_current_xp_override = -1
	_current_visual_scale = 1.0

	if current_wave_index < waves.size():
		_current_wave = waves[current_wave_index]
		_current_hp_mult = 1.0
		_current_speed_mult = 1.0
	else:
		_current_wave = _generate_wave(wave_number)

	wave_started.emit(wave_number)
	SignalBus.wave_started.emit(wave_number, _is_boss_wave)
	GameManager.set_play_state(_is_boss_wave)
	_spawn_queue.clear()
	_pending_boss = null

	# Regular monsters spawn on boss waves too now (scaled the same as any
	# other wave at this wave_number, via _current_wave/_current_hp_mult/
	# _current_speed_mult set above) -- the boss itself is held back as
	# "pending" and only actually spawns once this regular queue empties,
	# see _on_spawn_tick(). Kept as a separate spawn (not added to
	# _spawn_queue) since it needs its own boss-specific hp/damage/visual
	# multipliers, not the wave's normal ones.
	for i in _current_wave.enemy_pool.size():
		for _n in _current_wave.spawn_counts[i]:
			_spawn_queue.append(_current_wave.enemy_pool[i])
	_spawn_queue.shuffle()

	if _is_boss_wave:
		var cycle := wave_number / BOSS_WAVE_INTERVAL
		_pending_boss = boss_pool[(cycle - 1) % boss_pool.size()]
		_pending_boss_hp_mult = _boss_hp_mult(cycle)

	# The boss counts toward _alive_count from the start too (as "still
	# pending"), even though it isn't spawned yet -- otherwise the wave
	# could read as cleared the moment the last regular monster dies, before
	# the boss has even appeared. See _spawn_boss()/notify_enemy_died().
	_alive_count = _spawn_queue.size() + (1 if _is_boss_wave else 0)
	_spawn_timer.wait_time = _current_wave.spawn_interval
	_spawn_timer.start()


const PROCEDURAL_TYPES_PER_WAVE := 3  # (2026-07-16) was 1 -- a single random type per wave meant any wave that happened to roll the pool's one ranged species (Cursed Wraith) became 100% ranged monsters; picking several distinct types every wave mixes melee/ranged naturally without needing to hand-classify each species.
const BOSS_WAVE_MONSTER_MULT := 0.5  # (2026-07-16) regular monsters still spawn alongside the boss (see _start_next_wave()), but the normal per-wave count formula was never discounted for that -- wave 10 got the boss AND a full, further-scaled swarm of regular enemies at the same time, which read as much harder than every other wave. Halves the regular spawn count specifically on boss waves.


func _generate_wave(wave_number: int) -> WaveData:
	var wave := WaveData.new()
	wave.wave_number = wave_number
	var pool := procedural_enemy_pool.duplicate()
	pool.shuffle()
	var type_count: int = mini(PROCEDURAL_TYPES_PER_WAVE, pool.size())
	wave.enemy_pool = pool.slice(0, type_count)

	var extra_waves := wave_number - waves.size()
	var count: int = _last_authored_count() + COUNT_SCALING_PER_WAVE * extra_waves
	wave.is_boss_wave = wave_number % BOSS_WAVE_INTERVAL == 0
	if wave.is_boss_wave:
		count = roundi(count * BOSS_WAVE_MONSTER_MULT)
	wave.spawn_counts = _split_count(count, wave.enemy_pool.size())
	wave.spawn_interval = maxf(SPAWN_INTERVAL_FLOOR, _last_authored_interval() - SPAWN_INTERVAL_DECAY * extra_waves)

	# (2026-07-16) Scaled off extra_waves (wave 6 = extra_waves 1), not
	# wave_number directly -- wave 6 used to jump straight from waves 1-5's
	# flat 1.0x to 1.0 + HP_SCALING_PER_WAVE*(6-1) = 2.25x in a single step,
	# a hard difficulty wall. Starting the ramp fresh at wave 6 (1.25x) and
	# climbing from there removes the cliff without touching waves 1-5.
	_current_hp_mult = minf(1.0 + HP_SCALING_PER_WAVE * extra_waves, HP_MULT_CEILING)
	_current_speed_mult = 1.0 + SPEED_SCALING_PER_WAVE * extra_waves
	return wave


func _split_count(total: int, bucket_count: int) -> Array[int]:
	# Distributes total as evenly as possible across bucket_count buckets --
	# e.g. _split_count(11, 3) -> [4, 4, 3], preserving the exact total rather
	# than losing spawns to integer-division rounding.
	var result: Array[int] = []
	var base_count := total / bucket_count
	var remainder := total % bucket_count
	for i in bucket_count:
		result.append(base_count + (1 if i < remainder else 0))
	return result


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


func _on_spawn_tick() -> void:
	if _spawn_queue.is_empty():
		_spawn_timer.stop()
		if _pending_boss != null:
			_spawn_boss()
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
	# Only ever called for regular monsters -- the boss is spawned
	# separately via _spawn_boss(), so no need to exclude boss waves here.
	var is_elite := randf() < ELITE_CHANCE
	var hp_mult := _current_hp_mult * (ELITE_HP_MULT if is_elite else 1.0)
	var speed_mult := _current_speed_mult * (ELITE_SPEED_MULT if is_elite else 1.0)
	var damage_mult := _current_damage_mult * (ELITE_DAMAGE_MULT if is_elite else 1.0)
	var xp_override := roundi(enemy_data.xp_reward * ELITE_XP_MULT) if is_elite else _current_xp_override
	spawner.spawn(enemy_data, hp_mult, speed_mult, damage_mult, xp_override, _current_visual_scale, x_override, is_elite)


func _spawn_boss() -> void:
	var boss_data := _pending_boss
	_pending_boss = null
	spawner.spawn(boss_data, _pending_boss_hp_mult, 1.0, BOSS_DAMAGE_MULT, BOSS_XP_REWARD, BOSS_VISUAL_SCALE, -1.0, false)


func notify_enemy_died() -> void:
	_alive_count -= 1
	if _alive_count <= 0 and _spawn_queue.is_empty() and _pending_boss == null:
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
		player.gain_xp(roundi(xp_reward * MONSTER_XP_MULT))
	if randf() < drop_chance:
		var item: ItemData = roll_item_drop()
		if item != null:
			var pickup = ITEM_PICKUP_SCENE.instantiate()
			pickup.item_data = item  # BEFORE add_child — _ready() reads it synchronously
			pickup.global_position = death_position
			get_tree().current_scene.add_child(pickup)
