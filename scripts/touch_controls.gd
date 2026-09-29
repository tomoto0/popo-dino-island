extends Control
## Multi-touch controls: left side = floating horizontal stick, right side = JUMP (hold to
## flutter) and EGG buttons. Raw InputEventScreenTouch handling so both thumbs work at once.

const EGG_ICON = preload("res://assets/game/items/egg.webp")
const STICK_RADIUS := 64.0
const DEAD_ZONE := 0.18

var move_x := 0.0
var jump_held := false
var _jump_pressed := false
var _attack_pressed := false
var _stick_index := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _jump_index := -1
var _egg_index := -1
var _egg_flash := 0.0
var enabled := true
var touch_seen := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("transient_input")
	touch_seen = DisplayServer.is_touchscreen_available()
	visible = touch_seen
	get_viewport().size_changed.connect(clear_input)


func consume_jump() -> bool:
	var value := _jump_pressed
	_jump_pressed = false
	return value


func consume_attack() -> bool:
	var value := _attack_pressed
	_attack_pressed = false
	return value


func clear_input() -> void:
	move_x = 0.0
	jump_held = false
	_jump_pressed = false
	_attack_pressed = false
	_stick_index = -1
	_jump_index = -1
	_egg_index = -1
	queue_redraw()


func _jump_center() -> Vector2:
	var s := size
	var r := _button_radius()
	return Vector2(s.x - r - 28.0, s.y - r - 28.0)


func _egg_center() -> Vector2:
	var s := size
	var r := _button_radius()
	return Vector2(s.x - r * 3.1 - 34.0, s.y - r * 0.8 - 30.0)


func _button_radius() -> float:
	return clampf(minf(size.x, size.y) * 0.11, 40.0, 64.0)


func _input(event: InputEvent) -> void:
	if not enabled or get_tree().paused:
		return
	if event is InputEventScreenTouch:
		if not touch_seen:
			touch_seen = true
			visible = true
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_press(touch.index, touch.position)
		else:
			_release(touch.index)
		queue_redraw()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _stick_index:
			_stick_pos = drag.position
			var dx := (_stick_pos.x - _stick_origin.x) / STICK_RADIUS
			move_x = 0.0 if absf(dx) < DEAD_ZONE else clampf(dx, -1.0, 1.0)
			queue_redraw()


func _press(index: int, pos: Vector2) -> void:
	# Leave the top HUD strip (pause button) to the regular GUI.
	if pos.y < 84.0:
		return
	var r := _button_radius()
	if pos.distance_to(_egg_center()) < r * 1.25:
		_egg_index = index
		_attack_pressed = true
		_egg_flash = 1.0
		return
	if pos.x > size.x * 0.5:
		_jump_index = index
		jump_held = true
		_jump_pressed = true
		return
	if _stick_index == -1:
		_stick_index = index
		_stick_origin = pos
		_stick_pos = pos
		move_x = 0.0


func _release(index: int) -> void:
	if index == _stick_index:
		_stick_index = -1
		move_x = 0.0
	if index == _jump_index:
		_jump_index = -1
		jump_held = false
	if index == _egg_index:
		_egg_index = -1


func _process(delta: float) -> void:
	if _egg_flash > 0.0:
		_egg_flash = maxf(0.0, _egg_flash - delta * 4.0)
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		clear_input()


func _draw() -> void:
	if not touch_seen:
		return
	var r := _button_radius()
	var font := get_theme_default_font()
	# Stick
	if _stick_index != -1:
		draw_circle(_stick_origin, STICK_RADIUS, Color(1, 1, 1, 0.18))
		draw_arc(_stick_origin, STICK_RADIUS, 0, TAU, 40, Color(1, 1, 1, 0.55), 3.0)
		var knob := _stick_origin + Vector2(clampf(_stick_pos.x - _stick_origin.x, -STICK_RADIUS, STICK_RADIUS), 0)
		draw_circle(knob, 26.0, Color(1, 1, 1, 0.6))
	else:
		var hint := Vector2(96, size.y - 96)
		draw_arc(hint, STICK_RADIUS * 0.8, 0, TAU, 40, Color(1, 1, 1, 0.3), 3.0)
		draw_string(font, hint + Vector2(-44, 8), "◀  ▶", HORIZONTAL_ALIGNMENT_CENTER, 88, 22, Color(1, 1, 1, 0.55))
	# Jump button
	var jc := _jump_center()
	draw_circle(jc, r, Color(0.2, 0.75, 0.3, 0.55 if jump_held else 0.36))
	draw_arc(jc, r, 0, TAU, 48, Color(1, 1, 1, 0.8), 4.0)
	draw_string(font, jc + Vector2(-r, 8), "ジャンプ", HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 18, Color(1, 1, 1, 0.95))
	# Egg button
	var ec := _egg_center()
	var er := r * 0.78
	draw_circle(ec, er, Color(0.95, 0.55, 0.2, 0.36 + _egg_flash * 0.3))
	draw_arc(ec, er, 0, TAU, 40, Color(1, 1, 1, 0.8), 4.0)
	var icon := er * 1.0
	draw_texture_rect(EGG_ICON, Rect2(ec - Vector2(icon * 0.4, icon * 0.5), Vector2(icon * 0.8, icon)), false, Color(1, 1, 1, 0.9))
