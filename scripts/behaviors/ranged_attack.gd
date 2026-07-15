extends AttackBehavior
class_name RangedAttack

# (2026-07-16) Enemies spawn around y=-40 while the player sits at y=1150 --
# a freshly-spawned ranged enemy's very first shot (attack_timer starts
# immediately on_ready()) can be well over 1300px away, past
# Projectile.DEFAULT_MAX_RANGE (900). Without this override every enemy
# ranged attack that fired early expired mid-flight, silently vanishing
# before it ever reached the player -- the mirror image of the exact bug
# PLAYER_SHOT_MAX_RANGE already fixes for the player's own shots (see
# player.gd), just never applied to this side.
const ENEMY_SHOT_MAX_RANGE := 1400.0


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
	proj.activate(dir, enemy.data.projectile_speed, dmg, enemy.global_position, 0, "player", ENEMY_SHOT_MAX_RANGE)
	enemy._play_attack_lunge()
