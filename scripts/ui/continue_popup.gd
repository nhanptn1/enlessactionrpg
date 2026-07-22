extends CanvasLayer
class_name ContinuePopup

# Intercepts the player going down (SignalBus.player_downed) and offers a
# revive before the real game over. The first continue each run is free; the
# second costs essence. A third death never emits player_downed (see
# Player.MAX_CONTINUES), so GameOverScreen fires normally then.

const CONTINUE_ESSENCE_COST := 25  # cost of the 2nd (paid) continue -- easily tuned

@onready var panel: Control = $Panel
@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var info_label: Label = $Panel/VBox/InfoLabel
@onready var continue_button: Button = $Panel/VBox/ContinueButton
@onready var give_up_button: Button = $Panel/VBox/GiveUpButton

var player: Node
var _is_paid := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("continue_popup")
	panel.visible = false
	player = get_tree().get_first_node_in_group("player")
	SignalBus.player_downed.connect(_on_player_downed)
	continue_button.pressed.connect(_on_continue_pressed)
	give_up_button.pressed.connect(_on_give_up_pressed)


func _on_player_downed(continues_used: int) -> void:
	# continues_used 0 = the first (free) continue; 1 = the second (paid) one.
	_is_paid = continues_used >= 1
	title_label.text = "You Fell!"
	if _is_paid:
		info_label.text = "One last stand?\nCost: %d Essence   (You have %d)" % [CONTINUE_ESSENCE_COST, SaveManager.essence]
		continue_button.text = "Continue — %d Essence" % CONTINUE_ESSENCE_COST
		continue_button.disabled = SaveManager.essence < CONTINUE_ESSENCE_COST
	else:
		info_label.text = "Get back up and keep fighting!"
		continue_button.text = "Continue — Free"
		continue_button.disabled = false
	panel.visible = true
	GameManager.request_pause("continue")


func _on_continue_pressed() -> void:
	if _is_paid and not SaveManager.spend_essence(CONTINUE_ESSENCE_COST):
		return  # can't afford (button should already be disabled -- belt and suspenders)
	AudioManager.play_ui("ui_click")
	panel.visible = false
	if is_instance_valid(player):
		player.revive()
	GameManager.request_unpause("continue")


func _on_give_up_pressed() -> void:
	AudioManager.play_ui("ui_click")
	panel.visible = false
	# Trigger the real game over FIRST (adds the "game_over" pause source) so
	# releasing "continue" below leaves the tree paused on the game-over screen
	# rather than briefly unpausing.
	if is_instance_valid(player):
		player.decline_continue()
	GameManager.request_unpause("continue")
