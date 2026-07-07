extends MovementBehavior
class_name StraightMovement


func on_ready(enemy: EnemyBase) -> void:
	enemy.velocity = Vector2(0, enemy.data.base_speed * enemy._speed_mult)
