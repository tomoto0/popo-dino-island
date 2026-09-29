extends Node
## Bound the logical game surface, not the browser window or CSS canvas.
## Godot owns letterboxing and the corresponding input coordinate transform.

const BASE_SIZE := Vector2i(1280, 720)
const MIN_ASPECT := 1.0
const MAX_ASPECT := 16.0 / 6.0

var _last_window_size := Vector2i.ZERO
var _display_mode := 0
var _world_scale := 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_update_size()
	_bind_settings.call_deferred()


func _process(_delta: float) -> void:
	# With KEEP, physical resize need not emit the viewport's size_changed.
	if get_tree().root.size != _last_window_size:
		_update_size()


func _update_size() -> void:
	var window := get_tree().root
	if window.size.x <= 0 or window.size.y <= 0:
		return
	_last_window_size = window.size
	var aspect := 16.0 / 9.0 if _display_mode == 0 else clampf(float(window.size.x) / float(window.size.y), MIN_ASPECT, MAX_ASPECT)
	var design := Vector2(BASE_SIZE.x, float(BASE_SIZE.x) / aspect)
	if aspect >= float(BASE_SIZE.x) / BASE_SIZE.y:
		design = Vector2(float(BASE_SIZE.y) * aspect, BASE_SIZE.y)
	# Keep UI text/touch targets at actual pixels on smaller windows. The camera
	# uses this uniform ratio to retain the exact authored world view/physics.
	_world_scale = minf(1.0, minf(float(window.size.x) / design.x, float(window.size.y) / design.y))
	var logical_size := Vector2i(roundi(design.x * _world_scale), roundi(design.y * _world_scale))
	if window.content_scale_size != logical_size:
		window.content_scale_size = logical_size


func world_scale() -> float:
	return _world_scale


func _bind_settings() -> void:
	var store := get_node("/root/TuningStore")
	store.value_changed.connect(_on_setting_changed)
	_on_setting_changed("display_mode", store.get_value("display_mode"))


func _on_setting_changed(key: String, value: float) -> void:
	if key != "display_mode":
		return
	_display_mode = clampi(roundi(value), 0, 1)
	_update_size()
