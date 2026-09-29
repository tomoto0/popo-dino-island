extends RefCounted
## Stage registry for the 24 generated stages (6 worlds x 4). Data lives in
## res://data/stages/*.json and is produced by tools/stage_gen.py.

const INDEX_PATH := "res://data/stages/index.json"
const PATH := "res://data/stages/%s.json"

static var _index: Dictionary = {}
static var _cache: Dictionary = {}


static func _load_index() -> Dictionary:
	if _index.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(INDEX_PATH))
		_index = parsed if parsed is Dictionary else {"stages": [], "worlds": []}
	return _index


static func stages() -> Array:
	return (_load_index().get("stages", []) as Array).duplicate()


static func worlds() -> Array:
	return (_load_index().get("worlds", []) as Array).duplicate(true)


static func stage_count() -> int:
	return stages().size()


static func index_of(stage_id: String) -> int:
	return stages().find(stage_id)


static func load_stage(id: String) -> Dictionary:
	if _cache.has(id):
		return (_cache[id] as Dictionary).duplicate(true)
	if id not in stages():
		return {}
	var file := FileAccess.open(PATH % id, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or not validate(parsed):
		push_error("Invalid stage data: " + id)
		return {}
	_cache[id] = parsed
	return (parsed as Dictionary).duplicate(true)


static func validate(stage: Dictionary) -> bool:
	for key in ["id", "world", "index", "name", "theme", "music", "world_width", "spawn", "goal", "checkpoint", "grounds", "time"]:
		if not stage.has(key):
			return false
	if not _number(stage.world_width) or float(stage.world_width) < 1000.0 or float(stage.world_width) > 30000.0:
		return false
	for key in ["spawn", "goal", "checkpoint"]:
		if not _point(stage[key], float(stage.world_width)):
			return false
	return stage.grounds is Array and not (stage.grounds as Array).is_empty()


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _point(value: Variant, width: float) -> bool:
	return value is Array and value.size() == 2 and _number(value[0]) and _number(value[1]) and float(value[0]) >= 0.0 and float(value[0]) <= width
