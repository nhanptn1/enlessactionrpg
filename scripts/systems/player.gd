extends CharacterBody2D
class_name Player

const MAX_HP := 100.0

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var attack_origin: Marker2D = $AttackOrigin
@onready var basic_shot_timer: Timer = $BasicShotTimer

@export var basic_shot: SkillData

var current_hp := MAX_HP
var xp := 0

signal hp_changed(current: float, max_hp: float)


func _ready() -> void:
	add_to_group("player")
	basic_shot_timer.wait_time = basic_shot.cooldown
	basic_shot_timer.timeout.connect(_on_basic_shot_timeout)
	sprite.animation_finished.connect(_on_animation_finished)
	sprite.play("idle")


func _on_basic_shot_timeout() -> void:
	var target := _get_nearest_enemy()
	if target != null:
		_fire_at(target)


func _get_nearest_enemy() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist := INF
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy):
			continue
		var d := global_position.distance_squared_to(enemy.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = enemy
	return nearest


func _fire_at(target: Node2D) -> void:
	var proj = basic_shot.projectile_scene.instantiate()
	proj.direction = (target.global_position - attack_origin.global_position).normalized()
	proj.damage = basic_shot.base_damage
	proj.global_position = attack_origin.global_position
	get_tree().current_scene.add_child(proj)
	sprite.play("attack")


func _on_animation_finished() -> void:
	if sprite.animation == "attack":
		sprite.play("idle")


func take_damage(amount: float) -> void:
	current_hp = maxf(current_hp - amount, 0.0)
	hp_changed.emit(current_hp, MAX_HP)


func gain_xp(amount: int) -> void:
	xp += amount  # tracked but not spent yet — no level-up UI until MVP
