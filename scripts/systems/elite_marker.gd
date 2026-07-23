extends Node2D
class_name EliteMarker

# (2026-07-23) Unit identity pass. Elites, classes and bosses were ALL
# expressed as "modulate tint + scale", so none of them read as a distinct
# kind of thing -- a gold-tinted elite and a dark-tinted boss were the same
# visual idea at different sizes. Each now gets its own shape language:
#   boss   -> BossAura: big halo + orbiting runes (elaborate, ominous)
#   elite  -> this: angular spikes + a tight ring (aggressive, sharp)
#   player -> PlayerAura: a soft ground glow (supportive, calm)
# Procedural, no new art. The existing gold ELITE_TINT stays on top of this.

const RING_RADIUS := 30.0
const SPIKE_COUNT := 6
const SPIKE_LEN := 9.0
const SPIKE_WIDTH := 0.34   # radians of arc each spike spans at its base
const PULSE_SPEED := 3.4
const PULSE_AMOUNT := 0.12
const SPIN_SPEED := -0.9    # counter-rotates vs the boss aura, so the two never read alike
const COLOR := Color(1.0, 0.82, 0.25, 1.0)

var _t := 0.0


func _ready() -> void:
	z_index = -1  # behind the enemy sprite


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var pulse := 1.0 + sin(_t * PULSE_SPEED) * PULSE_AMOUNT
	var r := RING_RADIUS * pulse
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 28, Color(COLOR.r, COLOR.g, COLOR.b, 0.5), 2.0, true)
	# Angular spikes -- drawn as thin triangles pointing outward from the ring.
	var spin := _t * SPIN_SPEED
	for i in SPIKE_COUNT:
		var ang := spin + TAU * float(i) / float(SPIKE_COUNT)
		var tip := Vector2(cos(ang), sin(ang)) * (r + SPIKE_LEN)
		var a := Vector2(cos(ang - SPIKE_WIDTH), sin(ang - SPIKE_WIDTH)) * r
		var b := Vector2(cos(ang + SPIKE_WIDTH), sin(ang + SPIKE_WIDTH)) * r
		draw_colored_polygon(PackedVector2Array([tip, a, b]), Color(COLOR.r, COLOR.g, COLOR.b, 0.62))
