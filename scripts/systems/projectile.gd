extends Area2D
class_name Projectile

const DEFAULT_MAX_RANGE := 900.0

var direction := Vector2.UP
var speed := 500.0
var damage := 5.0
var pierce_count: int = 0
var target_group: String = "enemy"
var max_range := DEFAULT_MAX_RANGE
var _hits_remaining: int
var _already_hit: Array[Node] = []
var _spawn_position: Vector2
var _active := false


func _ready() -> void:
	# Connected once here, never per-activation -- pooled instances are reused
	# without _ready() running again, so re-connecting on every activate()
	# would double (or triple, ...) the signal.
	body_entered.connect(_on_body_entered)


func activate(p_direction: Vector2, p_speed: float, p_damage: float, p_position: Vector2, p_pierce_count: int, p_target_group: String, p_max_range: float = DEFAULT_MAX_RANGE) -> void:
	direction = p_direction
	speed = p_speed
	damage = p_damage
	pierce_count = p_pierce_count
	target_group = p_target_group
	max_range = p_max_range
	global_position = p_position
	rotation = direction.angle()
	_spawn_position = p_position
	_hits_remaining = pierce_count + 1  # 0 pierce = 1 total hit, matching prior behavior
	_already_hit.clear()
	_active = true
	visible = true
	set_physics_process(true)
	monitoring = true
	if has_node("Visual"):
		var visual_node = get_node("Visual")
		if visual_node is AnimatedSprite2D:
			visual_node.play()


func _physics_process(delta: float) -> void:
	if not _active:
		return
	position += direction * speed * delta
	if global_position.distance_to(_spawn_position) >= max_range:
		_deactivate()


func _on_body_entered(body: Node) -> void:
	# _active guard matters even with monitoring=false: a body_entered signal
	# from this same physics frame can still be queued for emission after
	# _deactivate() has already flipped monitoring off.
	if not _active:
		return
	if not body.is_in_group(target_group) or not body.has_method("take_damage"):
		return
	if body in _already_hit:
		return
	_already_hit.append(body)
	body.take_damage(damage)
	_hits_remaining -= 1
	if _hits_remaining <= 0:
		_deactivate()


func _deactivate() -> void:
	_active = false
	visible = false
	set_physics_process(false)
	monitoring = false
	var pool := get_tree().get_first_node_in_group("projectile_pool")
	if is_instance_valid(pool):
		pool.release(self)
	else:
		queue_free()
