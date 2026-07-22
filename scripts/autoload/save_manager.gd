extends Node
## Persists best-run stats and meta-progression to user://save.json.
## best_wave/best_level are validated all-or-nothing (a save missing either is
## rejected wholesale, since those two have existed since v1). essence/
## meta_upgrades are additive v2 fields -- a save that predates them still
## loads successfully with both defaulted, rather than being wiped.

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 2

# Permanent, essence-purchased run-start bonuses -- see Player._apply_meta_upgrades().
# bonus_per_rank matches the existing in-run upgrade increments 1:1 (damage
# +2%/cooldown -2%/xp_gain +3%, see player.gd::apply_upgrade()) so a meta rank
# reads as "one extra free pick from run zero," not a separately-balanced number.
const META_UPGRADES := {
	"vitality": {"display_name": "Vitality", "description": "+2 Max HP", "base_cost": 20, "cost_growth": 1.5, "max_rank": 5, "bonus_per_rank": 2.0},
	"power": {"display_name": "Power", "description": "+2% Damage", "base_cost": 25, "cost_growth": 1.5, "max_rank": 5, "bonus_per_rank": 0.02},
	"quickdraw": {"display_name": "Quickdraw", "description": "-2% Cooldown", "base_cost": 25, "cost_growth": 1.5, "max_rank": 5, "bonus_per_rank": 0.02},
	"insight": {"display_name": "Insight", "description": "+3% XP Gain", "base_cost": 15, "cost_growth": 1.4, "max_rank": 5, "bonus_per_rank": 0.03},
}

var best_wave := 0
var best_level := 0
var essence := 0
var meta_upgrades: Dictionary = {}  # id (String, key of META_UPGRADES) -> rank (int)


func _ready() -> void:
	load_save()


func load_save() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		best_wave = 0
		best_level = 0
		essence = 0
		meta_upgrades = {}
		return true
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	if not _validate_save(parsed):
		return false
	best_wave = int(parsed["best_wave"])
	best_level = int(parsed["best_level"])
	essence = int(parsed["essence"]) if parsed.has("essence") and (typeof(parsed["essence"]) == TYPE_FLOAT or typeof(parsed["essence"]) == TYPE_INT) else 0
	meta_upgrades = parsed["meta_upgrades"] if parsed.has("meta_upgrades") and typeof(parsed["meta_upgrades"]) == TYPE_DICTIONARY else {}
	return true


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
	# Generic essence sink (used by the paid continue) -- returns false without
	# spending if the player can't afford it, so callers can gate a button on it.
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


func save_to_disk() -> bool:
	var data := {
		"version": SAVE_VERSION,
		"best_wave": best_wave,
		"best_level": best_level,
		"essence": essence,
		"meta_upgrades": meta_upgrades,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	return true


func _validate_save(data: Dictionary) -> bool:
	if not data.has("version") or typeof(data["version"]) != TYPE_FLOAT and typeof(data["version"]) != TYPE_INT:
		return false
	if not data.has("best_wave") or typeof(data["best_wave"]) != TYPE_FLOAT and typeof(data["best_wave"]) != TYPE_INT:
		return false
	if not data.has("best_level") or typeof(data["best_level"]) != TYPE_FLOAT and typeof(data["best_level"]) != TYPE_INT:
		return false
	return true
