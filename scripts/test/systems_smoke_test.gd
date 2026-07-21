extends Node2D
## Headless smoke test — run: godot --headless --path . res://scenes/test/SystemsSmokeTest.tscn

const MAIN_SCENE := "res://scenes/main/Main.tscn"


# (2026-07-17) Shared by the tier-lookup loops below -- 3 near-identical
# copies of this had crept in across separate assertion functions written at
# different times, which is exactly how one of them (the fire tier-4 loop)
# went stale after entry 52 grew the real max tier to 5 while the others
# didn't need updating; caught by review.
func _find_upgrade(popup: WaveUpgradePopup, element: int, tier: int) -> UpgradeResource:
	for candidate in popup.upgrade_pool:
		if candidate.element == element and candidate.tier == tier:
			return candidate
	return null


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
	await _assert_dash_dodge()
	await _assert_ultimate_ability()
	_assert_trap_zone_activation()
	await _assert_stats_panel_renders()
	await _assert_elemental_homing_never_misses()
	await _assert_maxed_element_still_offers_repeatable_cards()
	await _assert_boss_mutations()
	await _assert_elemental_capstones()
	await _assert_run_modifiers()
	await _assert_review_fixes()


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


func _assert_dash_dodge() -> void:
	# (2026-07-21) Next-phase kickoff: player dash/dodge. Real Player.tscn
	# instance, real await get_tree().physics_frame ticks -- NOT manual
	# _physics_process() calls, which this session already found gives
	# unreliable move_and_slide() displacement (the engine "catches up" a
	# much larger delta than intended on the first real tick after a tight
	# synchronous loop with no yielding). Awaits after queue_free() (see
	# bottom) since every Main.tscn-loading test after this one calls
	# get_first_node_in_group("player"), and a leaked not-yet-freed instance
	# left in that group is exactly the recurring contamination bug this
	# project has hit before (entry 53's note on missing double-frame awaits).
	var player_scene = load("res://scenes/player/Player.tscn")
	var player = player_scene.instantiate()
	add_child(player)
	player.global_position = Vector2(300.0, 1150.0)
	await get_tree().physics_frame

	var start_x: float = player.global_position.x
	var hp_before: float = player.current_hp
	player._last_move_dir = 1.0
	player._start_dash()
	assert(player._is_dashing and player._is_invulnerable, "_start_dash() should set both dashing and invulnerable")

	player.take_damage(5.0)
	assert(player.current_hp == hp_before, "no damage should land while invulnerable during a dash")

	var ticks := 0
	while player._is_dashing and ticks < 60:
		await get_tree().physics_frame
		ticks += 1
	assert(not player._is_dashing and not player._is_invulnerable, "dash should end and clear invulnerability on its own")

	var dist: float = player.global_position.x - start_x
	assert(dist > 100.0 and dist < 200.0, "dash should cover roughly DASH_SPEED*DASH_DURATION, got %s" % dist)

	player.take_damage(3.0)
	assert(player.current_hp == hp_before - 3.0, "damage should apply normally again once the dash ends")

	assert(player._dash_cooldown_remaining > 0.0, "cooldown should still be active immediately after a dash, blocking spam")
	assert(not player.try_dash(), "try_dash() must refuse while the cooldown is running -- shared gate for Space and the HUD button")

	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _assert_ultimate_ability() -> void:
	# (2026-07-21) Phase 4 pillar 2: late-run ultimate. Standalone player (no
	# Main.tscn needed -- the ultimate reads only the enemy group and player
	# stats), real upgrade resources for the tier climb, real EnemyBase
	# targets. Same queue_free + double-await hygiene as _assert_dash_dodge().
	var player_scene = load("res://scenes/player/Player.tscn")
	var player = player_scene.instantiate()
	add_child(player)
	for path in [
		"res://resources/upgrades/fire_t1_searing_shot.tres",
		"res://resources/upgrades/fire_t2_inferno_growth.tres",
		"res://resources/upgrades/fire_t3_burning_legacy.tres",
		"res://resources/upgrades/fire_t4_inferno_mastery.tres",
		"res://resources/upgrades/fire_t5_inferno_heart.tres",
	]:
		player.apply_element_upgrade(load(path))
	# No projectile_pool here -- stop auto-fire so it can't error mid-test.
	player.attack_timer.stop()
	var fire_timer: Timer = player.get_elemental_timer_by_element(UpgradeResource.ElementType.FIRE)
	if is_instance_valid(fire_timer):
		fire_timer.stop()

	assert(player.is_ultimate_unlocked(), "fire capstone should unlock the ultimate")
	assert(not player.can_use_ultimate(), "uncharged ultimate must not be usable")

	for _i in player.ULTIMATE_KILLS_REQUIRED + 10:
		SignalBus.enemy_died.emit()
	assert(player.ultimate_charge == player.ULTIMATE_KILLS_REQUIRED, "charge should cap at ULTIMATE_KILLS_REQUIRED")
	assert(player.can_use_ultimate(), "capstone + full charge should make the ultimate usable")

	var slime: EnemyData = load("res://resources/enemies/slime_scout.tres")
	var enemy: EnemyBase = slime.scene.instantiate()
	enemy.setup(slime, 100.0)
	add_child(enemy)
	enemy.activate()
	enemy.global_position = Vector2(300, 300)
	var hp_before: float = enemy.current_hp
	player._use_ultimate()
	assert(player.ultimate_charge == 0, "using the ultimate should consume the full charge")
	assert(enemy.current_hp < hp_before, "the ultimate should damage every enemy in the group")
	assert(enemy.status.has(StatusEffects.FIRE), "the fire ultimate should burn every enemy it hits")

	enemy.queue_free()
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


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
	# (2026-07-17) Core + Run Modifier + Fire -- every player now always rolls
	# an active run modifier (Phase 3 pillar 3), so the Stats panel always
	# shows a 3rd section on top of the 2 this assertion originally expected.
	assert(sections.size() == 3, "expected Core + Run Modifier + Fire sections, got %d" % sections.size())
	var titles: Array[String] = []
	for section in sections:
		titles.append((section.get_child(0) as Label).text)
	assert(titles.has("Core"), "Stats panel missing Core section")
	assert(titles.has("Run Modifier"), "Stats panel missing Run Modifier section")
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
	# Missing here previously -- every other test in this file awaits a
	# couple frames after its own queue_free() calls so the next test's
	# group lookups can't pick up a stale instance still mid-deferred-free.
	# Surfaced by entry 53's next test asserting exact fire_level counts.
	await get_tree().process_frame
	await get_tree().process_frame


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

	# (2026-07-17) 1-5, not 1-4 -- entry 52 grew Fire's real max tier to 5
	# (the Inferno Heart capstone), so tier 4 alone is no longer "maxed" and
	# would legitimately still offer the tier-5 card as a next-tier option
	# (a real gap this test had already gone stale on, just not caught
	# deterministically since _get_offerable_upgrades() picks randomly).
	for tier in [1, 2, 3, 4, 5]:
		var upgrade := _find_upgrade(popup, UpgradeResource.ElementType.FIRE, tier)
		assert(upgrade != null, "missing a real fire tier-%d upgrade resource in the wired pool" % tier)
		player.apply_element_upgrade(upgrade)
	assert(player.fire_level == 5, "fire should be fully maxed, got tier %d" % player.fire_level)

	var offer := popup._get_offerable_upgrades(UpgradeResource.ElementType.FIRE)
	assert(not offer.is_empty(), "a maxed Fire should still offer its repeatable boost cards, not go silent for the rest of the run")
	assert(offer[0].tier == 0, "a maxed element should only ever offer tier=0 repeatable cards now, got tier %d" % offer[0].tier)

	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _assert_boss_mutations() -> void:
	# (2026-07-17) Phase 3 pillar 1: endless boss variety. Real boss instance,
	# not mocked -- confirms mutation_id actually changes stats/behavior, not
	# just that BossBase.MUTATIONS is a well-formed dictionary.
	var boss_data = load("res://resources/enemies/fallen_knight.tres")

	var enraged: BossBase = boss_data.scene.instantiate()
	enraged.mutation_id = "enraged"
	enraged.setup(boss_data, 1.0, 1.0, 1.0)
	add_child(enraged)
	var em: Dictionary = BossBase.MUTATIONS["enraged"]
	assert(is_equal_approx(enraged._speed_mult, em["speed_mult"]), "enraged should multiply _speed_mult")
	assert(is_equal_approx(enraged._damage_mult, em["damage_mult"]), "enraged should multiply _damage_mult")
	assert(is_equal_approx(enraged._cooldown_mult, em["cooldown_mult"]), "enraged should set _cooldown_mult")
	enraged.queue_free()

	var shielded: BossBase = boss_data.scene.instantiate()
	shielded.mutation_id = "shielded"
	shielded.setup(boss_data, 1.0, 1.0, 1.0)
	add_child(shielded)
	var hp_before := shielded.current_hp
	shielded._mutation_invulnerable = true
	shielded.take_damage(5.0)
	assert(shielded.current_hp == hp_before, "shielded boss must take zero damage during its invulnerability window")
	shielded._mutation_invulnerable = false
	shielded.take_damage(1.0)
	assert(shielded.current_hp < hp_before, "shielded boss should take damage again once the window closes")
	shielded.queue_free()

	# Wave-cycle gating: cycle 1 never mutates, cycle 2+ can.
	var cycle1_rolls := 0
	var cycle2_rolls := 0
	for _i in 200:
		if 1 >= WaveManager.BOSS_MUTATION_MIN_CYCLE and randf() < WaveManager.BOSS_MUTATION_CHANCE:
			cycle1_rolls += 1
		if 2 >= WaveManager.BOSS_MUTATION_MIN_CYCLE and randf() < WaveManager.BOSS_MUTATION_CHANCE:
			cycle2_rolls += 1
	assert(cycle1_rolls == 0, "a player's first-ever boss (cycle 1) must never roll a mutation")
	assert(cycle2_rolls > 0, "cycle 2+ should roll mutations some of the time at a 50% chance")

	await get_tree().process_frame


func _assert_elemental_capstones() -> void:
	# (2026-07-17) Phase 3 pillar 2: tier-5 elemental capstone passives
	# (Inferno Heart/Absolute Zero/Overcharge). Lighter than the throwaway
	# test -- one before/after damage ratio (Fire's burn-tick bonus) plus the
	# guaranteed-spread check, not all 3 elements' full combo math.
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
		var u := _find_upgrade(popup, UpgradeResource.ElementType.FIRE, tier)
		assert(u != null, "missing a real fire tier-%d upgrade resource" % tier)
		player.apply_element_upgrade(u)

	var slime: EnemyData = load("res://resources/enemies/slime_scout.tres")
	var e1: EnemyBase = slime.scene.instantiate()
	e1.setup(slime, 100.0)
	add_child(e1)
	e1.activate()
	e1.status[StatusEffects.FIRE] = 2.5
	var hp_before_capped := e1.current_hp
	StatusEffects.tick(e1, StatusEffects.FIRE_TICK_INTERVAL)
	var baseline_dmg := hp_before_capped - e1.current_hp
	e1.queue_free()

	var tier5 := _find_upgrade(popup, UpgradeResource.ElementType.FIRE, 5)
	assert(tier5 != null, "missing the fire tier-5 capstone resource in the wired pool")
	player.apply_element_upgrade(tier5)
	assert(player.fire_level == 5, "fire should reach capstone tier 5")
	var skill := player.get_current_skill_for_element(UpgradeResource.ElementType.FIRE)
	assert(skill.id == "wildfire_storm", "tier 5 is passive-only -- active skill should stay Wildfire Storm")

	var e2: EnemyBase = slime.scene.instantiate()
	e2.setup(slime, 100.0)
	add_child(e2)
	e2.activate()
	e2.status[StatusEffects.FIRE] = 2.5
	var hp_before_capstone := e2.current_hp
	StatusEffects.tick(e2, StatusEffects.FIRE_TICK_INTERVAL)
	var capped_dmg := hp_before_capstone - e2.current_hp
	e2.queue_free()

	var ratio := capped_dmg / baseline_dmg
	assert(is_equal_approx(ratio, StatusEffects.FIRE_CAPSTONE_DPS_MULT), "fire capstone should multiply burn tick damage by %s, got ratio %s" % [StatusEffects.FIRE_CAPSTONE_DPS_MULT, ratio])

	var e3: EnemyBase = slime.scene.instantiate()
	e3.setup(slime)
	add_child(e3)
	e3.activate()
	e3.global_position = Vector2(300, 300)
	var e4: EnemyBase = slime.scene.instantiate()
	e4.setup(slime)
	add_child(e4)
	e4.activate()
	e4.global_position = Vector2(320, 310)
	StatusEffects.apply(e3, StatusEffects.FIRE, 2.5)
	assert(e4.status.has(StatusEffects.FIRE), "Inferno Heart should guarantee a spread to a nearby enemy")
	e3.queue_free()
	e4.queue_free()

	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _assert_run_modifiers() -> void:
	# (2026-07-17) Phase 3 pillar 3: exactly one random modifier is active
	# every run. Lighter than the throwaway test -- roll coverage plus one
	# deterministic Player apply check and one WaveManager read check.
	var seen := {}
	for _i in 300:
		seen[RunModifiers.roll_random_id()] = true
	assert(seen.size() == RunModifiers.MODIFIERS.size(), "all %d modifiers should show up across 300 rolls, saw %d" % [RunModifiers.MODIFIERS.size(), seen.size()])

	for key in ["vitality", "power", "quickdraw", "insight"]:
		SaveManager.meta_upgrades[key] = 0
	var player_scene: PackedScene = load("res://scenes/player/Player.tscn")
	var player: Player = player_scene.instantiate()
	add_child(player)
	assert(RunModifiers.MODIFIERS.has(player.active_run_modifier_id), "rolled id '%s' should be a real key" % player.active_run_modifier_id)
	var expected_max_hp: float = 10.0 * RunModifiers.get_mult(player.active_run_modifier_id, "player_max_hp_mult")
	assert(is_equal_approx(player.max_hp, expected_max_hp), "max_hp should reflect the rolled modifier's mult")
	assert(player.current_hp == player.max_hp, "current_hp should be topped to the modifier-adjusted max_hp")

	# _generate_wave() must stay callable on a standalone WaveManager (never
	# add_child()'d) -- every other test in this file relies on that, and
	# _get_modifier_mult() reading get_tree() without an is_inside_tree()
	# guard broke it the first time this feature was added.
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
	assert(wave6_total > 0, "_generate_wave() must still work on a standalone WaveManager not in the scene tree")

	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _assert_review_fixes() -> void:
	# (2026-07-17) 2 real bugs a code-review pass caught right after pillar 3
	# shipped, both permanently covered since they're genuine correctness
	# gaps, not just style nits.
	_assert_bounty_hunter_affects_boss_hp()
	await _assert_enraged_speed_affects_post_engage_movement()


func _assert_bounty_hunter_affects_boss_hp() -> void:
	# Bounty Hunter's own description ("enemies have +25% HP") makes no boss
	# carve-out, unlike Swarm Warning's deliberately-documented one -- but
	# _pending_boss_hp_mult was only ever fed from _boss_hp_mult(cycle), never
	# multiplied by the modifier, leaving the boss completely unaffected.
	var spawner := EnemySpawner.new()
	spawner.name = "EnemySpawner"
	add_child(spawner)
	var wm := WaveManager.new()
	wm.waves = [
		load("res://resources/waves/wave_01.tres"), load("res://resources/waves/wave_02.tres"),
		load("res://resources/waves/wave_03.tres"), load("res://resources/waves/wave_04.tres"),
		load("res://resources/waves/wave_05.tres"),
	]
	wm.procedural_enemy_pool = [load("res://resources/enemies/slime_scout.tres")]
	wm.boss_pool = [load("res://resources/enemies/corrupted_forest_guardian.tres")]
	var player_scene: PackedScene = load("res://scenes/player/Player.tscn")
	var player: Player = player_scene.instantiate()
	add_child(player)
	player.active_run_modifier_id = "bounty_hunter"
	add_child(wm)

	for _i in 9:
		wm._start_next_wave()
	assert(wm._is_boss_wave, "wave 10 should be a boss wave")
	var expected: float = wm._boss_hp_mult(1) * RunModifiers.get_mult("bounty_hunter", "enemy_hp_mult")
	assert(is_equal_approx(wm._pending_boss_hp_mult, expected), "Bounty Hunter should multiply boss HP too, expected %s got %s" % [expected, wm._pending_boss_hp_mult])

	player.queue_free()
	wm.queue_free()
	spawner.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _assert_enraged_speed_affects_post_engage_movement() -> void:
	# Enraged's _speed_mult used to only reach the brief pre-engage walk-in --
	# the post-engage advance-to-lose-line movement read a flat constant,
	# making the mutation's namesake "faster" behavior invisible for the
	# entire actual fight. Real physics ticks, not a manual _physics_process()
	# call (which sidesteps move_and_slide()'s own handling unreliably).
	var boss_data: EnemyData = load("res://resources/enemies/fallen_knight.tres")
	var plain: BossBase = boss_data.scene.instantiate()
	plain.advances_to_lose_line = true
	plain.setup(boss_data, 1.0, 1.0, 1.0)
	add_child(plain)
	plain._engaged = true
	plain.global_position = Vector2(100, 300)

	var enraged: BossBase = boss_data.scene.instantiate()
	enraged.mutation_id = "enraged"
	enraged.advances_to_lose_line = true
	enraged.setup(boss_data, 1.0, 1.0, 1.0)
	add_child(enraged)
	enraged._engaged = true
	enraged.global_position = Vector2(600, 300)  # far apart so collision can't block either boss

	var plain_start := plain.global_position.y
	var enraged_start := enraged.global_position.y
	for _i in 10:
		await get_tree().physics_frame
	var plain_delta := plain.global_position.y - plain_start
	var enraged_delta := enraged.global_position.y - enraged_start
	assert(plain_delta > 0.0, "sanity: an unmutated advancing boss should move down over 10 physics ticks")
	var ratio := enraged_delta / plain_delta
	var em: Dictionary = BossBase.MUTATIONS["enraged"]
	assert(absf(ratio - em["speed_mult"]) < 0.01, "Enraged should move %sx faster during actual post-engage advance, got ratio %s" % [em["speed_mult"], ratio])

	plain.queue_free()
	enraged.queue_free()
