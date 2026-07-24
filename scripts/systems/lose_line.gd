extends Node2D
class_name LoseLine
## The line the player is defending. An enemy that crosses it costs 1 HP and is
## removed from the run.
##
## (2026-07-24) Replaces `VisibleOnScreenNotifier2D.screen_exited` as the leak
## trigger. Two reasons, both real:
##
##   * The rule was INVISIBLE. "An enemy got past you" was a thing that silently
##     happened somewhere off the bottom of the screen; nothing on screen said
##     where the boundary was or that crossing it cost anything. Per user, it
##     should read as a death zone the player can see.
##   * The rule was UNTESTABLE and renderer-dependent. VisibleOnScreenNotifier2D
##     does not work under the headless dummy renderer (it always reports
##     off-screen), so a mechanic that costs HP had no automated coverage at all
##     -- the damage tests had to explicitly DISCONNECT it to stop it forging
##     hits they never made. Whether the player loses HP should depend on where
##     the enemy is, not on viewport/camera state.
##
## `Y` lives on the class rather than the instance so EnemyBase can consult it
## without a node lookup, and so tests can reason about it with no LoseLine in
## the scene at all.

# Player sits at y=1150 with a 32px collision radius (bottom edge ~1182) on a
# 1280-tall viewport. 1215 puts the line clearly BELOW the player -- crossing it
# means the enemy genuinely got past, not merely alongside -- while leaving ~65px
# of margin above the screen edge so the line and the crossing are both visible
# rather than happening off-screen.
const Y := 1215.0

const LINE_COLOR := Color(0.95, 0.18, 0.22, 1.0)
const GLOW_COLOR := Color(0.95, 0.18, 0.22, 0.16)
const GLOW_HEIGHT := 26.0
const LINE_WIDTH := 3.0
const DASH_LENGTH := 22.0
const DASH_GAP := 14.0
const SCROLL_SPEED := 26.0  # px/sec the dashes drift, so the line reads as live rather than painted on
const PULSE_SPEED := 2.4
const PULSE_MIN := 0.55
const PULSE_MAX := 1.0

var _time := 0.0


func _ready() -> void:
	# Behind the player and enemies (z=0) so it never draws over a sprite, but
	# above the background.
	z_index = -1


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	# Arena width from the project's own viewport setting, converted through
	# to_local, so the line spans the full field regardless of where this node
	# sits in the scene -- not dependent on it happening to be at the origin.
	var width: float = float(ProjectSettings.get_setting("display/window/size/viewport_width", 720))
	var left: Vector2 = to_local(Vector2(0.0, Y))
	var right: Vector2 = to_local(Vector2(width, Y))
	var y: float = left.y
	var x_start: float = left.x
	var x_end: float = right.x
	var pulse: float = lerpf(PULSE_MIN, PULSE_MAX, (sin(_time * PULSE_SPEED) + 1.0) * 0.5)

	# Soft band under the line -- gives the zone depth so it reads as an area
	# you don't want anything to reach, not just a hairline.
	var glow := GLOW_COLOR
	glow.a *= pulse
	draw_rect(Rect2(x_start, y, x_end - x_start, GLOW_HEIGHT), glow)

	# Marching dashes. The offset is wrapped rather than growing without bound,
	# so this stays exact however long a run lasts.
	var color := LINE_COLOR
	color.a = pulse
	var period := DASH_LENGTH + DASH_GAP
	var offset := fposmod(_time * SCROLL_SPEED, period)
	var x := x_start - period + offset
	while x < x_end:
		draw_line(
			Vector2(maxf(x, x_start), y),
			Vector2(minf(x + DASH_LENGTH, x_end), y),
			color, LINE_WIDTH,
		)
		x += period
