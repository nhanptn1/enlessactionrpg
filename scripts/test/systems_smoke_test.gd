extends Node2D
## Headless smoke test — run: godot --headless --path . res://scenes/test/SystemsSmokeTest.tscn

const MAIN_SCENE := "res://scenes/main/Main.tscn"


func _ready() -> void:
	_assert_autoloads()
	_assert_skill_resources()
	await _assert_save_roundtrip()
	print("SystemsSmokeTest: ALL PASSED")
	get_tree().quit(0)


func _assert_autoloads() -> void:
	assert(SignalBus != null, "SignalBus missing")
	assert(GameManager != null, "GameManager missing")
	assert(AudioManager != null, "AudioManager missing")
	assert(SaveManager != null, "SaveManager missing")
	assert(AudioManager._streams.size() > 0, "AudioManager has no streams")


func _assert_skill_resources() -> void:
	var trap_shot = load("res://resources/skills/trap_shot.tres")
	assert(trap_shot != null, "trap_shot.tres failed to load")
	assert(trap_shot.fire_mode == SkillData.FireMode.TRAP_SHOT)
	assert(load(MAIN_SCENE) != null, "Main.tscn failed to load")


func _assert_save_roundtrip() -> void:
	var before_wave := SaveManager.best_wave
	SaveManager.record_run(before_wave + 1, SaveManager.best_level + 1)
	assert(SaveManager.best_wave >= before_wave + 1)
	assert(SaveManager.load_save())
	_assert_meta_progression()
	_assert_equipment_slots()
	_assert_audio_depth()
	_assert_wave_scale()
	await _assert_leaked_enemy_deactivates()
	await _assert_elite_tint_restores_own_color()
	_assert_player_movement_clamping()
	_assert_trap_zone_activation()


func _assert_meta_progression() -> void:
	# Reset vitality to rank 0 first -- repeated runs of this same smoke test
	# (e.g. during dev iteration) would otherwise accumulate rank across runs
	# until it hits max_rank, after which a fresh purchase correctly fails
	# and this assertion would flake.
	SaveManager.meta_upgrades["vitality"] = 0
	var before_essence := SaveManager.essence
	SaveManager.add_essence(1000)
	assert(SaveManager.essence == before_essence + 1000, "add_essence should increase essence")
	assert(SaveManager.purchase_meta_upgrade("vitality"), "purchase should succeed with enough essence")
	assert(SaveManager.get_meta_rank("vitality") == 1, "purchase should increment rank")
	assert(SaveManager.load_save(), "meta-progression state should round-trip through disk")
	assert(SaveManager.get_meta_rank("vitality") == 1, "rank should persist after reload")


func _assert_equipment_slots() -> void:
	var apprentice_bow = load("res://resources/items/apprentice_bow.tres")
	var silver_longbow = load("res://resources/items/silver_longbow.tres")
	var player_scene = load("res://scenes/player/Player.tscn")
	var player = player_scene.instantiate()
	add_child(player)

	var base_damage_mult: float = player.damage_mult
	player.apply_item(apprentice_bow)
	assert(player.equipped["weapon"] == apprentice_bow, "weapon slot should hold the equipped item")
	player.apply_item(silver_longbow)
	assert(player.equipped["weapon"] == silver_longbow, "2nd weapon should replace the 1st in the same slot")
	assert(is_equal_approx(player.damage_mult, base_damage_mult + 0.04), "replacing gear should revert the old bonus before applying the new one, got %s" % player.damage_mult)

	player.queue_free()


func _assert_audio_depth() -> void:
	for id in ["heal", "elite_spawn", "enemy_shot", "item_pickup_rare"]:
		assert(AudioManager._streams.has(id), "AudioManager missing stream '%s'" % id)

	var player_scene = load("res://scenes/player/Player.tscn")
	var player = player_scene.instantiate()
	add_child(player)
	var healed := [false]
	var conn := func(_amount): healed[0] = true
	SignalBus.player_healed.connect(conn)
	player.current_hp = 1.0
	player.apply_upgrade("hp")
	assert(healed[0], "a real heal should emit SignalBus.player_healed")
	SignalBus.player_healed.disconnect(conn)
	player.queue_free()


func _assert_wave_scale() -> void:
	var wm := WaveManager.new()
	wm.waves = [
		load("res://resources/waves/wave_01.tres"), load("res://resources/waves/wave_02.tres"),
		load("res://resources/waves/wave_03.tres"), load("res://resources/waves/wave_04.tres"),
		load("res://resources/waves/wave_05.tres"),
	]
	wm.procedural_enemy_pool = [load("res://resources/enemies/slime_scout.tres")]

	var wave6: WaveData = wm._generate_wave(6)
	var wave6_total := 0
	for c in wave6.spawn_counts:
		wave6_total += c
	assert(wave6_total == 50, "wave 6 should total 50 monsters per the plan's ramp, got %d" % wave6_total)

	var boss_wave: WaveData = wm._generate_wave(10)
	var boss_total := 0
	for c in boss_wave.spawn_counts:
		boss_total += c
	assert(boss_total >= 10 and boss_total <= 25, "boss wave support count should stay 10-25, got %d" % boss_total)

	var late_wave: WaveData = wm._generate_wave(40)
	var late_total := 0
	for c in late_wave.spawn_counts:
		late_total += c
	assert(late_total <= 100, "late-game wave total should stay capped at 100, got %d" % late_total)


func _assert_leaked_enemy_deactivates() -> void:
	var spawner := EnemySpawner.new()
	spawner.name = "EnemySpawner"
	add_child(spawner)
	var pool := EnemyPool.new()
	add_child(pool)

	var cursed_wraith = load("res://resources/enemies/cursed_wraith.tres")
	var enemy: EnemyBase = spawner.spawn(cursed_wraith, 1.0, 1.0, 1.0, -1, 1.0, 100.0, false)
	enemy._on_screen_exited()
	await get_tree().process_frame

	assert(not enemy.is_physics_processing(), "a leaked enemy must stop physics_process")
	assert(enemy.collision.disabled, "a leaked enemy must disable collision")
	assert(not enemy.hurtbox.monitoring, "a leaked enemy must stop hurtbox monitoring")
	assert(enemy.attack_timer.is_stopped(), "a leaked enemy must stop its attack_timer")

	spawner.queue_free()
	pool.queue_free()


func _assert_elite_tint_restores_own_color() -> void:
	var spawner := EnemySpawner.new()
	spawner.name = "EnemySpawner"
	add_child(spawner)
	var pool := EnemyPool.new()
	add_child(pool)

	var shield_skeleton = load("res://resources/enemies/shield_skeleton.tres")
	var elite: EnemyBase = spawner.spawn(shield_skeleton, 1.0, 1.0, 1.0, -1, 1.0, 100.0, true)
	elite._die()
	await get_tree().create_timer(elite.DEATH_FADE_DURATION + 0.15).timeout

	var reused: EnemyBase = spawner.spawn(shield_skeleton, 1.0, 1.0, 1.0, -1, 1.0, 100.0, false)
	assert(not reused.modulate.is_equal_approx(Color.WHITE), "a non-elite spawn must not fall back to plain white, must restore the species' own tint")

	spawner.queue_free()
	pool.queue_free()


func _assert_player_movement_clamping() -> void:
	var player_scene = load("res://scenes/player/Player.tscn")
	assert(player_scene != null, "Player.tscn failed to load")
	var player = player_scene.instantiate()
	add_child(player)
	
	# Set out-of-bounds positions and check clamping
	player.global_position = Vector2(800.0, 1150.0)
	player._physics_process(0.016)
	assert(player.global_position.x == 660.0, "Player max bounds clamp failed: %f" % player.global_position.x)
	
	player.global_position = Vector2(10.0, 1150.0)
	player._physics_process(0.016)
	assert(player.global_position.x == 60.0, "Player min bounds clamp failed: %f" % player.global_position.x)
	
	player.queue_free()


func _assert_trap_zone_activation() -> void:
	var trap_scene = load("res://scenes/effects/TrapZone.tscn")
	assert(trap_scene != null, "TrapZone.tscn failed to load")
	var trap = trap_scene.instantiate()

	# Replicates the player.gd setup: calling activate() before add_child()
	trap.activate(10.0, 3.0, 50.0, Vector2(100.0, 100.0))
	add_child(trap)

	assert(trap.visual != null, "TrapZone visual node is Nil")
	assert(trap.collision != null, "TrapZone collision node is Nil")
	assert(trap.collision.shape != null, "TrapZone collision shape is Nil")

	trap.queue_free()
	_assert_trap_detonation()


func _assert_trap_detonation() -> void:
	# Trap Mastery: detonate_mult flows through activate() and _detonate()
	# fires exactly once even if triggered twice (kill + expiry racing).
	var trap_scene = load("res://scenes/effects/TrapZone.tscn")
	var trap = trap_scene.instantiate()
	var no_status_rolls: Array[Dictionary] = []
	trap.activate(10.0, 3.0, 50.0, Vector2(100.0, 100.0), no_status_rolls, 0.8)
	add_child(trap)
	assert(trap.detonate_mult == 0.8, "TrapZone detonate_mult not set from activate()")
	trap._detonate()
	assert(trap._detonated, "TrapZone did not mark itself detonated")
	trap._detonate()  # second call must be a no-op, not a double-trigger
	trap.queue_free()
