extends AttackBehavior
class_name RangedAttack


func on_ready(enemy: EnemyBase) -> void:
	enemy.attack_timer.wait_time = enemy.data.attack_interval
	enemy.attack_timer.timeout.connect(enemy._on_attack_timer_timeout)
	enemy.attack_timer.start()


func on_attack_timer_timeout(enemy: EnemyBase) -> void:
	var player := enemy.get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player) or enemy.data.projectile_scene == null:
		return
	var pool := enemy.get_tree().get_first_node_in_group("projectile_pool")
	var dir = (player.global_position - enemy.global_position).normalized()
	var dmg := enemy.data.base_damage * enemy._damage_mult
	var proj = pool.acquire(enemy.data.projectile_scene)
	proj.activate(dir, enemy.data.projectile_speed, dmg, enemy.global_position, 0, "player")
	enemy._play_attack_lunge()
