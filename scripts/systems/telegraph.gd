extends RefCounted
class_name Telegraph
## Shared "warning circle that fades away after a delay" visual -- factored
## out so Player's area-strike skills (Arrow Rain, Burning Rain, Thunder
## Storm) can reuse the exact telegraph pattern boss_base.gd's own
## _show_circle_telegraph() already established, rather than reinventing it.

static func show_circle(pos: Vector2, radius: float, color: Color, duration: float, host: Node) -> void:
	if not is_instance_valid(host):
		return
	var shape := Polygon2D.new()
	shape.color = color
	shape.polygon = _circle_polygon(radius)
	shape.global_position = pos
	host.get_tree().current_scene.add_child(shape)
	host.get_tree().create_timer(duration, false).timeout.connect(func():
		if is_instance_valid(shape):
			shape.queue_free()
	)


static func _circle_polygon(radius: float, segments: int = 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var angle := TAU * i / segments
		pts.append(Vector2(cos(angle), sin(angle)) * radius)
	return pts
