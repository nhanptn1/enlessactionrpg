extends CharacterBody2D
class_name Player

const BASE_PROJECTILE_SPEED := 500.0

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

signal hp_changed(current: float, max_hp: float)
signal xp_changed(current: int, needed: int)
signal level_up(new_level: int)
signal skill_unlocked(skill_name: String)


func _ready() -> void:
	add_to_group("player")
	basic_shot_timer.wait_time = basic_shot.cooldown
	basic_shot_timer.timeout.connect(_on_basic_shot_timeout)
	multishot_timer.timeout.connect(_on_multishot_timeout)
	piercing_timer.timeout.connect(_on_piercing_timeout)
	sprite.animation_finished.connect(_on_animation_finished)
	sprite.play("idle")


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
	sprite.play("attack")


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
	var dir := (target.global_position - attack_origin.global_position).normalized().rotated(angle_offset)
	proj.direction = dir
	proj.damage = skill.base_damage * damage_mult * (2.0 if randf() < crit_chance else 1.0)
	proj.speed = BASE_PROJECTILE_SPEED * projectile_speed_mult
	proj.pierce_count = skill.pierce_count
	proj.global_position = attack_origin.global_position
	get_tree().current_scene.add_child(proj)


func _on_animation_finished() -> void:
	if sprite.animation == "attack":
		sprite.play("idle")


func take_damage(amount: float) -> void:
	var remaining := amount
	if current_shield > 0.0:
		var absorbed := minf(current_shield, remaining)
		current_shield -= absorbed
		remaining -= absorbed
	current_hp = maxf(current_hp - remaining, 0.0)
	hp_changed.emit(current_hp, max_hp)


func refill_shield() -> void:
	current_shield = shield_capacity  # called by WaveManager at the start of every wave
