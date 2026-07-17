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
	_assert_wave_tank_balance()
	await _assert_leaked_enemy_deactivates()
	await _assert_elite_tint_restores_own_color()
	await _assert_dead_enemy_not_targeted()
	_assert_player_movement_clamping()
	_assert_trap_zone_activation()
	await _assert_stats_panel_renders()
	await _assert_elemental_homing_never_misses()
	await _assert_maxed_element_still_offers_repeatable_cards()


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


func _assert_wave_tank_balance() -> void:
	# (2026-07-17) Real playtest report: waves 6+ could roll 2-3 tank species
	# at once and become nearly unclearable. Checks the fix holds across many
	# generations: never more than 1 tank species per wave, and when one
	# does appear, its population share stays capped.
	var wm := WaveManager.new()
	wm.waves = [
		load("res://resources/waves/wave_01.tres"), load("res://resources/waves/wave_02.tres"),
		load("res://resources/waves/wave_03.tres"), load("res://resources/waves/wave_04.tres"),
		load("res://resources/waves/wave_05.tres"),
	]
	wm.procedural_enemy_pool = [
		load("res://resources/enemies/slime_scout.tres"), load("res://resources/enemies/goblin_runner.tres"),
		load("res://resources/enemies/bat_swarm.tres"), load("res://resources/enemies/stinger_wasp.tres"),
		load("res://resources/enemies/cursed_wraith.tres"), load("res://resources/enemies/skeleton_soldier.tres"),
		load("res://resources/enemies/wolf_beast.tres"), load("res://resources/enemies/shield_skeleton.tres"),
		load("res://resources/enemies/armored_gargoyle.tres"), load("res://resources/enemies/armored_brute.tres"),
		load("res://resources/enemies/stone_golem.tres"),
	]
	for _trial in 30:
		var wave: WaveData = wm._generate_wave(9)
		var tank_species_count := 0
		var tank_count := 0
		var total := 0
		for i in wave.enemy_pool.size():
			total += wave.spawn_counts[i]
			if wave.enemy_pool[i].role == "tank":
				tank_species_count += 1
				tank_count += wave.spawn_counts[i]
		assert(tank_species_count <= 1, "wave 9 rolled %d tank species in one trial, expected at most 1" % tank_species_count)
		if tank_count > 0:
			assert(float(tank_count) / float(total) <= 0.2, "a rolled tank species' population share should stay capped around 15%%, got %.1f%%" % (float(tank_count) / float(total) * 100.0))


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
	assert(not enemy.is_in_group("enemy"), "a leaked enemy must leave the 'enemy' group")

	spawner.queue_free()
	pool.queue_free()
	# Both queue_free() calls above are deferred -- without actually waiting
	# for them, the next assertion's fresh EnemySpawner/EnemyPool would
	# coexist with these in the same groups, making get_first_node_in_group()
	# ambiguous (a node could get acquired-from/released-to this stale pool
	# instead, then vanish once ITS deferred free finally processes).
	await get_tree().process_frame
	await get_tree().process_frame


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
	await get_tree().process_frame
	await get_tree().process_frame


func _assert_dead_enemy_not_targeted() -> void:
	# (2026-07-17) Real bug caught by the user's first live playtest: a
	# defeated pooled enemy was never removed from the "enemy" group, so
	# Player._get_nearest_enemies() kept finding and aiming at dead,
	# invisible enemies -- reading as "attacks nothing" right after a kill.
	var spawner := EnemySpawner.new()
	spawner.name = "EnemySpawner"
	add_child(spawner)
	var pool := EnemyPool.new()
	add_child(pool)
	var player_scene = load("res://scenes/player/Player.tscn")
	var player: Player = player_scene.instantiate()
	add_child(player)
	player.global_position = Vector2(360, 1150)

	var slime = load("res://resources/enemies/slime_scout.tres")
	var enemy: EnemyBase = spawner.spawn(slime, 1.0, 1.0, 1.0, -1, 1.0, 400.0, false)
	enemy.global_position = Vector2(400, 300)
	assert(player._get_nearest_enemies(1).has(enemy), "a live enemy should be targetable")

	enemy._die()
	await get_tree().create_timer(enemy.DEATH_FADE_DURATION + 0.15).timeout

	assert(not enemy.is_in_group("enemy"), "a dead enemy must leave the 'enemy' group")
	assert(not player._get_nearest_enemies(5).has(enemy), "a dead enemy must never be selected as a target again")

	player.queue_free()
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


func _assert_stats_panel_renders() -> void:
	# (2026-07-17) New Pause Menu "Stats" panel showing the player's current
	# obtained stats (all sources folded together -- meta, in-run picks,
	# equipment -- since they share the same underlying vars on Player).
	# _build_stats_rows() finds the player via get_first_node_in_group("player"),
	# same as open_skills_panel() in real gameplay -- so any earlier test's
	# player still mid-deferred-free would be picked up instead of this one's.
	# See the recurring test-rig group-ambiguity issue elsewhere in this file.
	await get_tree().process_frame
	await get_tree().process_frame
	var player_scene = load("res://scenes/player/Player.tscn")
	var player: Player = player_scene.instantiate()
	add_child(player)
	var fire_t1 = load("res://resources/upgrades/fire_t1_searing_shot.tres")
	player.apply_element_upgrade(fire_t1)

	var pause_menu_scene = load("res://scenes/ui/PauseMenu.tscn")
	var pause_menu: PauseMenu = pause_menu_scene.instantiate()
	add_child(pause_menu)

	pause_menu._build_stats_rows()
	var sections := pause_menu.stats_rows_container.get_children()
	assert(sections.size() == 2, "expected Core + Fire sections only, got %d" % sections.size())
	var titles: Array[String] = []
	for section in sections:
		titles.append((section.get_child(0) as Label).text)
	assert(titles.has("Core"), "Stats panel missing Core section")
	assert(titles.has("Fire"), "Stats panel missing Fire section for an unlocked element")
	assert(not titles.has("Frost"), "Stats panel should not show a locked element's section")

	player.queue_free()
	pause_menu.queue_free()


func _assert_elemental_homing_never_misses() -> void:
	# (2026-07-17) User asked for elemental shots to never miss a target.
	# Fire Arrow's own straight-line lead prediction against a zigzagging
	# enemy previously landed well under 100% (see entries 30-31's measured
	# 76-80% at long range) -- Projectile.homing_target now re-aims at the
	# live target every physics frame instead, which should make a miss
	# structurally impossible as long as the enemy stays alive and in range.
	await get_tree().process_frame
	await get_tree().process_frame
	var pool := ProjectilePool.new()
	add_child(pool)
	var player_scene = load("res://scenes/player/Player.tscn")
	var player: Player = player_scene.instantiate()
	add_child(player)
	player.global_position = Vector2(360, 1150)
	var fire_t1 = load("res://resources/upgrades/fire_t1_searing_shot.tres")
	player.apply_element_upgrade(fire_t1)

	var spawner := EnemySpawner.new()
	spawner.name = "EnemySpawner"
	add_child(spawner)
	var enemy_pool := EnemyPool.new()
	add_child(enemy_pool)
	var goblin = load("res://resources/enemies/goblin_runner.tres")
	assert(goblin.zigzag_speed > 0.0, "sanity: goblin_runner should actually be a zigzag mover")

	var trials := 8
	var hits := 0
	for trial in trials:
		var enemy: EnemyBase = spawner.spawn(goblin, 1.0, 1.0, 1.0, -1, 1.0, 900.0, false)
		enemy.global_position = Vector2(randf_range(100.0, 620.0), 250.0)
		var hp_before: float = enemy.current_hp
		player._on_fire_skill_timeout()
		var elapsed := 0.0
		while elapsed < 2.5:
			await get_tree().physics_frame
			elapsed += 1.0 / 60.0
			if not is_instance_valid(enemy) or enemy.current_hp < hp_before:
				break
		if not is_instance_valid(enemy) or enemy.current_hp < hp_before:
			hits += 1
		if is_instance_valid(enemy):
			enemy.queue_free()
		await get_tree().process_frame
	assert(hits == trials, "homing Fire Arrow should hit a zigzagging enemy every trial, got %d/%d" % [hits, trials])

	player.queue_free()
	spawner.queue_free()
	enemy_pool.queue_free()
	pool.queue_free()


func _assert_maxed_element_still_offers_repeatable_cards() -> void:
	# (2026-07-17) User asked for elemental cooldown/damage boosts to still be
	# obtainable after an element is fully maxed. Found the pool already had
	# repeatable damage/cooldown/duration/combo cards for this exact purpose
	# (fire_damage_boost.tres etc.) -- an earlier pass had cut them off once
	# current_tier reached max_tier on the mistaken assumption they'd become a
	# dead choice, when the stats they modify (fire_skill_dmg_mult etc.) stay
	# in active use by _fire_elemental_skill() at every tier, maxed or not.
	await get_tree().process_frame
	await get_tree().process_frame
	var main = load(MAIN_SCENE).instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var player: Player = get_tree().get_first_node_in_group("player")
	var popup: WaveUpgradePopup = get_tree().get_first_node_in_group("wave_upgrade_popup")
	assert(is_instance_valid(player) and is_instance_valid(popup), "real Main.tscn should have a player + wave_upgrade_popup")

	for tier in [1, 2, 3, 4]:
		var upgrade: UpgradeResource = null
		for candidate in popup.upgrade_pool:
			if candidate.element == UpgradeResource.ElementType.FIRE and candidate.tier == tier:
				upgrade = candidate
				break
		assert(upgrade != null, "missing a real fire tier-%d upgrade resource in the wired pool" % tier)
		player.apply_element_upgrade(upgrade)
	assert(player.fire_level == 4, "fire should be fully maxed, got tier %d" % player.fire_level)

	var offer := popup._get_offerable_upgrades(UpgradeResource.ElementType.FIRE)
	assert(not offer.is_empty(), "a maxed Fire should still offer its repeatable boost cards, not go silent for the rest of the run")
	assert(offer[0].tier == 0, "a maxed element should only ever offer tier=0 repeatable cards now, got tier %d" % offer[0].tier)

	main.queue_free()
