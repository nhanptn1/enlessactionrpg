extends Control
class_name HeartHPDisplay
## Procedurally-drawn heart icon with the player's current HP as a number
## centered on top of it -- no heart art exists yet, matches this project's
## established no-art-yet fallback (radial_cooldown.gd/item_icon.gd/
## skill_icon.gd all draw their own art the same way). Sized to whatever
## rect it's given; redraw after changing current_hp.

const FILL_COLOR := Color(0.82, 0.14, 0.2, 1.0)
const OUTLINE_COLOR := Color(0.32, 0.03, 0.05, 1.0)
const EMPTY_FILL_COLOR := Color(0.3, 0.3, 0.3, 1.0)  # drawn when current_hp <= 0

# (2026-07-23) int -> float. Wave damage scaling makes enemy hits fractional
# (e.g. 1.0 base x 1.5 = 1.5), so HP legitimately sits on halves. The HUD used
# to push roundi(hp) in here, which meant a 0.5-damage hit could leave the
# displayed number completely unchanged -- the player took damage and the
# readout said otherwise (user report: "character not take hp reduce when
# hit"). Storing the real value and formatting below makes every hit visible.
var current_hp: float = 10.0:
	set(v):
		if is_equal_approx(v, current_hp):
			return
		current_hp = v
		_update_label()
		queue_redraw()

@onready var label: Label = $Label


func _ready() -> void:
	_update_label()


func _update_label() -> void:
	if not is_instance_valid(label):
		return
	var shown: float = maxf(current_hp, 0.0)
	# Whole numbers stay clean ("7"); a half only appears when HP really is
	# fractional ("7.5"), so the readout never contradicts what just happened.
	label.text = "%d" % int(shown) if is_equal_approx(shown, round(shown)) else "%.1f" % shown


func _draw() -> void:
	var w := size.x
	var h := size.y
	# Heart silhouette traced as a polygon in 0-1 normalized space, scaled to
	# the control's actual size -- two rounded lobes at the top, tapering to
	# a point at the bottom.
	var points := PackedVector2Array([
		Vector2(0.50, 0.32), Vector2(0.42, 0.16), Vector2(0.27, 0.06),
		Vector2(0.10, 0.14), Vector2(0.04, 0.32), Vector2(0.08, 0.50),
		Vector2(0.22, 0.68), Vector2(0.50, 0.94),
		Vector2(0.78, 0.68), Vector2(0.92, 0.50), Vector2(0.96, 0.32),
		Vector2(0.90, 0.14), Vector2(0.73, 0.06), Vector2(0.58, 0.16),
	])
	var scaled := PackedVector2Array()
	for p in points:
		scaled.append(Vector2(p.x * w, p.y * h))
	var fill := FILL_COLOR if current_hp > 0 else EMPTY_FILL_COLOR
	draw_colored_polygon(scaled, fill)
	for i in scaled.size():
		draw_line(scaled[i], scaled[(i + 1) % scaled.size()], OUTLINE_COLOR, 2.0, true)
