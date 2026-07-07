extends Node2D
class_name ProjectilePool

var _available: Dictionary = {}  # PackedScene.resource_path (String) -> Array[Node]


func _ready() -> void:
	add_to_group("projectile_pool")


func acquire(scene: PackedScene) -> Node:
	var key := scene.resource_path
	var bucket: Array = _available.get(key, [])
	var proj: Node
	if bucket.is_empty():
		proj = scene.instantiate()
		add_child(proj)
	else:
		proj = bucket.pop_back()
	proj.set_meta("pool_scene_path", key)
	_available[key] = bucket
	return proj


func release(proj: Node) -> void:
	var key: String = proj.get_meta("pool_scene_path", "")
	var bucket: Array = _available.get(key, [])
	bucket.append(proj)
	_available[key] = bucket
