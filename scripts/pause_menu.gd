extends CanvasLayer

signal main_menu_requested
signal restart_requested
const STYLE := preload("res://scripts/menu_style.gd")
const SETTINGS := preload("res://scripts/settings_panel.gd")
const MENU_MODAL := preload("res://scripts/menu_modal.gd")
var overlay: ColorRect
var panel: PanelContainer
var resume_button: Button
var menu_button: Button
var restart_button: Button
var is_open := false
var _prior_pause := false
var _prior_focus: WeakRef
var _confirm: VBoxContainer
var _actions: VBoxContainer
var _pending: StringName
var _settings: CanvasLayer
var _scroll: ScrollContainer
var _center: CenterContainer
var _content: VBoxContainer
var _cursor: Control

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 40
	_build_ui()

func _build_ui() -> void:
	overlay = ColorRect.new()
	overlay.name = "PauseOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.16, 0.08, 0.04, 1.0)
	overlay.material = FeltKit.veil_material(0.48)
	add_child(overlay)
	var center := CenterContainer.new()
	_center = center
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	panel = PanelContainer.new()
	panel.name = "PausePanel"
	panel.custom_minimum_size = Vector2(460, 0)
	STYLE.felt_card(panel, Color(1.0, 0.955, 0.86, 0.98), 24)
	center.add_child(panel)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	panel.add_child(_scroll)
	var content := VBoxContainer.new()
	_content = content
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 16)
	_scroll.add_child(content)
	var heading := STYLE.ribbon(I18n.t("pause.title"), 44)
	content.add_child(heading)
	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", 10)
	content.add_child(_actions)
	resume_button = STYLE.button(I18n.t("pause.resume"), true)
	resume_button.name = "ResumeButton"
	resume_button.custom_minimum_size.y = 56
	resume_button.pressed.connect(close_menu)
	_actions.add_child(resume_button)
	restart_button = STYLE.button(I18n.t("pause.restart"))
	restart_button.pressed.connect(func(): _ask_loss(&"restart"))
	_actions.add_child(restart_button)
	var settings := STYLE.button(I18n.t("settings.title"))
	settings.pressed.connect(_open_settings)
	_actions.add_child(settings)
	menu_button = STYLE.button(I18n.t("pause.menu"))
	menu_button.name = "MainMenuButton"
	menu_button.pressed.connect(_request_main_menu)
	_actions.add_child(menu_button)
	_confirm = VBoxContainer.new()
	_confirm.add_theme_constant_override("separation", 14)
	content.add_child(_confirm)
	var warning := STYLE.label(I18n.t("pause.confirm_loss"), 19)
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm.add_child(warning)
	var confirm := STYLE.button(I18n.t("menu.confirm"), true)
	confirm.name = "ConfirmLoss"
	confirm.pressed.connect(_confirm_loss)
	_confirm.add_child(confirm)
	var cancel := STYLE.button(I18n.t("menu.cancel"))
	cancel.pressed.connect(_cancel_loss)
	_confirm.add_child(cancel)
	# Secondary actions read as a menu list under the yarn-ball cursor.
	for item in _actions.get_children() + [cancel]:
		if item != resume_button: STYLE.menu_item(item)
	menu_button.set_meta("audio_cue", "back")
	_cursor = FeltKit.YarnCursor.new()
	overlay.add_child(_cursor)
	for item in panel.find_children("*", "Button", true, false):
		_cursor.track(item)
	_confirm.hide()
	overlay.hide()
	get_viewport().size_changed.connect(_layout)
	content.minimum_size_changed.connect(_layout)
	_layout()

func _layout() -> void:
	var reserved := 0.0
	_center.offset_bottom = -reserved
	var available := get_viewport().get_visible_rect().size - Vector2(24, 24 + reserved)
	# Size the card to its buttons instead of a fixed tall plate.
	var natural := _content.get_combined_minimum_size().y + 48.0
	panel.custom_minimum_size = Vector2(minf(420.0, available.x), minf(natural, available.y))
	_scroll.custom_minimum_size.y = maxf(12.0, minf(natural, available.y) - 48.0)

func toggle_menu() -> void:
	if is_open: close_menu()
	else: open_menu()

func open_menu() -> void:
	if is_open: return
	_prior_pause = get_tree().paused
	_prior_focus = weakref(get_viewport().gui_get_focus_owner())
	get_tree().call_group("transient_input", "clear_input")
	is_open = true
	get_tree().paused = true
	overlay.show()
	_cancel_loss()
	MENU_MODAL.pop_in(overlay, panel)

func close_menu() -> void:
	if not is_open: return
	is_open = false
	overlay.hide()
	get_tree().paused = _prior_pause
	get_tree().call_group("transient_input", "clear_input")
	var focused: Variant = _prior_focus.get_ref() if _prior_focus != null else null
	if is_instance_valid(focused) and focused is Control: focused.grab_focus()

func _open_settings() -> void:
	if is_instance_valid(_settings): return
	_settings = SETTINGS.new()
	add_child(_settings)
	_settings.open_panel()

func _request_main_menu() -> void:
	_ask_loss(&"title")

func _ask_loss(action: StringName) -> void:
	_pending = action
	_actions.hide()
	_confirm.show()
	_confirm.get_child(2).grab_focus()

func _cancel_loss() -> void:
	_confirm.hide()
	_actions.show()
	resume_button.grab_focus()

func _confirm_loss() -> void:
	close_menu()
	if _pending == &"restart": restart_requested.emit()
	else: main_menu_requested.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not is_open or is_instance_valid(_settings): return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		if _confirm.visible: _cancel_loss()
		else: close_menu()
		get_viewport().set_input_as_handled()
