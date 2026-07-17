extends Node2D
class_name EnemySpawner

# Gold glow + a slight size bump, applied on top of whatever visual_scale the
# spawn already asked for -- distinguishes an elite roll from a same-species
# normal enemy at a glance, per the art bible's "use color accents to show
# elite status" rule. No new sprite art needed.
const ELITE_TINT := Color(1.6, 1.3, 0.4, 1.0)
const ELITE_SCALE_BONUS := 1.2

@export var spawn_width: float = 600.0
@export var spawn_y: float = -40.0
@export var center_x: float = 360.0


func spawn(enemy_data: EnemyData, hp_mult: float = 1.0, speed_mult: float = 1.0, damage_mult: float = 1.0, xp_override: int = -1, visual_scale: float = 1.0, x_override: float = -1.0, is_elite: bool = false, is_boss: bool = false, mutation_id: String = "") -> Node:
	# (2026-07-17) Regular monsters (is_boss=false) go through EnemyPool when
	# one exists in the scene -- pooled instances are reused across many
	# lives (EnemyBase.activate()/_finish_life()) instead of instantiate/
	# queue_free() every spawn/death, for Phase 2 pillar 6's bigger wave
	# counts. Bosses opt out entirely (never pooled, never call activate() --
	# BossBase doesn't implement it) and keep the exact original
	# setup-before-add_child flow.
	var pool := null if is_boss else get_tree().get_first_node_in_group("enemy_pool")
	var enemy: Node
	if is_instance_valid(pool):
		enemy = pool.acquire(enemy_data.scene)
		enemy._pooled = true
		enemy.setup(enemy_data, hp_mult, speed_mult, damage_mult, xp_override)
	else:
		enemy = enemy_data.scene.instantiate()
		if is_boss:
			enemy.mutation_id = mutation_id  # before setup()/add_child() -- BossBase._ready() reads it synchronously, see _apply_mutation()
		enemy.setup(enemy_data, hp_mult, speed_mult, damage_mult, xp_override)  # BEFORE add_child — _ready() reads data synchronously
		get_tree().current_scene.add_child(enemy)
	var x: float = x_override if x_override >= 0.0 else randf_range(-spawn_width / 2.0, spawn_width / 2.0) + center_x
	enemy.global_position = Vector2(x, spawn_y)
	var final_scale := visual_scale * (ELITE_SCALE_BONUS if is_elite else 1.0)
	enemy.scale = Vector2(final_scale, final_scale)
	if is_elite:
		enemy.modulate = ELITE_TINT
		SignalBus.elite_spawned.emit()
	elif not is_boss:
		# (2026-07-17) A reused pooled instance may still carry a previous
		# life's elite tint -- must be reset explicitly every spawn, not just
		# "if elite". Restoring the species' own authored tint (captured once
		# in EnemyBase._ready(), e.g. Shield Skeleton's blue/Stone Golem's
		# orange/Armored Brute's red) instead of a hardcoded Color.WHITE --
		# the latter silently erased every species' intentional art tint on
		# every non-elite spawn (the vast majority of spawns).
		enemy.modulate = enemy._base_root_modulate
	if not is_boss:
		enemy.activate()
	var wm := get_tree().get_first_node_in_group("wave_manager")
	if is_instance_valid(wm):
		enemy.died.connect(wm._on_enemy_died.bind(is_boss))
	return enemy
