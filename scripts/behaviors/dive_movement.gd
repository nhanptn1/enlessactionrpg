extends MovementBehavior
class_name DiveMovement

# Locks a straight-line velocity toward wherever the player is at the exact
# moment this enemy spawns -- NOT a homing missile. physics_process() is
# deliberately left as the inherited no-op; do not add a per-frame update
# here, that would change gameplay behavior beyond this refactor's scope.


func on_ready(enemy: EnemyBase) -> void:
	var player := enemy.get_tree().get_first_node_in_group("player")
	if is_instance_valid(player):
		enemy.velocity = (player.global_position - enemy.global_position).normalized() * enemy.data.base_speed * enemy._speed_mult
	else:
		enemy.velocity = Vector2(0, enemy.data.base_speed * enemy._speed_mult)
