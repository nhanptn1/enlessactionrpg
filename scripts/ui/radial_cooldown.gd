extends Control
class_name RadialCooldown
## A small circular cooldown ring, drawn procedurally (no texture asset needed).
## `value` 0.0 = just used (empty ring), 1.0 = ready (full ring).

@export var radius: float = 14.0
@export var ring_width: float = 4.0
@export var bg_color: Color = Color(1, 1, 1, 0.18)
@export var fill_color: Color = Color(1.0, 0.8, 0.2, 1.0)

var value: float = 1.0:
	set(v):
		var clamped := clampf(v, 0.0, 1.0)
		if clamped == value:
			return
		value = clamped
		queue_redraw()


func _draw() -> void:
	var center := size / 2.0
	draw_arc(center, radius, 0.0, TAU, 48, bg_color, ring_width, true)
	if value > 0.0:
		var start_angle := -PI / 2.0
		draw_arc(center, radius, start_angle, start_angle + TAU * value, 48, fill_color, ring_width, true)
