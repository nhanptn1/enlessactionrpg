extends CharacterBody2D
class_name BossBase

# Not an EnemyBase: a phase/telegraph attack pattern is a different shape than
# EnemyBase's "walk down, contact-damage on overlap" loop. This keeps its own
# take_damage()/_die() (calling the same player.gain_xp()/wave_manager hooks)
# but owns movement/attack logic outright.

const ITEM_PICKUP_SCENE := preload("res://scenes/effects/ItemPickup.tscn")
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
	if current_hp <= 0.0:
		_die()
		return
	_play_hit_reaction()
	if current_phase == 1 and current_hp <= _max_hp * PHASE2_HP_RATIO:
		current_phase = 2


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
	var player := get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and player.has_method("gain_xp"):
		var xp_reward: int = _xp_override if _xp_override >= 0 else data.xp_reward
		player.gain_xp(xp_reward)
	var wm := get_tree().get_first_node_in_group("wave_manager")
	if is_instance_valid(wm):
		if randf() < data.drop_chance:
			var item: ItemData = wm.roll_item_drop()
			if item != null:
				var pickup = ITEM_PICKUP_SCENE.instantiate()
				pickup.item_data = item  # BEFORE add_child — _ready() reads it synchronously
				pickup.global_position = global_position
				get_tree().current_scene.add_child(pickup)
		wm.notify_enemy_died()
	set_physics_process(false)
	var death_tween := create_tween()
	death_tween.set_parallel(true)
	death_tween.tween_property(sprite, "scale", Vector2.ZERO, DEATH_FADE_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	death_tween.tween_property(sprite, "modulate:a", 0.0, DEATH_FADE_DURATION)
	death_tween.chain().tween_callback(queue_free)


func _run_attack_loop() -> void:
	await get_tree().create_timer(INITIAL_ATTACK_DELAY).timeout
	while _attack_loop_running and is_instance_valid(self):
		if not _engaged:
			await get_tree().create_timer(0.5).timeout
			continue
		var pool: Array[String] = PHASE_1_ATTACKS if current_phase == 1 else PHASE_2_ATTACKS
		var attack_id: String = pool[randi() % pool.size()]
		await _execute_attack(attack_id)


func _execute_attack(attack_id: String) -> void:
	if attack_id == "summon_saplings":
		_summon_saplings()
		await get_tree().create_timer(SUMMON_COOLDOWN).timeout
		return
	var info: Dictionary = ATTACK_DATA[attack_id]
	_show_telegraph(info)
	await get_tree().create_timer(info["telegraph_time"]).timeout
	if not is_instance_valid(self) or not _attack_loop_running:
		return
	_apply_attack_damage(info)
	await get_tree().create_timer(info["cooldown"]).timeout


func _apply_attack_damage(info: Dictionary) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and player.has_method("take_damage"):
		player.take_damage(info["damage"] * _damage_mult)


func _show_telegraph(info: Dictionary) -> void:
	var player := get_tree().get_first_node_in_group("player")
	var shape := Polygon2D.new()
	shape.color = info["color"]
	match info["shape"]:
		"player_circle":
			shape.polygon = _circle_polygon(info["radius"])
			if is_instance_valid(player):
				shape.global_position = player.global_position
		"self_circle":
			shape.polygon = _circle_polygon(info["radius"])
			shape.global_position = global_position
		"reach_line":
			if is_instance_valid(player):
				shape.polygon = _rect_polygon(global_position, player.global_position, info["width"])
	get_tree().current_scene.add_child(shape)
	var duration: float = info["telegraph_time"]
	get_tree().create_timer(duration).timeout.connect(func():
		if is_instance_valid(shape):
			shape.queue_free()
	)


func _summon_saplings() -> void:
	if sapling_data == null:
		return
	for _i in SAPLING_COUNT:
		var enemy = sapling_data.scene.instantiate()
		enemy.setup(sapling_data)  # BEFORE add_child — _ready() reads data synchronously
		enemy.global_position = global_position + Vector2(randf_range(-60.0, 60.0), 30.0 + randf_range(0.0, 20.0))
		enemy.modulate = Color(0.4, 0.8, 0.4, 1.0)
		get_tree().current_scene.add_child(enemy)


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
