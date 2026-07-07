extends Node2D
class_name ItemPickup

# Must stay on the default PROCESS_MODE_INHERIT (do NOT set ALWAYS like the
# UI popups) so this correctly freezes during the level-up popup or a
# game-over pause, exactly like every other gameplay node (enemies,
# projectiles).

const DRIFT_DURATION := 0.6

const RARITY_COLORS := {
	"common": Color(0.75, 0.75, 0.75, 1.0),
	"rare": Color(0.3, 0.55, 1.0, 1.0),
	"epic": Color(0.75, 0.25, 0.9, 1.0),
}

@onready var visual: Polygon2D = $Visual

var item_data: ItemData  # caller MUST set this before add_child()


func _ready() -> void:
	visual.color = RARITY_COLORS.get(item_data.rarity, RARITY_COLORS["common"])
	var player := get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player):
		queue_free()
		return
	var target: Vector2 = player.global_position  # snapshot once — player never moves
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(self, "global_position", target, DRIFT_DURATION)
	tween.finished.connect(_on_arrived.bind(player))


func _on_arrived(player: Node) -> void:
	if is_instance_valid(player) and player.has_method("apply_item"):
		player.apply_item(item_data)
	queue_free()
