extends "res://scripts/menu_modal.gd"

var _display_tabs: Array[Button] = []

func _ready() -> void:
	super._ready()
	heading("settings.title")
	for bus: StringName in [&"Master", &"Music", &"SFX", &"UI"]:
		var group := VBoxContainer.new()
		group.add_theme_constant_override("separation", 0)
		content.add_child(group)
		var caption := STYLE.label(I18n.t("settings.audio." + String(bus).to_lower()), 17)
		caption.add_theme_font_override("font", STYLE.BOLD)
		caption.add_theme_color_override("font_color", STYLE.COCOA)
		group.add_child(caption)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		group.add_child(row)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.value = GameAudio.get_bus_volume(bus)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.custom_minimum_size = Vector2(100, 48)
		slider.accessibility_name = caption.text
		_style_slider(slider)
		slider.value_changed.connect(func(value: float): GameAudio.set_bus_volume(bus, value))
		row.add_child(slider)
		var mute := CheckButton.new()
		mute.text = I18n.t("settings.mute")
		mute.button_pressed = GameAudio.is_bus_muted(bus)
		mute.custom_minimum_size.y = 48
		_style_toggle(mute)
		mute.toggled.connect(func(value: bool): GameAudio.set_bus_muted(bus, value))
		row.add_child(mute)
	var motion := CheckButton.new()
	motion.text = I18n.t("settings.reduced_motion")
	motion.custom_minimum_size.y = 48
	_style_toggle(motion)
	motion.button_pressed = TuningStore.get_player_setting("reduced_motion") > 0.5
	motion.toggled.connect(func(value: bool): TuningStore.set_player_setting("reduced_motion", 1.0 if value else 0.0))
	content.add_child(motion)
	var display_caption := STYLE.label(I18n.t("settings.display"), 17)
	display_caption.add_theme_font_override("font", STYLE.BOLD)
	display_caption.add_theme_color_override("font_color", STYLE.COCOA)
	content.add_child(display_caption)
	# Felt segmented tabs replace the stock dropdown; same setting, same values.
	var tabs := GridContainer.new()
	tabs.name = "DisplayTabs"
	tabs.columns = 2
	tabs.add_theme_constant_override("h_separation", 8)
	tabs.add_theme_constant_override("v_separation", 8)
	content.add_child(tabs)
	var group := ButtonGroup.new()
	var current := int(TuningStore.get_player_setting("display_mode"))
	for index in 2:
		var tab := STYLE.button(I18n.t("tuning.display.fixed" if index == 0 else "tuning.display.adaptive"))
		tab.toggle_mode = true
		tab.button_group = group
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tab.add_theme_font_size_override("font_size", 15)
		FeltKit.felt_button(tab, &"tab", STYLE.WOOL, STYLE.STITCH, 14.0, 12.0)
		for key in ["font_pressed_color", "font_hover_pressed_color"]:
			tab.add_theme_color_override(key, Color("#fff4dd"))
		tab.set_pressed_no_signal(index == current)
		tab.pressed.connect(func(): TuningStore.set_player_setting("display_mode", float(index)))
		tabs.add_child(tab)
		_display_tabs.append(tab)
	get_viewport().size_changed.connect(func(): tabs.columns = 1 if get_viewport().get_visible_rect().size.x < 560.0 else 2)
	tabs.columns = 1 if get_viewport().get_visible_rect().size.x < 560.0 else 2
	add_close_button()


## Felt track with a tomato wool fill and the game's yarn ball as the grabber.
func _style_slider(slider: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color("#ead3aa")
	track.border_color = Color(STYLE.STITCH, 0.7)
	track.set_border_width_all(2)
	track.set_corner_radius_all(8)
	track.content_margin_top = 7
	track.content_margin_bottom = 7
	track.shadow_color = Color(0.2, 0.08, 0.02, 0.18)
	track.shadow_size = 2
	track.shadow_offset = Vector2(0, 1)
	slider.add_theme_stylebox_override("slider", track)
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = STYLE.ACCENT
	fill.border_color = Color("#9b3520")
	fill.shadow_size = 0
	slider.add_theme_stylebox_override("grabber_area", fill)
	var fill_hover := fill.duplicate() as StyleBoxFlat
	fill_hover.bg_color = STYLE.ACCENT.lightened(0.1)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill_hover)
	for icon in ["grabber", "grabber_highlight"]:
		slider.add_theme_icon_override(icon, FeltKit.yarn_icon(34 if icon == "grabber_highlight" else 30))
	slider.add_theme_icon_override("grabber_disabled", FeltKit.yarn_icon(30))
	slider.material = FeltKit.felt_material()
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = STYLE.INK
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(12)
	focus.set_expand_margin_all(4)
	slider.add_theme_stylebox_override("focus", focus)


## Felt switch: a stitched track with a sewn-button knob (drawn icons, no files).
func _style_toggle(toggle: CheckButton) -> void:
	toggle.add_theme_font_size_override("font_size", 18)
	toggle.add_theme_font_override("font", STYLE.MEDIUM)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		toggle.add_theme_color_override(key, STYLE.INK)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var box := StyleBoxEmpty.new()
		box.content_margin_left = 6
		box.content_margin_right = 6
		toggle.add_theme_stylebox_override(state, box)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = STYLE.INK
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(14)
	focus.set_expand_margin_all(2)
	toggle.add_theme_stylebox_override("focus", focus)
	for icon in ["checked", "checked_disabled", "unchecked", "unchecked_disabled", "checked_mirrored", "unchecked_mirrored", "checked_disabled_mirrored", "unchecked_disabled_mirrored"]:
		toggle.add_theme_icon_override(icon, _switch_icon(icon.begins_with("checked")))


static var _switch_cache: Dictionary = {}

static func _switch_icon(on: bool) -> Texture2D:
	if _switch_cache.has(on): return _switch_cache[on]
	var w := 58
	var h := 32
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var track := STYLE.ACCENT if on else Color("#cdb592")
	var knob_c := Vector2(w - 16.0, 16.0) if on else Vector2(16.0, 16.0)
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var color := Color(0, 0, 0, 0)
			# Pill track (capsule SDF) with a darker rim.
			var q := Vector2(clampf(p.x, 16.0, w - 16.0), 16.0)
			var d := p.distance_to(q) - 12.0
			if d < 1.0:
				var rim := d > -2.5
				color = (track.darkened(0.25) if rim else track)
				color.a = clampf(1.0 - d, 0.0, 1.0)
				# Running stitch along the track centre line.
				if not on and absf(p.y - 16.0) < 0.9 and int(p.x) % 7 < 4 and p.x > 22 and p.x < w - 22:
					color = Color("#fff4dd")
			var kd := p.distance_to(knob_c) - 11.0
			if kd < 1.0:
				var knob := Color("#fff4dd").lerp(Color("#e9d2ad"), clampf((p.y - 8.0) / 16.0, 0.0, 1.0))
				if kd > -1.8: knob = Color("#b67c51")
				for hole: Vector2 in [Vector2(-3, -3), Vector2(3, -3), Vector2(-3, 3), Vector2(3, 3)]:
					if p.distance_to(knob_c + hole) < 1.5: knob = Color("#6b3a24")
				knob.a = clampf(1.0 - kd, 0.0, 1.0)
				color = color.blend(knob) if color.a > 0.0 else knob
			image.set_pixel(x, y, color)
	var texture := ImageTexture.create_from_image(image)
	_switch_cache[on] = texture
	return texture
