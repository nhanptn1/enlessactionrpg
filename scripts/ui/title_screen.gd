extends Control
class_name TitleScreen

# The game's front end -- shown at launch (project main_scene), before any run.
# Start jumps into the gameplay scene; Upgrades opens the meta shop (same
# SaveManager economy as the game-over shop, but built with dynamic rows here
# rather than hardcoded ones); How to Play shows the controls.

const GAME_SCENE := "res://scenes/main/Main.tscn"
const META_IDS: Array[String] = ["vitality", "power", "quickdraw", "insight"]

@onready var best_label: Label = $CenterBox/BestLabel
@onready var start_button: Button = $CenterBox/StartButton
@onready var upgrades_button: Button = $CenterBox/UpgradesButton
@onready var howto_button: Button = $CenterBox/HowToButton
@onready var shop_panel: Control = $ShopPanel
@onready var shop_essence_label: Label = $ShopPanel/ShopVBox/EssenceLabel
@onready var shop_rows_container: VBoxContainer = $ShopPanel/ShopVBox/Rows
@onready var shop_close_button: Button = $ShopPanel/ShopVBox/CloseButton
@onready var howto_panel: Control = $HowToPanel
@onready var howto_close_button: Button = $HowToPanel/HowToVBox/CloseButton

var _shop_rows: Array = []  # [{id, label, buy}]


func _ready() -> void:
	shop_panel.visible = false
	howto_panel.visible = false
	start_button.pressed.connect(_on_start_pressed)
	upgrades_button.pressed.connect(_on_upgrades_pressed)
	howto_button.pressed.connect(func(): AudioManager.play_ui("ui_open"); howto_panel.visible = true)
	howto_close_button.pressed.connect(func(): AudioManager.play_ui("ui_close"); howto_panel.visible = false)
	shop_close_button.pressed.connect(func(): AudioManager.play_ui("ui_close"); shop_panel.visible = false)
	_build_shop_rows()
	_update_header()
	AudioManager.play_music("gameplay")  # gentle ambient loop under the menu


func _update_header() -> void:
	best_label.text = "Best: Wave %d  —  Level %d\nEssence: %d" % [SaveManager.best_wave, SaveManager.best_level, SaveManager.essence]


func _on_start_pressed() -> void:
	AudioManager.play_ui("ui_click")
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_upgrades_pressed() -> void:
	AudioManager.play_ui("ui_open")
	_refresh_shop()
	shop_panel.visible = true


func _build_shop_rows() -> void:
	for id in META_IDS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 16)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		var buy := Button.new()
		buy.custom_minimum_size = Vector2(120, 44)
		buy.add_theme_font_size_override("font_size", 14)
		buy.pressed.connect(_on_buy_pressed.bind(id))
		row.add_child(label)
		row.add_child(buy)
		shop_rows_container.add_child(row)
		_shop_rows.append({"id": id, "label": label, "buy": buy})


func _refresh_shop() -> void:
	shop_essence_label.text = "Essence: %d" % SaveManager.essence
	for r in _shop_rows:
		var id: String = r["id"]
		var def: Dictionary = SaveManager.META_UPGRADES[id]
		var rank: int = SaveManager.get_meta_rank(id)
		var max_rank: int = def["max_rank"]
		r["label"].text = "%s (%d/%d) — %s" % [def["display_name"], rank, max_rank, def["description"]]
		if rank >= max_rank:
			r["buy"].text = "Maxed"
			r["buy"].disabled = true
		else:
			var cost: int = SaveManager.get_meta_cost(id)
			r["buy"].text = "Buy (%d)" % cost
			r["buy"].disabled = SaveManager.essence < cost


func _on_buy_pressed(id: String) -> void:
	if SaveManager.purchase_meta_upgrade(id):
		AudioManager.play_ui("ui_click")
		_refresh_shop()
		_update_header()
