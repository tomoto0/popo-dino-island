extends RefCounted
class_name PopoLevelArt
## Level art: textured terrain bodies, pillars/stumps and a parallax background layer.

const TILE_SCALE := 0.5          # 256 px texture -> 128 px world tile
const TOP_CROP := {"cloud": 26.0}  # rows of sky baked into some top tiles
const STUMP = preload("res://assets/game/props/stump.webp")

static var _tex_cache: Dictionary = {}


static func terrain_texture(theme: String, part: String) -> Texture2D:
	var key := theme + "_" + part
	if not _tex_cache.has(key):
		_tex_cache[key] = load("res://assets/game/terrain/%s.webp" % key)
	return _tex_cache[key]


static func background_texture(world: int) -> Texture2D:
	var key := "bg_%d" % world
	if not _tex_cache.has(key):
		_tex_cache[key] = load("res://assets/game/backgrounds/world_%d.webp" % clampi(world, 1, 6))
	return _tex_cache[key]


class Terrain:
	extends StaticBody2D
	var rect := Rect2()
	var theme := "grass"

	func _ready() -> void:
		add_to_group("terrain")
		collision_layer = 1
		collision_mask = 0
		position = rect.position
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = rect.size
		shape.shape = box
		shape.position = rect.size * 0.5
		add_child(shape)
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		z_index = -1

	func _draw() -> void:
		var top_tex := PopoLevelArt.terrain_texture(theme, "top")
		var fill_tex := PopoLevelArt.terrain_texture(theme, "fill")
		var s := TILE_SCALE
		var crop: float = TOP_CROP.get(theme, 0.0)
		var w := rect.size.x / s
		var h := rect.size.y / s
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
		var top_h := minf(256.0 - crop, h)
		# Tile the top strip horizontally; the source region skips baked sky rows.
		var x := 0.0
		while x < w:
			var seg := minf(256.0, w - x)
			draw_texture_rect_region(top_tex, Rect2(x, 0, seg, top_h), Rect2(0, crop, seg, top_h))
			x += 256.0
		if h > top_h:
			draw_texture_rect(fill_tex, Rect2(0, top_h - 1.0, w, h - top_h + 1.0), true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# Soft shadow lip under the grass edge for depth.
		draw_rect(Rect2(0, 0, rect.size.x, 3), Color(1, 1, 1, 0.18))


## Tree stump (grass/plains/forest) or a narrow terrain column (other themes).
class Pillar:
	extends StaticBody2D
	var center_x := 0.0
	var top := 500.0
	var height := 400.0
	var width := 96.0
	var theme := "grass"

	func _ready() -> void:
		add_to_group("terrain")
		collision_layer = 1
		collision_mask = 0
		position = Vector2(center_x, top)
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		var solid_w := width - 14.0 if _is_stump() else width
		box.size = Vector2(solid_w, height)
		shape.shape = box
		shape.position = Vector2(0, height * 0.5)
		add_child(shape)
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		z_index = -1

	func _is_stump() -> bool:
		return theme in ["grass", "plains", "forest"]

	func _draw() -> void:
		if _is_stump():
			var size := STUMP.get_size()
			var s := width / size.x
			var cap_src := 150.0
			var cap_h := cap_src * s
			var y := -cap_h * 0.3
			draw_texture_rect_region(STUMP, Rect2(-width * 0.5, y, width, cap_h), Rect2(0, 0, size.x, cap_src))
			y += cap_h
			var bark_src := Rect2(0, 170, size.x, 150)
			var bark_h := bark_src.size.y * s
			while y < height:
				var seg := minf(bark_h, height - y)
				draw_texture_rect_region(STUMP, Rect2(-width * 0.5, y, width, seg), Rect2(bark_src.position, Vector2(size.x, seg / s)))
				y += seg
			return
		var top_tex := PopoLevelArt.terrain_texture(theme, "top")
		var fill_tex := PopoLevelArt.terrain_texture(theme, "fill")
		var s2 := TILE_SCALE
		var crop: float = TOP_CROP.get(theme, 0.0)
		draw_set_transform(Vector2(-width * 0.5, 0), 0.0, Vector2(s2, s2))
		var w := width / s2
		var top_h := 256.0 - crop
		draw_texture_rect_region(top_tex, Rect2(0, 0, w, top_h), Rect2(0, crop, w, top_h))
		draw_texture_rect(fill_tex, Rect2(0, top_h - 1.0, w, height / s2 - top_h + 1.0), true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_rect(Rect2(-width * 0.5, 0, width, height), Color(0, 0, 0, 0.35), false, 2.0)


## Screen-space parallax backdrop that scrolls with the camera.
class Backdrop:
	extends Node2D
	var texture: Texture2D
	var factor := 0.22
	var camera: Camera2D
	var tint := Color.WHITE

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if texture == null:
			return
		var view := get_viewport_rect().size
		var s := view.y / texture.get_size().y
		var tile_w := texture.get_size().x * s
		var cam_x := 0.0
		if is_instance_valid(camera):
			cam_x = camera.get_screen_center_position().x
		var offset := -fposmod(cam_x * factor, tile_w)
		var x := offset
		while x < view.x:
			draw_texture_rect(texture, Rect2(x, 0, tile_w + 1.0, view.y), false, tint)
			x += tile_w
