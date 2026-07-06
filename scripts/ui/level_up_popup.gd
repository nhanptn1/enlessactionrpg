extends CanvasLayer
class_name LevelUpPopup

const UPGRADE_LABELS := {
	"damage": "Increase Damage (+10%)",
	"cooldown": "Reduce Cooldown (-8%)",
	"projectile_count": "+1 Arrow",
	"projectile_speed": "Increase Projectile Speed (+15%)",
	"crit_chance": "Increase Crit Chance (+5%)",
	"hp": "Gain Max HP (+20)",
	"shield": "Gain Shield (+20)",
	"xp_gain": "Improve XP Gain (+10%)",
}

@onready var panel: Control = $Panel
@onready var choice_buttons: Array[Button] = [$Panel/VBox/HBox/Choice1, $Panel/VBox/HBox/Choice2, $Panel/VBox/HBox/Choice3]
@onready var skill_banner_label: Label = $SkillBanner/Label

var player: Node
var _pending_ids: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel.visible = false
	player = get_tree().get_first_node_in_group("player")
	if player:
		player.level_up.connect(_on_level_up)
		player.skill_unlocked.connect(_on_skill_unlocked)
	for i in 3:
		choice_buttons[i].pressed.connect(_on_choice_selected.bind(i))


func _on_level_up(_new_level: int) -> void:
	_pending_ids = player.UPGRADE_POOL.duplicate()
	_pending_ids.shuffle()
	_pending_ids = _pending_ids.slice(0, 3)
	for i in 3:
		choice_buttons[i].text = UPGRADE_LABELS[_pending_ids[i]]
	panel.visible = true
	get_tree().paused = true


func _on_choice_selected(index: int) -> void:
	player.apply_upgrade(_pending_ids[index])
	panel.visible = false
	get_tree().paused = false


func _on_skill_unlocked(skill_name: String) -> void:
	skill_banner_label.text = "%s Unlocked!" % skill_name
