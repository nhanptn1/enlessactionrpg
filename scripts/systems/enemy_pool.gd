extends Node2D
class_name EnemyPool
## Same acquire/release pattern as projectile_pool.gd -- pooled instances
## stay children of this node for the whole game, toggled hidden/inactive
## (see EnemyBase.activate()/_finish_life()) instead of being freed and
## re-instantiated every spawn/death. Only regular EnemySpawner-spawned
## enemies go through this; bosses and boss-summoned minions never do.

var _available: Dictionary = {}  # PackedScene.resource_path (String) -> Array[EnemyBase]


func _ready() -> void:
	add_to_group("enemy_pool")


func acquire(scene: PackedScene) -> Node:
	var key := scene.resource_path
	var bucket: Array = _available.get(key, [])
	var enemy: Node
	if bucket.is_empty():
		enemy = scene.instantiate()
		add_child(enemy)
	else:
		enemy = bucket.pop_back()
	_available[key] = bucket
	return enemy


func release(enemy: Node) -> void:
	var key: String = enemy.data.scene.resource_path
	var bucket: Array = _available.get(key, [])
	bucket.append(enemy)
	_available[key] = bucket
