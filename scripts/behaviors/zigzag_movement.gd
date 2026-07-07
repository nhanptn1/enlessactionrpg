extends MovementBehavior
class_name ZigzagMovement


func on_ready(enemy: EnemyBase) -> void:
	enemy.velocity = Vector2(0, enemy.data.base_speed * enemy._speed_mult)


func physics_process(enemy: EnemyBase, _delta: float) -> void:
	enemy.velocity.x = sin(enemy._time_alive * enemy.data.zigzag_frequency * TAU) * enemy.data.zigzag_speed
