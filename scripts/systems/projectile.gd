extends Area2D
class_name Projectile

const MAX_RANGE := 900.0

var direction := Vector2.UP
var speed := 500.0
var damage := 5.0
var pierce_count: int = 0
var target_group: String = "enemy"
var _hits_remaining: int
var _already_hit: Array[Node] = []
var _spawn_position: Vector2


func _ready() -> void:
	rotation = direction.angle()
	_spawn_position = global_position
	_hits_remaining = pierce_count + 1  # 0 pierce = 1 total hit, matching prior behavior
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	if global_position.distance_to(_spawn_position) >= MAX_RANGE:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group(target_group) or not body.has_method("take_damage"):
		return
	if body in _already_hit:
		return
	_already_hit.append(body)
	body.take_damage(damage)
	_hits_remaining -= 1
	if _hits_remaining <= 0:
		queue_free()
