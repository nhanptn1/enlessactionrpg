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
# (2026-07-17) 1->10, plus a MAX_WAVE_MONSTER_COUNT ceiling -- Phase 2 pillar 6
# ("bigger wave scale", plan/monster-waves-progression.txt) targets 50-100
# total monsters by mid/late waves, not the previous ~1-per-wave crawl. Hand-
# authored waves 1-5 were retuned to the plan's own 20/25/30/35/40 totals (see
# those .tres files); this formula continues the same ramp from wave 6 on:
# 40 (wave 5's new total) + 10*extra_waves hits the plan's wave 6-9 targets
# (50/60/70/80) exactly, then the ceiling below caps further growth at the
# plan's stated "late game: 100 monsters maximum."
const COUNT_SCALING_PER_WAVE := 10
const MAX_WAVE_MONSTER_COUNT := 100
const SPAWN_INTERVAL_DECAY := 0.03
const SPAWN_INTERVAL_FLOOR := 0.35
# (2026-07-17) Active-on-screen cap for generated waves -- plan's own table
# ramps 9/10/12/12-15 across waves 6-9, then holds at "10 to 15 active"
# indefinitely. 8+extra_waves clamped to 15 tracks that closely without
# needing a literal per-wave lookup (hand-authored waves 1-5 set their own
# max_active directly in their .tres, matching the plan's 5/6/6/7/8 table).
const MAX_ACTIVE_CEILING := 15
const MAX_ACTIVE_BASE := 8
# (2026-07-17) 0.5->0.2 (regular-monster share) plus a direct clamp -- the
# plan's own target is "boss + 10 to 25 support monsters" regardless of how
# late the boss cycle is, but the generated count formula above keeps growing
# every wave (including boss waves), so a fixed fraction alone would drift
# well past 25 by later cycles. The clamp is what actually keeps this
# in-range long-term; the fraction just keeps early cycles from jumping
# straight to the clamp's ceiling.
const BOSS_WAVE_MONSTER_MULT := 0.2
const BOSS_WAVE_MONSTER_MIN := 10
const BOSS_WAVE_MONSTER_MAX := 25
# (2026-07-16) 15.0->75.0 (x5) per direct user request.
const BOSS_HP_MULT_BASE := 75.0
const BOSS_HP_MULT_GROWTH_PER_CYCLE := 0.2
const BOSS_DAMAGE_MULT := 2.0
const BOSS_XP_REWARD := 100  # (2026-07-16) 200->100, halved alongside every regular enemy's xp_reward
const BOSS_VISUAL_SCALE := 1.5
# (2026-07-17) Phase 3 pillar 1: endless boss variety. boss_pool only has 4
# entries, so once the rotation has gone around once (cycle 2+), a mutation
# rolled onto the spawn keeps repeat fights from being byte-for-byte
# identical -- see BossBase.MUTATIONS for what each one actually does. Cycle
# 1 (a player's very first-ever boss encounter, wave 10) is deliberately left
# unmutated so the fight is learned clean first.
const BOSS_MUTATION_CHANCE := 0.5
const BOSS_MUTATION_MIN_CYCLE := 2
const BOSS_MUTATION_IDS: Array[String] = ["enraged", "shielded", "volatile"]
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
# Subset of _alive_count that's actually been spawned and is still alive on
# screen (as opposed to still sitting in _spawn_queue) -- see
# WaveData.max_active / _on_spawn_tick(). Never touched by boss spawns/deaths
# (bosses go through _spawn_boss(), not _spawn_one(), and are never meant to
# count against the regular-monster active cap).
var _active_on_screen := 0
var _spawn_queue: Array[EnemyData] = []
var _spawn_timer: Timer
var _pending_boss: EnemyData = null  # set on boss waves, spawned once _spawn_queue empties -- see _spawn_boss()
var _pending_boss_hp_mult := 1.0
var _pending_boss_mutation_id: String = ""  # "" = no mutation this cycle -- see BOSS_MUTATION_* above


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
	# (2026-07-17) Bounty Hunter run modifier -- applies to every wave
	# (hand-authored 1-5 included), unlike enemy_count_mult below which only
	# touches generated waves since hand-authored spawn_counts are a fixed
	# array baked into each wave's .tres, not worth mutating at runtime.
	_current_hp_mult *= _get_modifier_mult("enemy_hp_mult")

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
		# (2026-07-17) Bounty Hunter run modifier -- was only reaching regular
		# wave monsters via _current_hp_mult above, leaving the boss itself
		# completely unaffected despite the modifier's own description ("enemies
		# have +25% HP") making no boss carve-out, unlike Swarm Warning's
		# deliberately-documented one. A real gap, caught by review.
		_pending_boss_hp_mult = _boss_hp_mult(cycle) * _get_modifier_mult("enemy_hp_mult")
		_pending_boss_mutation_id = ""
		if cycle >= BOSS_MUTATION_MIN_CYCLE and randf() < BOSS_MUTATION_CHANCE:
			_pending_boss_mutation_id = BOSS_MUTATION_IDS[randi() % BOSS_MUTATION_IDS.size()]

	# The boss counts toward _alive_count from the start too (as "still
	# pending"), even though it isn't spawned yet -- otherwise the wave
	# could read as cleared the moment the last regular monster dies, before
	# the boss has even appeared. See _spawn_boss()/notify_enemy_died().
	_alive_count = _spawn_queue.size() + (1 if _is_boss_wave else 0)
	_active_on_screen = 0
	_spawn_timer.wait_time = _current_wave.spawn_interval
	_spawn_timer.start()


const PROCEDURAL_TYPES_PER_WAVE := 3  # (2026-07-16) was 1 -- a single random type per wave meant any wave that happened to roll the pool's one ranged species (Cursed Wraith) became 100% ranged monsters; picking several distinct types every wave mixes melee/ranged naturally without needing to hand-classify each species.
# (2026-07-17) 4 of the 11 procedural species (EnemyData.role == "tank") are
# meaningfully tougher than everything else in the pool -- with the old
# uniform-random 3-species draw and an even count split, a wave could roll
# 2-3 tank species and end up almost entirely made of high-HP monsters,
# exactly the "wave 6+ has too many tanks, can't clear it" report this fixes.
# Caps species SELECTION to at most 1 tank per wave (structural -- see
# _pick_procedural_species()), and caps that tank species' POPULATION share
# once selected -- implementing plan/monster-waves-progression.txt section
# 6's "10% tank" mix rule, which was never actually wired up until now.
const TANK_SPECIES_CHANCE := 0.35  # odds a generated wave includes a tank species at all
const TANK_COUNT_SHARE := 0.15  # that species' population share of the wave, when it appears


func _generate_wave(wave_number: int) -> WaveData:
	var wave := WaveData.new()
	wave.wave_number = wave_number
	var type_count: int = mini(PROCEDURAL_TYPES_PER_WAVE, procedural_enemy_pool.size())
	wave.enemy_pool = _pick_procedural_species(type_count)

	var extra_waves := wave_number - waves.size()
	var count: int = mini(_last_authored_count() + COUNT_SCALING_PER_WAVE * extra_waves, MAX_WAVE_MONSTER_COUNT)
	# (2026-07-17) Swarm Warning run modifier -- only touches generated waves
	# (wave 6+); the boss-wave clamp just below re-clamps regardless, so this
	# naturally doesn't inflate a boss wave's support-monster count.
	count = mini(roundi(count * _get_modifier_mult("enemy_count_mult")), MAX_WAVE_MONSTER_COUNT)
	wave.is_boss_wave = wave_number % BOSS_WAVE_INTERVAL == 0
	if wave.is_boss_wave:
		count = clampi(roundi(count * BOSS_WAVE_MONSTER_MULT), BOSS_WAVE_MONSTER_MIN, BOSS_WAVE_MONSTER_MAX)
	wave.spawn_counts = _split_count_favoring_non_tanks(count, wave.enemy_pool)
	wave.spawn_interval = maxf(SPAWN_INTERVAL_FLOOR, _last_authored_interval() - SPAWN_INTERVAL_DECAY * extra_waves)
	wave.max_active = mini(MAX_ACTIVE_CEILING, MAX_ACTIVE_BASE + extra_waves)

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


func _pick_procedural_species(type_count: int) -> Array[EnemyData]:
	# At most 1 tank species per wave (structural, not a counted loop).
	# Whether a tank appears at all is decided up front with its own
	# roll (TANK_SPECIES_CHANCE): with 7 non-tank species in the pool today,
	# just "fill non-tanks first, tanks only if slots are left over" would
	# never actually leave a slot over and tanks would never appear at all --
	# reserving a slot explicitly is what keeps them a real, if capped,
	# possibility instead of an accidental total absence.
	var tanks: Array[EnemyData] = []
	var non_tanks: Array[EnemyData] = []
	for e in procedural_enemy_pool:
		if e.role == "tank":
			tanks.append(e)
		else:
			non_tanks.append(e)
	non_tanks.shuffle()
	tanks.shuffle()

	var include_tank := not tanks.is_empty() and randf() < TANK_SPECIES_CHANCE
	var non_tank_slots: int = type_count - (1 if include_tank else 0)
	var species: Array[EnemyData] = []
	species.append_array(non_tanks.slice(0, mini(non_tank_slots, non_tanks.size())))
	if include_tank:
		species.append(tanks[0])
	# Only reachable if the pool has fewer than type_count non-tank species
	# (not true today at 7 non-tank species, but stay correct if the roster
	# ever shrinks) -- fill any still-empty slots from whatever's left.
	while species.size() < type_count and species.size() < procedural_enemy_pool.size():
		for e in procedural_enemy_pool:
			if species.size() >= type_count:
				break
			if not species.has(e):
				species.append(e)
	return species


func _split_count_favoring_non_tanks(total: int, species: Array[EnemyData]) -> Array[int]:
	var tank_indices: Array[int] = []
	var non_tank_indices: Array[int] = []
	for i in species.size():
		if species[i].role == "tank":
			tank_indices.append(i)
		else:
			non_tank_indices.append(i)
	if tank_indices.is_empty() or non_tank_indices.is_empty():
		return _split_count(total, species.size())

	var tank_total := roundi(total * TANK_COUNT_SHARE)
	var non_tank_total := total - tank_total
	var tank_split := _split_count(tank_total, tank_indices.size())
	var non_tank_split := _split_count(non_tank_total, non_tank_indices.size())
	var result: Array[int] = []
	result.resize(species.size())
	for i in tank_indices.size():
		result[tank_indices[i]] = tank_split[i]
	for i in non_tank_indices.size():
		result[non_tank_indices[i]] = non_tank_split[i]
	return result


func _boss_hp_mult(cycle: int) -> float:
	return BOSS_HP_MULT_BASE * (1.0 + BOSS_HP_MULT_GROWTH_PER_CYCLE * (cycle - 1))


# WaveManager doesn't roll or own the active run modifier -- Player does (see
# _apply_run_modifier()), same as every other player-stat consultation in
# this codebase (StatusEffects._get_player(), boss_base.gd, etc.) fetching
# via group lookup rather than the value being pushed around.
func _get_modifier_mult(key: String) -> float:
	# _generate_wave() is designed to be callable on a standalone WaveManager
	# that was never add_child()'d (the established test pattern throughout
	# this file's own smoke tests) -- get_tree() is null in that case, not
	# just "no player found", so this must be checked first.
	if not is_inside_tree():
		return 1.0
	var player := get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player):
		return 1.0
	return RunModifiers.get_mult(player.active_run_modifier_id, key)


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
	# Peek (don't pop yet) so a clustering species' full cluster_size can be
	# checked against the cap as one unit -- checking only _active_on_screen
	# here (as if every entry were cluster_size 1) let a cluster's for-loop
	# below push _active_on_screen past max_active by up to cluster_size-1,
	# since nothing re-checked the cap between individual spawns in the loop.
	var enemy_data: EnemyData = _spawn_queue[-1]
	var cluster_size: int = maxi(enemy_data.cluster_size, 1)
	if _active_on_screen + cluster_size > _current_wave.max_active:
		return  # this entry's full cluster doesn't fit yet -- wait for a slot to open, try again next tick
	_spawn_queue.pop_back()
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
	_active_on_screen += 1


func _spawn_boss() -> void:
	var boss_data := _pending_boss
	var mutation_id := _pending_boss_mutation_id
	_pending_boss = null
	spawner.spawn(boss_data, _pending_boss_hp_mult, 1.0, BOSS_DAMAGE_MULT, BOSS_XP_REWARD, BOSS_VISUAL_SCALE, -1.0, false, true, mutation_id)


func notify_enemy_died() -> void:
	_alive_count -= 1
	if _alive_count <= 0 and _spawn_queue.is_empty() and _pending_boss == null:
		var was_boss := _is_boss_wave
		wave_cleared.emit(_current_wave.wave_number)
		SignalBus.wave_cleared.emit(_current_wave.wave_number, was_boss)
		_start_next_wave()


func _on_enemy_died(xp_reward: int, drop_chance: float, death_position: Vector2, is_boss: bool = false) -> void:
	# Bound to `true`/`false` at connect time in enemy_spawner.gd rather than
	# split into two near-identical functions -- a boss is spawned via
	# _spawn_boss(), never _spawn_one(), so it was never counted into
	# _active_on_screen in the first place and must not decrement it either.
	_grant_death_rewards(xp_reward, drop_chance, death_position)
	if not is_boss:
		_active_on_screen = maxi(_active_on_screen - 1, 0)
	notify_enemy_died()


func notify_enemy_left_screen() -> void:
	# A regular enemy that leaked off the bottom without dying (enemy_base.gd's
	# _on_screen_exited()) still frees up its active-on-screen slot, same as
	# an actual kill -- only ever called for _is_wave_tracked regular
	# enemies, so this can never apply to a boss (which has no leak mechanic
	# at all) or a boss-summoned minion (never wave-tracked).
	_active_on_screen = maxi(_active_on_screen - 1, 0)
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
