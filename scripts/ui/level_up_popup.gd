extends CanvasLayer
class_name LevelUpPopup

const UPGRADE_LABELS := {
	"damage": "Increase Damage (+2%)",
	"cooldown": "Reduce Cooldown (-3%)",
	"projectile_count": "+1 Arrow",
	"projectile_speed": "Increase Projectile Speed (+5%)",
	"crit_chance": "Increase Crit Chance (+2%)",
	"hp": "Restore HP (+2)",
	"xp_gain": "Improve XP Gain (+5%)",
}

@onready var panel: Control = $Panel
@onready var choice_buttons: Array[Button] = [$Panel/VBox/HBox/Choice1, $Panel/VBox/HBox/Choice2, $Panel/VBox/HBox/Choice3]

var player: Node
var _pending_ids: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel.visible = false
	player = get_tree().get_first_node_in_group("player")
	if player:
		player.level_up.connect(_on_level_up)
	for i in 3:
		choice_buttons[i].pressed.connect(_on_choice_selected.bind(i))


func _eligible_upgrade_ids() -> Array[String]:
	# Filters the generic level-up pool down to picks that would actually do
	# something. "+1 Arrow" (bonus_projectile_count) is a dead pick in two cases,
	# so drop it whenever it wouldn't actually add an arrow:
	#   1. Trap Shot ignores projectile_count entirely (see _fire_trap_shot()).
	#   2. The active cone skill is already firing the hard cap of MAX_SHOT_COUNT
	#      arrows (base projectile_count + bonus), so another +1 gets clamped
	#      away with zero effect (see the mini(..., MAX_SHOT_COUNT) in player.gd).
	var ids: Array[String] = player.UPGRADE_POOL.duplicate()
	var skill: SkillData = player.get_current_physical_skill()
	if skill != null:
		var ignores_count: bool = skill.fire_mode == SkillData.FireMode.TRAP_SHOT
		var at_arrow_cap: bool = skill.projectile_count + player.bonus_projectile_count >= player.MAX_SHOT_COUNT
		if ignores_count or at_arrow_cap:
			ids.erase("projectile_count")

	# (2026-07-24) Three more dead picks, same class as the arrow cap above and
	# found by measurement: a throughput probe showed how many repeatable stat
	# picks you have banked is the difference between dying at wave 20 and
	# holding at wave 60, so handing over a pick that does nothing is a real
	# cost, not a cosmetic one.
	#
	# "Reduce Cooldown" stops mattering once cooldown_mult reaches its floor --
	# ~24 picks from 1.0 at -0.03 each, and sooner with the quickdraw meta bonus
	# or a cooldown run modifier. The heavy build in that probe sat exactly on
	# the floor, so this is reachable in a real run, not a theoretical edge.
	if player.cooldown_mult <= player.COOLDOWN_MULT_FLOOR:
		ids.erase("cooldown")
	# "Increase Crit Chance" is clamped at 1.0 -- every point past that is lost.
	if player.crit_chance >= player.CRIT_CHANCE_MAX:
		ids.erase("crit_chance")
	# "Restore HP" heals via minf(current + 2, max), so at full health it is a
	# no-op -- and this is the one the player meets most often, since levelling
	# up while undamaged is the normal case.
	if player.current_hp >= player.max_hp:
		ids.erase("hp")

	# The pool can't currently drop below 3 (damage/projectile_speed/xp_gain
	# never go dead), but _on_level_up() indexes three buttons unconditionally,
	# so a future pool change must not be able to turn this into a crash.
	while ids.size() < 3:
		ids.append("damage")
	return ids


func _on_level_up(_new_level: int) -> void:
	_pending_ids = _eligible_upgrade_ids()
	_pending_ids.shuffle()
	_pending_ids = _pending_ids.slice(0, 3)
	for i in 3:
		choice_buttons[i].text = UPGRADE_LABELS[_pending_ids[i]]
	panel.visible = true
	GameManager.request_pause("level_up")


func _on_choice_selected(index: int) -> void:
	AudioManager.play_ui("ui_click")
	player.apply_upgrade(_pending_ids[index])
	panel.visible = false
	GameManager.request_unpause("level_up")
