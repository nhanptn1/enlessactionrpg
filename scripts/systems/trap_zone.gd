extends Area2D
class_name TrapZone

const ARM_DELAY := 0.25
const HIT_COOLDOWN := 0.45
const VISUAL_DIAMETER_MULT := 2.4  # radius-to-sprite-width ratio, matches ImpactVFX's own burst-scaling convention
const TRIGGER_FLASH_DURATION := 0.15

const TRIGGERED_TEXTURE := preload("res://art/vfx/trap_triggered.png")
const PLANTED_TEXTURE := preload("res://art/vfx/trap_planted.png")

@onready var visual: Sprite2D = $Visual
@onready var collision: CollisionShape2D = $CollisionShape2D

var damage := 10.0
var duration := 3.0
var radius := 55.0
var status_rolls: Array[Dictionary] = []  # {element, chance, duration} rolled once per shot by the shooter
var _armed := false
var _hit_cooldowns: Dictionary = {}
var _flash_tween: Tween


func activate(p_damage: float, p_duration: float, p_radius: float, p_position: Vector2, p_status_rolls: Array[Dictionary] = []) -> void:
	damage = p_damage
	duration = p_duration
	radius = p_radius
	status_rolls = p_status_rolls
	global_position = p_position
	monitoring = false


func _ready() -> void:
	visual.scale = Vector2.ONE * (radius * VISUAL_DIAMETER_MULT) / visual.texture.get_width()
	var shape := CircleShape2D.new()
	shape.radius = radius
	collision.shape = shape
	_arm_after_delay()


func _arm_after_delay() -> void:
	# process_always=false: without it these keep ticking in real time even
	# while paused, matching the same fix applied to boss_base.gd's timers.
	await get_tree().create_timer(ARM_DELAY, false).timeout
	if not is_instance_valid(self):
		return
	monitoring = true
	_armed = true
	await get_tree().create_timer(duration, false).timeout
	if is_instance_valid(self):
		queue_free()


func _on_body_entered(body: Node) -> void:
	if not _armed or not body.is_in_group("enemy"):
		return
	if not body.has_method("take_damage"):
		return
	var body_id: int = body.get_instance_id()
	var now := Time.get_ticks_msec()
	if _hit_cooldowns.has(body_id) and now - _hit_cooldowns[body_id] < int(HIT_COOLDOWN * 1000.0):
		return
	_hit_cooldowns[body_id] = now
	body.take_damage(damage)
	if body.has_method("apply_status"):
		for roll in status_rolls:
			if randf() < roll["chance"]:
				body.apply_status(roll["element"], roll["duration"])
	_play_trigger_flash()


func _play_trigger_flash() -> void:
	# Briefly swaps to the sparking/triggered art on every hit, matching
	# EnemyBase._play_hit_reaction()'s kill-and-restart convention so
	# overlapping hits (multiple enemies in the same frame) don't fight an
	# in-progress flash.
	if _flash_tween:
		_flash_tween.kill()
	visual.texture = TRIGGERED_TEXTURE
	_flash_tween = create_tween()
	_flash_tween.tween_interval(TRIGGER_FLASH_DURATION)
	_flash_tween.tween_callback(func(): visual.texture = PLANTED_TEXTURE)
