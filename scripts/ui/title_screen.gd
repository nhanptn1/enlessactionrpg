extends Control
class_name TitleScreen

# The game's front end. Handles local account + character selection (up to 3
# characters per account, per-character progression -- see SaveManager), then
# Start jumps into a run as the active character. Upgrades opens the meta shop;
# How to Play shows the controls. Accounts are on-device only (no server).

const GAME_SCENE := "res://scenes/main/Main.tscn"
const META_IDS: Array[String] = ["vitality", "power", "quickdraw", "insight"]

@onready var playing_as_label: Label = $CenterBox/PlayingAsLabel
@onready var best_label: Label = $CenterBox/BestLabel
@onready var start_button: Button = $CenterBox/StartButton
@onready var switch_char_button: Button = $CenterBox/SwitchCharButton
@onready var upgrades_button: Button = $CenterBox/UpgradesButton
@onready var howto_button: Button = $CenterBox/HowToButton
@onready var shop_panel: Control = $ShopPanel
@onready var shop_essence_label: Label = $ShopPanel/ShopVBox/EssenceLabel
@onready var shop_rows_container: VBoxContainer = $ShopPanel/ShopVBox/Rows
@onready var shop_close_button: Button = $ShopPanel/ShopVBox/CloseButton
@onready var howto_panel: Control = $HowToPanel
@onready var howto_close_button: Button = $HowToPanel/HowToVBox/CloseButton
# Account panel
@onready var account_panel: Control = $AccountPanel
@onready var accounts_list: VBoxContainer = $AccountPanel/AccountVBox/AccountsList
@onready var account_name_edit: LineEdit = $AccountPanel/AccountVBox/CreateRow/NameEdit
@onready var create_account_button: Button = $AccountPanel/AccountVBox/CreateRow/CreateAccountButton
@onready var account_cancel_button: Button = $AccountPanel/AccountVBox/AccountCancelButton
# Character panel
@onready var character_panel: Control = $CharacterPanel
@onready var chars_list: VBoxContainer = $CharacterPanel/CharVBox/CharsList
@onready var char_account_label: Label = $CharacterPanel/CharVBox/CharAccountLabel
@onready var char_name_edit: LineEdit = $CharacterPanel/CharVBox/CharCreateRow/CharNameEdit
@onready var create_char_button: Button = $CharacterPanel/CharVBox/CharCreateRow/CreateCharButton
@onready var char_back_button: Button = $CharacterPanel/CharVBox/CharBackButton

var _shop_rows: Array = []
var _selected_account: String = ""


func _ready() -> void:
	shop_panel.visible = false
	howto_panel.visible = false
	account_panel.visible = false
	character_panel.visible = false
	start_button.pressed.connect(_on_start_pressed)
	switch_char_button.pressed.connect(_open_account_panel)
	upgrades_button.pressed.connect(_on_upgrades_pressed)
	howto_button.pressed.connect(func(): AudioManager.play_ui("ui_open"); howto_panel.visible = true)
	howto_close_button.pressed.connect(func(): AudioManager.play_ui("ui_close"); howto_panel.visible = false)
	shop_close_button.pressed.connect(func(): AudioManager.play_ui("ui_close"); shop_panel.visible = false)
	create_account_button.pressed.connect(_on_create_account)
	account_cancel_button.pressed.connect(_on_account_cancel)
	create_char_button.pressed.connect(_on_create_character)
	char_back_button.pressed.connect(_open_account_panel)
	_build_shop_rows()
	_refresh_main()
	AudioManager.play_music("gameplay")
	# No character yet (fresh install / just deleted) -> force selection first.
	if not SaveManager.has_active_character():
		_open_account_panel()


func _refresh_main() -> void:
	var active := SaveManager.has_active_character()
	start_button.disabled = not active
	upgrades_button.disabled = not active
	if active:
		playing_as_label.text = "Playing as: %s  (%s)" % [SaveManager.current_character_name(), SaveManager.current_account_name()]
	else:
		playing_as_label.text = "No character selected"
	best_label.text = "Best: Wave %d  —  Level %d\nEssence: %d" % [SaveManager.best_wave, SaveManager.best_level, SaveManager.essence]


func _on_start_pressed() -> void:
	if not SaveManager.has_active_character():
		return
	AudioManager.play_ui("ui_click")
	get_tree().change_scene_to_file(GAME_SCENE)


# --- Account selection ---------------------------------------------------------

func _open_account_panel() -> void:
	AudioManager.play_ui("ui_open")
	character_panel.visible = false
	account_name_edit.text = ""
	_refresh_accounts_list()
	# Cancel only makes sense if the player already has a character to fall back on.
	account_cancel_button.visible = SaveManager.has_active_character()
	account_panel.visible = true


func _refresh_accounts_list() -> void:
	for c in accounts_list.get_children():
		c.queue_free()
	for name in SaveManager.list_accounts():
		var b := Button.new()
		b.text = "%s  (%d/%d)" % [name, SaveManager.character_count(name), SaveManager.MAX_CHARACTERS]
		b.custom_minimum_size = Vector2(0, 46)
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(_open_character_panel.bind(name))
		accounts_list.add_child(b)


func _on_create_account() -> void:
	if SaveManager.create_account(account_name_edit.text):
		AudioManager.play_ui("ui_click")
		_open_character_panel(SaveManager._sanitize_name(account_name_edit.text))
	# else: name empty or already taken -- the field just stays for a retry.


func _on_account_cancel() -> void:
	AudioManager.play_ui("ui_close")
	account_panel.visible = false


# --- Character selection -------------------------------------------------------

func _open_character_panel(account: String) -> void:
	AudioManager.play_ui("ui_open")
	_selected_account = account
	account_panel.visible = false
	char_account_label.text = "Account: %s" % account
	char_name_edit.text = ""
	_refresh_chars_list()
	character_panel.visible = true


func _refresh_chars_list() -> void:
	for c in chars_list.get_children():
		c.queue_free()
	var chars: Array = SaveManager.list_characters(_selected_account)
	for i in chars.size():
		var ch: Dictionary = chars[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var lbl := Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", 18)
		lbl.text = "%s   —   Best W%d L%d" % [ch.get("name", "?"), int(ch.get("best_wave", 0)), int(ch.get("best_level", 0))]
		var play := Button.new()
		play.text = "Play"
		play.custom_minimum_size = Vector2(96, 44)
		play.pressed.connect(_on_play_character.bind(i))
		row.add_child(lbl)
		row.add_child(play)
		chars_list.add_child(row)
	var full: bool = chars.size() >= SaveManager.MAX_CHARACTERS
	create_char_button.disabled = full
	char_name_edit.editable = not full
	char_name_edit.placeholder_text = "Max %d characters reached" % SaveManager.MAX_CHARACTERS if full else "New character name"


func _on_create_character() -> void:
	if SaveManager.create_character(_selected_account, char_name_edit.text) >= 0:
		AudioManager.play_ui("ui_click")
		char_name_edit.text = ""
		_close_selection()


func _on_play_character(index: int) -> void:
	if SaveManager.select_character(_selected_account, index):
		AudioManager.play_ui("ui_click")
		_close_selection()


func _close_selection() -> void:
	character_panel.visible = false
	account_panel.visible = false
	_refresh_main()


# --- Meta-upgrade shop ---------------------------------------------------------

func _on_upgrades_pressed() -> void:
	if not SaveManager.has_active_character():
		return
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
		_refresh_main()
