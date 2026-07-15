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

var current_hp: int = 10:
	set(v):
		if v == current_hp:
			return
		current_hp = v
		_update_label()
		queue_redraw()

@onready var label: Label = $Label


func _ready() -> void:
	_update_label()


func _update_label() -> void:
	if is_instance_valid(label):
		label.text = str(maxi(current_hp, 0))


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
