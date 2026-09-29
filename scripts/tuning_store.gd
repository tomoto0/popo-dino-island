extends Node
## One catalog owns validation, requested values, active values and run integrity.
signal value_changed(key: String, value: float)
signal requested_changed(key: String, value: float)
signal saved(success: bool)
signal validation_failed

const SAVE_PATH := "user://platformer_tuning.json"
const PLAYER_SAVE_PATH := "user://platformer_player_settings.json"
const SCHEMA_PATH := "res://config/tuning.json"
const CATEGORIES := ["UI", "GAMEPLAY", "AUDIO", "PLAYER", "ENEMIES", "ENVIRONMENT"]
const BOUNDARIES := ["LIVE", "NEXT_ACTION", "NEXT_SPAWN", "NEXT_STAGE", "NEXT_RUN"]
const PLAYER_SETTINGS := ["display_mode", "reduced_motion", "filter_enabled", "filter_intensity", "hud_opacity"]

var schema_version := 0
var settings: Array = []
var settings_by_key: Dictionary = {}
var defaults: Dictionary = {}
var values: Dictionary = {}
var requested_values: Dictionary = {}
var player_values: Dictionary = {}
var run_active := false
var run_tainted := false
var persistence_enabled := true
var last_save_ok := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not _load_schema():
		push_error("Tuning catalog could not be loaded")
		return
	reset_defaults(false)
	_load_player_settings()


func owner_preview_enabled() -> bool:
	return OS.is_debug_build() and not OS.has_feature("release") and not OS.has_feature("checkpoint")


func _load_schema() -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SCHEMA_PATH))
	if not parsed is Dictionary or int(parsed.get("version", 0)) <= 0 or not parsed.get("settings") is Array:
		return false
	var next_settings: Array = []
	var next_by_key: Dictionary = {}
	var next_defaults: Dictionary = {}
	var ids: Dictionary = {}
	for entry: Variant in parsed.settings:
		if not entry is Dictionary:
			return false
		var key := str(entry.get("key", ""))
		var identifier := str(entry.get("id", ""))
		if key.is_empty() or identifier.is_empty() or next_by_key.has(key) or ids.has(identifier):
			return false
		if not entry.get("category") in CATEGORIES or not entry.get("apply_mode") in BOUNDARIES:
			return false
		if not entry.get("type") in ["boolean", "integer", "float", "enum"] or not entry.get("integrity") in ["COSMETIC", "GAMEPLAY", "SCORE_AFFECTING"]:
			return false
		if str(entry.get("label_key", "")).is_empty() or str(entry.get("description_key", "")).is_empty():
			return false
		for field in ["default", "min", "max", "step"]:
			if not _is_number(entry.get(field)) or not is_finite(float(entry[field])):
				return false
		if float(entry.min) > float(entry.max) or float(entry.step) <= 0.0 or float(entry.default) < float(entry.min) or float(entry.default) > float(entry.max):
			return false
		if entry.type == "enum" and (not entry.get("choices") is Array or entry.choices.is_empty()):
			return false
		next_settings.append(entry.duplicate(true))
		next_by_key[key] = entry.duplicate(true)
		next_defaults[key] = float(entry.default)
		ids[identifier] = true
	if not _valid_combination(next_defaults):
		return false
	schema_version = int(parsed.version)
	settings = next_settings
	settings_by_key = next_by_key
	defaults = next_defaults
	return true


func _is_number(value: Variant) -> bool:
	return value is int or value is float


func get_settings() -> Array:
	return settings.duplicate(true)


func get_schema_version() -> int:
	return schema_version


func get_value(key: String) -> float:
	return float(values.get(key, defaults.get(key, 0.0)))


func get_requested_value(key: String) -> float:
	return float(requested_values.get(key, defaults.get(key, 0.0)))


func get_values() -> Dictionary:
	return values.duplicate(true)


func get_run_config() -> Dictionary:
	var result: Dictionary = {}
	for entry: Dictionary in settings:
		if entry.integrity != "COSMETIC":
			result[entry.key] = get_value(entry.key)
	return result


func get_jump_apex_height() -> float:
	return get_value("jump_power") * get_value("jump_power") / maxf(1.0, 2.0 * get_value("gravity"))


func _valid_value(key: String, value: Variant) -> bool:
	if not settings_by_key.has(key) or not _is_number(value) or not is_finite(float(value)):
		return false
	var entry: Dictionary = settings_by_key[key]
	var number := float(value)
	if number < float(entry.min) or number > float(entry.max):
		return false
	var steps := (number - float(entry.min)) / float(entry.step)
	return absf(steps - roundf(steps)) < 0.001


func _valid_combination(candidate: Dictionary) -> bool:
	var jump := float(candidate.get("jump_power", 800.0))
	var gravity := float(candidate.get("gravity", 1750.0))
	# The tallest required jump is 150px, with 24px clearance for the cat.
	return gravity > 0 and jump * jump / (2.0 * gravity) >= 174.0 and 2.0 * jump * float(candidate.get("move_speed", 310.0)) / gravity >= 180.0 and float(candidate.get("jump_release_speed", 320.0)) <= jump


func set_value(key: String, value: float) -> bool:
	return set_values({key: value})


func set_values(changes: Dictionary) -> bool:
	if not owner_preview_enabled(): return false
	var next := requested_values.duplicate(true)
	for key: String in changes:
		if not _valid_value(key, changes[key]): return false
		next[key] = float(changes[key])
	if not _valid_combination(next): return false
	var live := values.duplicate(true)
	for entry: Dictionary in settings:
		if entry.apply_mode == "LIVE": live[entry.key] = next[entry.key]
	if not _valid_combination(live): return false
	var changed: Array[String] = []
	var activated: Array[String] = []
	for key: String in changes:
		if requested_values[key] != next[key]: changed.append(key)
		if values[key] != live[key]: activated.append(key)
	requested_values = next
	values = live
	for key: String in activated:
		if run_active and settings_by_key[key].integrity != "COSMETIC" and values[key] != defaults[key]: run_tainted = true
	for key: String in changed: requested_changed.emit(key, get_requested_value(key))
	for key: String in activated: value_changed.emit(key, get_value(key))
	return true


func apply_boundary(mode: String) -> void:
	if not mode in BOUNDARIES:
		return
	var next := values.duplicate(true)
	for entry: Dictionary in settings:
		if entry.apply_mode == mode or mode == "NEXT_RUN":
			next[entry.key] = get_requested_value(entry.key)
	if not _valid_combination(next):
		validation_failed.emit()
		return
	for entry: Dictionary in settings:
		var key: String = entry.key
		var value := float(next[key])
		if run_active and entry.integrity != "COSMETIC" and not is_equal_approx(value, float(defaults[key])):
			run_tainted = true
		if not is_equal_approx(get_value(key), value):
			values[key] = value
			value_changed.emit(key, value)


func begin_run() -> void:
	run_active = true
	run_tainted = false
	apply_boundary("NEXT_RUN")


func end_run() -> void:
	run_active = false


func is_run_tainted() -> bool:
	return run_tainted


func reset_setting(key: String) -> bool:
	if not defaults.has(key):
		return false
	return set_value(key, float(defaults[key]))


func reset_defaults(_save_after: bool = true) -> void:
	requested_values = defaults.duplicate(true)
	if values.is_empty():
		values = requested_values.duplicate(true)
	elif run_active:
		apply_boundary("LIVE")
	else:
		apply_boundary("NEXT_RUN")
	for key: String in requested_values:
		requested_changed.emit(key, get_requested_value(key))
	

func get_player_setting(key: String) -> float:
	return float(player_values.get(key, defaults.get(key, 0.0))) if key in PLAYER_SETTINGS else 0.0


func set_player_setting(key: String, value: float) -> bool:
	if not key in PLAYER_SETTINGS or not _valid_value(key, value) or settings_by_key[key].integrity != "COSMETIC":
		return false
	player_values[key] = value
	requested_values[key] = value
	values[key] = value
	requested_changed.emit(key, value)
	value_changed.emit(key, value)
	if persistence_enabled:
		_write_json(PLAYER_SAVE_PATH, {"version": 1, "values": player_values})
	return true


func _load_player_settings() -> void:
	if not persistence_enabled or not FileAccess.file_exists(PLAYER_SAVE_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PLAYER_SAVE_PATH))
	if not parsed is Dictionary or int(parsed.get("version", 0)) != 1 or not parsed.get("values") is Dictionary:
		return
	for key: String in parsed.values:
		if key in PLAYER_SETTINGS and _valid_value(key, parsed.values[key]) and settings_by_key[key].integrity == "COSMETIC":
			player_values[key] = float(parsed.values[key])
			requested_values[key] = player_values[key]
			values[key] = player_values[key]


func _write_json(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	file.flush()
	var success := file.get_error() == OK
	file.close()
	return success and DirAccess.rename_absolute(path + ".tmp", path) == OK
