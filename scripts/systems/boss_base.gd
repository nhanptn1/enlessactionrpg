extends CharacterBody2D
class_name BossBase

# Not an EnemyBase: a phase/telegraph attack pattern is a different shape than
# EnemyBase's "walk down, contact-damage on overlap" loop. This keeps its own
# take_damage()/_die() (emitting the same `died` signal EnemyBase does, so
# WaveManager handles both uniformly) but owns movement/attack logic outright.

const HIT_FLASH_DURATION := 0.08
const HIT_PUNCH_SCALE := 1.06
const DEATH_FADE_DURATION := 0.4

const ATTACK_DATA := {
	"root_slam": {
		"damage": 12.0, "telegraph_time": 0.9, "cooldown": 2.0,
		"shape": "player_circle", "radius": 36.0, "color": Color(0.55, 0.35, 0.15, 0.5),
	},
	"vine_whip": {
		"damage": 14.0, "telegraph_time": 0.9, "cooldown": 2.2,
		"shape": "reach_line", "width": 20.0, "color": Color(0.25, 0.55, 0.2, 0.5),
	},
	"poison_burst": {
		"damage": 18.0, "telegraph_time": 1.1, "cooldown": 2.4,
		"shape": "self_circle", "radius": 100.0, "color": Color(0.5, 0.15, 0.55, 0.5),
	},
}
const PHASE_1_ATTACKS: Array[String] = ["root_slam", "vine_whip"]
const PHASE_2_ATTACKS: Array[String] = ["poison_burst", "summon_saplings"]
const PHASE2_HP_RATIO := 0.5
const SUMMON_COOLDOWN := 5.0
const SAPLING_COUNT := 3
const INITIAL_ATTACK_DELAY := 1.5

@export var engage_y: float = 400.0
@export var sapling_data: EnemyData

@onready var sprite: AnimatedSprite2D = $Sprite

signal died(xp_reward: int, drop_chance: float, death_position: Vector2)

var data: EnemyData
var current_hp: float
var _max_hp: float
var current_phase := 1
var _engaged := false
var _hp_mult := 1.0
var _speed_mult := 1.0
var _damage_mult := 1.0
var _xp_override := -1
var _attack_loop_running := false
var _base_modulate: Color
var _base_scale: Vector2
var _hit_tween: Tween
var _is_dying := false


func setup(enemy_data: EnemyData, hp_mult: float = 1.0, speed_mult: float = 1.0, damage_mult: float = 1.0, xp_override: int = -1) -> void:
	data = enemy_data  # caller MUST call this before add_child()
	_hp_mult = hp_mult
	_speed_mult = speed_mult
	_damage_mult = damage_mult
	_xp_override = xp_override


func _ready() -> void:
	add_to_group("enemy")
	_max_hp = data.base_hp * _hp_mult
	current_hp = _max_hp
	velocity = Vector2(0, data.base_speed * _speed_mult)
	_base_modulate = sprite.modulate
	_base_scale = sprite.scale
	sprite.play("move")
	_attack_loop_running = true
	_run_attack_loop()


func _physics_process(_delta: float) -> void:
	if _engaged:
		return
	move_and_slide()
	if global_position.y >= engage_y:
		global_position.y = engage_y
		velocity = Vector2.ZERO
		_engaged = true


func take_damage(amount: float) -> void:
	if _is_dying:
		return
	current_hp -= amount
	SignalBus.enemy_hit.emit()
	if current_hp <= 0.0:
		_die()
		return
	_play_hit_reaction()
	if current_phase == 1 and current_hp <= _max_hp * PHASE2_HP_RATIO:
		current_phase = 2
		SignalBus.boss_phase_changed.emit(current_phase)
		var cam := get_viewport().get_camera_2d()
		if is_instance_valid(cam) and cam.has_method("shake"):
			cam.shake(14.0, 0.3)


func _play_hit_reaction() -> void:
	if _hit_tween:
		_hit_tween.kill()
	sprite.scale = _base_scale
	sprite.modulate = Color(2.5, 2.5, 2.5, 1.0)
	_hit_tween = create_tween()
	_hit_tween.set_parallel(true)
	_hit_tween.tween_property(sprite, "modulate", _base_modulate, HIT_FLASH_DURATION)
	_hit_tween.tween_property(sprite, "scale", _base_scale * HIT_PUNCH_SCALE, HIT_FLASH_DURATION * 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hit_tween.chain().tween_property(sprite, "scale", _base_scale, HIT_FLASH_DURATION * 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _die() -> void:
	if _is_dying:
		return
	_is_dying = true
	_attack_loop_running = false
	var xp_reward: int = _xp_override if _xp_override >= 0 else data.xp_reward
	died.emit(xp_reward, data.drop_chance, global_position)
	SignalBus.enemy_died.emit()
	set_physics_process(false)
	var death_tween := create_tween()
	death_tween.set_parallel(true)
	death_tween.tween_property(sprite, "scale", Vector2.ZERO, DEATH_FADE_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	death_tween.tween_property(sprite, "modulate:a", 0.0, DEATH_FADE_DURATION)
	death_tween.chain().tween_callback(queue_free)


func _run_attack_loop() -> void:
	# process_always=false on every timer in this loop -- without it, Godot's
	# default (true) keeps these counting down in real time even while
	# get_tree().paused is set by the Pause Menu, so the boss would keep
	# telegraphing and landing hits on a "paused" screen.
	await get_tree().create_timer(INITIAL_ATTACK_DELAY, false).timeout
	while _attack_loop_running and is_instance_valid(self):
		if not _engaged:
			await get_tree().create_timer(0.5, false).timeout
			continue
		var pool: Array[String] = PHASE_1_ATTACKS if current_phase == 1 else PHASE_2_ATTACKS
		var attack_id: String = pool[randi() % pool.size()]
		await _execute_attack(attack_id)


func _execute_attack(attack_id: String) -> void:
	if attack_id == "summon_saplings":
		_summon_saplings()
		await get_tree().create_timer(SUMMON_COOLDOWN, false).timeout
		return
	var info: Dictionary = ATTACK_DATA[attack_id]
	SignalBus.boss_attack_telegraph.emit()
	
	var player := get_tree().get_first_node_in_group("player")
	var target_pos := Vector2.ZERO
	if is_instance_valid(player):
		target_pos = player.global_position
		
	_show_telegraph(info, target_pos)
	await get_tree().create_timer(info["telegraph_time"], false).timeout
	if not is_instance_valid(self) or not _attack_loop_running:
		return
	_apply_attack_damage(info, target_pos)
	await get_tree().create_timer(info["cooldown"], false).timeout


func _apply_attack_damage(info: Dictionary, target_pos: Vector2) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player) or not player.has_method("take_damage"):
		return
		
	var hit := false
	match info["shape"]:
		"player_circle":
			if player.global_position.distance_to(target_pos) <= info["radius"]:
				hit = true
		"self_circle":
			if player.global_position.distance_to(global_position) <= info["radius"]:
				hit = true
		"reach_line":
			var poly := _rect_polygon(global_position, target_pos, info["width"])
			if Geometry2D.is_point_in_polygon(player.global_position, poly):
				hit = true
				
	if hit:
		player.take_damage(info["damage"] * _damage_mult)


func _show_telegraph(info: Dictionary, target_pos: Vector2) -> void:
	var shape := Polygon2D.new()
	shape.color = info["color"]
	match info["shape"]:
		"player_circle":
			shape.polygon = _circle_polygon(info["radius"])
			shape.global_position = target_pos
		"self_circle":
			shape.polygon = _circle_polygon(info["radius"])
			shape.global_position = global_position
		"reach_line":
			shape.polygon = _rect_polygon(global_position, target_pos, info["width"])
	get_tree().current_scene.add_child(shape)
	var duration: float = info["telegraph_time"]
	get_tree().create_timer(duration, false).timeout.connect(func():
		if is_instance_valid(shape):
			shape.queue_free()
	)


func _summon_saplings() -> void:
	if sapling_data == null:
		return
	var wm := get_tree().get_first_node_in_group("wave_manager")
	for _i in SAPLING_COUNT:
		var enemy = sapling_data.scene.instantiate()
		enemy.setup(sapling_data)  # BEFORE add_child — _ready() reads data synchronously
		enemy._is_wave_tracked = false  # a boss add, not part of the wave's own spawn queue -- must never affect wave-clear
		enemy.global_position = global_position + Vector2(randf_range(-60.0, 60.0), 30.0 + randf_range(0.0, 20.0))
		enemy.modulate = Color(0.4, 0.8, 0.4, 1.0)
		get_tree().current_scene.add_child(enemy)
		if is_instance_valid(wm):
			enemy.died.connect(wm._on_minion_died)


func _circle_polygon(radius: float, segments: int = 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var angle := TAU * i / segments
		pts.append(Vector2(cos(angle), sin(angle)) * radius)
	return pts


func _rect_polygon(from_point: Vector2, to_point: Vector2, width: float) -> PackedVector2Array:
	var dir := (to_point - from_point).normalized()
	var normal := Vector2(-dir.y, dir.x) * (width / 2.0)
	return PackedVector2Array([from_point + normal, to_point + normal, to_point - normal, from_point - normal])
