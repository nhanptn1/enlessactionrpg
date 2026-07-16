extends CanvasLayer
class_name GameOverScreen

# Row order matches SaveManager.META_UPGRADES iteration order (Dictionary
# literals preserve insertion order in GDScript) -- kept explicit here so the
# UI rows stay decoupled from that iteration order, in case META_UPGRADES
# ever gets reordered or extended.
const META_UPGRADE_IDS: Array[String] = ["vitality", "power", "quickdraw", "insight"]

@onready var panel: Control = $Panel
@onready var info_label: Label = $Panel/VBox/InfoLabel
@onready var restart_button: Button = $Panel/VBox/RestartButton
@onready var upgrades_button: Button = $Panel/VBox/UpgradesButton
@onready var shop_panel: Control = $Panel/ShopPanel
@onready var essence_label: Label = $Panel/ShopPanel/ShopVBox/EssenceLabel
@onready var close_button: Button = $Panel/ShopPanel/ShopVBox/CloseButton
@onready var shop_rows: Array[HBoxContainer] = [
	$Panel/ShopPanel/ShopVBox/Row1, $Panel/ShopPanel/ShopVBox/Row2,
	$Panel/ShopPanel/ShopVBox/Row3, $Panel/ShopPanel/ShopVBox/Row4,
]

var player: Node
var _last_wave := 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel.visible = false
	shop_panel.visible = false
	player = get_tree().get_first_node_in_group("player")
	if player:
		player.died.connect(_on_player_died)
	var wave_manager := get_tree().get_first_node_in_group("wave_manager")
	if wave_manager:
		wave_manager.wave_started.connect(_on_wave_started)
	restart_button.pressed.connect(_on_restart_pressed)
	upgrades_button.pressed.connect(_on_upgrades_pressed)
	close_button.pressed.connect(_on_close_shop_pressed)
	for i in shop_rows.size():
		var buy_button: Button = shop_rows[i].get_node("BuyButton")
		buy_button.pressed.connect(_on_buy_pressed.bind(META_UPGRADE_IDS[i]))


func _on_wave_started(wave_number: int) -> void:
	_last_wave = wave_number


func _on_player_died() -> void:
	var level: int = player.level if player else 1
	SaveManager.record_run(_last_wave, level)
	# Simple performance-scaled payout -- ties essence to both how far the run
	# got and how much the character grew, so a longer/stronger run always
	# earns more, without needing a separate economy to balance.
	var essence_earned := _last_wave * 2 + level
	SaveManager.add_essence(essence_earned)
	info_label.text = "Reached Wave %d — Level %d\nBest: Wave %d — Level %d\n+%d Essence (Total: %d)" % [
		_last_wave, level, SaveManager.best_wave, SaveManager.best_level, essence_earned, SaveManager.essence,
	]
	panel.visible = true
	GameManager.request_pause("game_over")


func _on_restart_pressed() -> void:
	AudioManager.play_ui("ui_click")
	GameManager.reset_state()
	get_tree().reload_current_scene()


func _on_upgrades_pressed() -> void:
	AudioManager.play_ui("ui_click")
	_refresh_shop()
	shop_panel.visible = true


func _on_close_shop_pressed() -> void:
	AudioManager.play_ui("ui_click")
	shop_panel.visible = false


func _on_buy_pressed(id: String) -> void:
	if SaveManager.purchase_meta_upgrade(id):
		AudioManager.play_ui("ui_click")
		_refresh_shop()


func _refresh_shop() -> void:
	essence_label.text = "Essence: %d" % SaveManager.essence
	for i in META_UPGRADE_IDS.size():
		var id := META_UPGRADE_IDS[i]
		var def: Dictionary = SaveManager.META_UPGRADES[id]
		var rank: int = SaveManager.get_meta_rank(id)
		var max_rank: int = def["max_rank"]
		var row := shop_rows[i]
		var label: Label = row.get_node("Label")
		var buy_button: Button = row.get_node("BuyButton")
		label.text = "%s (%d/%d) — %s" % [def["display_name"], rank, max_rank, def["description"]]
		if rank >= max_rank:
			buy_button.text = "Maxed"
			buy_button.disabled = true
		else:
			var cost := SaveManager.get_meta_cost(id)
			buy_button.text = "Buy (%d)" % cost
			buy_button.disabled = SaveManager.essence < cost
