extends Control
## World map: pick a world (◀ ▶) and one of its four stages. Shows lives, coins, medals,
## best scores, locks and cloud-save status.

const CATALOG = preload("res://scripts/stage_catalog.gd")
const MENU_STYLE = preload("res://scripts/menu_style.gd")
const SETTINGS = preload("res://scripts/settings_panel.gd")
const ICON_MEDAL = preload("res://assets/game/items/medal.webp")
const ICON_COIN = preload("res://assets/game/items/coin.webp")
const ICON_HERO = preload("res://assets/game/hero/idle.webp")
const WORLD_COLORS := [Color("#43a047"), Color("#ef8f1f"), Color("#3d6fb6"), Color("#35a9e0"), Color("#7b4fb3"), Color("#c0392b")]

var world := 1
var bg: TextureRect
var world_title: Label
var grid: GridContainer
var prev_button: Button
var next_button: Button
var status_label: Label
var info_row: HBoxContainer
var _settings: CanvasLayer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	GameAudio.select_track(&"map")
	GameAudio.begin_title()
	var current := CATALOG.index_of(SaveStore.selected_stage)
	if current < 0 or not SaveStore.is_unlocked(current):
		current = mini(SaveStore.unlocked_count(), CATALOG.stage_count()) - 1
	world = clampi(current / 4 + 1, 1, 6)
	_build()
	SaveStore.cloud_status_changed.connect(_on_cloud_status)
	get_viewport().size_changed.connect(_layout)
	_show_world(world, current)
	_on_cloud_status(SaveStore.cloud_status, "")


func _build() -> void:
	bg = TextureRect.new()
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.08, 0.2, 0.25)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	scroll.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	# Top info bar
	info_row = HBoxContainer.new()
	info_row.add_theme_constant_override("separation", 8)
	column.add_child(info_row)
	# World header
	var header := HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", 14)
	column.add_child(header)
	prev_button = _arrow_button("◀")
	prev_button.name = "PrevWorld"
	prev_button.pressed.connect(_change_world.bind(-1))
	header.add_child(prev_button)
	world_title = Label.new()
	world_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	world_title.custom_minimum_size = Vector2(360, 0)
	MENU_STYLE.display(world_title, 38, Color("#fff4c2"), Color("#1d2a5a"), 12)
	header.add_child(world_title)
	next_button = _arrow_button("▶")
	next_button.name = "NextWorld"
	next_button.pressed.connect(_change_world.bind(1))
	header.add_child(next_button)
	# Stage cards
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(center)
	grid = GridContainer.new()
	grid.name = "StageGrid"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	center.add_child(grid)
	# Footer
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 12)
	column.add_child(footer)
	var back := MENU_STYLE.button("タイトルへ", false)
	back.name = "TitleButton"
	back.custom_minimum_size = Vector2(170, 48)
	back.pressed.connect(_to_title)
	footer.add_child(back)
	var settings := MENU_STYLE.button("設定", false)
	settings.custom_minimum_size = Vector2(130, 48)
	settings.pressed.connect(_open_settings)
	footer.add_child(settings)
	status_label = _outlined("", 14)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(status_label)
	_refresh_info()
	_layout()


func _outlined(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", MENU_STYLE.BOLD)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.15, 0.95))
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _chip(items: Array) -> void:
	var chip := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.12, 0.25, 0.7)
	style.border_color = Color(1, 1, 1, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left = 10
	style.content_margin_right = 12
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	chip.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	chip.add_child(row)
	for item in items:
		row.add_child(item)
	info_row.add_child(chip)


func _icon(texture: Texture2D, size: float) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = texture
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(size, size)
	return icon


func _refresh_info() -> void:
	for c in info_row.get_children():
		c.queue_free()
	_chip([_outlined(("プレイヤー：%s" % SaveStore.username) if not SaveStore.is_guest() else "ゲスト（この端末にセーブ）", 17)])
	_chip([_icon(ICON_HERO, 28), _outlined("×%d" % SaveStore.lives(), 18)])
	_chip([_icon(ICON_COIN, 24), _outlined("×%02d" % SaveStore.coins(), 18)])
	_chip([_icon(ICON_MEDAL, 24), _outlined("%d / %d" % [SaveStore.medal_total(), CATALOG.stage_count() * 3], 18)])
	_chip([_outlined("クリア %d / %d" % [SaveStore.cleared_count(), CATALOG.stage_count()], 17)])


func _arrow_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(56, 52)
	b.add_theme_font_override("font", MENU_STYLE.BOLD)
	b.add_theme_font_size_override("font_size", 24)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(1, 1, 1, 0.92) if state != "disabled" else Color(1, 1, 1, 0.35)
		if state == "hover" or state == "focus":
			s.bg_color = Color("#fff4c2")
		s.border_color = Color("#1d2a5a")
		s.set_border_width_all(3)
		s.set_corner_radius_all(26)
		b.add_theme_stylebox_override(state, s)
	b.add_theme_color_override("font_color", Color("#1d2a5a"))
	b.add_theme_color_override("font_hover_color", Color("#1d2a5a"))
	b.add_theme_color_override("font_focus_color", Color("#1d2a5a"))
	b.add_theme_color_override("font_pressed_color", Color("#1d2a5a"))
	return b


func _layout() -> void:
	var size := get_viewport_rect().size
	grid.columns = 4 if size.x >= 1000 else 2
	world_title.custom_minimum_size.x = clampf(size.x - 200.0, 200.0, 460.0)
	world_title.add_theme_font_size_override("font_size", 38 if size.x >= 700 else 26)
	var margin: MarginContainer = get_node("Scroll/Margin")
	margin.custom_minimum_size = size


func _change_world(delta: int) -> void:
	var target := clampi(world + delta, 1, 6)
	if target == world:
		return
	GameAudio.play_ui(&"ui_selection")
	_show_world(target, -1)


func _show_world(value: int, focus_index: int) -> void:
	world = value
	var worlds := CATALOG.worlds()
	var info: Dictionary = worlds[world - 1] if world - 1 < worlds.size() else {"name": "?"}
	bg.texture = load("res://assets/game/backgrounds/world_%d.webp" % world)
	world_title.text = "ワールド%d  %s" % [world, info.get("name", "")]
	prev_button.disabled = world <= 1
	next_button.disabled = world >= 6
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	var ids := CATALOG.stages()
	var focus_target: Button = null
	for i in 4:
		var index := (world - 1) * 4 + i
		if index >= ids.size():
			break
		var card := _stage_card(ids[index], index)
		grid.add_child(card)
		if index == focus_index or (focus_target == null and not card.disabled and focus_index < 0):
			focus_target = card
		if index == focus_index:
			focus_target = card
	if focus_target == null and grid.get_child_count() > 0:
		focus_target = prev_button if not prev_button.disabled else next_button
	if focus_target != null:
		focus_target.grab_focus.call_deferred()


func _stage_card(id: String, index: int) -> Button:
	var stage := CATALOG.load_stage(id)
	var unlocked := SaveStore.is_unlocked(index)
	var record := SaveStore.stage_record(id)
	var color: Color = WORLD_COLORS[(world - 1) % WORLD_COLORS.size()]
	var card := Button.new()
	card.name = "Stage_%s" % id
	card.custom_minimum_size = Vector2(210, 190)
	card.disabled = not unlocked
	card.focus_mode = Control.FOCUS_ALL
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var s := StyleBoxFlat.new()
		s.bg_color = color if state != "disabled" else Color(0.35, 0.37, 0.45, 0.85)
		if state == "hover" or state == "focus":
			s.bg_color = color.lightened(0.18)
		s.border_color = Color.WHITE if state in ["hover", "focus"] else Color(1, 1, 1, 0.55)
		s.set_border_width_all(5 if state in ["hover", "focus"] else 3)
		s.set_corner_radius_all(20)
		s.shadow_color = Color(0, 0, 0, 0.35)
		s.shadow_size = 6
		s.shadow_offset = Vector2(0, 4)
		card.add_theme_stylebox_override(state, s)
	card.pressed.connect(_start_stage.bind(id))
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 10
	box.offset_right = -10
	box.offset_top = 10
	box.offset_bottom = -10
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var label := _outlined(str(stage.get("label", "")), 34)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	var name_label := _outlined(str(stage.get("name", "")) if unlocked else "？？？", 16)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(name_label)
	if stage.has("boss") and unlocked:
		var boss := _outlined("ボス戦", 14)
		boss.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		boss.add_theme_color_override("font_color", Color("#ffd35a"))
		box.add_child(boss)
	var medals := HBoxContainer.new()
	medals.alignment = BoxContainer.ALIGNMENT_CENTER
	medals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(medals)
	for m in 3:
		var icon := _icon(ICON_MEDAL, 26)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.modulate = Color.WHITE if record.medals[m] else Color(0.1, 0.1, 0.2, 0.45)
		medals.add_child(icon)
	var foot := "ロック中" if not unlocked else ("ベスト %d" % int(record.best) if record.cleared else "NEW！")
	var foot_label := _outlined(foot, 15)
	foot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if record.cleared:
		foot_label.add_theme_color_override("font_color", Color("#fff4c2"))
	box.add_child(foot_label)
	return card


func _start_stage(id: String) -> void:
	SaveStore.selected_stage = id
	GameAudio.play_ui(&"confirm")
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _to_title() -> void:
	get_tree().change_scene_to_file("res://scenes/title_screen.tscn")


func _open_settings() -> void:
	if is_instance_valid(_settings):
		return
	_settings = SETTINGS.new()
	add_child(_settings)
	_settings.open_panel()


func _on_cloud_status(status: String, _detail: String) -> void:
	if status_label == null:
		return
	match status:
		"syncing": status_label.text = "クラウドと同期中…"
		"synced": status_label.text = "クラウドセーブ：最新です"
		"error": status_label.text = "クラウドにつながりません（この端末には保存されています）"
		"expired": status_label.text = "ログインの有効期限が切れました。タイトルから再ログインしてください"
		_: status_label.text = "ゲストモード：進みぐあいはこの端末に保存されます" if SaveStore.is_guest() else ""
	if status == "synced":
		_refresh_info()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not is_instance_valid(_settings):
		_to_title()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Q or event.keycode == KEY_PAGEUP:
			_change_world(-1)
		elif event.keycode == KEY_E or event.keycode == KEY_PAGEDOWN:
			_change_world(1)
