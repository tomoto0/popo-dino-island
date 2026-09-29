extends CanvasLayer

signal closed
const STYLE := preload("res://scripts/menu_style.gd")
var overlay: ColorRect
var panel: PanelContainer
var content: VBoxContainer
var scroll: ScrollContainer
var chrome: VBoxContainer
var _center: CenterContainer
var is_open := false
var _prior_pause := false
var _prior_focus: WeakRef
var cursor: Control

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 65
	overlay = ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Blurred, warm-vignetted veil over the scene instead of a flat dim.
	overlay.color = Color(0.16, 0.08, 0.04, 1.0)
	overlay.material = FeltKit.veil_material(0.5)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var center := CenterContainer.new()
	_center = center
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	panel = PanelContainer.new()
	STYLE.felt_card(panel, Color(1.0, 0.955, 0.86, 0.98), 24)
	center.add_child(panel)
	chrome = VBoxContainer.new()
	chrome.add_theme_constant_override("separation", 16)
	panel.add_child(chrome)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	chrome.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	scroll.add_child(content)
	get_viewport().size_changed.connect(_layout)
	content.minimum_size_changed.connect(_layout)
	overlay.hide()

func _layout() -> void:
	var reserved := 0.0
	_center.offset_bottom = -reserved
	var available := get_viewport().get_visible_rect().size - Vector2(24, 24 + reserved)
	var margin := 8 if available.y < 160.0 else 24
	panel.add_theme_stylebox_override("panel", STYLE.card(Color(1.0, 0.955, 0.86, 0.98), margin))
	# Hug the content: no tall empty plate under short lists.
	var chrome_h := float(margin * 2 + 64)
	var natural := content.get_combined_minimum_size().y + chrome_h
	var height := minf(minf(natural, 640.0), available.y)
	panel.custom_minimum_size = Vector2(minf(600.0, available.x), height)
	scroll.custom_minimum_size.y = maxf(12.0, height - chrome_h)

func heading(key: String) -> void:
	content.add_child(STYLE.ribbon(I18n.t(key), 38))

func add_close_button() -> Button:
	var button := STYLE.button(I18n.t("menu.close"))
	button.set_meta("audio_cue", "back")
	button.name = "CloseButton"
	button.pressed.connect(close_panel)
	chrome.add_child(button)
	_layout()
	return button

func open_panel() -> void:
	if is_open: return
	is_open = true
	_prior_pause = get_tree().paused
	_prior_focus = weakref(get_viewport().gui_get_focus_owner())
	get_tree().call_group("transient_input", "clear_input")
	get_tree().paused = true
	overlay.show()
	_layout()
	if cursor == null:
		cursor = FeltKit.YarnCursor.new()
		overlay.add_child(cursor)
	for control in panel.find_children("*", "BaseButton", true, false):
		cursor.track(control)
	var first := content.find_next_valid_focus()
	if first != null: first.grab_focus()
	pop_in(overlay, panel)

## Veil fades in while the felt plaque pops up with a soft overshoot.
static func pop_in(veil: CanvasItem, plaque: Control) -> void:
	if FeltKit.reduced_motion() or not plaque.is_inside_tree(): return
	veil.modulate.a = 0.0
	plaque.pivot_offset = plaque.size * 0.5
	plaque.scale = Vector2(0.86, 0.86)
	var tween := plaque.create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(veil, "modulate:a", 1.0, 0.18)
	tween.tween_property(plaque, "scale", Vector2.ONE, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Keep the pivot centred while containers settle the plaque's final size.
	tween.tween_method(func(_v: float): plaque.pivot_offset = plaque.size * 0.5, 0.0, 1.0, 0.34)

func close_panel() -> void:
	if not is_open: return
	is_open = false
	overlay.hide()
	get_tree().paused = _prior_pause
	get_tree().call_group("transient_input", "clear_input")
	var focused: Variant = _prior_focus.get_ref() if _prior_focus != null else null
	if is_instance_valid(focused) and focused is Control: focused.grab_focus()
	closed.emit()
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()
