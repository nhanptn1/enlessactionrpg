extends Node
## Persists best-run stats to user://save.json with all-or-nothing validation.

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1

var best_wave := 0
var best_level := 0


func _ready() -> void:
	load_save()


func load_save() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		best_wave = 0
		best_level = 0
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


func save_to_disk() -> bool:
	var data := {
		"version": SAVE_VERSION,
		"best_wave": best_wave,
		"best_level": best_level,
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
