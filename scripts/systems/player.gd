extends CharacterBody2D
class_name Player

const BASE_PROJECTILE_SPEED := 500.0
const IDLE_BOB_AMPLITUDE := 2.5
const IDLE_BOB_DURATION := 1.1
const RECOIL_OFFSET := 6.0
const RECOIL_DURATION := 0.12

const UPGRADE_POOL: Array[String] = [
	"damage", "cooldown", "projectile_count", "projectile_speed",
	"crit_chance", "hp", "shield", "xp_gain",
]

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var attack_origin: Marker2D = $AttackOrigin
@onready var basic_shot_timer: Timer = $BasicShotTimer
@onready var multishot_timer: Timer = $MultishotTimer
@onready var piercing_timer: Timer = $PiercingArrowTimer

@export var basic_shot: SkillData
@export var multishot: SkillData
@export var piercing_arrow: SkillData

var max_hp := 100.0  # was a const; now mutable since HP upgrades increase it
var current_hp := max_hp

var level := 1
var xp := 0

var damage_mult := 1.0
var cooldown_mult := 1.0
var bonus_projectile_count := 0
var projectile_speed_mult := 1.0
var crit_chance := 0.0
var shield_capacity := 0.0
var current_shield := 0.0
var xp_gain_mult := 1.0

var multishot_unlocked := false
var piercing_arrow_unlocked := false
var is_dead := false

var _sprite_base_position: Vector2
var _idle_tween: Tween
var _recoil_tween: Tween

signal hp_changed(current: float, max_hp: float)
signal xp_changed(current: int, needed: int)
signal level_up(new_level: int)
signal skill_unlocked(skill_name: String)
signal died
signal item_collected(item: ItemData)


func _ready() -> void:
	add_to_group("player")
	basic_shot_timer.wait_time = basic_shot.cooldown
	basic_shot_timer.timeout.connect(_on_basic_shot_timeout)
	multishot_timer.timeout.connect(_on_multishot_timeout)
	piercing_timer.timeout.connect(_on_piercing_timeout)
	sprite.animation_finished.connect(_on_animation_finished)
	_sprite_base_position = sprite.position
	sprite.play("idle")
	_start_idle_bob()


func xp_to_next_level() -> int:
	return 20 + 10 * (level - 1)


func gain_xp(amount: int) -> void:
	xp += roundi(amount * xp_gain_mult)
	xp_changed.emit(xp, xp_to_next_level())
	while xp >= xp_to_next_level():
		xp -= xp_to_next_level()
		level += 1
		_on_level_up(level)
	xp_changed.emit(xp, xp_to_next_level())


func _on_level_up(new_level: int) -> void:
	level_up.emit(new_level)
	if new_level == 3:
		multishot_unlocked = true
		multishot_timer.wait_time = multishot.cooldown * cooldown_mult
		multishot_timer.start()
		skill_unlocked.emit("Multishot")
	if new_level == 5:
		piercing_arrow_unlocked = true
		piercing_timer.wait_time = piercing_arrow.cooldown * cooldown_mult
		piercing_timer.start()
		skill_unlocked.emit("Piercing Arrow")
	if new_level == 8:
		# TODO: replace with a real Arrow Rain/Trap Shot skill; stubbed for now
		apply_upgrade("damage")
		apply_upgrade("damage")
		skill_unlocked.emit("Power Surge (+20% dmg)")


func apply_upgrade(upgrade_id: String) -> void:
	match upgrade_id:
		"damage":
			damage_mult += 0.10
		"cooldown":
			cooldown_mult = maxf(cooldown_mult - 0.08, 0.3)
		"projectile_count":
			bonus_projectile_count += 1
		"projectile_speed":
			projectile_speed_mult += 0.15
		"crit_chance":
			crit_chance = minf(crit_chance + 0.05, 1.0)
		"hp":
			max_hp += 20.0
			current_hp += 20.0
			hp_changed.emit(current_hp, max_hp)
		"shield":
			shield_capacity += 20.0
			current_shield = shield_capacity
		"xp_gain":
			xp_gain_mult += 0.10
	_refresh_timer_cooldowns()


func _refresh_timer_cooldowns() -> void:
	basic_shot_timer.wait_time = basic_shot.cooldown * cooldown_mult
	if multishot_unlocked:
		multishot_timer.wait_time = multishot.cooldown * cooldown_mult
	if piercing_arrow_unlocked:
		piercing_timer.wait_time = piercing_arrow.cooldown * cooldown_mult


func _on_basic_shot_timeout() -> void:
	_auto_fire(basic_shot)


func _on_multishot_timeout() -> void:
	if multishot_unlocked:
		_auto_fire(multishot)


func _on_piercing_timeout() -> void:
	if piercing_arrow_unlocked:
		_auto_fire(piercing_arrow)


func _auto_fire(skill: SkillData) -> void:
	var shot_count: int = skill.projectile_count + bonus_projectile_count
	var targets := _get_nearest_enemies(shot_count)
	if targets.is_empty():
		return
	for i in shot_count:
		var target: Node2D = targets[i % targets.size()]
		var angle_offset := 0.0
		if targets.size() < shot_count:
			angle_offset = deg_to_rad(15.0 * (i - float(shot_count - 1) / 2.0))
		_fire_at(target, skill, angle_offset)
	_stop_idle_bob()
	_play_recoil()
	sprite.play("attack")


func _start_idle_bob() -> void:
	if _idle_tween:
		_idle_tween.kill()
	sprite.position = _sprite_base_position
	_idle_tween = create_tween()
	_idle_tween.set_loops()
	_idle_tween.tween_property(sprite, "position:y", _sprite_base_position.y - IDLE_BOB_AMPLITUDE, IDLE_BOB_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_idle_tween.tween_property(sprite, "position:y", _sprite_base_position.y + IDLE_BOB_AMPLITUDE, IDLE_BOB_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _stop_idle_bob() -> void:
	if _idle_tween:
		_idle_tween.kill()
		_idle_tween = null
	sprite.position = _sprite_base_position


func _play_recoil() -> void:
	if _recoil_tween:
		_recoil_tween.kill()
	sprite.position.x = _sprite_base_position.x
	_recoil_tween = create_tween()
	_recoil_tween.tween_property(sprite, "position:x", _sprite_base_position.x - RECOIL_OFFSET, RECOIL_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_recoil_tween.tween_property(sprite, "position:x", _sprite_base_position.x, RECOIL_DURATION * 1.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _get_nearest_enemies(count: int) -> Array[Node2D]:
	var enemies: Array[Node2D] = []
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(enemy):
			enemies.append(enemy)
	enemies.sort_custom(func(a, b): return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position))
	if enemies.size() > count:
		enemies.resize(count)
	return enemies


func _fire_at(target: Node2D, skill: SkillData, angle_offset: float = 0.0) -> void:
	var proj = skill.projectile_scene.instantiate()
	var proj_speed: float = BASE_PROJECTILE_SPEED * projectile_speed_mult
	var aim_point := _predict_intercept(attack_origin.global_position, target, proj_speed)
	var dir := (aim_point - attack_origin.global_position).normalized().rotated(angle_offset)
	proj.direction = dir
	proj.damage = skill.base_damage * damage_mult * (2.0 if randf() < crit_chance else 1.0)
	proj.speed = proj_speed
	proj.pierce_count = skill.pierce_count
	proj.global_position = attack_origin.global_position
	get_tree().current_scene.add_child(proj)


func _predict_intercept(from: Vector2, target: Node2D, proj_speed: float) -> Vector2:
	# Enemies keep falling while the shot is in flight, so aiming at their
	# current position alone would systematically miss (arrows travel far
	# slower relative to fall speed than it looks at a glance). Since
	# proj_speed is much greater than any enemy's speed, a couple of
	# fixed-point passes converges to a good intercept point without a full
	# quadratic solve.
	var target_vel: Vector2 = target.velocity if "velocity" in target else Vector2.ZERO
	var predicted := target.global_position
	for _i in 4:
		var travel_time := from.distance_to(predicted) / proj_speed
		predicted = target.global_position + target_vel * travel_time
	return predicted


func _on_animation_finished() -> void:
	if sprite.animation == "attack":
		sprite.play("idle")
		_start_idle_bob()


func take_damage(amount: float) -> void:
	var remaining := amount
	if current_shield > 0.0:
		var absorbed := minf(current_shield, remaining)
		current_shield -= absorbed
		remaining -= absorbed
	current_hp = maxf(current_hp - remaining, 0.0)
	hp_changed.emit(current_hp, max_hp)
	if current_hp <= 0.0 and not is_dead:
		is_dead = true
		died.emit()


func refill_shield() -> void:
	current_shield = shield_capacity  # called by WaveManager at the start of every wave


func apply_item(item: ItemData) -> void:
	match item.effect_type:
		"stat_boost":
			for _i in item.upgrade_stacks:
				apply_upgrade(item.upgrade_id)
		"instant_heal":
			current_hp = minf(current_hp + item.effect_amount, max_hp)
			hp_changed.emit(current_hp, max_hp)
		"instant_bomb":
			for enemy in get_tree().get_nodes_in_group("enemy"):
				if is_instance_valid(enemy) and enemy.has_method("take_damage"):
					enemy.take_damage(item.effect_amount)
		"instant_xp":
			gain_xp(int(item.effect_amount))
	item_collected.emit(item)
