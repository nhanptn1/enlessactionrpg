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
	var proj = enemy.data.projectile_scene.instantiate()
	proj.direction = (player.global_position - enemy.global_position).normalized()
	proj.damage = enemy.data.base_damage * enemy._damage_mult
	proj.speed = enemy.data.projectile_speed
	proj.target_group = "player"
	proj.global_position = enemy.global_position
	enemy.get_tree().current_scene.add_child(proj)
	enemy._play_attack_lunge()
