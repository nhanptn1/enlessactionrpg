extends Node2D
class_name PlayerAura

# (2026-07-23) Unit identity pass. The player's class was communicated ONLY by
# a sprite tint, which is invisible mid-fight against a busy background and
# used the exact same visual idea as elite enemies. This adds a soft ground
# glow in the class colour under the player -- deliberately the calmest of the
# three shape languages (boss = orbiting runes, elite = angular spikes,
# player = a soft pool of light), so the three never read as the same thing.
# Procedural, no new art.

const RADIUS := 34.0
const SQUASH := 0.30        # flattened into a floor pool rather than a sphere
const RINGS := 4
const PULSE_SPEED := 1.7    # slower than elite/boss -- calm, not threatening
const PULSE_AMOUNT := 0.08
const Y_OFFSET := 26.0      # sits at the feet, not the chest
const BASE_ALPHA := 0.20

var color: Color = Color(1, 1, 1, 1)
var _t := 0.0


func _ready() -> void:
	z_index = -1  # under the player sprite
	position.y = Y_OFFSET


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var pulse := 1.0 + sin(_t * PULSE_SPEED) * PULSE_AMOUNT
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, SQUASH))
	for i in RINGS:
		var f := float(i + 1) / float(RINGS)
		var a := BASE_ALPHA * (1.0 - f) + 0.04
		draw_circle(Vector2.ZERO, RADIUS * pulse * f, Color(color.r, color.g, color.b, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
