extends Resource
class_name MovementBehavior

# Stateless by design: one .tres instance of a concrete subclass is shared
# across every EnemyData that references it, so all per-enemy state must
# live on the `enemy` argument (velocity, _time_alive, etc.), never here.

func on_ready(enemy: EnemyBase) -> void:
	pass


func physics_process(enemy: EnemyBase, delta: float) -> void:
	pass
