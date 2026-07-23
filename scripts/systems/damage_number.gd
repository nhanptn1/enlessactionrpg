extends Node2D
class_name DamageNumber

# (2026-07-23) Combat juice pass. Floating damage readouts, spawned ONLY for
# big moments (fusion combo procs, boss damage) -- deliberately NOT on every
# hit: waves run 50-100 monsters, so a number per hit would be unreadable
# confetti and a per-frame allocation storm. See spawn()'s callers.
#
# Self-freeing: drifts up, fades, frees itself. Built in code (no scene file)
# to match the other one-shot VFX in this project.

const RISE := 46.0
const DRIFT := 18.0        # slight sideways drift so stacked numbers don't overlap into a smear
const LIFETIME := 0.75
const FONT_SIZE := 26
const CRIT_FONT_SIZE := 34


static func spawn(amount: float, pos: Vector2, color: Color, host: Node, big: bool = false) -> void:
	if not is_instance_valid(host):
		return
	var n := DamageNumber.new()
	n.global_position = pos
	host.add_child(n)
	n._show(amount, color, big)


func _show(amount: float, color: Color, big: bool) -> void:
	var label := Label.new()
	label.text = str(roundi(amount))
	label.add_theme_font_size_override("font_size", CRIT_FONT_SIZE if big else FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 5)
	# Centre the text on the spawn point rather than hanging off to the right.
	label.position = Vector2(-40, -14)
	label.custom_minimum_size = Vector2(80, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	z_index = 200  # above enemies and VFX -- a readout the player must not lose

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position", position + Vector2(randf_range(-DRIFT, DRIFT), -RISE), LIFETIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, LIFETIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)
