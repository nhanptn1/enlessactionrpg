extends Resource
class_name AttackBehavior

# Stateless by design; see movement_behavior.gd for why.

func on_ready(enemy: EnemyBase) -> void:
	pass


func on_contact(enemy: EnemyBase, body: Node) -> void:
	pass


func on_contact_tick(enemy: EnemyBase) -> void:
	pass


func on_attack_timer_timeout(enemy: EnemyBase) -> void:
	pass
