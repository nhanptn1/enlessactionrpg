extends Area2D
class_name Projectile

const MAX_RANGE := 900.0

var direction := Vector2.UP
var speed := 500.0
var damage := 5.0
var _spawn_position: Vector2


func _ready() -> void:
	rotation = direction.angle()
	_spawn_position = global_position
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	if global_position.distance_to(_spawn_position) >= MAX_RANGE:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("enemy") and body.has_method("take_damage"):
		body.take_damage(damage)
		queue_free()
