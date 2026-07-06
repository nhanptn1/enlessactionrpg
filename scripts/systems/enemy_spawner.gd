extends Node2D
class_name EnemySpawner

@export var spawn_width: float = 600.0
@export var spawn_y: float = -40.0
@export var center_x: float = 360.0


func spawn(enemy_data: EnemyData) -> void:
	var enemy = enemy_data.scene.instantiate()
	enemy.setup(enemy_data)  # BEFORE add_child — _ready() reads data synchronously
	enemy.global_position = Vector2(randf_range(-spawn_width / 2.0, spawn_width / 2.0) + center_x, spawn_y)
	get_tree().current_scene.add_child(enemy)
