extends Node2D
## Headless smoke test — run: godot --headless --path . res://scenes/test/SystemsSmokeTest.tscn

const MAIN_SCENE := "res://scenes/main/Main.tscn"


func _ready() -> void:
	_assert_autoloads()
	_assert_skill_resources()
	_assert_save_roundtrip()
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
	_assert_player_movement_clamping()
	_assert_trap_zone_activation()


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
