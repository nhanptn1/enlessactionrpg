extends Node2D
class_name DangerIndicator

# Gives the player something to actually read before an enemy reaches them --
# previously the only cue was the enemy sprite itself, easy to lose track of
# against the background. Draws a growing/brightening marker at each nearby
# enemy's current x, along a line above the player, as it closes in. Bosses
# stop and use their own dedicated telegraph system (see boss_base.gd), so
# they're excluded here to avoid visual clutter.

const WARNING_RANGE := 300.0
const MARKER_Y_OFFSET := -70.0
const MIN_MARKER_SIZE := 4.0
const MAX_MARKER_SIZE := 11.0
const MIN_ALPHA := 0.15
const MAX_ALPHA := 0.85
const MARKER_COLOR := Color(1.0, 0.25, 0.2, 1.0)

var _player: Node2D


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")


func _process(_delta: float) -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	queue_redraw()


func _draw() -> void:
	if not is_instance_valid(_player):
		return
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy) or enemy is BossBase:
			continue
		var dist_above: float = _player.global_position.y - enemy.global_position.y
		if dist_above <= 0.0 or dist_above > WARNING_RANGE:
			continue
		var closeness := 1.0 - (dist_above / WARNING_RANGE)
		var size: float = lerpf(MIN_MARKER_SIZE, MAX_MARKER_SIZE, closeness)
		var color := MARKER_COLOR
		color.a = lerpf(MIN_ALPHA, MAX_ALPHA, closeness)
		var marker_pos := to_local(Vector2(enemy.global_position.x, _player.global_position.y + MARKER_Y_OFFSET))
		var points := PackedVector2Array([
			marker_pos + Vector2(-size, -size),
			marker_pos + Vector2(size, -size),
			marker_pos + Vector2(0.0, size * 0.8),
		])
		draw_colored_polygon(points, color)
