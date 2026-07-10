extends Area2D
class_name TrapZone

const ARM_DELAY := 0.25
const HIT_COOLDOWN := 0.45

@onready var visual: Polygon2D = $Visual
@onready var collision: CollisionShape2D = $CollisionShape2D

var damage := 10.0
var duration := 3.0
var radius := 55.0
var _armed := false
var _hit_cooldowns: Dictionary = {}


func activate(p_damage: float, p_duration: float, p_radius: float, p_position: Vector2) -> void:
	damage = p_damage
	duration = p_duration
	radius = p_radius
	global_position = p_position
	monitoring = false


func _ready() -> void:
	visual.polygon = _circle_polygon(radius)
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


func _circle_polygon(r: float, segments: int = 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var angle := TAU * i / segments
		pts.append(Vector2(cos(angle), sin(angle)) * r)
	return pts
