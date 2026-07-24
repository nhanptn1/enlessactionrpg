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


# (2026-07-23) The suite used raw assert(), which under headless Godot prints
# "SCRIPT ERROR: Assertion failed: ..." and then KEEPS GOING -- so a run with a
# genuine failure still finished by printing "ALL PASSED". That happened for
# real (a hitstop bug), and was only caught because the output was being
# grepped for "Assertion failed". Every check now goes through _expect(), which
# records the failure, and _ready() ends with a real verdict + a non-zero exit
# code so a failing run cannot masquerade as a passing one.
var _failures: Array[String] = []


func _expect(condition: bool, message: String = "(no message)") -> void:
	if condition:
		return
	_failures.append(message)
	push_error("CHECK FAILED: %s" % message)
	printerr("CHECK FAILED: %s" % message)


func _ready() -> void:
	_assert_autoloads()
	_assert_skill_resources()
	await _assert_save_roundtrip()
	if _failures.is_empty():
		print("SystemsSmokeTest: ALL PASSED")
		get_tree().quit(0)
		return
	printerr("SystemsSmokeTest: %d CHECK(S) FAILED" % _failures.size())
	for f in _failures:
		printerr("  - %s" % f)
	print("SystemsSmokeTest: FAILED (%d)" % _failures.size())
	get_tree().quit(1)


func _assert_autoloads() -> void:
	_expect(SignalBus != null, "SignalBus missing")
	_expect(GameManager != null, "GameManager missing")
	_expect(AudioManager != null, "AudioManager missing")
	_expect(SaveManager != null, "SaveManager missing")
	_expect(AudioManager._streams.size() > 0, "AudioManager has no streams")


func _assert_skill_resources() -> void:
	var trap_shot = load("res://resources/skills/trap_shot.tres")
	_expect(trap_shot != null, "trap_shot.tres failed to load")
	_expect(trap_shot.fire_mode == SkillData.FireMode.TRAP_SHOT)
	_expect(load(MAIN_SCENE) != null, "Main.tscn failed to load")


func _assert_accounts_and_characters() -> void:
	# (2026-07-21) Local characters, up to 3, per-character progression, no
	# accounts. Works on a scratch state and restores whatever was there after.
	var saved_chars: Array = SaveManager.characters.duplicate(true)
	var saved_cur: int = SaveManager.current_character
	SaveManager.characters = []
	SaveManager.current_character = -1
	SaveManager._reset_active_fields()

	_expect(SaveManager.character_count() == 0)
	var i0 := SaveManager.create_character("Alpha")
	_expect(i0 == 0 and SaveManager.has_active_character(), "creating a character selects it")
	_expect(SaveManager.current_character_name() == "Alpha")
	_expect(SaveManager.create_character("") == -1, "an empty name is refused")
	# Per-character progression: Alpha earns essence.
	SaveManager.add_essence(50)
	_expect(SaveManager.essence >= 50)

	var i1 := SaveManager.create_character("Beta")
	_expect(i1 == 1 and SaveManager.current_character_name() == "Beta", "second character, selected")
	# Beta gets a FRESH profile (per-character, not shared).
	_expect(SaveManager.essence == 0, "a new character starts with its own 0 essence, not Alpha's")

	_expect(SaveManager.create_character("Gamma") == 2)
	_expect(SaveManager.create_character("Delta") == -1, "at most %d characters" % SaveManager.MAX_CHARACTERS)

	# Switch back to Alpha -> her essence is restored (persisted separately).
	_expect(SaveManager.select_character(0))
	_expect(SaveManager.essence >= 50, "Alpha's own essence should be intact after switching")

	# Survives a reload from disk.
	_expect(SaveManager.save_to_disk() and SaveManager.load_save())
	_expect(SaveManager.character_count() == 3, "characters persist through a save reload")

	# delete_character removes one and fixes up the selection.
	_expect(SaveManager.delete_character(1))
	_expect(SaveManager.character_count() == 2, "delete removes a character")

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
	_expect(SaveManager.has_active_character(), "a character must be active for the save tests")

	var before_wave := SaveManager.best_wave
	SaveManager.record_run(before_wave + 1, SaveManager.best_level + 1)
	_expect(SaveManager.best_wave >= before_wave + 1)
	_expect(SaveManager.load_save())
	_expect(SaveManager.best_wave >= before_wave + 1, "recorded best should survive a reload (per-character persistence)")
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
	_assert_card_frames_are_per_element()
	await _assert_bosses_have_own_art()
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
	await _assert_every_monster_hurts_on_contact()
	await _assert_lose_line()
	_assert_elite_density_scales()
	await _assert_elite_damage_mult_is_inert_on_the_player()
	_assert_tutorial_hints()


func _assert_meta_progression() -> void:
	# Reset vitality to rank 0 first -- repeated runs of this same smoke test
	# (e.g. during dev iteration) would otherwise accumulate rank across runs
	# until it hits max_rank, after which a fresh purchase correctly fails
	# and this assertion would flake.
	SaveManager.meta_upgrades["vitality"] = 0
	var before_essence := SaveManager.essence
	SaveManager.add_essence(1000)
	_expect(SaveManager.essence == before_essence + 1000, "add_essence should increase essence")
	_expect(SaveManager.purchase_meta_upgrade("vitality"), "purchase should succeed with enough essence")
	_expect(SaveManager.get_meta_rank("vitality") == 1, "purchase should increment rank")
	_expect(SaveManager.load_save(), "meta-progression state should round-trip through disk")
	_expect(SaveManager.get_meta_rank("vitality") == 1, "rank should persist after reload")


func _assert_equipment_slots() -> void:
	var apprentice_bow = load("res://resources/items/apprentice_bow.tres")
	var silver_longbow = load("res://resources/items/silver_longbow.tres")
	var player_scene = load("res://scenes/player/Player.tscn")
	var player = player_scene.instantiate()
	add_child(player)

	var base_damage_mult: float = player.damage_mult
	player.apply_item(apprentice_bow)
	_expect(player.equipped["weapon"] == apprentice_bow, "weapon slot should hold the equipped item")
	player.apply_item(silver_longbow)
	_expect(player.equipped["weapon"] == silver_longbow, "2nd weapon should replace the 1st in the same slot")
	_expect(is_equal_approx(player.damage_mult, base_damage_mult + 0.04), "replacing gear should revert the old bonus before applying the new one, got %s" % player.damage_mult)

	player.queue_free()


func _assert_audio_depth() -> void:
	for id in ["heal", "elite_spawn", "enemy_shot", "item_pickup_rare"]:
		_expect(AudioManager._streams.has(id), "AudioManager missing stream '%s'" % id)

	var player_scene = load("res://scenes/player/Player.tscn")
	var player = player_scene.instantiate()
	add_child(player)
	var healed := [false]
	var conn := func(_amount): healed[0] = true
	SignalBus.player_healed.connect(conn)
	player.current_hp = 1.0
	player.apply_upgrade("hp")
	_expect(healed[0], "a real heal should emit SignalBus.player_healed")
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
	_expect(wave6_total == 50, "wave 6 should total 50 monsters per the plan's ramp, got %d" % wave6_total)

	var boss_wave: WaveData = wm._generate_wave(10)
	var boss_total := 0
	for c in boss_wave.spawn_counts:
		boss_total += c
	_expect(boss_total >= 10 and boss_total <= 25, "boss wave support count should stay 10-25, got %d" % boss_total)

	var late_wave: WaveData = wm._generate_wave(40)
	var late_total := 0
	for c in late_wave.spawn_counts:
		late_total += c
	_expect(late_total <= 100, "late-game wave total should stay capped at 100, got %d" % late_total)


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
		_expect(tank_species_count <= 1, "wave 9 rolled %d tank species in one trial, expected at most 1" % tank_species_count)
		if tank_count > 0:
			_expect(float(tank_count) / float(total) <= 0.2, "a rolled tank species' population share should stay capped around 15%%, got %.1f%%" % (float(tank_count) / float(total) * 100.0))


func _assert_leaked_enemy_deactivates() -> void:
	var spawner := EnemySpawner.new()
	spawner.name = "EnemySpawner"
	add_child(spawner)
	var pool := EnemyPool.new()
	add_child(pool)

	var cursed_wraith = load("res://resources/enemies/cursed_wraith.tres")
	var enemy: EnemyBase = spawner.spawn(cursed_wraith, 1.0, 1.0, 1.0, -1, 1.0, 100.0, false)
	# (2026-07-24) Driven by actually WALKING the enemy across the lose line on
	# real physics frames, rather than calling the leak handler directly as this
	# test used to. That is the entire point of replacing
	# VisibleOnScreenNotifier2D (which never fires headlessly) with a position
	# check -- the trigger itself is now covered, not just its consequences.
	enemy.global_position.y = LoseLine.Y - 6.0
	var crossed := false
	for i in 60:
		await get_tree().physics_frame
		if enemy._is_dying:
			crossed = true
			break
	_expect(crossed, "an enemy walking past the lose line must trigger the leak on its own")
	await get_tree().process_frame

	_expect(not enemy.is_physics_processing(), "a leaked enemy must stop physics_process")
	_expect(enemy.collision.disabled, "a leaked enemy must disable collision")
	_expect(not enemy.hurtbox.monitoring, "a leaked enemy must stop hurtbox monitoring")
	_expect(enemy.attack_timer.is_stopped(), "a leaked enemy must stop its attack_timer")
	_expect(not enemy.is_in_group("enemy"), "a leaked enemy must leave the 'enemy' group")

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
	_expect(not reused.modulate.is_equal_approx(Color.WHITE), "a non-elite spawn must not fall back to plain white, must restore the species' own tint")

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
	_expect(player._get_nearest_enemies(1).has(enemy), "a live enemy should be targetable")

	enemy._die()
	await get_tree().create_timer(enemy.DEATH_FADE_DURATION + 0.15).timeout

	_expect(not enemy.is_in_group("enemy"), "a dead enemy must leave the 'enemy' group")
	_expect(not player._get_nearest_enemies(5).has(enemy), "a dead enemy must never be selected as a target again")

	player.queue_free()
	spawner.queue_free()
	pool.queue_free()


func _assert_player_movement_clamping() -> void:
	var player_scene = load("res://scenes/player/Player.tscn")
	_expect(player_scene != null, "Player.tscn failed to load")
	var player = player_scene.instantiate()
	add_child(player)
	
	# Set out-of-bounds positions and check clamping
	player.global_position = Vector2(800.0, 1150.0)
	player._physics_process(0.016)
	_expect(player.global_position.x == 660.0, "Player max bounds clamp failed: %f" % player.global_position.x)
	
	player.global_position = Vector2(10.0, 1150.0)
	player._physics_process(0.016)
	_expect(player.global_position.x == 60.0, "Player min bounds clamp failed: %f" % player.global_position.x)
	
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
	_expect(player._is_dashing and player._is_invulnerable, "_start_dash() should set both dashing and invulnerable")

	player.take_damage(5.0)
	_expect(player.current_hp == hp_before, "no damage should land while invulnerable during a dash")

	var ticks := 0
	while player._is_dashing and ticks < 60:
		await get_tree().physics_frame
		ticks += 1
	_expect(not player._is_dashing and not player._is_invulnerable, "dash should end and clear invulnerability on its own")

	var dist: float = player.global_position.x - start_x
	_expect(dist > 100.0 and dist < 200.0, "dash should cover roughly DASH_SPEED*DASH_DURATION, got %s" % dist)

	player.take_damage(3.0)
	_expect(player.current_hp == hp_before - Player.HIT_COST, "damage should apply normally again once the dash ends")

	_expect(player._dash_cooldown_remaining > 0.0, "cooldown should still be active immediately after a dash, blocking spam")
	_expect(not player.try_dash(), "try_dash() must refuse while the cooldown is running -- shared gate for Space and the HUD button")

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
	_expect(not player.is_ultimate_unlocked(), "ultimate must stay locked below the unlock tier (tier 3)")
	player.apply_element_upgrade(load("res://resources/upgrades/fire_t4_inferno_mastery.tres"))
	_expect(player.is_ultimate_unlocked(), "reaching the unlock tier (4) should unlock the ultimate")
	player.apply_element_upgrade(load("res://resources/upgrades/fire_t5_inferno_heart.tres"))
	# No projectile_pool here -- stop auto-fire so it can't error mid-test.
	player.attack_timer.stop()
	var fire_timer: Timer = player.get_elemental_timer_by_element(UpgradeResource.ElementType.FIRE)
	if is_instance_valid(fire_timer):
		fire_timer.stop()

	_expect(player.is_ultimate_unlocked(), "a maxed element should keep the ultimate unlocked")
	_expect(not player.can_use_ultimate(), "uncharged ultimate must not be usable")

	for _i in player.ULTIMATE_KILLS_REQUIRED + 10:
		SignalBus.enemy_died.emit()
	_expect(player.ultimate_charge == player.ULTIMATE_KILLS_REQUIRED, "charge should cap at ULTIMATE_KILLS_REQUIRED")
	_expect(player.can_use_ultimate(), "capstone + full charge should make the ultimate usable")

	var slime: EnemyData = load("res://resources/enemies/slime_scout.tres")
	var enemy: EnemyBase = slime.scene.instantiate()
	enemy.setup(slime, 100.0)
	add_child(enemy)
	enemy.activate()
	enemy.global_position = Vector2(300, 300)
	var hp_before: float = enemy.current_hp
	player._use_ultimate()
	_expect(player.ultimate_charge == 0, "using the ultimate should consume the full charge")
	_expect(enemy.current_hp < hp_before, "the ultimate should damage every enemy in the group")
	_expect(enemy.status.has(StatusEffects.FIRE), "the fire ultimate should burn every enemy it hits")

	enemy.queue_free()
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _assert_trap_zone_activation() -> void:
	var trap_scene = load("res://scenes/effects/TrapZone.tscn")
	_expect(trap_scene != null, "TrapZone.tscn failed to load")
	var trap = trap_scene.instantiate()

	# Replicates the player.gd setup: calling activate() before add_child()
	trap.activate(10.0, 3.0, 50.0, Vector2(100.0, 100.0))
	add_child(trap)

	_expect(trap.visual != null, "TrapZone visual node is Nil")
	_expect(trap.collision != null, "TrapZone collision node is Nil")
	_expect(trap.collision.shape != null, "TrapZone collision shape is Nil")

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
	_expect(trap.detonate_mult == 0.8, "TrapZone detonate_mult not set from activate()")
	trap._detonate()
	_expect(trap._detonated, "TrapZone did not mark itself detonated")
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
	_expect(sections.size() == 3, "expected Core + Run Modifier + Fire sections, got %d" % sections.size())
	var titles: Array[String] = []
	for section in sections:
		titles.append((section.get_child(0) as Label).text)
	_expect(titles.has("Core"), "Stats panel missing Core section")
	_expect(titles.has("Run Modifier"), "Stats panel missing Run Modifier section")
	_expect(titles.has("Fire"), "Stats panel missing Fire section for an unlocked element")
	_expect(not titles.has("Frost"), "Stats panel should not show a locked element's section")

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
	_expect(goblin.zigzag_speed > 0.0, "sanity: goblin_runner should actually be a zigzag mover")

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
	_expect(hits == trials, "homing Fire Arrow should hit a zigzagging enemy every trial, got %d/%d" % [hits, trials])

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
	_expect(is_instance_valid(player) and is_instance_valid(popup), "real Main.tscn should have a player + wave_upgrade_popup")

	# (2026-07-17) 1-5, not 1-4 -- entry 52 grew Fire's real max tier to 5
	# (the Inferno Heart capstone), so tier 4 alone is no longer "maxed" and
	# would legitimately still offer the tier-5 card as a next-tier option
	# (a real gap this test had already gone stale on, just not caught
	# deterministically since _get_offerable_upgrades() picks randomly).
	for tier in [1, 2, 3, 4, 5]:
		var upgrade := _find_upgrade(popup, UpgradeResource.ElementType.FIRE, tier)
		_expect(upgrade != null, "missing a real fire tier-%d upgrade resource in the wired pool" % tier)
		player.apply_element_upgrade(upgrade)
	_expect(player.fire_level == 5, "fire should be fully maxed, got tier %d" % player.fire_level)

	var offer := popup._get_offerable_upgrades(UpgradeResource.ElementType.FIRE)
	_expect(not offer.is_empty(), "a maxed Fire whose stat cards aren't capped yet should still offer its repeatable boost cards")
	_expect(offer[0].tier == 0, "a maxed element should only ever offer tier=0 repeatable cards now, got tier %d" % offer[0].tier)

	# (2026-07-22) ...but once the skill tier is maxed AND every repeatable stat
	# card has hit its max_stacks, the line must go silent -- so a fully-finished
	# element drops out of the picker (and when all lines are done, the popup
	# stops appearing). Cap every Fire tier-0 card by applying it max_stacks times.
	var fire_repeatables: Array = []
	for candidate in popup.upgrade_pool:
		if candidate.element == UpgradeResource.ElementType.FIRE and candidate.tier == 0:
			fire_repeatables.append(candidate)
	_expect(fire_repeatables.size() > 0, "Fire should have repeatable tier-0 cards to cap")
	for card in fire_repeatables:
		_expect(card.max_stacks > 0, "%s must declare a max_stacks cap" % card.id)
		for _s in card.max_stacks:
			player.apply_element_upgrade(card)
		_expect(int(player.repeatable_stacks.get(card.id, 0)) == card.max_stacks, "%s should be capped at %d stacks" % [card.id, card.max_stacks])
	var offer_capped := popup._get_offerable_upgrades(UpgradeResource.ElementType.FIRE)
	_expect(offer_capped.is_empty(), "a fully-maxed Fire (skill maxed AND all stat cards capped) must offer nothing -- it should drop out of the picker")

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
	_expect(is_instance_valid(player) and popup != null, "real Main.tscn should have a player + LevelUpPopup")

	var skill := player.get_current_physical_skill()
	_expect(skill != null and skill.fire_mode != SkillData.FireMode.TRAP_SHOT, "baseline physical skill should be a cone for this test")
	_expect(skill.projectile_count < player.MAX_SHOT_COUNT, "baseline skill must start below the arrow cap")

	# Below the cap -> +1 Arrow is offered.
	player.bonus_projectile_count = 0
	_expect("projectile_count" in popup._eligible_upgrade_ids(), "+1 Arrow should be offered while below the arrow cap")

	# Exactly at the cap -> +1 Arrow is dropped.
	player.bonus_projectile_count = player.MAX_SHOT_COUNT - skill.projectile_count
	_expect(skill.projectile_count + player.bonus_projectile_count == player.MAX_SHOT_COUNT, "test should drive the shot count to exactly the cap")
	_expect(not ("projectile_count" in popup._eligible_upgrade_ids()), "+1 Arrow must not be offered once arrows are capped at MAX_SHOT_COUNT")

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
	_expect(get_tree().get_first_node_in_group("player") == player, "test player must be the sole node in the player group")

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
	_expect(player.fire_level == 5, "fire should be maxed, got %d" % player.fire_level)
	_expect(player.active_fusions.is_empty(), "one line alone must not unlock any fusion")

	# (2026-07-22) Gate is FUSION_UNLOCK_TIER (4), not the tier-5 capstone --
	# requiring capstones on two lines made fusions effectively unreachable.
	# Frost through tier 3 -> still locked; tier 4 -> Frostfire unlocks.
	for i in 3:
		player.apply_element_upgrade(load(frost_paths[i]))
	_expect(player.frost_level == 3 and player.active_fusions.is_empty(), "below the unlock tier the fusion must stay locked")
	player.apply_element_upgrade(load(frost_paths[3]))
	_expect(player.frost_level == player.FUSION_UNLOCK_TIER, "frost should be at the unlock tier")
	_expect("fire_frost" in player.active_fusions, "reaching tier %d on a second line must unlock the fusion" % player.FUSION_UNLOCK_TIER)
	# Pushing on to the capstone must not double-unlock or drop it.
	player.apply_element_upgrade(load(frost_paths[4]))
	_expect(player.frost_level == 5, "frost should be maxed, got %d" % player.frost_level)
	_expect(player.active_fusions.count("fire_frost") == 1, "a fusion must unlock exactly once")
	_expect("fire_frost" in player.active_fusions, "maxing fire + frost must unlock the fire_frost fusion")
	_expect(fusion_signal["fired"], "fusion_unlocked signal should have fired")
	# (2026-07-23) Unlocking only makes a fusion SELECTABLE -- it fuses nothing
	# until the player equips it. That's what gives the HUD's Activate button
	# something to do.
	_expect(player.active_fusion_id == "", "a freshly unlocked fusion must not be auto-equipped")
	_expect(player.get_fusion_partners("fire").is_empty(), "an un-equipped fusion must not fuse attacks")

	_expect(player.select_active_fusion("fire_frost"), "an unlocked fusion should be equippable")
	_expect(player.active_fusion_id == "fire_frost", "the fusion should now be equipped")
	_expect(player.get_current_fusion_skill() != null, "equipping should load the fusion's own SkillData")
	_expect(player.fusion_skill_timer != null and not player.fusion_skill_timer.is_stopped(), "equipping should start the fusion's auto-fire timer")
	_expect(player.get_fusion_partners("fire").has("frost") and player.get_fusion_partners("fire").size() == 1, "fire's fusion partner should be exactly frost")
	_expect(player.get_fusion_partners("frost").has("fire"), "frost's fusion partner should be fire")
	_expect(not player.select_active_fusion("frost_lightning"), "a fusion that isn't unlocked must not be equippable")

	# Picking an element again un-equips the fusion and stops its timer.
	player.select_active_element(UpgradeResource.ElementType.FIRE)
	_expect(player.active_fusion_id == "", "picking an element should un-equip the fusion")
	_expect(player.fusion_skill_timer.is_stopped(), "un-equipping should stop the fusion timer")
	_expect(player.get_fusion_partners("fire").is_empty(), "attacks should stop fusing once un-equipped")
	# Re-equip for the combo assertions below, which depend on fusing.
	_expect(player.select_active_fusion("fire_frost"), "should be able to re-equip")

	# Every fusion needs display data -- it's surfaced as an owned "skill" in the
	# HUD row + pause-menu Fusions section, so a missing name/icon/description
	# would render as a blank entry.
	for pid in ElementFusions.FUSIONS:
		_expect(ElementFusions.display_name(pid) != "", "%s needs a display name" % pid)
		_expect(ElementFusions.description(pid) != "", "%s needs a description" % pid)
		var ipath := ElementFusions.icon_path(pid)
		_expect(ipath != "" and ResourceLoader.exists(ipath), "%s needs an icon that actually exists (%s)" % [pid, ipath])

	# (2026-07-23) Real extracted fusion art -- every frame must be on disk, or
	# the combo silently plays nothing.
	var fusion_anims := {
		"frostfire bolt": [ImpactVFX.FROSTFIRE_BOLT_FRAME_PATHS, ImpactVFX._get_frostfire_bolt_frames()],
		"superconductor arc": [ImpactVFX.SUPERCONDUCTOR_ARC_FRAME_PATHS, ImpactVFX._get_superconductor_arc_frames()],
		"overload burst": [ImpactVFX.OVERLOAD_BURST_FRAME_PATHS, ImpactVFX._get_overload_burst_frames()],
	}
	for anim_name in fusion_anims:
		var paths: Array = fusion_anims[anim_name][0]
		var frames: SpriteFrames = fusion_anims[anim_name][1]
		for fpath in paths:
			_expect(ResourceLoader.exists(fpath), "%s frame missing: %s" % [anim_name, fpath])
		_expect(frames != null and frames.get_frame_count("burst") == paths.size(), "the %s animation should build all %d frames" % [anim_name, paths.size()])

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
	_expect(not is_instance_valid(e1) or e1.current_hp < hp1, "with Frostfire active, a fire hit alone must trigger the combo and damage the enemy")
	_expect(not is_instance_valid(e1) or not (e1.status.has(StatusEffects.FIRE) and e1.status.has(StatusEffects.FROST)), "the combo should have consumed both statuses")
	if is_instance_valid(e1):
		e1.queue_free()

	# Overload: the NEW Fire+Lightning combo, reachable only via fusion. Force
	# just that fusion and confirm a fire hit alone discharges it.
	player.active_fusions = ["fire_lightning"]
	_expect(player.select_active_fusion("fire_lightning"), "Overload should be equippable once unlocked")
	var e2: EnemyBase = spawner.spawn(goblin, 1.0, 1.0, 1.0, -1, 1.0, 900.0, false)
	e2.global_position = Vector2(360, 400)
	var hp2: float = e2.current_hp
	e2.apply_status(StatusEffects.FIRE, 2.0)
	_expect(not is_instance_valid(e2) or e2.current_hp < hp2, "with Overload active, a fire hit alone must trigger the fire+lightning combo")
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
	_expect(WaveManager.SPEED_MULT_CEILING < late, "sanity: 500 waves should exceed the ceiling")
	_expect(minf(late, WaveManager.SPEED_MULT_CEILING) == WaveManager.SPEED_MULT_CEILING, "speed scaling must clamp to SPEED_MULT_CEILING")
	# A shocked enemy at the speed ceiling must still be slower than an
	# un-shocked baseline enemy -- the whole point of capping.
	_expect(WaveManager.SPEED_MULT_CEILING * StatusEffects.LIGHTNING_SLOW_MULT < 1.0, "a shocked late-wave enemy must not outrun an unshocked wave-1 enemy")

	var spawner := EnemySpawner.new()
	spawner.name = "EnemySpawner"
	add_child(spawner)
	var enemy_pool := EnemyPool.new()
	add_child(enemy_pool)
	var goblin = load("res://resources/enemies/goblin_runner.tres")

	# 2. Shock = brief hard stun, then the slow. Frost = full stop throughout.
	var shocked: EnemyBase = spawner.spawn(goblin, 1.0, 1.0, 1.0, -1, 1.0, 300.0, false)
	shocked.apply_status(StatusEffects.LIGHTNING, StatusEffects.LIGHTNING_DURATION)
	_expect(StatusEffects.is_stunned(shocked), "a fresh shock should stun")
	_expect(shocked.status.has(StatusEffects.STUN), "the stun is tracked in the status dict")
	# The stun expires well before the shock does, leaving the slow behind.
	StatusEffects.tick(shocked, StatusEffects.LIGHTNING_STUN_DURATION + 0.01)
	_expect(not StatusEffects.is_stunned(shocked), "the stun should expire after LIGHTNING_STUN_DURATION")
	_expect(shocked.status.has(StatusEffects.LIGHTNING), "the shock slow should outlast its opening stun")
	_expect(StatusEffects.speed_multiplier(shocked) < 1.0, "a shocked enemy should still be slowed after the stun")
	shocked.queue_free()

	var frozen: EnemyBase = spawner.spawn(goblin, 1.0, 1.0, 1.0, -1, 1.0, 400.0, false)
	frozen.apply_status(StatusEffects.FROST, StatusEffects.FROST_DURATION)
	_expect(StatusEffects.is_frozen(frozen), "frost should freeze")
	_expect(not StatusEffects.is_stunned(frozen), "frost freezes via is_frozen, it must not set the shock stun")
	frozen.queue_free()

	# Fire is deliberately a pure DOT -- it must never stop or slow anything.
	var burning: EnemyBase = spawner.spawn(goblin, 1.0, 1.0, 1.0, -1, 1.0, 500.0, false)
	burning.apply_status(StatusEffects.FIRE, StatusEffects.FIRE_DURATION)
	_expect(not StatusEffects.is_frozen(burning) and not StatusEffects.is_stunned(burning), "fire must not apply a movement lock")
	_expect(is_equal_approx(StatusEffects.speed_multiplier(burning), 1.0), "fire must not slow")
	burning.queue_free()

	# 4. Burn scales with the enemy's own wave HP multiplier, so a tankier
	#    late-wave enemy burns proportionally as fast as a wave-1 one.
	var tanky: EnemyBase = spawner.spawn(goblin, 8.0, 1.0, 1.0, -1, 1.0, 600.0, false)
	_expect(is_equal_approx(StatusEffects._burn_scale(tanky), 8.0), "burn should scale by the enemy's hp_mult")
	var plain: EnemyBase = spawner.spawn(goblin, 1.0, 1.0, 1.0, -1, 1.0, 700.0, false)
	_expect(is_equal_approx(StatusEffects._burn_scale(plain), 1.0), "an unscaled enemy burns at the base rate")
	tanky.queue_free()
	plain.queue_free()

	# 3. Bosses: slowed while chilled/shocked, but never fully stopped.
	var boss_data = load("res://resources/enemies/fallen_knight.tres")
	var boss: BossBase = boss_data.scene.instantiate()
	boss.setup(boss_data, 1.0, 1.0, 1.0)
	add_child(boss)
	_expect(is_equal_approx(StatusEffects.boss_speed_multiplier(boss), 1.0), "an unafflicted boss moves at full speed")
	boss.apply_status(StatusEffects.FROST, StatusEffects.FROST_DURATION)
	var boss_slow := StatusEffects.boss_speed_multiplier(boss)
	_expect(boss_slow < 1.0, "a chilled boss should be slowed")
	_expect(boss_slow > 0.0, "a boss must never be fully stopped -- that's the whole point of the boss carve-out")
	_expect(is_equal_approx(boss_slow, StatusEffects.BOSS_STATUS_SLOW_MULT), "boss slow should be BOSS_STATUS_SLOW_MULT")
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
	_expect(is_instance_valid(player) and pause_menu != null, "need a real player + PauseMenu")

	var physical_skill := player.get_current_physical_skill()
	_expect(physical_skill != null, "the basic line always has a skill")

	# --- Basic line: damage + cooldown must track the player's multipliers ---
	var before: String = pause_menu._format_skill_stats(physical_skill, player, UpgradeResource.ElementType.PHYSICAL)
	var base_dmg := roundi(physical_skill.base_damage * player.damage_mult)
	_expect(("Damage %d" % base_dmg) in before, "the basic row should show effective damage; got '%s'" % before)

	# Take real upgrades through the real apply path.
	for _i in 12:
		player.apply_upgrade("damage")    # +2% damage each
		player.apply_upgrade("cooldown")  # -3% cooldown each
	var after: String = pause_menu._format_skill_stats(physical_skill, player, UpgradeResource.ElementType.PHYSICAL)
	_expect(after != before, "skill panel stats must change after damage/cooldown upgrades\nbefore: %s\nafter:  %s" % [before, after])
	var up_dmg := roundi(physical_skill.base_damage * player.damage_mult)
	_expect(up_dmg > base_dmg, "sanity: 12 damage upgrades should raise effective damage")
	_expect(("Damage %d" % up_dmg) in after, "the row should show the RAISED damage; got '%s'" % after)
	_expect(("Cooldown %.1fs" % (physical_skill.cooldown * player.cooldown_mult)) in after, "the row should show the REDUCED cooldown; got '%s'" % after)

	# --- "+1 Arrow" must show up, and must respect the hard cap ---
	if physical_skill.fire_mode != SkillData.FireMode.TRAP_SHOT:
		player.bonus_projectile_count = 0
		var no_bonus: String = pause_menu._format_skill_stats(physical_skill, player, UpgradeResource.ElementType.PHYSICAL)
		player.bonus_projectile_count = 2
		var with_bonus: String = pause_menu._format_skill_stats(physical_skill, player, UpgradeResource.ElementType.PHYSICAL)
		_expect(no_bonus != with_bonus, "+1 Arrow picks should change the displayed arrow count")
		player.bonus_projectile_count = 99  # way past the cap
		var capped: String = pause_menu._format_skill_stats(physical_skill, player, UpgradeResource.ElementType.PHYSICAL)
		_expect(("%d arrows" % player.MAX_SHOT_COUNT) in capped, "arrow count must clamp to MAX_SHOT_COUNT; got '%s'" % capped)
		player.bonus_projectile_count = 0

	# --- Element line: its own separate multipliers, not the basic line's ---
	player.apply_element_upgrade(load("res://resources/upgrades/fire_t1_searing_shot.tres"))
	var fire_skill := player.get_current_skill_for_element(UpgradeResource.ElementType.FIRE)
	_expect(fire_skill != null, "fire tier 1 should set a fire skill")
	var fire_before: String = pause_menu._format_skill_stats(fire_skill, player, UpgradeResource.ElementType.FIRE)
	player.fire_skill_dmg_mult += 0.5
	player.fire_skill_cd_mult -= 0.2
	var fire_after: String = pause_menu._format_skill_stats(fire_skill, player, UpgradeResource.ElementType.FIRE)
	_expect(fire_after != fire_before, "element row must track its own dmg/cd multipliers\nbefore: %s\nafter:  %s" % [fire_before, fire_after])
	_expect(("Damage %d" % roundi(fire_skill.base_damage * player.fire_skill_dmg_mult)) in fire_after, "fire row should use fire_skill_dmg_mult; got '%s'" % fire_after)

	# The whole panel must still build with the extra player arg threaded through.
	pause_menu._build_skill_rows()
	await get_tree().process_frame
	_expect(pause_menu.skill_rows_container.get_child_count() > 0, "skills panel should still build")

	# (2026-07-22) The skill panel is two tabs (tree / stats) sharing one
	# scroll -- exactly one view is visible at a time, and opening the panel
	# always lands on the tree tab rather than remembering the last one.
	pause_menu.open_skills_panel()
	await get_tree().process_frame
	_expect(pause_menu.tree_view.visible and not pause_menu.skill_rows_container.visible, "the panel should open on the Skill Tree tab")
	_expect(pause_menu.tree_tab.button_pressed and not pause_menu.stats_tab.button_pressed, "the tree tab should read as selected")
	# Drive the REAL button signals, so the .bind() wiring is covered too.
	pause_menu.stats_tab.pressed.emit()
	_expect(pause_menu.skill_rows_container.visible and not pause_menu.tree_view.visible, "the Skill Stats tab should swap the visible view")
	_expect(pause_menu.stats_tab.button_pressed and not pause_menu.tree_tab.button_pressed, "the stats tab should read as selected")
	pause_menu.tree_tab.pressed.emit()
	_expect(pause_menu.tree_view.visible and not pause_menu.skill_rows_container.visible, "switching back should restore the tree")
	_expect(pause_menu.tree_tab.button_pressed and not pause_menu.stats_tab.button_pressed, "the tree tab should read as selected again")

	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _assert_card_frames_are_per_element() -> void:
	# (2026-07-23) Card frames moved from one greyscale base + a multiply tint
	# to five pre-baked duotone textures, so Lightning can finally be
	# purple+yellow (multiply could only ever produce a single hue). Guards the
	# two ways that can regress: a missing texture file, or two lines silently
	# sharing one frame again.
	var seen: Array[String] = []
	for element in WaveUpgradePopup.CARD_FRAMES:
		var path: String = WaveUpgradePopup.CARD_FRAMES[element]
		_expect(ResourceLoader.exists(path), "card frame missing on disk: %s" % path)
		_expect(not (path in seen), "each line needs its OWN frame texture, %s is reused" % path)
		seen.append(path)
		_expect(load(path) != null, "card frame failed to load: %s" % path)
	_expect(seen.size() == WaveUpgradePopup.CARD_FRAMES.size(), "every declared line needs a frame, got %d" % seen.size())
	_expect(seen.size() >= 6, "expected frames for physical/fire/frost/lightning/class/fusion, got %d" % seen.size())

	# The lightning frame must genuinely carry BOTH hues -- that's the whole
	# point of the duotone, and the one thing a flat tint could never do.
	var img: Image = (load(WaveUpgradePopup.CARD_FRAMES[UpgradeResource.ElementType.LIGHTNING]) as Texture2D).get_image()
	img.convert(Image.FORMAT_RGBA8)
	var purple := 0
	var yellow := 0
	for y in range(0, img.get_height(), 3):  # sampled -- a full scan is needless work in a smoke test
		for x in range(0, img.get_width(), 3):
			var p := img.get_pixel(x, y)
			if p.a < 0.5 or p.s < 0.3:
				continue
			if p.h > 0.70 and p.h < 0.88:
				purple += 1
			elif p.h > 0.08 and p.h < 0.20:
				yellow += 1
	_expect(purple > 0 and yellow > 0, "the lightning frame must be two-tone (purple shadows + yellow highlights), got purple=%d yellow=%d" % [purple, yellow])


func _assert_bosses_have_own_art() -> void:
	# (2026-07-23) Every boss used to borrow a REGULAR enemy's sprites, and
	# Fallen Knight / Dark Ranger Commander shared the exact same skeleton
	# frames. As each boss gets real art this guards two ways that can regress:
	# a boss silently pointing back at shared/enemy art, and -- for the Forest
	# Guardian, whose scene had to be rebuilt around its animation -- losing the
	# sapling_data its summon attack depends on.
	var boss_scenes := {
		"fallen_knight": "res://scenes/enemies/FallenKnight.tscn",
		"dark_ranger_commander": "res://scenes/enemies/DarkRangerCommander.tscn",
		"demon_beast": "res://scenes/enemies/DemonBeast.tscn",
		"corrupted_forest_guardian": "res://scenes/enemies/CorruptedForestGuardian.tscn",
	}
	var seen_textures: Dictionary = {}
	for boss_name in boss_scenes:
		var packed: PackedScene = load(boss_scenes[boss_name])
		_expect(packed != null, "%s scene failed to load" % boss_name)
		if packed == null:
			continue
		# Deliberately NOT added to the tree: BossBase._ready() needs setup()
		# to have supplied its EnemyData, and this check only cares about
		# authored scene contents, which instantiate() already populates.
		var inst := packed.instantiate()
		var spr: AnimatedSprite2D = inst.get_node_or_null("Sprite")
		_expect(spr != null and spr.sprite_frames != null, "%s needs a Sprite with frames" % boss_name)
		if spr != null and spr.sprite_frames != null:
			var count := spr.sprite_frames.get_frame_count("move")
			_expect(count >= 4, "%s should have a real multi-frame walk, got %d" % [boss_name, count])
			for i in count:
				var tex: Texture2D = spr.sprite_frames.get_frame_texture("move", i)
				_expect(tex != null, "%s move frame %d has no texture" % [boss_name, i])
				if tex == null:
					continue
				var path := tex.resource_path
				# Its OWN art, not a regular enemy's, and not another boss's.
				_expect(path.begins_with("res://art/bosses/"), "%s should use dedicated boss art, got %s" % [boss_name, path])
				_expect(not seen_textures.has(path), "%s reuses a texture another boss already uses: %s" % [boss_name, path])
				seen_textures[path] = boss_name
		inst.free()

	# The Guardian's summon attack reads sapling_data off the scene; rebuilding
	# that scene for its animation is exactly when it could go missing.
	var guardian := (load(boss_scenes["corrupted_forest_guardian"]) as PackedScene).instantiate()
	_expect(guardian.sapling_data != null, "the Forest Guardian lost sapling_data -- its summon attack would break")
	guardian.free()
	await get_tree().process_frame

	# (2026-07-23) Death animations: every boss must have one, and it must be
	# NON-LOOPING -- a looping death would never reach the tween that frees the
	# boss, leaving a corpse animating forever.
	for boss_name in boss_scenes:
		var inst2 := (load(boss_scenes[boss_name]) as PackedScene).instantiate()
		var frames: SpriteFrames = inst2.get_node("Sprite").sprite_frames
		_expect(frames.has_animation(&"death"), "%s needs a death animation" % boss_name)
		if frames.has_animation(&"death"):
			_expect(not frames.get_animation_loop(&"death"), "%s's death animation must not loop, or it would never free" % boss_name)
			_expect(frames.get_frame_count(&"death") >= 4, "%s's death should be a real sequence" % boss_name)
		# (2026-07-24) Attack used to be optional here, because the Guardian's row
		# merged two poses into one cut and it shipped without one. That row has
		# since been re-extracted with a declared column count, so all four bosses
		# have a real attack and this is now required -- a boss silently falling
		# back to the frozen-frame telegraph is the regression worth catching.
		_expect(frames.has_animation(&"attack"), "%s needs an attack animation" % boss_name)
		if frames.has_animation(&"attack"):
			_expect(not frames.get_animation_loop(&"attack"), "%s's attack animation must not loop" % boss_name)
			_expect(frames.get_frame_count(&"attack") >= 4, "%s's attack should be a real sequence" % boss_name)
		# `move` is the resting state and MUST loop.
		_expect(frames.get_animation_loop(&"move"), "%s's move animation must loop" % boss_name)
		inst2.free()


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
	_expect(boss._base_scale.is_equal_approx(authored_scale * BossBase.BOSS_VISUAL_SCALE), "boss sprite should be scaled by BOSS_VISUAL_SCALE; got %s from %s" % [boss._base_scale, authored_scale])
	# The boss NODE is separately scaled by WaveManager.BOSS_VISUAL_SCALE at
	# spawn, so this sprite bump must stay modest or the two stack into a
	# ~2.3x boss (which is exactly what a playtest caught).
	_expect(BossBase.BOSS_VISUAL_SCALE * WaveManager.BOSS_VISUAL_SCALE <= 1.9, "combined boss scale must stay reasonable, got %.2f" % (BossBase.BOSS_VISUAL_SCALE * WaveManager.BOSS_VISUAL_SCALE))

	# Aura exists, sits behind the sprite, and carries this boss's own colour.
	var aura: BossAura = boss._aura
	_expect(is_instance_valid(aura), "a boss should spawn a BossAura")
	_expect(aura.get_parent() == boss, "the aura should be parented to the boss so it follows without per-frame code")
	_expect(aura.z_index < 0, "the aura must draw BEHIND the boss sprite")
	_expect(aura.color.is_equal_approx(BossBase.AURA_COLORS["fallen_knight"]), "fallen_knight should use its own aura colour")

	# Phase 2 visibly escalates the aura rather than only moving the HP bar.
	var base_intensity := aura.intensity
	aura.set_phase(2)
	_expect(aura.intensity > base_intensity, "phase 2 should intensify the aura")
	aura.set_phase(1)
	_expect(is_equal_approx(aura.intensity, base_intensity), "dropping back to phase 1 should restore the base intensity")

	_expect(entrance["fired"], "spawning a boss should emit boss_entrance for the HUD flash")
	var flash_color: Color = entrance["color"]
	_expect(flash_color.is_equal_approx(BossBase.AURA_COLORS["fallen_knight"]), "the entrance flash should carry the boss's aura colour")
	boss.queue_free()
	await get_tree().process_frame

	# An affinity outranks the per-boss colour -- while a boss resists an
	# element, the colour is actionable (it matches the counter-cycle diagram).
	var affinity_boss: BossBase = boss_data.scene.instantiate()
	affinity_boss.affinity_id = "frost"
	affinity_boss.setup(boss_data, 1.0, 1.0, 1.0)
	add_child(affinity_boss)
	await get_tree().process_frame
	_expect(affinity_boss._aura.color.is_equal_approx(BossBase.AURA_AFFINITY_COLORS["frost"]), "an affinity boss's aura should use the affinity colour, not the per-boss one")
	affinity_boss.queue_free()

	SignalBus.boss_entrance.disconnect(cb)
	await get_tree().process_frame
	await get_tree().process_frame


func _assert_combat_juice() -> void:
	# (2026-07-23) Combat juice pass. Hitstop is the risky half -- it writes a
	# GLOBAL Engine.time_scale, so a bug here strands the whole game in slow
	# motion. These assertions exist mainly to prove it always restores.
	_expect(is_equal_approx(Engine.time_scale, 1.0), "time_scale should start clean")

	GameManager.hitstop(0.05)
	_expect(Engine.time_scale < 1.0, "hitstop should slow time while active")
	await get_tree().create_timer(0.2, true, false, true).timeout
	_expect(is_equal_approx(Engine.time_scale, 1.0), "hitstop MUST restore time_scale, got %s" % Engine.time_scale)

	# Overlapping calls must not let the first one restore early and leave the
	# second running un-slowed (generation-token guard).
	GameManager.hitstop(0.05)
	GameManager.hitstop(0.30)
	await get_tree().create_timer(0.15, true, false, true).timeout
	_expect(Engine.time_scale < 1.0, "the longer overlapping hitstop should still be holding time slowed")
	await get_tree().create_timer(0.35, true, false, true).timeout
	_expect(is_equal_approx(Engine.time_scale, 1.0), "overlapping hitstops must still restore, got %s" % Engine.time_scale)

	# A restart mid-hitstop must never strand the game slowed.
	GameManager.hitstop(5.0)
	_expect(Engine.time_scale < 1.0, "sanity: long hitstop is active")
	GameManager.reset_state()
	_expect(is_equal_approx(Engine.time_scale, 1.0), "reset_state must clear an in-flight hitstop")
	await get_tree().create_timer(0.1, true, false, true).timeout
	_expect(is_equal_approx(Engine.time_scale, 1.0), "the cancelled hitstop must not restore-then-reslow later")

	# Damage numbers: spawn, then free themselves rather than accumulating.
	var host := Node2D.new()
	add_child(host)
	DamageNumber.spawn(123.0, Vector2(100, 100), Color.WHITE, host, true)
	_expect(host.get_child_count() == 1, "a damage number should have been added")
	await get_tree().create_timer(DamageNumber.LIFETIME + 0.3, true, false, true).timeout
	_expect(host.get_child_count() == 0, "damage numbers must free themselves, %d left" % host.get_child_count())
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
	_expect(marker != null and marker is EliteMarker, "an elite should get an EliteMarker")
	_expect(marker.z_index < 0, "the elite marker must draw behind the enemy sprite")

	# Same instance reused as a NON-elite must lose the marker.
	spawner._ensure_elite_marker(elite, false)
	await get_tree().process_frame
	_expect(elite.get_node_or_null(EnemySpawner.ELITE_MARKER_NAME) == null, "a pooled non-elite reuse must not keep the elite marker")

	# A plain spawn never has one to begin with.
	var normal: EnemyBase = spawner.spawn(goblin, 1.0, 1.0, 1.0, -1, 1.0, 300.0, false)
	_expect(normal.get_node_or_null(EnemySpawner.ELITE_MARKER_NAME) == null, "a normal enemy should have no elite marker")
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
	_expect(found != null, "applying a class should add a PlayerAura")
	_expect(found.color.is_equal_approx(CharacterClasses.get_vfx_color("juggernaut")), "the class aura should use the class's vfx colour")
	_expect(found.z_index < 0, "the class aura must draw under the player sprite")

	# The three shape languages must be genuinely different scripts, not one
	# effect reused at three sizes (which is what the tint approach amounted to).
	_expect(EliteMarker != BossAura and PlayerAura != BossAura, "elite/player/boss must each have their own visual treatment")

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
	_expect(is_equal_approx(enraged._speed_mult, em["speed_mult"]), "enraged should multiply _speed_mult")
	_expect(is_equal_approx(enraged._damage_mult, em["damage_mult"]), "enraged should multiply _damage_mult")
	_expect(is_equal_approx(enraged._cooldown_mult, em["cooldown_mult"]), "enraged should set _cooldown_mult")
	enraged.queue_free()

	var shielded: BossBase = boss_data.scene.instantiate()
	shielded.mutation_id = "shielded"
	shielded.setup(boss_data, 1.0, 1.0, 1.0)
	add_child(shielded)
	var hp_before := shielded.current_hp
	shielded._mutation_invulnerable = true
	shielded.take_damage(5.0)
	_expect(shielded.current_hp == hp_before, "shielded boss must take zero damage during its invulnerability window")
	shielded._mutation_invulnerable = false
	shielded.take_damage(1.0)
	_expect(shielded.current_hp < hp_before, "shielded boss should take damage again once the window closes")
	shielded.queue_free()

	# Wave-cycle gating: cycle 1 never mutates, cycle 2+ can.
	var cycle1_rolls := 0
	var cycle2_rolls := 0
	for _i in 200:
		if 1 >= WaveManager.BOSS_MUTATION_MIN_CYCLE and randf() < WaveManager.BOSS_MUTATION_CHANCE:
			cycle1_rolls += 1
		if 2 >= WaveManager.BOSS_MUTATION_MIN_CYCLE and randf() < WaveManager.BOSS_MUTATION_CHANCE:
			cycle2_rolls += 1
	_expect(cycle1_rolls == 0, "a player's first-ever boss (cycle 1) must never roll a mutation")
	_expect(cycle2_rolls > 0, "cycle 2+ should roll mutations some of the time at a 50% chance")

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
	_expect(is_instance_valid(player) and is_instance_valid(popup), "real Main.tscn should have a player + wave_upgrade_popup")

	for tier in [1, 2, 3, 4]:
		var u := _find_upgrade(popup, UpgradeResource.ElementType.FIRE, tier)
		_expect(u != null, "missing a real fire tier-%d upgrade resource" % tier)
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
	_expect(tier5 != null, "missing the fire tier-5 capstone resource in the wired pool")
	player.apply_element_upgrade(tier5)
	_expect(player.fire_level == 5, "fire should reach capstone tier 5")
	var skill := player.get_current_skill_for_element(UpgradeResource.ElementType.FIRE)
	_expect(skill.id == "wildfire_storm", "tier 5 is passive-only -- active skill should stay Wildfire Storm")

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
	_expect(is_equal_approx(ratio, StatusEffects.FIRE_CAPSTONE_DPS_MULT), "fire capstone should multiply burn tick damage by %s, got ratio %s" % [StatusEffects.FIRE_CAPSTONE_DPS_MULT, ratio])

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
	_expect(e4.status.has(StatusEffects.FIRE), "Inferno Heart should guarantee a spread to a nearby enemy")
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
	_expect(seen.size() == RunModifiers.MODIFIERS.size(), "all %d modifiers should show up across 300 rolls, saw %d" % [RunModifiers.MODIFIERS.size(), seen.size()])

	for key in ["vitality", "power", "quickdraw", "insight"]:
		SaveManager.meta_upgrades[key] = 0
	var player_scene: PackedScene = load("res://scenes/player/Player.tscn")
	var player: Player = player_scene.instantiate()
	add_child(player)
	_expect(RunModifiers.MODIFIERS.has(player.active_run_modifier_id), "rolled id '%s' should be a real key" % player.active_run_modifier_id)
	var expected_max_hp: float = 10.0 * RunModifiers.get_mult(player.active_run_modifier_id, "player_max_hp_mult")
	_expect(is_equal_approx(player.max_hp, expected_max_hp), "max_hp should reflect the rolled modifier's mult")
	_expect(player.current_hp == player.max_hp, "current_hp should be topped to the modifier-adjusted max_hp")

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
	_expect(wave6_total > 0, "_generate_wave() must still work on a standalone WaveManager not in the scene tree")

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
	_expect(wm._is_boss_wave, "wave 10 should be a boss wave")
	var expected: float = wm._boss_hp_mult(1) * RunModifiers.get_mult("bounty_hunter", "enemy_hp_mult")
	_expect(is_equal_approx(wm._pending_boss_hp_mult, expected), "Bounty Hunter should multiply boss HP too, expected %s got %s" % [expected, wm._pending_boss_hp_mult])

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
	_expect(plain_delta > 0.0, "sanity: an unmutated advancing boss should move down over 10 physics ticks")
	var ratio := enraged_delta / plain_delta
	var em: Dictionary = BossBase.MUTATIONS["enraged"]
	_expect(absf(ratio - em["speed_mult"]) < 0.01, "Enraged should move %sx faster during actual post-engage advance, got ratio %s" % [em["speed_mult"], ratio])

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
	_expect(boss.affinity_id == "fire", "spawner should set affinity_id on the boss instance")
	_expect(announced.size() == 1 and announced[0] == "Enraged Flamebound (weak to Frost)", "combined announcement should carry both names plus the weak-to hint, got %s" % str(announced))

	var hp0: float = boss.current_hp
	boss.take_damage(10.0, "fire")
	_expect(is_equal_approx(hp0 - boss.current_hp, 10.0 * BossBase.AFFINITY_RESIST_MULT), "Flamebound must resist fire damage")
	hp0 = boss.current_hp
	boss.take_damage(10.0, "frost")
	_expect(is_equal_approx(hp0 - boss.current_hp, 10.0 * BossBase.AFFINITY_WEAK_MULT), "Flamebound must be weak to frost")
	hp0 = boss.current_hp
	boss.take_damage(10.0, "lightning")
	_expect(is_equal_approx(hp0 - boss.current_hp, 10.0), "the off-element (neither resist nor counter) must stay neutral")
	hp0 = boss.current_hp
	boss.take_damage(10.0)
	_expect(is_equal_approx(hp0 - boss.current_hp, 10.0), "physical/untyped damage must ignore affinity entirely")
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
	_expect(wm._is_boss_wave and wm._current_wave.wave_number == 30, "call count drifted -- expected to be sitting on wave 30")
	_expect(wm._pending_boss_mutation_id != "", "every 3rd boss cycle (wave 30) must guarantee a mutation")

	for _i in 20:
		wm._start_next_wave()
	_expect(wm._is_boss_wave and wm._current_wave.wave_number == 50, "call count drifted -- expected to be sitting on wave 50")
	_expect(wm._pending_boss_mutation_id != "", "an Overlord cycle (wave 50) must have a mutation")
	_expect(wm._pending_boss_affinity_id != "", "an Overlord cycle (wave 50) must have an affinity")
	var expected_hp: float = wm._boss_hp_mult(5) * WaveManager.OVERLORD_HP_MULT
	_expect(is_equal_approx(wm._pending_boss_hp_mult, expected_hp), "Overlord should multiply boss HP by %s, expected %s got %s" % [WaveManager.OVERLORD_HP_MULT, expected_hp, wm._pending_boss_hp_mult])

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
	_expect(sniper.active_class_id == "sniper")
	_expect(is_equal_approx(sniper.crit_chance, crit_before + 0.15), "sniper should add crit chance")
	_expect(is_equal_approx(sniper.max_hp, hp_before * 0.85), "sniper should trade max HP away")
	_expect(is_equal_approx(sniper.projectile_speed_mult, proj_before * 1.15), "sniper should speed up projectiles")
	sniper.queue_free()

	var elementalist: Player = player_scene.instantiate()
	add_child(elementalist)
	var fire_before: float = elementalist.fire_skill_dmg_mult
	var dmg_before: float = elementalist.damage_mult
	elementalist.apply_class("elementalist")
	_expect(is_equal_approx(elementalist.fire_skill_dmg_mult, fire_before * 1.25), "elementalist should boost elemental damage")
	_expect(is_equal_approx(elementalist.frost_skill_dmg_mult, 1.25) and is_equal_approx(elementalist.lightning_skill_dmg_mult, 1.25), "all 3 elements should get the boost")
	_expect(is_equal_approx(elementalist.damage_mult, dmg_before * 0.85), "elementalist should trade physical damage away")
	elementalist.queue_free()

	var ranger: Player = player_scene.instantiate()
	add_child(ranger)
	var r_hp: float = ranger.max_hp
	var r_dmg: float = ranger.damage_mult
	var r_crit: float = ranger.crit_chance
	ranger.apply_class("ranger")
	_expect(ranger.max_hp == r_hp and ranger.damage_mult == r_dmg and ranger.crit_chance == r_crit, "ranger must be a true stat no-op")
	ranger.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	# Real popup flow on a live Main.tscn.
	var main = load(MAIN_SCENE).instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(get_tree().paused, "the run-start class picker should hold the game paused")
	var popup = main.get_node("ClassSelectPopup")
	_expect(popup.panel.visible, "class picker should be visible at run start")
	var live_player: Player = get_tree().get_first_node_in_group("player")
	var live_hp: float = live_player.max_hp
	popup.select_class("juggernaut")
	_expect(not get_tree().paused, "picking a class should unpause the run")
	_expect(not popup.panel.visible, "picker should hide after the pick")
	_expect(is_equal_approx(live_player.max_hp, live_hp * 1.4), "juggernaut pick should apply through the real popup path")
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

	_expect(not SaveManager.has_seen_hint("move"), "a hint should be unseen before it's marked")
	SaveManager.mark_hint_seen("move")
	_expect(SaveManager.has_seen_hint("move"), "marking a hint should make it seen")
	_expect(SaveManager.load_save(), "seen-hint state should round-trip through disk")
	_expect(SaveManager.has_seen_hint("move"), "a seen hint should persist across a save reload")
	SaveManager.mark_hint_seen("move")  # idempotent -- no duplicate
	_expect(SaveManager.seen_hints.count("move") == 1, "marking twice must not duplicate")

	# Every id the HUD can queue must have copy defined.
	for id in ["move", "dash", "switch_element", "boss", "affinity", "ultimate"]:
		_expect(TutorialHints.HINTS.has(id), "missing tutorial copy for '%s'" % id)

	SaveManager.seen_hints = saved
	SaveManager.save_to_disk()


func _assert_elite_density_scales() -> void:
	# (2026-07-24) User: "after 10 waves, the elite spawn monster need to increase
	# for more difficult". Guards the shape of the curve, not just that it moves --
	# the early game was hand-tuned around elites being rare, and the ceiling
	# exists so an elite stays a distinct KIND of enemy rather than the baseline.
	var wm := WaveManager.new()

	for w in [1, 5, 9, 10]:
		_expect(is_equal_approx(wm.elite_chance_for_wave(w), WaveManager.ELITE_CHANCE),
			"wave %d must keep the hand-tuned base elite rate, got %s" % [w, wm.elite_chance_for_wave(w)])

	# Strictly increasing between the start wave and the ceiling.
	var prev: float = wm.elite_chance_for_wave(WaveManager.ELITE_CHANCE_START_WAVE)
	var reached_ceiling_at := -1
	for w in range(WaveManager.ELITE_CHANCE_START_WAVE + 1, 120):
		var cur: float = wm.elite_chance_for_wave(w)
		_expect(cur >= prev, "elite chance must never fall (wave %d: %s -> %s)" % [w, prev, cur])
		_expect(cur <= WaveManager.ELITE_CHANCE_CEILING + 0.0001,
			"elite chance must never exceed its ceiling (wave %d: %s)" % [w, cur])
		if reached_ceiling_at < 0 and is_equal_approx(cur, WaveManager.ELITE_CHANCE_CEILING):
			reached_ceiling_at = w
		prev = cur
	_expect(wm.elite_chance_for_wave(11) > WaveManager.ELITE_CHANCE, "wave 11 must already be above the base rate")
	# The climb has to last long enough to be felt as escalation rather than a
	# step change, but still arrive -- if this drifts far either way the late-game
	# pacing this was built to fix is back.
	_expect(reached_ceiling_at > 20 and reached_ceiling_at < 60,
		"the elite curve should reach its ceiling somewhere in the 20s-50s, got wave %d" % reached_ceiling_at)
	_expect(WaveManager.ELITE_CHANCE_CEILING <= 0.5,
		"past half the wave, 'elite' stops meaning anything -- ceiling is %s" % WaveManager.ELITE_CHANCE_CEILING)

	# Real rolls at the ceiling land near the declared rate (guards the wiring
	# between the curve and _spawn_one's roll, which a refactor could sever).
	seed(12345)
	var hits := 0
	var rolls := 4000
	var ceiling_chance: float = wm.elite_chance_for_wave(100)
	for i in rolls:
		if randf() < ceiling_chance:
			hits += 1
	var observed: float = float(hits) / float(rolls)
	_expect(absf(observed - ceiling_chance) < 0.04,
		"rolling at the ceiling rate should produce ~%s elites, observed %s" % [ceiling_chance, observed])

	wm.free()


func _assert_elite_damage_mult_is_inert_on_the_player() -> void:
	# (2026-07-24) Recorded deliberately, because it is a live trap rather than a
	# bug: ELITE_DAMAGE_MULT (1.4) still multiplies through spawn() -> setup() ->
	# _damage_mult -> contact_damage(), but the player's flat HIT_COST rule
	# (entry 90) ignores the incoming amount, so an elite hits for exactly as much
	# as anything else. Elites are therefore tougher and worth more XP, but NOT
	# individually more dangerous per hit. Anyone tuning elite difficulty by
	# raising that constant would see no effect whatsoever; this test says so out
	# loud, and will fail the moment the flat rule changes and the constant
	# silently comes back to life.
	var player: Player = load("res://scenes/player/Player.tscn").instantiate()
	add_child(player)
	player.get_node("BasicShotTimer").stop()
	await get_tree().physics_frame

	var data: EnemyData = load("res://resources/enemies/slime_scout.tres")
	var elite: EnemyBase = data.scene.instantiate()
	elite.setup(data, WaveManager.ELITE_HP_MULT, 1.0, WaveManager.ELITE_DAMAGE_MULT, -1)
	add_child(elite)
	elite.activate()
	await get_tree().physics_frame

	_expect(elite.contact_damage() > data.base_damage,
		"the elite damage multiplier should still reach contact_damage()")
	player.current_hp = player.max_hp
	player.take_damage(elite.contact_damage())
	_expect(is_equal_approx(player.current_hp, player.max_hp - Player.HIT_COST),
		"an elite hit still costs one HP -- ELITE_DAMAGE_MULT cannot change player damage while the flat rule stands")

	elite._deactivate()
	elite.queue_free()
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _assert_lose_line() -> void:
	# (2026-07-24) User: "when enemy run over character line, reduce character hp
	# (can create a line of death zone for player to know it). And when enemy run
	# pass this line, remove this enemy too." Replaces the old
	# VisibleOnScreenNotifier2D trigger, which could not be tested at all under
	# the headless dummy renderer -- so this whole mechanic previously shipped
	# with zero coverage despite costing the player HP.
	_expect(LoseLine.Y > 1150.0, "the lose line must sit BELOW the player, or crossing it wouldn't mean getting past them")
	_expect(LoseLine.Y < 1280.0, "the lose line must sit above the screen edge, or the player could never see it")

	# The rule working is not the same as the player being able to SEE it, and a
	# silently-missing visual is exactly the half that headless cannot notice.
	# instantiate() alone doesn't run _ready(), so this stays cheap.
	var main_inst := (load(MAIN_SCENE) as PackedScene).instantiate()
	var line_node := main_inst.get_node_or_null("LoseLine")
	_expect(line_node != null, "Main.tscn must contain the LoseLine node, or the death zone is invisible")
	_expect(line_node == null or line_node is LoseLine, "Main.tscn's LoseLine node must carry the LoseLine script")
	main_inst.free()

	var spawner := EnemySpawner.new()
	spawner.name = "EnemySpawner"
	add_child(spawner)
	var pool := EnemyPool.new()
	add_child(pool)
	var player: Player = load("res://scenes/player/Player.tscn").instantiate()
	add_child(player)
	player.global_position = Vector2(360.0, 1150.0)
	player.get_node("BasicShotTimer").stop()  # no projectile pool here; see the contact test
	await get_tree().physics_frame

	var data: EnemyData = load("res://resources/enemies/slime_scout.tres")

	# An enemy that has NOT reached the line is untouched and costs nothing.
	var safe: EnemyBase = spawner.spawn(data, 1.0, 1.0, 1.0, -1, 1.0, 100.0, false)
	safe.global_position = Vector2(100.0, LoseLine.Y - 240.0)
	player.current_hp = player.max_hp
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect(not safe._is_dying, "an enemy above the line must not leak")
	_expect(is_equal_approx(player.current_hp, player.max_hp), "an enemy above the line must not cost HP")
	safe._deactivate()
	safe.queue_free()
	await get_tree().physics_frame

	# One that walks across it costs exactly 1 HP and is removed from the run.
	var leaker: EnemyBase = spawner.spawn(data, 1.0, 1.0, 1.0, -1, 1.0, 100.0, false)
	leaker.global_position = Vector2(100.0, LoseLine.Y - 6.0)
	player.current_hp = player.max_hp
	var hp_before: float = player.current_hp
	var frames := 0
	while frames < 90 and not leaker._is_dying:
		await get_tree().physics_frame
		frames += 1
	_expect(leaker._is_dying, "an enemy crossing the lose line must be taken out of the run")
	_expect(is_equal_approx(hp_before - player.current_hp, Player.HIT_COST),
		"crossing the lose line must cost exactly %s HP, got %s" % [Player.HIT_COST, hp_before - player.current_hp])
	_expect(not leaker.is_in_group("enemy"), "a leaked enemy must leave the 'enemy' group")

	# The check runs every physics frame, so an enemy sitting past the line must
	# not keep billing the player -- the single most likely way this regresses.
	var hp_after_leak: float = player.current_hp
	for i in 20:
		await get_tree().physics_frame
	_expect(is_equal_approx(player.current_hp, hp_after_leak),
		"crossing the line must cost HP once, not once per frame (lost %s more)" % (hp_after_leak - player.current_hp))

	player.queue_free()
	spawner.queue_free()
	pool.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


const CONTACT_DAMAGE_SPECIES := [
	"armored_brute", "armored_gargoyle", "bat_swarm", "cursed_wraith",
	"goblin_runner", "sapling", "shield_skeleton", "skeleton_soldier",
	"slime_scout", "stinger_wasp", "stone_golem", "wolf_beast",
]


func _assert_every_monster_hurts_on_contact() -> void:
	# (2026-07-24) User report: "sometimes character hp not reduce when hit by
	# flying monster". A probe run of all 12 species head-on into a real player
	# found exactly one that dealt nothing: the Cursed Wraith -- the only
	# RangedAttack species (and a flier), which inherited AttackBehavior's
	# do-nothing on_contact() and so flew straight through the player for free.
	# Contact damage now lives in EnemyBase itself; this walks every species into
	# the player to keep it that way, and pins the flat one-HP-per-hit rule.
	var player: Player = load("res://scenes/player/Player.tscn").instantiate()
	add_child(player)
	player.global_position = Vector2(360.0, 1150.0)
	# No Main.tscn here means no projectile pool, and the player's auto-fire
	# would spam "acquire on a null instance" through the whole run -- it has
	# nothing to do with contact damage, so just don't let it shoot.
	player.get_node("BasicShotTimer").stop()
	await get_tree().physics_frame

	for id in CONTACT_DAMAGE_SPECIES:
		var data: EnemyData = load("res://resources/enemies/%s.tres" % id)
		var enemy: EnemyBase = data.scene.instantiate()
		enemy.setup(data, 1.0, 1.0, 1.0, -1)
		add_child(enemy)
		# Just outside the hurtbox's reach, straight overhead, then (re)arm the
		# movement behavior from HERE so dive species actually aim at the player.
		enemy.global_position = player.global_position + Vector2(0, -90)
		enemy.activate()
		if data.movement_behavior:
			data.movement_behavior.on_ready(enemy)
		enemy._base_velocity = enemy.velocity

		player.current_hp = player.max_hp
		var hp_before: float = player.current_hp
		var frames := 0
		var by_contact := false
		while frames < 200 and is_instance_valid(enemy) and player.current_hp == hp_before:
			await get_tree().physics_frame
			frames += 1
			if enemy._player_in_contact != null:
				by_contact = true
		var dealt: float = hp_before - player.current_hp
		_expect(dealt > 0.0, "%s must damage the player on contact (dealt nothing in %d frames)" % [id, frames])
		# (2026-07-24) Crossing the lose line also costs exactly one HP, so a
		# species that slipped PAST the player without touching them would satisfy
		# the checks above while proving nothing about contact. Requiring the
		# hurtbox to have actually latched keeps the two paths distinguishable --
		# the reason the old test had to disable the leak trigger outright.
		_expect(by_contact, "%s's damage must come from contact, not from crossing the lose line" % id)
		_expect(is_equal_approx(dealt, Player.HIT_COST),
			"%s should cost exactly %s HP per hit regardless of its base_damage (%s), got %s" % [
				id, Player.HIT_COST, data.base_damage, dealt,
			])
		enemy._deactivate()
		enemy.queue_free()
		await get_tree().physics_frame

	# The flat cost covers every ordinary source regardless of its own number:
	# a wave-scaled elite hit is worth the same single HP as a nibble.
	player.current_hp = player.max_hp
	player.take_damage(999.0)
	_expect(is_equal_approx(player.current_hp, player.max_hp - Player.HIT_COST),
		"a huge incoming amount must still cost exactly one HP")

	# Bosses are the deliberate exception -- their attacks stay weighted, so a
	# Leap Smash is worth more than a bat nibble (user decision, 2026-07-24).
	player.current_hp = player.max_hp
	player.take_boss_damage(3.0)
	_expect(is_equal_approx(player.current_hp, player.max_hp - 3.0),
		"boss damage must keep its own weight, not collapse to HIT_COST")

	# Enemy/boss ARROWS reach the player through Projectile, not through a
	# direct call -- a separate path that has to work on its own.
	player.current_hp = player.max_hp
	await _fire_bolt_at(player, 4.0, false)
	_expect(is_equal_approx(player.current_hp, player.max_hp - Player.HIT_COST),
		"an enemy arrow must cost exactly one HP (it landed for %s)" % (player.max_hp - player.current_hp))

	player.current_hp = player.max_hp
	await _fire_bolt_at(player, 4.0, true)
	_expect(is_equal_approx(player.current_hp, player.max_hp - 4.0),
		"a boss arrow must keep its weight (it landed for %s)" % (player.max_hp - player.current_hp))

	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _fire_bolt_at(player: Player, dmg: float, weighted: bool) -> void:
	# Drops a live bolt just above the player aimed straight down, exactly as
	# RangedAttack / BossBase._rapid_volley() do, and lets it fly into them.
	var bolt: Projectile = load("res://scenes/effects/CursedBolt.tscn").instantiate()
	add_child(bolt)
	bolt.activate(Vector2.DOWN, 400.0, dmg, player.global_position + Vector2(0, -70), 0, "player",
		600.0, [], 0.0, 0, 1.0, "", null, Color(0, 0, 0, 0), 0.0, weighted)
	var frames := 0
	while frames < 60 and is_instance_valid(bolt) and bolt._active:
		await get_tree().physics_frame
		frames += 1
	if is_instance_valid(bolt):
		bolt.queue_free()
	await get_tree().physics_frame


# (2026-07-24) Player damage is a flat Player.HIT_COST per hit now, so a single
# take_damage(99999.0) no longer kills -- these tests care about the death/revive
# path, not about how many hits it took to get there.
func _drain_hp(player: Player) -> void:
	var guard := 0
	while player.current_hp > 0.0 and guard < 1000:
		player.take_damage(1.0)
		guard += 1
	_expect(guard < 1000, "_drain_hp should reach 0 HP well inside its guard")


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
	_expect(player.continues_used == 0, "a fresh run starts with 0 continues used")

	# 1st death -> offers the free continue, no final death yet.
	_drain_hp(player)
	_expect(downed_events.size() == 1 and downed_events[0] == 0, "1st death should offer the free (index 0) continue")
	_expect(final_deaths.is_empty(), "no game over while a continue is still available")
	_expect(player.is_dead, "player is down until revived")

	player.revive()
	_expect(not player.is_dead and player.continues_used == 1, "revive clears death + spends a continue")
	_expect(is_equal_approx(player.current_hp, player.max_hp), "revive restores full HP")
	player._revive_invuln = false  # skip the i-frame window so the next hit lands

	# 2nd death -> offers the paid continue.
	_drain_hp(player)
	_expect(downed_events.size() == 2 and downed_events[1] == 1, "2nd death should offer the paid (index 1) continue")
	_expect(final_deaths.is_empty(), "still no game over on the 2nd down")
	player.revive()
	_expect(player.continues_used == 2, "2nd revive brings continues used to the max")
	player._revive_invuln = false

	# 3rd death -> the real game over (no more continue offers).
	_drain_hp(player)
	_expect(downed_events.size() == 2, "no 3rd continue offer past the max")
	_expect(final_deaths.size() == 1, "the 3rd death is the real game over (player_died fires)")

	# Essence sink used by the paid continue.
	var before: int = SaveManager.essence
	SaveManager.add_essence(100)
	_expect(SaveManager.spend_essence(30), "spend should succeed when affordable")
	_expect(SaveManager.essence == before + 70, "spend should deduct exactly")
	_expect(not SaveManager.spend_essence(999999), "spend should refuse (and not deduct) when unaffordable")
	_expect(SaveManager.essence == before + 70, "a refused spend must not change essence")

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
		_expect(offer.size() == 1, "class tree should offer exactly 1 card, got %d" % offer.size())
		_expect(offer[0].id == "class_sniper_t1", "a sniper must only ever see sniper class cards, got %s" % offer[0].id)

	# Tier climb through the real apply path.
	player.apply_element_upgrade(load("res://resources/upgrades/class_sniper_t1.tres"))
	_expect(player.class_skill_level == 1 and player._current_class_skill.id == "class_power_shot")
	_expect(not player.class_skill_timer.is_stopped(), "class skill timer should start on the tier-1 pick")
	player.apply_element_upgrade(load("res://resources/upgrades/class_sniper_t2.tres"))
	player.apply_element_upgrade(load("res://resources/upgrades/class_sniper_t3.tres"))
	_expect(player.class_skill_level == 3 and player._current_class_skill.id == "class_railshot", "tier picks should swap the class skill wholesale")
	_expect(popup._get_offerable_upgrades(UpgradeResource.ElementType.CLASS).is_empty(), "a maxed class tree (no repeatables) should offer nothing")

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
	_expect(jugg._current_class_skill.id == "class_second_wind")

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
	_expect(jugg._fire_self_burst(jugg._current_class_skill), "pulse should fire with an enemy in range")
	_expect(enemy.current_hp < enemy_hp, "pulse should damage enemies in range")
	_expect(is_equal_approx(jugg.current_hp, hp_after_hit + 1.0), "Second Wind should heal 1 HP per successful cast")

	enemy.global_position = jugg.global_position + Vector2(0, -2000)  # far outside
	var hp_before_idle: float = jugg.current_hp
	_expect(not jugg._fire_self_burst(jugg._current_class_skill), "pulse must refuse to fire with nothing in range")
	_expect(jugg.current_hp == hp_before_idle, "no free Second Wind healing while idle")

	enemy.queue_free()
	jugg.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
