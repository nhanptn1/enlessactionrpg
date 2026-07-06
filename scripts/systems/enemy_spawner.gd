extends Node2D
class_name EnemySpawner

@export var spawn_width: float = 600.0
@export var spawn_y: float = -40.0
@export var center_x: float = 360.0


func spawn(enemy_data: EnemyData, hp_mult: float = 1.0, speed_mult: float = 1.0, damage_mult: float = 1.0, xp_override: int = -1, visual_scale: float = 1.0) -> void:
	var enemy = enemy_data.scene.instantiate()
	enemy.setup(enemy_data, hp_mult, speed_mult, damage_mult, xp_override)  # BEFORE add_child — _ready() reads data synchronously
	enemy.global_position = Vector2(randf_range(-spawn_width / 2.0, spawn_width / 2.0) + center_x, spawn_y)
	if visual_scale != 1.0:
		enemy.scale = Vector2(visual_scale, visual_scale)
	get_tree().current_scene.add_child(enemy)
