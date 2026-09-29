extends RefCounted
## Felted-wool UI kit (materials drawn by felt_kit.gd): cream felt cards with stitched borders, chunky display
## type for titles/headings/numbers, Nunito (+ Noto Sans SC) for body copy and buttons.

const INK := Color("#42291d")
const CREAM := Color("#fff1d1")
const ACCENT := Color("#d85537")
const STITCH := Color("#b67c51")
const WOOL := Color("#f6e2bb")
const COCOA := Color("#6b3a24")
const MUTED := Color("#8a5a3c")
const FONT := preload("res://assets/template/fonts/ui_regular.tres")
const MEDIUM := preload("res://assets/template/fonts/ui_medium.tres")
const BOLD := preload("res://assets/template/fonts/ui_bold.tres")
const DISPLAY := preload("res://assets/template/fonts/display/display_title.tres")
const HEADING := preload("res://assets/template/fonts/display/display_heading.tres")
## Below ~28px Chinese falls through to Noto Sans SC Bold; HuangYou is reserved for large display.
const SMALL_HEADING := preload("res://assets/template/fonts/display/display_small.tres")

static func heading_font(font_size: int) -> Font:
	return HEADING if font_size >= 28 else SMALL_HEADING

static func plate(color: Color = CREAM, margin: int = 24) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(18)
	style.set_content_margin_all(margin)
	style.border_color = STITCH
	style.set_border_width_all(2)
	return style

## Raised felt card used by the title menu, modals, pause and results.
static func card(color: Color = CREAM, margin: int = 24) -> StyleBoxFlat:
	var style := plate(color, margin)
	style.set_corner_radius_all(26)
	style.set_border_width_all(3)
	style.shadow_color = Color(0.26, 0.12, 0.05, 0.28)
	style.shadow_size = 18
	style.shadow_offset = Vector2(0, 8)
	style.anti_aliasing_size = 1.2
	return style

static func pill(color: Color, h_margin: int = 14, v_margin: int = 5) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(999)
	style.content_margin_left = h_margin
	style.content_margin_right = h_margin
	style.content_margin_top = v_margin
	style.content_margin_bottom = v_margin
	return style

static func is_cjk() -> bool:
	return I18n.get_locale().begins_with("zh")

## Modest tracking for Latin all-caps labels; CJK stays at natural spacing.
static func tracked(font: Font, latin_spacing: int) -> Font:
	if latin_spacing == 0 or is_cjk():
		return font
	var variation := _variant(font)
	variation.spacing_glyph = latin_spacing
	return variation

## Copy a composite FontVariation (keeping its axes and fallback chain) so
## spacing tweaks never drop the weight coordinates of the display font.
static func _variant(font: Font) -> FontVariation:
	if font is FontVariation:
		return (font as FontVariation).duplicate() as FontVariation
	var variation := FontVariation.new()
	variation.base_font = font
	return variation

static func label(text: String, font_size: int = 20) -> Label:
	var node := Label.new()
	node.text = text
	# Body copy uses the UI Medium composite (Nunito 500 + Noto Sans SC 500).
	node.add_theme_font_override("font", HEADING if font_size >= 28 else MEDIUM)
	node.add_theme_color_override("font_color", INK)
	node.add_theme_font_size_override("font_size", font_size)
	return node

## Chunky display type with a felt-stitch outline and soft drop shadow.
## Baloo 2 carries very tall line metrics; trim them (in em) so lockups stack tightly.
static func trimmed(base: Font, font_size: int, top_em: float, bottom_em: float) -> FontVariation:
	var variation := _variant(base)
	variation.spacing_top = -roundi(font_size * top_em)
	variation.spacing_bottom = -roundi(font_size * bottom_em)
	return variation

static func display(node: Label, font_size: int, fill: Color = CREAM, outline: Color = COCOA, outline_size: int = 10) -> Label:
	node.add_theme_font_override("font", trimmed(DISPLAY, font_size, 0.34, 0.36))
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", fill)
	node.add_theme_color_override("font_outline_color", outline)
	node.add_theme_constant_override("outline_size", outline_size)
	node.add_theme_color_override("font_shadow_color", Color(0.26, 0.12, 0.05, 0.45))
	node.add_theme_constant_override("shadow_offset_x", 0)
	node.add_theme_constant_override("shadow_offset_y", maxi(2, font_size / 14))
	node.add_theme_constant_override("shadow_outline_size", outline_size)
	return node

static func heading(text: String, font_size: int = 34) -> Label:
	var node := Label.new()
	node.text = text
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.add_theme_font_override("font", trimmed(heading_font(font_size), font_size, 0.2, 0.28))
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", COCOA)
	return node

static func _button_face(color: Color, edge: Color, press_depth: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = edge
	style.set_border_width_all(2)
	# A thicker bottom edge reads as the felt button's stuffed depth.
	style.border_width_bottom = 2 + press_depth
	style.set_corner_radius_all(16)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 6 + (4 - press_depth)
	style.content_margin_bottom = 6 + press_depth
	style.anti_aliasing_size = 1.0
	return style

## Stuffed felt button: the face (grain, running stitch, depth, focus ring) is
## drawn by FeltKit.FeltFace behind the text; hover lifts it, press squashes it.
static func button(text: String, primary: bool = false) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size = Vector2(0, 48)
	node.add_theme_font_override("font", BOLD if primary else MEDIUM)
	node.add_theme_font_size_override("font_size", 22 if primary else 18)
	if primary:
		FeltKit.felt_button(node, &"primary", ACCENT, Color("#9b3520"))
	else:
		FeltKit.felt_button(node, &"wool", WOOL, STITCH)
	var font_color := Color("#fffaf0") if primary else INK
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		node.add_theme_color_override(key, font_color)
	node.add_theme_color_override("font_disabled_color", Color(font_color, 0.5))
	if primary:
		node.add_theme_color_override("font_outline_color", Color("#8e2f1b"))
		node.add_theme_constant_override("outline_size", 4)
	node.accessibility_name = text
	return node

## Menu list row: no box at rest; a light felt patch + stitch appears under the
## yarn-ball cursor when hovered or focused.
static func menu_item(node: Button) -> Button:
	FeltKit.felt_button(node, &"item", WOOL, STITCH, 16.0)
	node.custom_minimum_size.y = maxf(node.custom_minimum_size.y, 44.0)
	node.add_theme_font_override("font", BOLD)
	for key in ["font_color", "font_focus_color", "font_pressed_color"]:
		node.add_theme_color_override(key, COCOA)
	for key in ["font_hover_color", "font_hover_pressed_color"]:
		node.add_theme_color_override(key, ACCENT.darkened(0.2))
	return node

## Felt plaque: cream card stylebox + felt grain + a running stitch inside the edge.
static func felt_card(panel: Control, color: Color = CREAM, margin: int = 24, thread: Color = STITCH) -> StyleBoxFlat:
	var style := card(color, margin)
	panel.add_theme_stylebox_override("panel", style)
	FeltKit.decorate_panel(panel, thread, 8.0)
	return style

## Felt ribbon banner heading; the label stays a normal Label (name/text queries work).
static func ribbon(text: String, font_size: int = 40, color: Color = ACCENT, label_name: String = "") -> PanelContainer:
	var holder := PanelContainer.new()
	holder.name = "Ribbon"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxEmpty.new()
	box.content_margin_left = 44
	box.content_margin_right = 44
	box.content_margin_top = 8
	box.content_margin_bottom = 12
	holder.add_theme_stylebox_override("panel", box)
	holder.material = FeltKit.felt_material()
	var label := Label.new()
	if not label_name.is_empty(): label.name = label_name
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", trimmed(heading_font(font_size), font_size, 0.2, 0.28))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("#fff6e2"))
	label.add_theme_color_override("font_outline_color", Color(color.darkened(0.45), 0.9))
	label.add_theme_constant_override("outline_size", maxi(4, font_size / 7))
	label.add_theme_color_override("font_shadow_color", Color(0.2, 0.08, 0.02, 0.35))
	label.add_theme_constant_override("shadow_offset_y", 3)
	holder.add_child(label)
	holder.set_meta("ribbon_color", color)
	holder.draw.connect(func():
		var h := holder.size.y - 6.0
		var tail := minf(44.0, h * 0.62)
		FeltKit.draw_ribbon(holder, Rect2(Vector2(tail, 0), Vector2(holder.size.x - tail * 2.0, h)), holder.get_meta("ribbon_color", color)))
	return holder

## Small, quiet footer action (licenses): readable but visually secondary.
static func quiet_button(text: String) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size = Vector2(0, 44)
	node.add_theme_font_override("font", MEDIUM)
	node.add_theme_font_size_override("font_size", 15)
	var states := {"normal": 0.55, "hover": 0.72, "pressed": 0.8, "hover_pressed": 0.8}
	for state: String in states:
		node.add_theme_stylebox_override(state, quiet_face(states[state]))
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		node.add_theme_color_override(key, Color("#fff4dd"))
	var focus := pill(Color.TRANSPARENT)
	focus.draw_center = false
	focus.border_color = Color("#fff4dd")
	focus.set_border_width_all(2)
	focus.set_expand_margin_all(3)
	node.add_theme_stylebox_override("focus", focus)
	node.accessibility_name = text
	return node

## Translucent cocoa pill shared by footer items (licenses, Tweak Controls).
static func quiet_face(alpha: float) -> StyleBoxFlat:
	var style := pill(Color(0.22, 0.12, 0.07, alpha), 16, 6)
	style.set_corner_radius_all(14)
	style.border_color = Color(1.0, 0.94, 0.82, 0.28)
	style.set_border_width_all(1)
	return style

## Restyle a quiet button for use on the cream card (compact layouts).
static func quiet_on_card(node: Button, on_card: bool) -> void:
	var states := {"normal": 0.0, "hover": 0.08, "pressed": 0.14, "hover_pressed": 0.14}
	for state: String in states:
		var style: StyleBoxFlat
		if on_card:
			style = pill(Color(INK, states[state]), 16, 6)
		else:
			style = quiet_face(0.55 + states[state] * 2.0)
		node.add_theme_stylebox_override(state, style)
	var color := MUTED if on_card else Color("#fff4dd")
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		node.add_theme_color_override(key, color)
	var focus := node.get_theme_stylebox("focus") as StyleBoxFlat
	if focus != null:
		focus.border_color = INK if on_card else Color("#fff4dd")
