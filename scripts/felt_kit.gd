class_name FeltKit
extends RefCounted
## Handmade felt & yarn presentation kit, drawn entirely in code:
## felt-grain shader, running stitches, sewn buttons, yarn balls, ribbons,
## felt button faces with stuffed depth, the sliding yarn-ball selection cursor
## and the drifting wool-fluff ambience. Presentation only.

const YARN := preload("res://assets/template/cat/yarn.webp")
const FISH := preload("res://assets/template/cat/fish.webp")
const INK := Color("#42291d")
const COCOA := Color("#6b3a24")
const CREAM := Color("#fff1d1")
const THREAD := Color("#fff4dd")
const STITCH := Color("#b67c51")
const TOMATO := Color("#d85537")
const MUSTARD := Color("#e3a33b")
const TEAL := Color("#4f9a93")
const ROSE := Color("#d9788a")

const FELT_SHADER := """
shader_type canvas_item;
uniform float grain = 0.07;
uniform float fiber = 0.022;
varying vec2 local_pos;
void vertex() { local_pos = VERTEX; }
float hash(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void fragment() {
	vec2 p = local_pos;
	float mottled = vnoise(p * 0.05) * 0.5 + vnoise(p * 0.16) * 0.3 + vnoise(p * 0.6) * 0.2;
	float speck = hash(floor(p * 0.75)) - 0.5;
	float f1 = vnoise(vec2(p.x * 0.35 + p.y * 0.12, p.y * 0.05 - p.x * 0.015));
	float f2 = vnoise(vec2(p.y * 0.35 - p.x * 0.12, p.x * 0.05 + 3.1));
	float fibers = smoothstep(0.7, 0.95, max(f1, f2));
	COLOR.rgb *= 1.0 + (mottled - 0.5) * grain * 2.0 + speck * grain * 0.5 + fibers * fiber;
}
"""

const VEIL_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec4 tint : source_color = vec4(0.2, 0.1, 0.05, 1.0);
uniform float strength = 0.55;
uniform float blur = 2.2;
void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * blur;
	vec3 c = texture(screen_tex, SCREEN_UV).rgb * 0.2;
	c += texture(screen_tex, SCREEN_UV + vec2(px.x, 0.0)).rgb * 0.1;
	c += texture(screen_tex, SCREEN_UV - vec2(px.x, 0.0)).rgb * 0.1;
	c += texture(screen_tex, SCREEN_UV + vec2(0.0, px.y)).rgb * 0.1;
	c += texture(screen_tex, SCREEN_UV - vec2(0.0, px.y)).rgb * 0.1;
	c += texture(screen_tex, SCREEN_UV + px * 1.6).rgb * 0.1;
	c += texture(screen_tex, SCREEN_UV - px * 1.6).rgb * 0.1;
	c += texture(screen_tex, SCREEN_UV + vec2(px.x, -px.y) * 1.6).rgb * 0.1;
	c += texture(screen_tex, SCREEN_UV + vec2(-px.x, px.y) * 1.6).rgb * 0.1;
	float v = smoothstep(0.25, 0.8, distance(UV, vec2(0.5)));
	vec3 col = mix(c, tint.rgb, clamp(strength + v * 0.3, 0.0, 1.0));
	COLOR = vec4(col, COLOR.a);
}
"""

static var _felt: ShaderMaterial
static var _veil_shader: Shader
static var _yarn_small: Dictionary = {}

static func felt_material() -> ShaderMaterial:
	if _felt == null:
		var shader := Shader.new()
		shader.code = FELT_SHADER
		_felt = ShaderMaterial.new()
		_felt.shader = shader
	return _felt

## Blurred, warm-vignetted veil for modal backdrops (reads the screen behind it).
static func veil_material(strength: float = 0.55) -> ShaderMaterial:
	if _veil_shader == null:
		_veil_shader = Shader.new()
		_veil_shader.code = VEIL_SHADER
	var material := ShaderMaterial.new()
	material.shader = _veil_shader
	material.set_shader_parameter("strength", strength)
	return material

static func reduced_motion() -> bool:
	return TuningStore.get_value("reduced_motion") > 0.0

# --- geometry -----------------------------------------------------------------

static func rounded_points(rect: Rect2, radius: float, segments: int = 6) -> PackedVector2Array:
	var r := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	var points := PackedVector2Array()
	var corners := [
		[rect.position + Vector2(rect.size.x - r, r), -PI * 0.5],
		[rect.end - Vector2(r, r), 0.0],
		[rect.position + Vector2(r, rect.size.y - r), PI * 0.5],
		[rect.position + Vector2(r, r), PI],
	]
	for corner: Array in corners:
		for i in segments + 1:
			var angle: float = corner[1] + PI * 0.5 * float(i) / segments
			points.append(corner[0] + Vector2(cos(angle), sin(angle)) * r)
	points.append(points[0])
	return points

## Running stitch along a rounded rectangle, with a soft thread shadow for depth.
static func draw_stitches(ci: CanvasItem, rect: Rect2, radius: float, color: Color, width: float = 2.0, dash: float = 7.0, gap: float = 5.0, progress: float = 1.0) -> void:
	if rect.size.x < 4.0 or rect.size.y < 4.0 or progress <= 0.0: return
	var path := rounded_points(rect, radius)
	var total := 0.0
	for i in path.size() - 1: total += path[i].distance_to(path[i + 1])
	var budget := total * clampf(progress, 0.0, 1.0)
	var travelled := 0.0
	var segments := PackedVector2Array()
	var carry := 0.0
	var drawing := true
	for i in path.size() - 1:
		var a := path[i]
		var b := path[i + 1]
		var length := a.distance_to(b)
		var t := 0.0
		if travelled > budget: break
		travelled += length
		while t < length and travelled - length + t < budget:
			var span := (dash if drawing else gap) - carry
			var step := minf(span, length - t)
			if drawing:
				segments.append(a.lerp(b, t / length))
				segments.append(a.lerp(b, (t + step) / length))
			t += step
			carry += step
			if carry >= (dash if drawing else gap) - 0.001:
				carry = 0.0
				drawing = not drawing
	if segments.is_empty(): return
	var shadow := PackedVector2Array()
	for p in segments: shadow.append(p + Vector2(0, 1.2))
	ci.draw_multiline(shadow, Color(0.2, 0.08, 0.02, 0.22 * color.a), width)
	ci.draw_multiline(segments, color, width)

static func draw_dashes(ci: CanvasItem, from: Vector2, to: Vector2, color: Color, width: float = 2.0, dash: float = 7.0, gap: float = 5.0) -> void:
	var length := from.distance_to(to)
	var dir := (to - from) / maxf(length, 0.001)
	var segments := PackedVector2Array()
	var t := 0.0
	while t < length:
		segments.append(from + dir * t)
		segments.append(from + dir * minf(t + dash, length))
		t += dash + gap
	if segments.is_empty(): return
	var shadow := PackedVector2Array()
	for p in segments: shadow.append(p + Vector2(0, 1.2))
	ci.draw_multiline(shadow, Color(0.2, 0.08, 0.02, 0.22 * color.a), width)
	ci.draw_multiline(segments, color, width)

static func flat(color: Color, radius: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(int(radius))
	style.anti_aliasing_size = 1.0
	return style

# --- motifs ---------------------------------------------------------------------

## A felt sewing button: rim groove, four holes and a cross of thread.
static func draw_sewn_button(ci: CanvasItem, c: Vector2, r: float, base: Color, thread: Color = THREAD) -> void:
	ci.draw_circle(c + Vector2(0, r * 0.14), r, Color(0.2, 0.08, 0.02, 0.25))
	ci.draw_circle(c, r, base.darkened(0.12))
	ci.draw_circle(c + Vector2(0, -r * 0.05), r * 0.9, base)
	ci.draw_arc(c, r * 0.7, 0, TAU, 28, base.darkened(0.16), maxf(1.0, r * 0.08), true)
	var d := r * 0.24
	for offset: Vector2 in [Vector2(-d, -d), Vector2(d, -d), Vector2(-d, d), Vector2(d, d)]:
		ci.draw_circle(c + offset, r * 0.1, base.darkened(0.5))
	ci.draw_line(c + Vector2(-d, -d), c + Vector2(d, d), thread, maxf(1.2, r * 0.1), true)
	ci.draw_line(c + Vector2(d, -d), c + Vector2(-d, d), thread, maxf(1.2, r * 0.1), true)

## The in-game yarn ball sprite, reused as a UI motif (cursor, badges).
static func draw_yarn(ci: CanvasItem, c: Vector2, r: float, spin: float = 0.0, alpha: float = 1.0) -> void:
	ci.draw_circle(c + Vector2(0, r * 0.2), r * 0.92, Color(0.2, 0.08, 0.02, 0.22 * alpha))
	ci.draw_set_transform(c, spin, Vector2.ONE)
	ci.draw_texture_rect(YARN, Rect2(Vector2(-r, -r) * 1.08, Vector2(r, r) * 2.16), false, Color(1, 1, 1, alpha))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## Small yarn texture for slider grabbers (HSlider draws icons at native size).
static func yarn_icon(size: int) -> Texture2D:
	if _yarn_small.has(size): return _yarn_small[size]
	var image := YARN.get_image()
	var texture: Texture2D = YARN
	if image != null and not image.is_empty():
		if image.is_compressed(): image.decompress()
		image.resize(size, size, Image.INTERPOLATE_LANCZOS)
		texture = ImageTexture.create_from_image(image)
	_yarn_small[size] = texture
	return texture

## Felt ribbon banner with notched tails and a running stitch along both edges.
static func draw_ribbon(ci: CanvasItem, rect: Rect2, color: Color, thread: Color = THREAD) -> void:
	var h := rect.size.y
	var tail := h * 0.62
	var dark := color.darkened(0.3)
	var left := rect.position.x
	var right := rect.end.x
	var top := rect.position.y
	for side: float in [-1.0, 1.0]:
		var x0 := left if side < 0 else right
		var x1 := x0 + side * tail
		var poly := PackedVector2Array([
			Vector2(x0 - side * h * 0.1, top + h * 0.22), Vector2(x1, top + h * 0.22),
			Vector2(x1 - side * h * 0.32, top + h * 0.72), Vector2(x1, top + h * 1.22),
			Vector2(x0 - side * h * 0.1, top + h * 1.22),
		])
		ci.draw_colored_polygon(poly, color.darkened(0.14))
		ci.draw_colored_polygon(PackedVector2Array([Vector2(x0, top + h), Vector2(x0 - side * h * 0.1, top + h * 1.22), Vector2(x0 - side * h * 0.1, top + h)]), dark)
	flat(Color(0.2, 0.08, 0.02, 0.22), 6).draw(ci.get_canvas_item(), Rect2(rect.position + Vector2(0, 4), rect.size))
	flat(color, 6).draw(ci.get_canvas_item(), rect)
	draw_dashes(ci, rect.position + Vector2(8, 5), Vector2(right - 8, top + 5), Color(thread, 0.85), 1.6, 6, 4)
	draw_dashes(ci, Vector2(left + 8, rect.end.y - 5), rect.end - Vector2(8, 5), Color(thread, 0.85), 1.6, 6, 4)

## Tiny felt clock (for the timer): rim, face, ticks and one moving hand.
static func draw_clock(ci: CanvasItem, c: Vector2, r: float, fraction: float, urgent: bool) -> void:
	ci.draw_circle(c + Vector2(0, r * 0.14), r, Color(0.2, 0.08, 0.02, 0.22))
	ci.draw_circle(c, r, TOMATO if urgent else TEAL)
	ci.draw_circle(c, r * 0.72, CREAM)
	for i in 4:
		var a := i * PI * 0.5
		ci.draw_line(c + Vector2(cos(a), sin(a)) * r * 0.5, c + Vector2(cos(a), sin(a)) * r * 0.64, COCOA, maxf(1.2, r * 0.09), true)
	var hand := -PI * 0.5 + TAU * fraction
	ci.draw_line(c, c + Vector2(cos(hand), sin(hand)) * r * 0.5, COCOA, maxf(1.5, r * 0.12), true)
	ci.draw_circle(c, r * 0.1, COCOA)
	ci.draw_circle(c + Vector2(0, -r * 1.05), r * 0.18, TOMATO if urgent else TEAL)

## Five-point felt star (results rank, score badge).
static func draw_star(ci: CanvasItem, c: Vector2, r: float, color: Color, filled: bool = true) -> void:
	var points := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + i * PI / 5.0
		points.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.48))
	var shadow := PackedVector2Array()
	for p in points: shadow.append(p + Vector2(0, r * 0.12))
	ci.draw_colored_polygon(shadow, Color(0.2, 0.08, 0.02, 0.25))
	if filled:
		ci.draw_colored_polygon(points, color)
	else:
		ci.draw_colored_polygon(points, Color(COCOA, 0.18))
	points.append(points[0])
	ci.draw_polyline(points, color.darkened(0.3) if filled else Color(COCOA, 0.35), maxf(1.2, r * 0.08), true)

# --- panel decoration ------------------------------------------------------------

## Felt grain + running stitch on any Panel/PanelContainer drawing a StyleBoxFlat.
static func decorate_panel(panel: Control, thread: Color = STITCH, inset: float = 7.0) -> void:
	panel.material = felt_material()
	if panel.has_meta("felt_stitched"): return
	panel.set_meta("felt_stitched", true)
	panel.draw.connect(func():
		var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
		var radius := float(style.corner_radius_top_left) if style != null else 18.0
		var rect := Rect2(Vector2.ZERO, panel.size).grow(-inset)
		draw_stitches(panel, rect, maxf(4.0, radius - inset), panel.get_meta("felt_thread", thread), 2.0, 8.0, 6.0, panel.get_meta("stitch_progress", 1.0)))

# --- felt button face --------------------------------------------------------------

## Replaces a Button's flat boxes with a stuffed felt face drawn behind its text.
## kinds: &"primary", &"wool", &"item" (menu list row), &"tab" (segmented toggle),
## &"round" (circular HUD button), &"ghost" (transparent until hovered).
class FeltFace extends Control:
	var button: BaseButton
	var kind: StringName
	var tone: Color
	var edge: Color
	var radius := 18.0
	var depth := 5.0
	var lift := 0.0:
		set(value):
			lift = value
			queue_redraw()
	var pop := 1.0:
		set(value):
			pop = value
			queue_redraw()
	var badge_color := Color.TRANSPARENT
	var key_hint := ""
	var badge_glyph := ""
	var _tween: Tween

	func _init(target: BaseButton, face_kind: StringName, face_tone: Color, face_edge: Color) -> void:
		button = target
		kind = face_kind
		tone = face_tone
		edge = face_edge
		name = "FeltFace"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		show_behind_parent = true
		material = FeltKit.felt_material()
		if kind == &"item" or kind == &"ghost": depth = 0.0
		if kind == &"tab": depth = 3.0

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for signal_name in ["mouse_entered", "mouse_exited", "focus_entered", "focus_exited", "button_down", "button_up", "toggled"]:
			if button.has_signal(signal_name):
				button.connect(signal_name, _on_state.bind(signal_name).unbind(1) if signal_name == "toggled" else _on_state.bind(signal_name))
		button.resized.connect(queue_redraw)

	func _on_state(what: String) -> void:
		queue_redraw()
		if FeltKit.reduced_motion() or not is_inside_tree(): return
		match what:
			"mouse_entered", "focus_entered":
				_start_tween().tween_property(self, "lift", 2.0, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			"mouse_exited", "focus_exited":
				if not button.is_hovered() and not button.has_focus():
					_start_tween().tween_property(self, "lift", 0.0, 0.14)
			"button_down":
				_start_tween().tween_property(self, "pop", 0.95, 0.06)
			"button_up":
				_start_tween().tween_property(self, "pop", 1.0, 0.28).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	func _start_tween() -> Tween:
		if _tween != null: _tween.kill()
		_tween = create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		return _tween

	func _draw() -> void:
		if button == null: return
		var mode := button.get_draw_mode()
		var pressed := mode == BaseButton.DRAW_PRESSED or mode == BaseButton.DRAW_HOVER_PRESSED
		var hovered := mode == BaseButton.DRAW_HOVER or mode == BaseButton.DRAW_HOVER_PRESSED
		var disabled := mode == BaseButton.DRAW_DISABLED
		var focused := button.has_focus()
		var toggled_on := button.toggle_mode and button.button_pressed
		var w := size.x
		var h := size.y
		draw_set_transform(size * 0.5 * (1.0 - pop), 0.0, Vector2(pop, pop))
		var face_tone := tone
		var face_edge := edge
		if kind == &"tab" and toggled_on:
			face_tone = FeltKit.COCOA
			face_edge = Color("#40200f")
		if disabled:
			face_tone = face_tone.lerp(Color("#d9c9ad"), 0.6)
			face_edge = face_edge.lerp(Color("#c7b394"), 0.6)
		elif hovered and not pressed:
			face_tone = face_tone.lightened(0.07)
		var active := hovered or focused
		if kind == &"item" or kind == &"ghost":
			if active or pressed:
				var patch := Rect2(Vector2(0, 2 - lift), Vector2(w, h - 4))
				FeltKit.flat(Color(1.0, 0.98, 0.93, 0.92 if kind == &"item" else 0.25), radius).draw(get_canvas_item(), patch)
				FeltKit.draw_stitches(self, patch.grow(-5), radius - 5, Color(FeltKit.STITCH, 0.9), 1.6, 6, 4)
			_badge(h * 0.5 - (lift if active else 0.0))
			return
		var travel := depth - 1.0 if pressed else -lift
		if toggled_on and kind == &"tab": travel = depth - 1.0
		var face := Rect2(Vector2(0, travel), Vector2(w, h - depth))
		if kind == &"round":
			var c := Vector2(w * 0.5, (h - depth) * 0.5)
			var r := minf(w, h - depth) * 0.5
			draw_circle(c + Vector2(0, depth + 2), r, Color(0.2, 0.08, 0.02, 0.25))
			draw_circle(c + Vector2(0, depth), r, face_edge)
			draw_circle(c + Vector2(0, travel), r, face_tone)
			_ring_stitch(c + Vector2(0, travel), r - 5)
			if focused: draw_arc(c + Vector2(0, travel), r + 4, 0, TAU, 40, FeltKit.INK, 3, true)
			return
		var shadow := FeltKit.flat(face_edge, radius)
		shadow.shadow_color = Color(0.2, 0.08, 0.02, 0.26)
		shadow.shadow_size = 6
		shadow.shadow_offset = Vector2(0, 3)
		shadow.draw(get_canvas_item(), Rect2(Vector2(0, depth), Vector2(w, h - depth)))
		FeltKit.flat(face_tone, radius).draw(get_canvas_item(), face)
		var thread := Color(FeltKit.THREAD, 0.85) if kind == &"primary" or toggled_on else Color(FeltKit.STITCH, 0.95)
		FeltKit.draw_stitches(self, face.grow(-5), maxf(3.0, radius - 5), thread, 1.6, 6, 4)
		if not key_hint.is_empty() and w > 220.0:
			var font := button.get_theme_font("font")
			var fs := 12
			var tw := font.get_string_size(key_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var cap := Rect2(Vector2(w - tw - 34.0, face.position.y + face.size.y * 0.5 - 12.0), Vector2(tw + 16.0, 24.0))
			var cap_box := FeltKit.flat(Color(0.35, 0.1, 0.04, 0.35), 7)
			cap_box.border_color = Color(FeltKit.THREAD, 0.7)
			cap_box.set_border_width_all(1)
			cap_box.border_width_bottom = 3
			cap_box.draw(get_canvas_item(), cap)
			draw_string(font, Vector2(cap.position.x + 8.0, cap.position.y + 16.5), key_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(FeltKit.THREAD, 0.95))
		if kind == &"primary":
			draw_line(face.position + Vector2(radius, 3.5), face.position + Vector2(w - radius, 3.5), Color(1, 1, 1, 0.16), 2)
		_badge(face.position.y + face.size.y * 0.5)
		if focused:
			var ring := StyleBoxFlat.new()
			ring.draw_center = false
			ring.border_color = FeltKit.INK
			ring.set_border_width_all(3)
			ring.set_corner_radius_all(int(radius + 4))
			ring.anti_aliasing_size = 1.0
			ring.draw(get_canvas_item(), Rect2(Vector2(0, travel), Vector2(w, h - depth + (depth - travel))).grow(4))

	func _badge(y: float) -> void:
		if badge_color.a <= 0.0: return
		var br := clampf(size.y * 0.2, 7.0, 12.0)
		FeltKit.draw_sewn_button(self, Vector2(8 + br, y), br, badge_color)

	func _ring_stitch(c: Vector2, r: float) -> void:
		var segments := PackedVector2Array()
		var count := maxi(8, int(TAU * r / 10.0))
		for i in count:
			var a0 := TAU * i / count
			var a1 := a0 + TAU / count * 0.6
			segments.append(c + Vector2(cos(a0), sin(a0)) * r)
			segments.append(c + Vector2(cos(a1), sin(a1)) * r)
		draw_multiline(segments, Color(FeltKit.THREAD, 0.8), 1.6)

## Apply a felt face to a Button, keeping its text drawn crisply on top.
## Empty state boxes keep the layout metrics and shift text with the face.
static func felt_button(button: BaseButton, kind: StringName, tone: Color, edge: Color, radius: float = 18.0, h_margin: float = 18.0, v_margin: float = 6.0) -> FeltFace:
	var old := button.get_node_or_null("FeltFace")
	if old != null:
		button.remove_child(old)
		old.queue_free()
	var face := FeltFace.new(button, kind, tone, edge)
	face.radius = radius
	var depth := face.depth
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var box := StyleBoxEmpty.new()
		var down := state == "pressed" or state == "hover_pressed"
		var shift := (depth - 1.0) if down else (-1.0 if state == "hover" and depth > 0.0 else 0.0)
		box.content_margin_left = h_margin
		box.content_margin_right = h_margin
		box.content_margin_top = v_margin + shift
		box.content_margin_bottom = v_margin + depth - shift
		button.add_theme_stylebox_override(state, box)
	button.add_child(face)
	return face

# --- yarn cursor --------------------------------------------------------------------

## A yarn ball that rolls to the focused (or hovered) menu item, trailing its thread.
class YarnCursor extends Control:
	var targets: Array[Control] = []
	var target: Control
	var hovered: Control
	var radius := 15.0
	var _pos := Vector2(-100, -100)
	var _spin := 0.0
	var _time := 0.0
	var _shown := 0.0
	var _placed := false

	func _init() -> void:
		name = "YarnCursor"
		top_level = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		z_index = 20

	func _ready() -> void:
		get_viewport().gui_focus_changed.connect(_on_focus)
		_on_focus(get_viewport().gui_get_focus_owner())

	func track(control: Control) -> void:
		if control in targets: return
		targets.append(control)
		control.mouse_entered.connect(func(): hovered = control)
		control.mouse_exited.connect(func(): if hovered == control: hovered = null)
		control.tree_exiting.connect(func(): targets.erase(control))

	func _on_focus(node: Control) -> void:
		if node in targets: target = node

	func _current() -> Control:
		for candidate: Control in [hovered, target]:
			if is_instance_valid(candidate) and candidate.is_visible_in_tree():
				return candidate
		return null

	func _process(delta: float) -> void:
		_time += delta
		var control := _current()
		var visible_goal := 0.0
		if control != null:
			var rect := control.get_global_rect()
			var goal := Vector2(rect.position.x + 2.0, rect.get_center().y - 2.0)
			var face := control.get_node_or_null("FeltFace") as FeltKit.FeltFace
			if face != null and face.depth > 0.0: goal.y -= face.depth * 0.5
			visible_goal = 1.0
			if not _placed or FeltKit.reduced_motion():
				_pos = goal
				_placed = true
			else:
				var before := _pos
				_pos = _pos.lerp(goal, 1.0 - exp(-delta * 16.0))
				_spin += (_pos.x - before.x + (_pos.y - before.y) * 0.6) / radius
		_shown = move_toward(_shown, visible_goal, delta * 6.0)
		queue_redraw()

	func _draw() -> void:
		if _shown <= 0.01: return
		var bob := 0.0 if FeltKit.reduced_motion() else sin(_time * 3.2) * 1.6
		var c := _pos + Vector2(0, bob)
		var r := radius * (0.6 + 0.4 * _shown)
		# Loose thread trailing behind the ball.
		var thread := PackedVector2Array()
		for i in 10:
			var t := float(i) / 9.0
			var sway := (0.0 if FeltKit.reduced_motion() else sin(_time * 2.4 + t * 5.0) * 3.0 * t) + sin(t * 7.0) * 3.0 * t
			thread.append(c + Vector2(-r * 0.3 - t * 10.0 + sway * 0.5, r * 0.7 + t * 16.0))
		draw_polyline(thread, Color(Color("#c8453a"), 0.9 * _shown), 2.4, true)
		FeltKit.draw_yarn(self, c, r, _spin, _shown)

# --- ambience ---------------------------------------------------------------------------

## Drifting wool fluff and a few lazily swimming felt fish for the title sky.
class FeltAmbience extends Control:
	var motes: Array[Dictionary] = []
	var _time := 0.0
	var fluff_count := 18
	var fish_count := 2

	func _init() -> void:
		name = "FeltAmbience"
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var rng := RandomNumberGenerator.new()
		rng.seed = 5157
		for i in fluff_count + fish_count:
			var fish := i >= fluff_count
			motes.append({
				"u": rng.randf(), "v": rng.randf_range(0.05, 0.95) if not fish else rng.randf_range(0.06, 0.26),
				"r": rng.randf_range(2.5, 6.5) if not fish else rng.randf_range(20.0, 28.0),
				"speed": rng.randf_range(0.006, 0.018) if not fish else rng.randf_range(0.012, 0.02),
				"rise": rng.randf_range(0.004, 0.012), "phase": rng.randf() * TAU, "fish": fish,
				"dir": 1.0 if rng.randf() < 0.5 else -1.0,
			})

	func _process(delta: float) -> void:
		if FeltKit.reduced_motion(): return
		_time += delta
		for mote in motes:
			mote.u = fposmod(mote.u + mote.speed * mote.dir * delta, 1.1)
			if not mote.fish: mote.v = fposmod(mote.v - mote.rise * delta, 1.0)
		queue_redraw()

	func _draw() -> void:
		for mote in motes:
			var p := Vector2((mote.u - 0.05) * size.x, mote.v * size.y)
			var wobble := sin(_time * 1.3 + mote.phase)
			if mote.fish:
				var s: float = mote.r
				p.y += wobble * 8.0
				draw_set_transform(p, wobble * 0.12, Vector2(mote.dir * s / 32.0, s / 32.0))
				draw_texture_rect(FeltKit.FISH, Rect2(-32, -32, 64, 64), false, Color(1, 1, 1, 0.7))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			else:
				p.x += wobble * 10.0
				var r: float = mote.r
				draw_circle(p, r * 1.8, Color(1.0, 0.96, 0.88, 0.1))
				draw_circle(p, r, Color(1.0, 0.97, 0.9, 0.55))
				for k in 3:
					var a: float = mote.phase + k * 2.1 + _time * 0.2
					draw_line(p, p + Vector2(cos(a), sin(a)) * r * 1.9, Color(1.0, 0.97, 0.9, 0.4), 1.0, true)
