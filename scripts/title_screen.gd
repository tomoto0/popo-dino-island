extends Control
## Title: register (username + password only), log in, or play as a guest. Accounts sync
## progress to the Manus database; guests save on this device.

const OpenSourceLicenses = preload("res://scripts/manus/open_source_licenses.gd")
const MENU_STYLE = preload("res://scripts/menu_style.gd")
const BG = preload("res://assets/game/backgrounds/world_1.webp")
const HERO = preload("res://assets/game/hero/idle.webp")
const HERO_JUMP = preload("res://assets/game/hero/flutter.webp")

var mode := "register"   # register | login
var card_box: VBoxContainer
var name_edit: LineEdit
var pass_edit: LineEdit
var status_label: Label
var submit_button: Button
var busy := false
var hero_rect: TextureRect
var t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	GameAudio.select_track(&"map")
	GameAudio.begin_title()
	_build()
	get_viewport().size_changed.connect(_layout)
	_layout()
	if SaveStore.has_saved_session():
		_show_welcome()
	else:
		_show_form()


func _build() -> void:
	var bg := TextureRect.new()
	bg.texture = BG
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var shade := ColorRect.new()
	shade.color = Color(0.1, 0.15, 0.35, 0.18)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	var center := CenterContainer.new()
	center.name = "Center"
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var root := HBoxContainer.new()
	root.name = "Root"
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 36)
	center.add_child(root)
	var left := VBoxContainer.new()
	left.name = "Brand"
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_theme_constant_override("separation", 4)
	root.add_child(left)
	var logo := Label.new()
	logo.name = "Logo"
	logo.text = "ポポの\nダイノアイランド"
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MENU_STYLE.display(logo, 64, Color("#fff4c2"), Color("#b3261e"), 16)
	left.add_child(logo)
	var sub := Label.new()
	sub.text = "6つのワールド・24ステージの大冒険！"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MENU_STYLE.display(sub, 22, Color.WHITE, Color("#1d2a5a"), 8)
	left.add_child(sub)
	hero_rect = TextureRect.new()
	hero_rect.texture = HERO
	hero_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hero_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hero_rect.custom_minimum_size = Vector2(170, 190)
	hero_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(hero_rect)
	var card := PanelContainer.new()
	card.name = "Card"
	MENU_STYLE.felt_card(card, MENU_STYLE.CREAM, 22)
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	root.add_child(card)
	card_box = VBoxContainer.new()
	card_box.add_theme_constant_override("separation", 9)
	card_box.custom_minimum_size = Vector2(380, 0)
	card.add_child(card_box)
	var licenses := MENU_STYLE.quiet_button("ライセンス")
	licenses.name = "OpenSourceLicensesButton"
	licenses.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	licenses.offset_left = 10
	licenses.offset_top = -44
	licenses.offset_bottom = -8
	licenses.pressed.connect(OpenSourceLicenses.open.bind(self))
	add_child(licenses)


func _layout() -> void:
	var size := get_viewport_rect().size
	var narrow := size.x < 860 or size.x < size.y
	var brand: VBoxContainer = get_node("Scroll/Center/Root/Brand")
	var logo: Label = brand.get_node("Logo")
	logo.add_theme_font_size_override("font_size", 40 if narrow else 64)
	hero_rect.visible = size.y > 560 and not narrow
	brand.visible = not narrow or size.x > 700
	card_box.custom_minimum_size = Vector2(minf(380.0, size.x - 70.0), 0)
	var center: CenterContainer = get_node("Scroll/Center")
	center.custom_minimum_size = size


func _process(delta: float) -> void:
	t += delta
	if hero_rect != null and hero_rect.visible:
		hero_rect.texture = HERO_JUMP if fmod(t, 2.4) > 1.9 else HERO
		hero_rect.pivot_offset = hero_rect.size * Vector2(0.5, 1.0)
		hero_rect.scale = Vector2(1.0, 1.0 + sin(t * 3.0) * 0.02)


func _clear_card() -> void:
	for child in card_box.get_children():
		card_box.remove_child(child)
		child.queue_free()


func _title(text: String) -> void:
	var h := MENU_STYLE.heading(text, 30)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_box.add_child(h)


func _note(text: String, size: int = 15) -> Label:
	var l := MENU_STYLE.label(text, size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_box.add_child(l)
	return l


func _show_welcome() -> void:
	_clear_card()
	_title("おかえりなさい！")
	_note("%s さんのセーブデータ" % SaveStore.username, 18)
	var progress := _note("クリア %d / 24 ステージ　メダル %d / 72" % [SaveStore.cleared_count(), SaveStore.medal_total()], 16)
	progress.add_theme_color_override("font_color", MENU_STYLE.MUTED)
	status_label = _note("", 14)
	var go := MENU_STYLE.button("つづきからあそぶ", true)
	go.name = "ContinueButton"
	go.custom_minimum_size = Vector2(0, 56)
	go.pressed.connect(_continue_session)
	card_box.add_child(go)
	var other := MENU_STYLE.quiet_button("別のアカウント／ログアウト")
	other.pressed.connect(_logout)
	card_box.add_child(other)
	go.grab_focus()


func _show_form() -> void:
	_clear_card()
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	card_box.add_child(tabs)
	var tab_register := MENU_STYLE.button("はじめて", mode == "register")
	var tab_login := MENU_STYLE.button("ログイン", mode == "login")
	tab_register.name = "RegisterTab"
	tab_login.name = "LoginTab"
	for b in [tab_register, tab_login]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 44)
		tabs.add_child(b)
	tab_register.pressed.connect(_set_mode.bind("register"))
	tab_login.pressed.connect(_set_mode.bind("login"))
	_note("ユーザー名とパスワードを決めるだけで、すぐにあそべます。メールアドレスは不要です。" if mode == "register" else "登録したユーザー名とパスワードを入れてください。", 15)
	card_box.add_child(MENU_STYLE.label("ユーザー名（半角英数字と _ 、3〜16文字）", 15))
	name_edit = _line_edit("例：popo_fan", false)
	name_edit.name = "UsernameField"
	card_box.add_child(name_edit)
	card_box.add_child(MENU_STYLE.label("パスワード（半角6文字以上）", 15))
	pass_edit = _line_edit("6文字以上", true)
	pass_edit.name = "PasswordField"
	card_box.add_child(pass_edit)
	name_edit.text_submitted.connect(_on_name_submitted)
	pass_edit.text_submitted.connect(_on_pass_submitted)
	status_label = _note("", 14)
	status_label.name = "StatusLabel"
	status_label.add_theme_color_override("font_color", MENU_STYLE.ACCENT)
	submit_button = MENU_STYLE.button("登録してはじめる" if mode == "register" else "ログインしてはじめる", true)
	submit_button.name = "SubmitButton"
	submit_button.custom_minimum_size = Vector2(0, 56)
	submit_button.pressed.connect(_submit)
	card_box.add_child(submit_button)
	var guest := MENU_STYLE.quiet_button("ゲストであそぶ（この端末にだけセーブ）")
	guest.name = "GuestButton"
	guest.pressed.connect(_play_guest)
	card_box.add_child(guest)
	if not SaveStore.online_available():
		status_label.text = "この画面ではオンライン機能を使えません。ゲストであそべます。"
	if not DisplayServer.is_touchscreen_available():
		name_edit.grab_focus()


func _on_name_submitted(_text: String) -> void:
	pass_edit.grab_focus()


func _on_pass_submitted(_text: String) -> void:
	_submit()


func _line_edit(placeholder: String, secret: bool) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.secret = secret
	edit.max_length = 64 if secret else 16
	edit.custom_minimum_size = Vector2(0, 46)
	edit.add_theme_font_size_override("font_size", 20)
	edit.add_theme_font_override("font", MENU_STYLE.MEDIUM)
	edit.add_theme_color_override("font_color", MENU_STYLE.INK)
	edit.add_theme_color_override("font_placeholder_color", Color(MENU_STYLE.MUTED, 0.55))
	edit.add_theme_color_override("caret_color", MENU_STYLE.ACCENT)
	edit.add_theme_color_override("selection_color", Color(MENU_STYLE.ACCENT, 0.3))
	for state in ["normal", "focus", "read_only"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color.WHITE if state != "read_only" else MENU_STYLE.WOOL
		box.border_color = MENU_STYLE.ACCENT if state == "focus" else MENU_STYLE.STITCH
		box.set_border_width_all(3 if state == "focus" else 2)
		box.set_corner_radius_all(12)
		box.content_margin_left = 14
		box.content_margin_right = 14
		box.content_margin_top = 6
		box.content_margin_bottom = 6
		if state == "focus":
			box.draw_center = false
		edit.add_theme_stylebox_override(state, box)
	edit.virtual_keyboard_enabled = true
	edit.focus_entered.connect(_maybe_prompt.bind(edit))
	return edit


## Mobile browsers cannot always raise the keyboard for canvas text fields; fall back to a
## native prompt so touch players can still type.
func _maybe_prompt(edit: LineEdit) -> void:
	if not OS.has_feature("web") or not DisplayServer.is_touchscreen_available():
		return
	var label := "パスワード（半角6文字以上）" if edit.secret else "ユーザー名（半角英数字と _ 、3〜16文字）"
	var value: Variant = JavaScriptBridge.eval("window.prompt(%s, %s)" % [JSON.stringify(label), JSON.stringify("" if edit.secret else edit.text)], true)
	if value is String:
		edit.text = (value as String).strip_edges()
	edit.release_focus()


func _set_mode(value: String) -> void:
	if busy:
		return
	mode = value
	_show_form()


func _submit() -> void:
	if busy:
		return
	var name := name_edit.text.strip_edges()
	var password := pass_edit.text
	if not SaveStore.valid_username(name):
		status_label.text = SaveStore.error_text("invalid_username")
		return
	if not SaveStore.valid_password(password):
		status_label.text = SaveStore.error_text("invalid_password")
		return
	busy = true
	submit_button.disabled = true
	status_label.add_theme_color_override("font_color", MENU_STYLE.MUTED)
	status_label.text = "通信中…"
	var result: Dictionary
	if mode == "register":
		result = await SaveStore.register(name, password)
	else:
		result = await SaveStore.login(name, password)
	busy = false
	if not is_inside_tree():
		return
	submit_button.disabled = false
	if result.get("ok", false):
		_go_map()
		return
	status_label.add_theme_color_override("font_color", MENU_STYLE.ACCENT)
	status_label.text = SaveStore.error_text(str(result.get("error", "")))


func _continue_session() -> void:
	if busy:
		return
	busy = true
	status_label.text = "セーブデータを読みこみ中…"
	var result: Dictionary = await SaveStore.resume_session()
	busy = false
	if not is_inside_tree():
		return
	if not result.get("ok", false):
		var remembered := SaveStore.username
		mode = "login"
		_show_form()
		status_label.text = SaveStore.error_text("session_invalid")
		name_edit.text = remembered
		return
	_go_map()


func _logout() -> void:
	if busy:
		return
	busy = true
	await SaveStore.logout()
	busy = false
	if is_inside_tree():
		mode = "login"
		_show_form()


func _play_guest() -> void:
	SaveStore.play_as_guest()
	_go_map()


func _go_map() -> void:
	GameAudio.play_ui(&"confirm")
	get_tree().change_scene_to_file("res://scenes/world_map.tscn")
