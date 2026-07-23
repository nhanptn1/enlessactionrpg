extends Node2D
class_name BossAura

# (2026-07-23) Boss presence pass. Every boss in the game reuses a REGULAR
# enemy's sprite (Fallen Knight and Dark Ranger Commander literally share the
# same skeleton frames), so the every-10-waves climax read as "a recoloured
# normal enemy". No new sprite art was available, so presence is built
# procedurally instead: a pulsing ground-glow + halo + slowly rotating rune
# ring drawn BEHIND the boss, in a per-boss colour. Same procedural-_draw()
# convention as radial_cooldown.gd / element_cycle_diagram.gd -- zero assets.
#
# Phase 2 intensifies it (see set_phase()) so the fight visibly escalates
# rather than only the HP bar changing.

const BASE_RADIUS := 74.0
const PULSE_AMOUNT := 0.10        # +/- fraction of radius
const PULSE_SPEED := 2.2          # radians/sec
const HALO_RINGS := 5             # concentric translucent rings = soft glow, no gradient texture needed
const RUNE_COUNT := 8
const RUNE_RADIUS := 5.0
const RUNE_ORBIT := 1.18          # fraction of radius the runes orbit at
const RUNE_SPIN_SPEED := 0.55     # radians/sec
const GROUND_SQUASH := 0.34       # y-scale of the ground ellipse -- sells a floor shadow, not a sphere
const PHASE_2_INTENSITY := 1.55
const PHASE_2_SPIN_BOOST := 2.1

var color: Color = Color(0.9, 0.2, 0.2, 1.0)
var intensity := 1.0
var _spin_mult := 1.0
var _t := 0.0


func _ready() -> void:
	# Behind the boss sprite. The parent is the boss body, so this inherits its
	# position automatically and needs no per-frame follow logic.
	z_index = -1


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()  # the pulse is time-based, so it has to redraw every frame


func set_phase(phase: int) -> void:
	intensity = PHASE_2_INTENSITY if phase >= 2 else 1.0
	_spin_mult = PHASE_2_SPIN_BOOST if phase >= 2 else 1.0


func _draw() -> void:
	var pulse := 1.0 + sin(_t * PULSE_SPEED) * PULSE_AMOUNT
	var radius := BASE_RADIUS * pulse

	# Ground glow: a squashed ellipse under the boss, brightest at the centre.
	# draw_circle can't squash, so scale the transform for this pass only.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, GROUND_SQUASH))
	for i in HALO_RINGS:
		var f := float(i + 1) / float(HALO_RINGS)
		var a: float = (0.16 * intensity) * (1.0 - f) + 0.03
		draw_circle(Vector2.ZERO, radius * f * 1.25, Color(color.r, color.g, color.b, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Halo: concentric rings fading outward -- reads as a glow without a texture.
	for i in HALO_RINGS:
		var f := float(i + 1) / float(HALO_RINGS)
		var a: float = (0.20 * intensity) * (1.0 - f)
		draw_arc(Vector2.ZERO, radius * f, 0.0, TAU, 36, Color(color.r, color.g, color.b, a), 2.5, true)

	# Rune ring: small orbiting dots, spinning faster in phase 2.
	var spin := _t * RUNE_SPIN_SPEED * _spin_mult
	var orbit := radius * RUNE_ORBIT
	for i in RUNE_COUNT:
		var ang := spin + TAU * float(i) / float(RUNE_COUNT)
		var p := Vector2(cos(ang), sin(ang) * GROUND_SQUASH) * orbit
		draw_circle(p, RUNE_RADIUS, Color(color.r, color.g, color.b, 0.55 * intensity))
