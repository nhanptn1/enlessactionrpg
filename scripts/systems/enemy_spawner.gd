extends Node2D
class_name EnemySpawner

@export var spawn_width: float = 600.0
@export var spawn_y: float = -40.0
@export var center_x: float = 360.0


func spawn(enemy_data: EnemyData, hp_mult: float = 1.0, speed_mult: float = 1.0, damage_mult: float = 1.0, xp_override: int = -1, visual_scale: float = 1.0, x_override: float = -1.0) -> Node:
	var enemy = enemy_data.scene.instantiate()
	enemy.setup(enemy_data, hp_mult, speed_mult, damage_mult, xp_override)  # BEFORE add_child — _ready() reads data synchronously
	var x: float = x_override if x_override >= 0.0 else randf_range(-spawn_width / 2.0, spawn_width / 2.0) + center_x
	enemy.global_position = Vector2(x, spawn_y)
	if visual_scale != 1.0:
		enemy.scale = Vector2(visual_scale, visual_scale)
	get_tree().current_scene.add_child(enemy)
	var wm := get_tree().get_first_node_in_group("wave_manager")
	if is_instance_valid(wm):
		enemy.died.connect(wm._on_enemy_died)
	return enemy
