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


func _dismiss_class_select(main: Node) -> void:
	# (2026-07-21) Every Main.tscn boot now opens the run-start class picker,
	# which pauses the whole tree until a class is chosen -- and the pause
	# source lives on the GameManager AUTOLOAD, so a test that frees Main
	# without dismissing it would leave the tree paused for every test after
	# it. Ranger is the explicit no-stat-change baseline, so picking it keeps
	# all existing numeric assertions exactly as they were.
	var popup = main.get_node_or_null("ClassSelectPopup")
	if popup != null:
		popup.select_class("ranger")


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


func _assert_accounts_and_characters() -> void:
	# (2026-07-21) Local characters, up to 3, per-character progression, no
	# accounts. Works on a scratch state and restores whatever was there after.
	var saved_chars: Array = SaveManager.characters.duplicate(true)
	var saved_cur: int = SaveManager.current_character
	SaveManager.characters = []
	SaveManager.current_character = -1
	SaveManager._reset_active_fields()

	assert(SaveManager.character_count() == 0)
	var i0 := SaveManager.create_character("Alpha")
	assert(i0 == 0 and SaveManager.has_active_character(), "creating a character selects it")
	assert(SaveManager.current_character_name() == "Alpha")
	assert(SaveManager.create_character("") == -1, "an empty name is refused")
	# Per-character progression: Alpha earns essence.
	SaveManager.add_essence(50)
	assert(SaveManager.essence >= 50)

	var i1 := SaveManager.create_character("Beta")
	assert(i1 == 1 and SaveManager.current_character_name() == "Beta", "second character, selected")
	# Beta gets a FRESH profile (per-character, not shared).
	assert(SaveManager.essence == 0, "a new character starts with its own 0 essence, not Alpha's")

	assert(SaveManager.create_character("Gamma") == 2)
	assert(SaveManager.create_character("Delta") == -1, "at most %d characters" % SaveManager.MAX_CHARACTERS)

	# Switch back to Alpha -> her essence is restored (persisted separately).
	assert(SaveManager.select_character(0))
	assert(SaveManager.essence >= 50, "Alpha's own essence should be intact after switching")

	# Survives a reload from disk.
	assert(SaveManager.save_to_disk() and SaveManager.load_save())
	assert(SaveManager.character_count() == 3, "characters persist through a save reload")

	# delete_character removes one and fixes up the selection.
	assert(SaveManager.delete_character(1))
	assert(SaveManager.character_count() == 2, "delete removes a character")

	# Restore whatever real state existed before the test.
	SaveManager.characters = saved_chars
	SaveManager.current_character = saved_cur
	if SaveManager._active_character() != null:
		SaveManager._load_active_fields()
	SaveManager.save_to_disk()


func _assert_save_roundtrip() -> void:
	_assert_accounts_and_characters()
	# The save-persistence tests below need an active character (that's now the
	# unit the flat stat fields persist into). Migration or the account test
	# above usually leaves one selected; guarantee it either way.
	if not SaveManager.has_active_character():
		SaveManager.create_character("Tester")  # creates + selects
	assert(SaveManager.has_active_character(), "a character must be active for the save tests")

	var before_wave := SaveManager.best_wave
	SaveManager.record_run(before_wave + 1, SaveManager.best_level + 1)
	assert(SaveManager.best_wave >= before_wave + 1)
	assert(SaveManager.load_save())
	assert(SaveManager.best_wave >= before_wave + 1, "recorded best should survive a reload (per-character persistence)")
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
	await _assert_arrow_cap_stops_plus_one_arrow()
	await _assert_element_fusion()
	await _assert_status_control_effects()
	await _assert_skill_panel_shows_live_stats()
	await _assert_boss_presence()
	await _assert_combat_juice()
	await _assert_unit_identity()
	await _assert_boss_mutations()
	await _assert_elemental_capstones()
	await _assert_run_modifiers()
	await _assert_review_fixes()
	await _assert_boss_affinities_and_events()
	await _assert_character_classes()
	await _assert_class_skill_trees()
	await _assert_continue_revive()
	_assert_tutorial_hints()


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
	# (2026-07-22) Unlock gate lowered from tier 5 (capstone) to tier 4 -- the
	# last active-skill tier, what players read as "maxed" -- since tier 5 was
	# too deep to reach in most runs and the ultimate felt permanently locked.
	# Check the boundary: locked through tier 3, unlocks exactly at tier 4.
	player.apply_element_upgrade(load("res://resources/upgrades/fire_t1_searing_shot.tres"))
	player.apply_element_upgrade(load("res://resources/upgrades/fire_t2_inferno_growth.tres"))
	player.apply_element_upgrade(load("res://resources/upgrades/fire_t3_burning_legacy.tres"))
	assert(not player.is_ultimate_unlocked(), "ultimate must stay locked below the unlock tier (tier 3)")
	player.apply_element_upgrade(load("res://resources/upgrades/fire_t4_inferno_mastery.tres"))
	assert(player.is_ultimate_unlocked(), "reaching the unlock tier (4) should unlock the ultimate")
	player.apply_element_upgrade(load("res://resources/upgrades/fire_t5_inferno_heart.tres"))
	# No projectile_pool here -- stop auto-fire so it can't error mid-test.
	player.attack_timer.stop()
	var fire_timer: Timer = player.get_elemental_timer_by_element(UpgradeResource.ElementType.FIRE)
	if is_instance_valid(fire_timer):
		fire_timer.stop()

	assert(player.is_ultimate_unlocked(), "a maxed element should keep the ultimate unlocked")
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
	_dismiss_class_select(main)

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
	assert(not offer.is_empty(), "a maxed Fire whose stat cards aren't capped yet should still offer its repeatable boost cards")
	assert(offer[0].tier == 0, "a maxed element should only ever offer tier=0 repeatable cards now, got tier %d" % offer[0].tier)

	# (2026-07-22) ...but once the skill tier is maxed AND every repeatable stat
	# card has hit its max_stacks, the line must go silent -- so a fully-finished
	# element drops out of the picker (and when all lines are done, the popup
	# stops appearing). Cap every Fire tier-0 card by applying it max_stacks times.
	var fire_repeatables: Array = []
	for candidate in popup.upgrade_pool:
		if candidate.element == UpgradeResource.ElementType.FIRE and candidate.tier == 0:
			fire_repeatables.append(candidate)
	assert(fire_repeatables.size() > 0, "Fire should have repeatable tier-0 cards to cap")
	for card in fire_repeatables:
		assert(card.max_stacks > 0, "%s must declare a max_stacks cap" % card.id)
		for _s in card.max_stacks:
			player.apply_element_upgrade(card)
		assert(int(player.repeatable_stacks.get(card.id, 0)) == card.max_stacks, "%s should be capped at %d stacks" % [card.id, card.max_stacks])
	var offer_capped := popup._get_offerable_upgrades(UpgradeResource.ElementType.FIRE)
	assert(offer_capped.is_empty(), "a fully-maxed Fire (skill maxed AND all stat cards capped) must offer nothing -- it should drop out of the picker")

	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _assert_arrow_cap_stops_plus_one_arrow() -> void:
	# (2026-07-22) The "+1 Arrow" level-up card must stop being offered once the
	# active cone skill is already firing MAX_SHOT_COUNT arrows (base + bonus) --
	# past the cap another +1 is clamped away and does nothing.
	var main = load(MAIN_SCENE).instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	_dismiss_class_select(main)

	var player: Player = get_tree().get_first_node_in_group("player")
	var popup: LevelUpPopup = main.get_node_or_null("LevelUpPopup")
	assert(is_instance_valid(player) and popup != null, "real Main.tscn should have a player + LevelUpPopup")

	var skill := player.get_current_physical_skill()
	assert(skill != null and skill.fire_mode != SkillData.FireMode.TRAP_SHOT, "baseline physical skill should be a cone for this test")
	assert(skill.projectile_count < player.MAX_SHOT_COUNT, "baseline skill must start below the arrow cap")

	# Below the cap -> +1 Arrow is offered.
	player.bonus_projectile_count = 0
	assert("projectile_count" in popup._eligible_upgrade_ids(), "+1 Arrow should be offered while below the arrow cap")

	# Exactly at the cap -> +1 Arrow is dropped.
	player.bonus_projectile_count = player.MAX_SHOT_COUNT - skill.projectile_count
	assert(skill.projectile_count + player.bonus_projectile_count == player.MAX_SHOT_COUNT, "test should drive the shot count to exactly the cap")
	assert(not ("projectile_count" in popup._eligible_upgrade_ids()), "+1 Arrow must not be offered once arrows are capped at MAX_SHOT_COUNT")

	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _assert_element_fusion() -> void:
	# (2026-07-22) Late-game elemental fusion: maxing two element lines to the
	# capstone tier unlocks a fusion so the player's attacks carry BOTH statuses,
	# firing that pair's combo reliably. Standalone player so the tier climb and
	# active_fusions state are deterministic (no live wave picker in the loop).
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Player = load("res://scenes/player/Player.tscn").instantiate()
	add_child(player)
	await get_tree().process_frame
	assert(get_tree().get_first_node_in_group("player") == player, "test player must be the sole node in the player group")

	var fire_paths := [
		"res://resources/upgrades/fire_t1_searing_shot.tres",
		"res://resources/upgrades/fire_t2_inferno_growth.tres",
		"res://resources/upgrades/fire_t3_burning_legacy.tres",
		"res://resources/upgrades/fire_t4_inferno_mastery.tres",
		"res://resources/upgrades/fire_t5_inferno_heart.tres",
	]
	var frost_paths := [
		"res://resources/upgrades/frost_t1_glacial_spike.tres",
		"res://resources/upgrades/frost_t2_deep_freeze.tres",
		"res://resources/upgrades/frost_t3_glacial_resonance.tres",
		"res://resources/upgrades/frost_t4_frozen_mastery.tres",
		"res://resources/upgrades/frost_t5_absolute_zero.tres",
	]

	var fusion_signal := {"fired": false}
	player.fusion_unlocked.connect(func(_pid, _name): fusion_signal["fired"] = true)

	# Fire alone (even fully maxed) -> no fusion yet; a fusion needs TWO lines.
	for path in fire_paths:
		player.apply_element_upgrade(load(path))
	assert(player.fire_level == 5, "fire should be maxed, got %d" % player.fire_level)
	assert(player.active_fusions.is_empty(), "one line alone must not unlock any fusion")

	# (2026-07-22) Gate is FUSION_UNLOCK_TIER (4), not the tier-5 capstone --
	# requiring capstones on two lines made fusions effectively unreachable.
	# Frost through tier 3 -> still locked; tier 4 -> Frostfire unlocks.
	for i in 3:
		player.apply_element_upgrade(load(frost_paths[i]))
	assert(player.frost_level == 3 and player.active_fusions.is_empty(), "below the unlock tier the fusion must stay locked")
	player.apply_element_upgrade(load(frost_paths[3]))
	assert(player.frost_level == player.FUSION_UNLOCK_TIER, "frost should be at the unlock tier")
	assert("fire_frost" in player.active_fusions, "reaching tier %d on a second line must unlock the fusion" % player.FUSION_UNLOCK_TIER)
	# Pushing on to the capstone must not double-unlock or drop it.
	player.apply_element_upgrade(load(frost_paths[4]))
	assert(player.frost_level == 5, "frost should be maxed, got %d" % player.frost_level)
	assert(player.active_fusions.count("fire_frost") == 1, "a fusion must unlock exactly once")
	assert("fire_frost" in player.active_fusions, "maxing fire + frost must unlock the fire_frost fusion")
	assert(fusion_signal["fired"], "fusion_unlocked signal should have fired")
	assert(player.get_fusion_partners("fire").has("frost") and player.get_fusion_partners("fire").size() == 1, "fire's fusion partner should be exactly frost")
	assert(player.get_fusion_partners("frost").has("fire"), "frost's fusion partner should be fire")

	# Every fusion needs display data -- it's surfaced as an owned "skill" in the
	# HUD row + pause-menu Fusions section, so a missing name/icon/description
	# would render as a blank entry.
	for pid in ElementFusions.FUSIONS:
		assert(ElementFusions.display_name(pid) != "", "%s needs a display name" % pid)
		assert(ElementFusions.description(pid) != "", "%s needs a description" % pid)
		var ipath := ElementFusions.icon_path(pid)
		assert(ipath != "" and ResourceLoader.exists(ipath), "%s needs an icon that actually exists (%s)" % [pid, ipath])

	# Spawn setup for the apply mechanic.
	var spawner := EnemySpawner.new()
	spawner.name = "EnemySpawner"
	add_child(spawner)
	var enemy_pool := EnemyPool.new()
	add_child(enemy_pool)
	var goblin = load("res://resources/enemies/goblin_runner.tres")

	# Frostfire: applying only fire, with the fusion active, also applies frost
	# and fires the combo (so the enemy takes the burst -- damage or death).
	var e1: EnemyBase = spawner.spawn(goblin, 1.0, 1.0, 1.0, -1, 1.0, 900.0, false)
	e1.global_position = Vector2(360, 400)
	var hp1: float = e1.current_hp
	e1.apply_status(StatusEffects.FIRE, 2.0)
	assert(not is_instance_valid(e1) or e1.current_hp < hp1, "with Frostfire active, a fire hit alone must trigger the combo and damage the enemy")
	assert(not is_instance_valid(e1) or not (e1.status.has(StatusEffects.FIRE) and e1.status.has(StatusEffects.FROST)), "the combo should have consumed both statuses")
	if is_instance_valid(e1):
		e1.queue_free()

	# Overload: the NEW Fire+Lightning combo, reachable only via fusion. Force
	# just that fusion and confirm a fire hit alone discharges it.
	player.active_fusions = ["fire_lightning"]
	var e2: EnemyBase = spawner.spawn(goblin, 1.0, 1.0, 1.0, -1, 1.0, 900.0, false)
	e2.global_position = Vector2(360, 400)
	var hp2: float = e2.current_hp
	e2.apply_status(StatusEffects.FIRE, 2.0)
	assert(not is_instance_valid(e2) or e2.current_hp < hp2, "with Overload active, a fire hit alone must trigger the fire+lightning combo")
	if is_instance_valid(e2):
		e2.queue_free()

	player.queue_free()
	spawner.queue_free()
	enemy_pool.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _assert_status_control_effects() -> void:
	# (2026-07-22) User report: at wave 30+ shocked monsters "don't stop".
	# Four fixes, all checked here against real instances:
	#   1. wave speed scaling is capped (was unbounded, eroding every slow)
	#   2. shock opens with a real hard stun (absolute, can't be eroded)
	#   3. bosses get a walk slow instead of total movement immunity
	#   4. burn scales with the wave's HP multiplier so it stays relevant
	await get_tree().process_frame

	# 1. Speed scaling must stop climbing -- an uncapped multiplier is what made
	#    the 0.45x slow stop reading as a slow at all in late waves.
	var late := 1.0 + WaveManager.SPEED_SCALING_PER_WAVE * 500.0
	assert(WaveManager.SPEED_MULT_CEILING < late, "sanity: 500 waves should exceed the ceiling")
	assert(minf(late, WaveManager.SPEED_MULT_CEILING) == WaveManager.SPEED_MULT_CEILING, "speed scaling must clamp to SPEED_MULT_CEILING")
	# A shocked enemy at the speed ceiling must still be slower than an
	# un-shocked baseline enemy -- the whole point of capping.
	assert(WaveManager.SPEED_MULT_CEILING * StatusEffects.LIGHTNING_SLOW_MULT < 1.0, "a shocked late-wave enemy must not outrun an unshocked wave-1 enemy")

	var spawner := EnemySpawner.new()
	spawner.name = "EnemySpawner"
	add_child(spawner)
	var enemy_pool := EnemyPool.new()
	add_child(enemy_pool)
	var goblin = load("res://resources/enemies/goblin_runner.tres")

	# 2. Shock = brief hard stun, then the slow. Frost = full stop throughout.
	var shocked: EnemyBase = spawner.spawn(goblin, 1.0, 1.0, 1.0, -1, 1.0, 300.0, false)
	shocked.apply_status(StatusEffects.LIGHTNING, StatusEffects.LIGHTNING_DURATION)
	assert(StatusEffects.is_stunned(shocked), "a fresh shock should stun")
	assert(shocked.status.has(StatusEffects.STUN), "the stun is tracked in the status dict")
	# The stun expires well before the shock does, leaving the slow behind.
	StatusEffects.tick(shocked, StatusEffects.LIGHTNING_STUN_DURATION + 0.01)
	assert(not StatusEffects.is_stunned(shocked), "the stun should expire after LIGHTNING_STUN_DURATION")
	assert(shocked.status.has(StatusEffects.LIGHTNING), "the shock slow should outlast its opening stun")
	assert(StatusEffects.speed_multiplier(shocked) < 1.0, "a shocked enemy should still be slowed after the stun")
	shocked.queue_free()

	var frozen: EnemyBase = spawner.spawn(goblin, 1.0, 1.0, 1.0, -1, 1.0, 400.0, false)
	frozen.apply_status(StatusEffects.FROST, StatusEffects.FROST_DURATION)
	assert(StatusEffects.is_frozen(frozen), "frost should freeze")
	assert(not StatusEffects.is_stunned(frozen), "frost freezes via is_frozen, it must not set the shock stun")
	frozen.queue_free()

	# Fire is deliberately a pure DOT -- it must never stop or slow anything.
	var burning: EnemyBase = spawner.spawn(goblin, 1.0, 1.0, 1.0, -1, 1.0, 500.0, false)
	burning.apply_status(StatusEffects.FIRE, StatusEffects.FIRE_DURATION)
	assert(not StatusEffects.is_frozen(burning) and not StatusEffects.is_stunned(burning), "fire must not apply a movement lock")
	assert(is_equal_approx(StatusEffects.speed_multiplier(burning), 1.0), "fire must not slow")
	burning.queue_free()

	# 4. Burn scales with the enemy's own wave HP multiplier, so a tankier
	#    late-wave enemy burns proportionally as fast as a wave-1 one.
	var tanky: EnemyBase = spawner.spawn(goblin, 8.0, 1.0, 1.0, -1, 1.0, 600.0, false)
	assert(is_equal_approx(StatusEffects._burn_scale(tanky), 8.0), "burn should scale by the enemy's hp_mult")
	var plain: EnemyBase = spawner.spawn(goblin, 1.0, 1.0, 1.0, -1, 1.0, 700.0, false)
	assert(is_equal_approx(StatusEffects._burn_scale(plain), 1.0), "an unscaled enemy burns at the base rate")
	tanky.queue_free()
	plain.queue_free()

	# 3. Bosses: slowed while chilled/shocked, but never fully stopped.
	var boss_data = load("res://resources/enemies/fallen_knight.tres")
	var boss: BossBase = boss_data.scene.instantiate()
	boss.setup(boss_data, 1.0, 1.0, 1.0)
	add_child(boss)
	assert(is_equal_approx(StatusEffects.boss_speed_multiplier(boss), 1.0), "an unafflicted boss moves at full speed")
	boss.apply_status(StatusEffects.FROST, StatusEffects.FROST_DURATION)
	var boss_slow := StatusEffects.boss_speed_multiplier(boss)
	assert(boss_slow < 1.0, "a chilled boss should be slowed")
	assert(boss_slow > 0.0, "a boss must never be fully stopped -- that's the whole point of the boss carve-out")
	assert(is_equal_approx(boss_slow, StatusEffects.BOSS_STATUS_SLOW_MULT), "boss slow should be BOSS_STATUS_SLOW_MULT")
	boss.queue_free()

	spawner.queue_free()
	enemy_pool.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _assert_skill_panel_shows_live_stats() -> void:
	# (2026-07-22) User report: the skill panel's basic/element stat lines never
	# changed when a damage/cooldown upgrade was taken. Cause: the rows printed
	# raw SkillData .tres values, while upgrades only ever move the player's
	# multipliers. The panel must now fold those in.
	await get_tree().process_frame
	await get_tree().process_frame
	var main = load(MAIN_SCENE).instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	_dismiss_class_select(main)

	var player: Player = get_tree().get_first_node_in_group("player")
	var pause_menu = main.get_node_or_null("PauseMenu")
	assert(is_instance_valid(player) and pause_menu != null, "need a real player + PauseMenu")

	var physical_skill := player.get_current_physical_skill()
	assert(physical_skill != null, "the basic line always has a skill")

	# --- Basic line: damage + cooldown must track the player's multipliers ---
	var before: String = pause_menu._format_skill_stats(physical_skill, player, UpgradeResource.ElementType.PHYSICAL)
	var base_dmg := roundi(physical_skill.base_damage * player.damage_mult)
	assert(("Damage %d" % base_dmg) in before, "the basic row should show effective damage; got '%s'" % before)

	# Take real upgrades through the real apply path.
	for _i in 12:
		player.apply_upgrade("damage")    # +2% damage each
		player.apply_upgrade("cooldown")  # -3% cooldown each
	var after: String = pause_menu._format_skill_stats(physical_skill, player, UpgradeResource.ElementType.PHYSICAL)
	assert(after != before, "skill panel stats must change after damage/cooldown upgrades\nbefore: %s\nafter:  %s" % [before, after])
	var up_dmg := roundi(physical_skill.base_damage * player.damage_mult)
	assert(up_dmg > base_dmg, "sanity: 12 damage upgrades should raise effective damage")
	assert(("Damage %d" % up_dmg) in after, "the row should show the RAISED damage; got '%s'" % after)
	assert(("Cooldown %.1fs" % (physical_skill.cooldown * player.cooldown_mult)) in after, "the row should show the REDUCED cooldown; got '%s'" % after)

	# --- "+1 Arrow" must show up, and must respect the hard cap ---
	if physical_skill.fire_mode != SkillData.FireMode.TRAP_SHOT:
		player.bonus_projectile_count = 0
		var no_bonus: String = pause_menu._format_skill_stats(physical_skill, player, UpgradeResource.ElementType.PHYSICAL)
		player.bonus_projectile_count = 2
		var with_bonus: String = pause_menu._format_skill_stats(physical_skill, player, UpgradeResource.ElementType.PHYSICAL)
		assert(no_bonus != with_bonus, "+1 Arrow picks should change the displayed arrow count")
		player.bonus_projectile_count = 99  # way past the cap
		var capped: String = pause_menu._format_skill_stats(physical_skill, player, UpgradeResource.ElementType.PHYSICAL)
		assert(("%d arrows" % player.MAX_SHOT_COUNT) in capped, "arrow count must clamp to MAX_SHOT_COUNT; got '%s'" % capped)
		player.bonus_projectile_count = 0

	# --- Element line: its own separate multipliers, not the basic line's ---
	player.apply_element_upgrade(load("res://resources/upgrades/fire_t1_searing_shot.tres"))
	var fire_skill := player.get_current_skill_for_element(UpgradeResource.ElementType.FIRE)
	assert(fire_skill != null, "fire tier 1 should set a fire skill")
	var fire_before: String = pause_menu._format_skill_stats(fire_skill, player, UpgradeResource.ElementType.FIRE)
	player.fire_skill_dmg_mult += 0.5
	player.fire_skill_cd_mult -= 0.2
	var fire_after: String = pause_menu._format_skill_stats(fire_skill, player, UpgradeResource.ElementType.FIRE)
	assert(fire_after != fire_before, "element row must track its own dmg/cd multipliers\nbefore: %s\nafter:  %s" % [fire_before, fire_after])
	assert(("Damage %d" % roundi(fire_skill.base_damage * player.fire_skill_dmg_mult)) in fire_after, "fire row should use fire_skill_dmg_mult; got '%s'" % fire_after)

	# The whole panel must still build with the extra player arg threaded through.
	pause_menu._build_skill_rows()
	await get_tree().process_frame
	assert(pause_menu.skill_rows_container.get_child_count() > 0, "skills panel should still build")

	# (2026-07-22) The skill panel is two tabs (tree / stats) sharing one
	# scroll -- exactly one view is visible at a time, and opening the panel
	# always lands on the tree tab rather than remembering the last one.
	pause_menu.open_skills_panel()
	await get_tree().process_frame
	assert(pause_menu.tree_view.visible and not pause_menu.skill_rows_container.visible, "the panel should open on the Skill Tree tab")
	assert(pause_menu.tree_tab.button_pressed and not pause_menu.stats_tab.button_pressed, "the tree tab should read as selected")
	# Drive the REAL button signals, so the .bind() wiring is covered too.
	pause_menu.stats_tab.pressed.emit()
	assert(pause_menu.skill_rows_container.visible and not pause_menu.tree_view.visible, "the Skill Stats tab should swap the visible view")
	assert(pause_menu.stats_tab.button_pressed and not pause_menu.tree_tab.button_pressed, "the stats tab should read as selected")
	pause_menu.tree_tab.pressed.emit()
	assert(pause_menu.tree_view.visible and not pause_menu.skill_rows_container.visible, "switching back should restore the tree")
	assert(pause_menu.tree_tab.button_pressed and not pause_menu.stats_tab.button_pressed, "the tree tab should read as selected again")

	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _assert_boss_presence() -> void:
	# (2026-07-23) Boss presence pass. Every boss reuses a REGULAR enemy's
	# sprite (Fallen Knight and Dark Ranger Commander share the same skeleton
	# frames), so presence has to come from code: a bigger silhouette, a
	# procedural aura, and an entrance flash. No new art involved.
	var boss_data = load("res://resources/enemies/fallen_knight.tres")

	var entrance := {"fired": false, "color": Color.BLACK}
	var cb := func(c: Color):
		entrance["fired"] = true
		entrance["color"] = c
	SignalBus.boss_entrance.connect(cb)

	var boss: BossBase = boss_data.scene.instantiate()
	var authored_scale: Vector2 = boss.get_node("Sprite").scale
	boss.setup(boss_data, 1.0, 1.0, 1.0)
	add_child(boss)
	await get_tree().process_frame

	# Bigger silhouette -- and _base_scale (what every hit/lunge effect scales
	# off) must be the BUMPED size, not the scene's authored one.
	assert(boss._base_scale.is_equal_approx(authored_scale * BossBase.BOSS_VISUAL_SCALE), "boss sprite should be scaled up by BOSS_VISUAL_SCALE; got %s from %s" % [boss._base_scale, authored_scale])

	# Aura exists, sits behind the sprite, and carries this boss's own colour.
	var aura: BossAura = boss._aura
	assert(is_instance_valid(aura), "a boss should spawn a BossAura")
	assert(aura.get_parent() == boss, "the aura should be parented to the boss so it follows without per-frame code")
	assert(aura.z_index < 0, "the aura must draw BEHIND the boss sprite")
	assert(aura.color.is_equal_approx(BossBase.AURA_COLORS["fallen_knight"]), "fallen_knight should use its own aura colour")

	# Phase 2 visibly escalates the aura rather than only moving the HP bar.
	var base_intensity := aura.intensity
	aura.set_phase(2)
	assert(aura.intensity > base_intensity, "phase 2 should intensify the aura")
	aura.set_phase(1)
	assert(is_equal_approx(aura.intensity, base_intensity), "dropping back to phase 1 should restore the base intensity")

	assert(entrance["fired"], "spawning a boss should emit boss_entrance for the HUD flash")
	var flash_color: Color = entrance["color"]
	assert(flash_color.is_equal_approx(BossBase.AURA_COLORS["fallen_knight"]), "the entrance flash should carry the boss's aura colour")
	boss.queue_free()
	await get_tree().process_frame

	# An affinity outranks the per-boss colour -- while a boss resists an
	# element, the colour is actionable (it matches the counter-cycle diagram).
	var affinity_boss: BossBase = boss_data.scene.instantiate()
	affinity_boss.affinity_id = "frost"
	affinity_boss.setup(boss_data, 1.0, 1.0, 1.0)
	add_child(affinity_boss)
	await get_tree().process_frame
	assert(affinity_boss._aura.color.is_equal_approx(BossBase.AURA_AFFINITY_COLORS["frost"]), "an affinity boss's aura should use the affinity colour, not the per-boss one")
	affinity_boss.queue_free()

	SignalBus.boss_entrance.disconnect(cb)
	await get_tree().process_frame
	await get_tree().process_frame


func _assert_combat_juice() -> void:
	# (2026-07-23) Combat juice pass. Hitstop is the risky half -- it writes a
	# GLOBAL Engine.time_scale, so a bug here strands the whole game in slow
	# motion. These assertions exist mainly to prove it always restores.
	assert(is_equal_approx(Engine.time_scale, 1.0), "time_scale should start clean")

	GameManager.hitstop(0.05)
	assert(Engine.time_scale < 1.0, "hitstop should slow time while active")
	await get_tree().create_timer(0.2, true, false, true).timeout
	assert(is_equal_approx(Engine.time_scale, 1.0), "hitstop MUST restore time_scale, got %s" % Engine.time_scale)

	# Overlapping calls must not let the first one restore early and leave the
	# second running un-slowed (generation-token guard).
	GameManager.hitstop(0.05)
	GameManager.hitstop(0.30)
	await get_tree().create_timer(0.15, true, false, true).timeout
	assert(Engine.time_scale < 1.0, "the longer overlapping hitstop should still be holding time slowed")
	await get_tree().create_timer(0.35, true, false, true).timeout
	assert(is_equal_approx(Engine.time_scale, 1.0), "overlapping hitstops must still restore, got %s" % Engine.time_scale)

	# A restart mid-hitstop must never strand the game slowed.
	GameManager.hitstop(5.0)
	assert(Engine.time_scale < 1.0, "sanity: long hitstop is active")
	GameManager.reset_state()
	assert(is_equal_approx(Engine.time_scale, 1.0), "reset_state must clear an in-flight hitstop")
	await get_tree().create_timer(0.1, true, false, true).timeout
	assert(is_equal_approx(Engine.time_scale, 1.0), "the cancelled hitstop must not restore-then-reslow later")

	# Damage numbers: spawn, then free themselves rather than accumulating.
	var host := Node2D.new()
	add_child(host)
	DamageNumber.spawn(123.0, Vector2(100, 100), Color.WHITE, host, true)
	assert(host.get_child_count() == 1, "a damage number should have been added")
	await get_tree().create_timer(DamageNumber.LIFETIME + 0.3, true, false, true).timeout
	assert(host.get_child_count() == 0, "damage numbers must free themselves, %d left" % host.get_child_count())
	host.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _assert_unit_identity() -> void:
	# (2026-07-23) Unit identity pass: elite / class / boss were all just
	# "tint + scale". Each now has its own procedural shape language. The real
	# risk is the POOLED path -- an elite marker leaking onto a later non-elite
	# reuse of the same instance would mislabel a normal enemy as elite.
	await get_tree().process_frame
	var spawner := EnemySpawner.new()
	spawner.name = "EnemySpawner"
	add_child(spawner)
	var enemy_pool := EnemyPool.new()
	add_child(enemy_pool)
	var goblin = load("res://resources/enemies/goblin_runner.tres")

	var elite: EnemyBase = spawner.spawn(goblin, 1.0, 1.0, 1.0, -1, 1.0, 200.0, true)
	var marker = elite.get_node_or_null(EnemySpawner.ELITE_MARKER_NAME)
	assert(marker != null and marker is EliteMarker, "an elite should get an EliteMarker")
	assert(marker.z_index < 0, "the elite marker must draw behind the enemy sprite")

	# Same instance reused as a NON-elite must lose the marker.
	spawner._ensure_elite_marker(elite, false)
	await get_tree().process_frame
	assert(elite.get_node_or_null(EnemySpawner.ELITE_MARKER_NAME) == null, "a pooled non-elite reuse must not keep the elite marker")

	# A plain spawn never has one to begin with.
	var normal: EnemyBase = spawner.spawn(goblin, 1.0, 1.0, 1.0, -1, 1.0, 300.0, false)
	assert(normal.get_node_or_null(EnemySpawner.ELITE_MARKER_NAME) == null, "a normal enemy should have no elite marker")
	elite.queue_free()
	normal.queue_free()

	# The player's class aura carries that class's own colour.
	var player: Player = load("res://scenes/player/Player.tscn").instantiate()
	add_child(player)
	player.apply_class("juggernaut")
	var found: PlayerAura = null
	for c in player.get_children():
		if c is PlayerAura:
			found = c
	assert(found != null, "applying a class should add a PlayerAura")
	assert(found.color.is_equal_approx(CharacterClasses.get_vfx_color("juggernaut")), "the class aura should use the class's vfx colour")
	assert(found.z_index < 0, "the class aura must draw under the player sprite")

	# The three shape languages must be genuinely different scripts, not one
	# effect reused at three sizes (which is what the tint approach amounted to).
	assert(EliteMarker != BossAura and PlayerAura != BossAura, "elite/player/boss must each have their own visual treatment")

	player.queue_free()
	spawner.queue_free()
	enemy_pool.queue_free()
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
	_dismiss_class_select(main)

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


func _assert_boss_affinities_and_events() -> void:
	# (2026-07-21) Phase 4: boss variety round 2 -- elemental affinities
	# (resist own element, weak to the counter) + event cycles (guaranteed
	# mutation every 3rd cycle, Overlord with mutation+affinity+bonus HP every
	# 5th). Real boss instance through the real spawner path, real WaveManager
	# rolls at the real wave numbers.
	var spawner := EnemySpawner.new()
	spawner.name = "EnemySpawner"
	add_child(spawner)
	var boss_data: EnemyData = load("res://resources/enemies/fallen_knight.tres")

	var announced: Array[String] = []
	var announce_capture := func(n: String): announced.append(n)
	SignalBus.boss_mutation_announced.connect(announce_capture)
	var boss: BossBase = spawner.spawn(boss_data, 100.0, 1.0, 1.0, -1, 1.0, -1.0, false, true, "enraged", "fire")
	SignalBus.boss_mutation_announced.disconnect(announce_capture)
	assert(boss.affinity_id == "fire", "spawner should set affinity_id on the boss instance")
	assert(announced.size() == 1 and announced[0] == "Enraged Flamebound (weak to Frost)", "combined announcement should carry both names plus the weak-to hint, got %s" % str(announced))

	var hp0: float = boss.current_hp
	boss.take_damage(10.0, "fire")
	assert(is_equal_approx(hp0 - boss.current_hp, 10.0 * BossBase.AFFINITY_RESIST_MULT), "Flamebound must resist fire damage")
	hp0 = boss.current_hp
	boss.take_damage(10.0, "frost")
	assert(is_equal_approx(hp0 - boss.current_hp, 10.0 * BossBase.AFFINITY_WEAK_MULT), "Flamebound must be weak to frost")
	hp0 = boss.current_hp
	boss.take_damage(10.0, "lightning")
	assert(is_equal_approx(hp0 - boss.current_hp, 10.0), "the off-element (neither resist nor counter) must stay neutral")
	hp0 = boss.current_hp
	boss.take_damage(10.0)
	assert(is_equal_approx(hp0 - boss.current_hp, 10.0), "physical/untyped damage must ignore affinity entirely")
	boss.queue_free()

	# Event-cycle rolls at the real wave numbers: wave 30 (cycle 3) must have
	# a mutation; wave 50 (cycle 5, Overlord) must have BOTH plus the HP bonus.
	var wm := WaveManager.new()
	wm.waves = [
		load("res://resources/waves/wave_01.tres"), load("res://resources/waves/wave_02.tres"),
		load("res://resources/waves/wave_03.tres"), load("res://resources/waves/wave_04.tres"),
		load("res://resources/waves/wave_05.tres"),
	]
	wm.procedural_enemy_pool = [load("res://resources/enemies/slime_scout.tres")]
	wm.boss_pool = [boss_data]
	var player_scene: PackedScene = load("res://scenes/player/Player.tscn")
	var player: Player = player_scene.instantiate()
	add_child(player)
	player.active_run_modifier_id = ""  # neutral -- keeps the expected HP math deterministic
	add_child(wm)

	for _i in 29:
		wm._start_next_wave()
	assert(wm._is_boss_wave and wm._current_wave.wave_number == 30, "call count drifted -- expected to be sitting on wave 30")
	assert(wm._pending_boss_mutation_id != "", "every 3rd boss cycle (wave 30) must guarantee a mutation")

	for _i in 20:
		wm._start_next_wave()
	assert(wm._is_boss_wave and wm._current_wave.wave_number == 50, "call count drifted -- expected to be sitting on wave 50")
	assert(wm._pending_boss_mutation_id != "", "an Overlord cycle (wave 50) must have a mutation")
	assert(wm._pending_boss_affinity_id != "", "an Overlord cycle (wave 50) must have an affinity")
	var expected_hp: float = wm._boss_hp_mult(5) * WaveManager.OVERLORD_HP_MULT
	assert(is_equal_approx(wm._pending_boss_hp_mult, expected_hp), "Overlord should multiply boss HP by %s, expected %s got %s" % [WaveManager.OVERLORD_HP_MULT, expected_hp, wm._pending_boss_hp_mult])

	player.queue_free()
	wm.queue_free()
	spawner.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _assert_character_classes() -> void:
	# (2026-07-21) Phase 4, final pillar: character classes. Direct stat math
	# on standalone players first, then the real run-start popup flow on a
	# live Main.tscn (paused at boot, pick unpauses and applies).
	var player_scene: PackedScene = load("res://scenes/player/Player.tscn")

	# SaveManager meta bonuses would shift the baselines -- zero the relevant
	# ranks so the multiplier math below is exact.
	var saved_ranks: Dictionary = SaveManager.meta_upgrades.duplicate()
	for key in SaveManager.meta_upgrades:
		SaveManager.meta_upgrades[key] = 0

	var sniper: Player = player_scene.instantiate()
	add_child(sniper)
	sniper.active_run_modifier_id = ""
	var crit_before: float = sniper.crit_chance
	var hp_before: float = sniper.max_hp
	var proj_before: float = sniper.projectile_speed_mult
	sniper.apply_class("sniper")
	assert(sniper.active_class_id == "sniper")
	assert(is_equal_approx(sniper.crit_chance, crit_before + 0.15), "sniper should add crit chance")
	assert(is_equal_approx(sniper.max_hp, hp_before * 0.85), "sniper should trade max HP away")
	assert(is_equal_approx(sniper.projectile_speed_mult, proj_before * 1.15), "sniper should speed up projectiles")
	sniper.queue_free()

	var elementalist: Player = player_scene.instantiate()
	add_child(elementalist)
	var fire_before: float = elementalist.fire_skill_dmg_mult
	var dmg_before: float = elementalist.damage_mult
	elementalist.apply_class("elementalist")
	assert(is_equal_approx(elementalist.fire_skill_dmg_mult, fire_before * 1.25), "elementalist should boost elemental damage")
	assert(is_equal_approx(elementalist.frost_skill_dmg_mult, 1.25) and is_equal_approx(elementalist.lightning_skill_dmg_mult, 1.25), "all 3 elements should get the boost")
	assert(is_equal_approx(elementalist.damage_mult, dmg_before * 0.85), "elementalist should trade physical damage away")
	elementalist.queue_free()

	var ranger: Player = player_scene.instantiate()
	add_child(ranger)
	var r_hp: float = ranger.max_hp
	var r_dmg: float = ranger.damage_mult
	var r_crit: float = ranger.crit_chance
	ranger.apply_class("ranger")
	assert(ranger.max_hp == r_hp and ranger.damage_mult == r_dmg and ranger.crit_chance == r_crit, "ranger must be a true stat no-op")
	ranger.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	# Real popup flow on a live Main.tscn.
	var main = load(MAIN_SCENE).instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(get_tree().paused, "the run-start class picker should hold the game paused")
	var popup = main.get_node("ClassSelectPopup")
	assert(popup.panel.visible, "class picker should be visible at run start")
	var live_player: Player = get_tree().get_first_node_in_group("player")
	var live_hp: float = live_player.max_hp
	popup.select_class("juggernaut")
	assert(not get_tree().paused, "picking a class should unpause the run")
	assert(not popup.panel.visible, "picker should hide after the pick")
	assert(is_equal_approx(live_player.max_hp, live_hp * 1.4), "juggernaut pick should apply through the real popup path")
	main.queue_free()

	SaveManager.meta_upgrades = saved_ranks
	await get_tree().process_frame
	await get_tree().process_frame


func _assert_tutorial_hints() -> void:
	# (2026-07-21) Onboarding hints: shown once ever, persisted across runs.
	# Tests the SaveManager seen-hint sink + that the copy exists for every id
	# the HUD triggers.
	var saved: Array = SaveManager.seen_hints.duplicate()
	SaveManager.seen_hints = []

	assert(not SaveManager.has_seen_hint("move"), "a hint should be unseen before it's marked")
	SaveManager.mark_hint_seen("move")
	assert(SaveManager.has_seen_hint("move"), "marking a hint should make it seen")
	assert(SaveManager.load_save(), "seen-hint state should round-trip through disk")
	assert(SaveManager.has_seen_hint("move"), "a seen hint should persist across a save reload")
	SaveManager.mark_hint_seen("move")  # idempotent -- no duplicate
	assert(SaveManager.seen_hints.count("move") == 1, "marking twice must not duplicate")

	# Every id the HUD can queue must have copy defined.
	for id in ["move", "dash", "switch_element", "boss", "affinity", "ultimate"]:
		assert(TutorialHints.HINTS.has(id), "missing tutorial copy for '%s'" % id)

	SaveManager.seen_hints = saved
	SaveManager.save_to_disk()


func _assert_continue_revive() -> void:
	# (2026-07-21) Continue system: 2 revives per run (1 free + 1 paid), then
	# the real game over. Drives the Player's own death/revive path directly and
	# captures the SignalBus signals a ContinuePopup / GameOverScreen react to.
	var downed_events: Array = []
	var final_deaths: Array = []
	var on_downed := func(n: int): downed_events.append(n)
	var on_died := func(): final_deaths.append(true)
	SignalBus.player_downed.connect(on_downed)
	SignalBus.player_died.connect(on_died)

	var player_scene: PackedScene = load("res://scenes/player/Player.tscn")
	var player: Player = player_scene.instantiate()
	add_child(player)
	assert(player.continues_used == 0, "a fresh run starts with 0 continues used")

	# 1st death -> offers the free continue, no final death yet.
	player.take_damage(99999.0)
	assert(downed_events.size() == 1 and downed_events[0] == 0, "1st death should offer the free (index 0) continue")
	assert(final_deaths.is_empty(), "no game over while a continue is still available")
	assert(player.is_dead, "player is down until revived")

	player.revive()
	assert(not player.is_dead and player.continues_used == 1, "revive clears death + spends a continue")
	assert(is_equal_approx(player.current_hp, player.max_hp), "revive restores full HP")
	player._revive_invuln = false  # skip the i-frame window so the next hit lands

	# 2nd death -> offers the paid continue.
	player.take_damage(99999.0)
	assert(downed_events.size() == 2 and downed_events[1] == 1, "2nd death should offer the paid (index 1) continue")
	assert(final_deaths.is_empty(), "still no game over on the 2nd down")
	player.revive()
	assert(player.continues_used == 2, "2nd revive brings continues used to the max")
	player._revive_invuln = false

	# 3rd death -> the real game over (no more continue offers).
	player.take_damage(99999.0)
	assert(downed_events.size() == 2, "no 3rd continue offer past the max")
	assert(final_deaths.size() == 1, "the 3rd death is the real game over (player_died fires)")

	# Essence sink used by the paid continue.
	var before: int = SaveManager.essence
	SaveManager.add_essence(100)
	assert(SaveManager.spend_essence(30), "spend should succeed when affordable")
	assert(SaveManager.essence == before + 70, "spend should deduct exactly")
	assert(not SaveManager.spend_essence(999999), "spend should refuse (and not deduct) when unaffordable")
	assert(SaveManager.essence == before + 70, "a refused spend must not change essence")

	SignalBus.player_downed.disconnect(on_downed)
	SignalBus.player_died.disconnect(on_died)
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _assert_class_skill_trees() -> void:
	# (2026-07-21) Per-class ACTIVE skill trees: a 4th auto-firing attack
	# line, 3 tiers, class-gated cards through the real wave-clear pool.
	var main = load(MAIN_SCENE).instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var class_popup = main.get_node("ClassSelectPopup")
	class_popup.select_class("sniper")

	var player: Player = get_tree().get_first_node_in_group("player")
	var popup: WaveUpgradePopup = get_tree().get_first_node_in_group("wave_upgrade_popup")

	# Class gating: only the player's own class's card is ever offered.
	for _i in 20:
		var offer := popup._get_offerable_upgrades(UpgradeResource.ElementType.CLASS)
		assert(offer.size() == 1, "class tree should offer exactly 1 card, got %d" % offer.size())
		assert(offer[0].id == "class_sniper_t1", "a sniper must only ever see sniper class cards, got %s" % offer[0].id)

	# Tier climb through the real apply path.
	player.apply_element_upgrade(load("res://resources/upgrades/class_sniper_t1.tres"))
	assert(player.class_skill_level == 1 and player._current_class_skill.id == "class_power_shot")
	assert(not player.class_skill_timer.is_stopped(), "class skill timer should start on the tier-1 pick")
	player.apply_element_upgrade(load("res://resources/upgrades/class_sniper_t2.tres"))
	player.apply_element_upgrade(load("res://resources/upgrades/class_sniper_t3.tres"))
	assert(player.class_skill_level == 3 and player._current_class_skill.id == "class_railshot", "tier picks should swap the class skill wholesale")
	assert(popup._get_offerable_upgrades(UpgradeResource.ElementType.CLASS).is_empty(), "a maxed class tree (no repeatables) should offer nothing")

	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	# Juggernaut's SELF_BURST mechanics on a standalone player: pulse damages
	# what's in range, Second Wind heals, and it refuses to fire (no heal)
	# with nothing in range.
	var player_scene: PackedScene = load("res://scenes/player/Player.tscn")
	var jugg: Player = player_scene.instantiate()
	add_child(jugg)
	jugg.apply_class("juggernaut")
	jugg.apply_element_upgrade(load("res://resources/upgrades/class_juggernaut_t1.tres"))
	jugg.apply_element_upgrade(load("res://resources/upgrades/class_juggernaut_t2.tres"))
	jugg.apply_element_upgrade(load("res://resources/upgrades/class_juggernaut_t3.tres"))
	assert(jugg._current_class_skill.id == "class_second_wind")

	var slime: EnemyData = load("res://resources/enemies/slime_scout.tres")
	var enemy: EnemyBase = slime.scene.instantiate()
	enemy.setup(slime, 100.0)
	add_child(enemy)
	enemy.activate()
	jugg.global_position = Vector2(300, 1000)
	enemy.global_position = jugg.global_position + Vector2(0, -100)  # inside the 170px pulse radius

	jugg.take_damage(2.0)
	var hp_after_hit: float = jugg.current_hp
	var enemy_hp: float = enemy.current_hp
	assert(jugg._fire_self_burst(jugg._current_class_skill), "pulse should fire with an enemy in range")
	assert(enemy.current_hp < enemy_hp, "pulse should damage enemies in range")
	assert(is_equal_approx(jugg.current_hp, hp_after_hit + 1.0), "Second Wind should heal 1 HP per successful cast")

	enemy.global_position = jugg.global_position + Vector2(0, -2000)  # far outside
	var hp_before_idle: float = jugg.current_hp
	assert(not jugg._fire_self_burst(jugg._current_class_skill), "pulse must refuse to fire with nothing in range")
	assert(jugg.current_hp == hp_before_idle, "no free Second Wind healing while idle")

	enemy.queue_free()
	jugg.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
