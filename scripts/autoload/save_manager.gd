extends Node
## Persists local accounts + characters to user://save.json.
##
## Structure (v3): { accounts: { <username>: { characters: [ <char>, ... up to
## MAX_CHARACTERS ] } }, current_account, current_character }. Each <char> is a
## full progression profile (name + best_wave/best_level/essence/meta_upgrades/
## seen_hints). The currently-selected character's stats are mirrored into the
## flat fields below, which stay the single source of truth the rest of the game
## reads/writes -- select_character() loads a character INTO them, save_to_disk()
## writes them BACK before persisting. This keeps all existing gameplay code
## (Player/HUD/shops) unchanged; only the front end knows about accounts.
##
## Accounts are LOCAL/on-device only (a client game -- no server). Old v1/v2
## flat saves migrate into a single "Player"/"Archer" character so a returning
## player keeps their progress.

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 3
const MAX_CHARACTERS := 3
const MAX_NAME_LEN := 16

# Permanent, essence-purchased run-start bonuses -- see Player._apply_meta_upgrades().
const META_UPGRADES := {
	"vitality": {"display_name": "Vitality", "description": "+2 Max HP", "base_cost": 20, "cost_growth": 1.5, "max_rank": 5, "bonus_per_rank": 2.0},
	"power": {"display_name": "Power", "description": "+2% Damage", "base_cost": 25, "cost_growth": 1.5, "max_rank": 5, "bonus_per_rank": 0.02},
	"quickdraw": {"display_name": "Quickdraw", "description": "-2% Cooldown", "base_cost": 25, "cost_growth": 1.5, "max_rank": 5, "bonus_per_rank": 0.02},
	"insight": {"display_name": "Insight", "description": "+3% XP Gain", "base_cost": 15, "cost_growth": 1.4, "max_rank": 5, "bonus_per_rank": 0.03},
}

# --- Active character's live stats (the flat API the rest of the game uses) ---
var best_wave := 0
var best_level := 0
var essence := 0
var meta_upgrades: Dictionary = {}  # id -> rank
var seen_hints: Array = []           # one-time tutorial hint ids

# --- Account/character store ---
var accounts: Dictionary = {}        # username -> { "characters": Array[char dict] }
var current_account: String = ""
var current_character: int = -1


func _ready() -> void:
	load_save()


# --- Accounts & characters -----------------------------------------------------

func list_accounts() -> Array:
	var names := accounts.keys()
	names.sort()
	return names


func account_exists(username: String) -> bool:
	return accounts.has(_sanitize_name(username))


func create_account(username: String) -> bool:
	var name := _sanitize_name(username)
	if name == "" or accounts.has(name):
		return false
	accounts[name] = {"characters": []}
	save_to_disk()
	return true


func character_count(username: String) -> int:
	var acct: Dictionary = accounts.get(_sanitize_name(username), {})
	return acct.get("characters", []).size()


func list_characters(username: String) -> Array:
	var acct: Dictionary = accounts.get(_sanitize_name(username), {})
	return acct.get("characters", [])


func create_character(username: String, char_name: String) -> int:
	# Returns the new character's index (and selects it), or -1 on failure
	# (unknown account, already at MAX_CHARACTERS, or invalid name).
	var acct_name := _sanitize_name(username)
	if not accounts.has(acct_name):
		return -1
	var chars: Array = accounts[acct_name]["characters"]
	if chars.size() >= MAX_CHARACTERS:
		return -1
	var cname := _sanitize_name(char_name)
	if cname == "":
		return -1
	chars.append(_new_character(cname))
	var idx := chars.size() - 1
	select_character(acct_name, idx)  # save_to_disk happens here
	return idx


func delete_character(username: String, index: int) -> bool:
	var acct_name := _sanitize_name(username)
	if not accounts.has(acct_name):
		return false
	var chars: Array = accounts[acct_name]["characters"]
	if index < 0 or index >= chars.size():
		return false
	chars.remove_at(index)
	if current_account == acct_name and current_character == index:
		current_account = ""
		current_character = -1
		_reset_active_fields()
	save_to_disk()
	return true


func select_character(username: String, index: int) -> bool:
	var acct_name := _sanitize_name(username)
	if not accounts.has(acct_name):
		return false
	var chars: Array = accounts[acct_name]["characters"]
	if index < 0 or index >= chars.size():
		return false
	current_account = acct_name
	current_character = index
	_load_active_fields()
	save_to_disk()
	return true


func has_active_character() -> bool:
	return _active_character() != null


func current_character_name() -> String:
	var ch = _active_character()
	return ch["name"] if ch != null else ""


func current_account_name() -> String:
	return current_account


# --- Live-stat API (unchanged for the rest of the game) ------------------------

func has_seen_hint(id: String) -> bool:
	return id in seen_hints


func mark_hint_seen(id: String) -> void:
	if id in seen_hints:
		return
	seen_hints.append(id)
	save_to_disk()


func record_run(wave: int, level: int) -> void:
	var updated := false
	if wave > best_wave:
		best_wave = wave
		updated = true
	if level > best_level:
		best_level = level
		updated = true
	if updated:
		save_to_disk()


func add_essence(amount: int) -> void:
	if amount <= 0:
		return
	essence += amount
	save_to_disk()


func spend_essence(amount: int) -> bool:
	if amount < 0 or essence < amount:
		return false
	essence -= amount
	save_to_disk()
	return true


func get_meta_rank(id: String) -> int:
	return meta_upgrades.get(id, 0)


func get_meta_bonus(id: String) -> float:
	if not META_UPGRADES.has(id):
		return 0.0
	return get_meta_rank(id) * float(META_UPGRADES[id]["bonus_per_rank"])


func get_meta_cost(id: String) -> int:
	var def: Dictionary = META_UPGRADES[id]
	return roundi(def["base_cost"] * pow(def["cost_growth"], get_meta_rank(id)))


func can_purchase_meta(id: String) -> bool:
	if not META_UPGRADES.has(id):
		return false
	if get_meta_rank(id) >= int(META_UPGRADES[id]["max_rank"]):
		return false
	return essence >= get_meta_cost(id)


func purchase_meta_upgrade(id: String) -> bool:
	if not can_purchase_meta(id):
		return false
	essence -= get_meta_cost(id)
	meta_upgrades[id] = get_meta_rank(id) + 1
	save_to_disk()
	return true


# --- Persistence ---------------------------------------------------------------

func load_save() -> bool:
	accounts = {}
	current_account = ""
	current_character = -1
	_reset_active_fields()
	if not FileAccess.file_exists(SAVE_PATH):
		return true
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	if parsed.has("accounts") and typeof(parsed["accounts"]) == TYPE_DICTIONARY:
		accounts = parsed["accounts"]
		current_account = str(parsed.get("current_account", ""))
		current_character = int(parsed.get("current_character", -1))
		if _active_character() != null:
			_load_active_fields()
		else:
			current_account = ""
			current_character = -1
		return true
	# Legacy v1/v2 flat save -> migrate into one default character so the
	# returning player keeps their progress.
	if parsed.has("best_wave"):
		var ch := _new_character("Archer")
		ch["best_wave"] = int(parsed.get("best_wave", 0))
		ch["best_level"] = int(parsed.get("best_level", 0))
		ch["essence"] = int(parsed["essence"]) if _is_num(parsed.get("essence")) else 0
		ch["meta_upgrades"] = parsed["meta_upgrades"] if typeof(parsed.get("meta_upgrades")) == TYPE_DICTIONARY else {}
		ch["seen_hints"] = parsed["seen_hints"] if typeof(parsed.get("seen_hints")) == TYPE_ARRAY else []
		accounts = {"Player": {"characters": [ch]}}
		current_account = "Player"
		current_character = 0
		_load_active_fields()
		save_to_disk()
	return true


func save_to_disk() -> bool:
	_writeback_active_fields()
	var data := {
		"version": SAVE_VERSION,
		"accounts": accounts,
		"current_account": current_account,
		"current_character": current_character,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	return true


# --- Internals -----------------------------------------------------------------

func _new_character(char_name: String) -> Dictionary:
	return {
		"name": char_name,
		"best_wave": 0,
		"best_level": 0,
		"essence": 0,
		"meta_upgrades": {},
		"seen_hints": [],
	}


func _active_character():
	if not accounts.has(current_account):
		return null
	var chars: Array = accounts[current_account].get("characters", [])
	if current_character < 0 or current_character >= chars.size():
		return null
	return chars[current_character]


func _load_active_fields() -> void:
	var ch = _active_character()
	if ch == null:
		_reset_active_fields()
		return
	best_wave = int(ch.get("best_wave", 0))
	best_level = int(ch.get("best_level", 0))
	essence = int(ch.get("essence", 0))
	meta_upgrades = (ch.get("meta_upgrades", {}) as Dictionary).duplicate()
	seen_hints = (ch.get("seen_hints", []) as Array).duplicate()


func _writeback_active_fields() -> void:
	var ch = _active_character()
	if ch == null:
		return
	ch["best_wave"] = best_wave
	ch["best_level"] = best_level
	ch["essence"] = essence
	ch["meta_upgrades"] = meta_upgrades
	ch["seen_hints"] = seen_hints


func _reset_active_fields() -> void:
	best_wave = 0
	best_level = 0
	essence = 0
	meta_upgrades = {}
	seen_hints = []


func _sanitize_name(s: String) -> String:
	return s.strip_edges().substr(0, MAX_NAME_LEN)


func _is_num(v) -> bool:
	return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT
