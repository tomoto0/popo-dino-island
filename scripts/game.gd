extends Node2D
## Stage session: builds the level from JSON, runs the HUD, lives/coins/medals, the boss
## fight, death/respawn at the checkpoint and the clear/game-over flow.

const ENTITIES = preload("res://scripts/entities.gd")
const LEVEL_ART = preload("res://scripts/level_art.gd")
const PLAYER = preload("res://scripts/player.gd")
const EGG = preload("res://scripts/egg.gd")
const PAUSE_MENU = preload("res://scripts/pause_menu.gd")
const TOUCH = preload("res://scripts/touch_controls.gd")
const VISUAL_EFFECTS = preload("res://scripts/visual_effects.gd")
const CATALOG = preload("res://scripts/stage_catalog.gd")
const MENU_STYLE = preload("res://scripts/menu_style.gd")
const ICON_HEART = preload("res://assets/game/items/heart.webp")
const ICON_EGG = preload("res://assets/game/items/egg.webp")
const ICON_COIN = preload("res://assets/game/items/coin.webp")
const ICON_MEDAL = preload("res://assets/game/items/medal.webp")
const ICON_HERO = preload("res://assets/game/hero/idle.webp")
const BASE_VIEWPORT_HEIGHT := 720.0
const MAX_EGGS_IN_FLIGHT := 3
const THEME_MUSIC := {"grass": &"overworld", "plains": &"overworld", "cave": &"cave", "cloud": &"sky", "forest": &"forest", "castle": &"castle"}
const WORLD_TINT := {"cave": Color(0.85, 0.9, 1.0), "forest": Color(0.8, 0.8, 0.95), "castle": Color(0.95, 0.85, 0.85)}

## Carried across scene reloads when the hero loses a life on the same stage.
static var respawn_stage := ""
static var respawn_checkpoint := false

var stage: Dictionary = {}
var stage_id := "w1_1"
var stage_index := 0
var world_width := 6000.0
var player: CharacterBody2D
var camera: Camera2D
var visual_effects: Node
var pause_menu = null
var touch: Control
var backdrop: Node2D
var goal = null
var boss = null
var boss_active := false
var boss_wall: StaticBody2D
var spawn_point := Vector2.ZERO
var checkpoint_point := Vector2.ZERO
var checkpoint_active := false
var time_left := 300.0
var stage_score := 0
var coins := 0
var lives := 5
var medals := [false, false, false]
var finished := false
var resetting := false
var shake_time := 0.0
var enemy_speed_scale := 1.0

# HUD
var hud_root: Control
var heart_row: HBoxContainer
var egg_label: Label
var coin_label: Label
var life_label: Label
var score_label: Label
var time_label: Label
var medal_icons: Array[TextureRect] = []
var boss_bar: ProgressBar
var boss_panel: PanelContainer
var cloud_label: Label
var message_layer: CanvasLayer


func _ready() -> void:
	add_to_group("game")
	stage_id = SaveStore.selected_stage
	stage = CATALOG.load_stage(stage_id)
	if stage.is_empty():
		stage_id = "w1_1"
		stage = CATALOG.load_stage(stage_id)
	stage_index = CATALOG.index_of(stage_id)
	world_width = float(stage.world_width)
	enemy_speed_scale = float(stage.get("enemy_speed", 1.0))
	time_left = float(stage.time)
	coins = SaveStore.coins()
	lives = SaveStore.lives()
	TuningStore.begin_run()
	_build_backdrop()
	build_world()
	visual_effects = VISUAL_EFFECTS.new()
	visual_effects.name = "VisualEffects"
	add_child(visual_effects)
	var use_checkpoint := respawn_checkpoint and respawn_stage == stage_id
	respawn_checkpoint = false
	respawn_stage = ""
	spawn_player(checkpoint_point if use_checkpoint else spawn_point)
	if use_checkpoint:
		checkpoint_active = true
		_mark_checkpoint_active()
	build_hud()
	pause_menu = PAUSE_MENU.new()
	pause_menu.name = "PauseMenu"
	pause_menu.main_menu_requested.connect(return_to_map)
	pause_menu.restart_requested.connect(restart_stage)
	add_child(pause_menu)
	SaveStore.cloud_status_changed.connect(_on_cloud_status)
	GameAudio.select_track(THEME_MUSIC.get(stage.theme, &"overworld"))
	GameAudio.begin_game()
	_show_intro()


# ------------------------------------------------------------------ world building --------
func _p(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))


func _build_backdrop() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Backdrop"
	layer.layer = -10
	add_child(layer)
	backdrop = LEVEL_ART.Backdrop.new()
	backdrop.texture = LEVEL_ART.background_texture(int(stage.world))
	backdrop.tint = WORLD_TINT.get(stage.theme, Color.WHITE)
	layer.add_child(backdrop)


func _add(node: Node) -> Node:
	add_child(node)
	return node


func build_world() -> void:
	var theme := str(stage.theme)
	for g: Array in stage.grounds:
		var t := LEVEL_ART.Terrain.new()
		t.rect = Rect2(float(g[0]), float(g[1]), float(g[2]), float(g[3]))
		t.theme = theme
		_add(t)
	for s: Array in stage.get("stumps", []):
		var p := LEVEL_ART.Pillar.new()
		p.center_x = float(s[0])
		p.top = float(s[1])
		p.height = float(s[2])
		p.width = float(s[3])
		p.theme = theme
		_add(p)
	var platform_style := "rock" if theme in ["cave", "castle"] else "log"
	for pl: Array in stage.get("platforms", []):
		var lp := ENTITIES.LogPlatform.new()
		lp.position = Vector2(float(pl[0]), float(pl[1]))
		lp.width = float(pl[2])
		lp.style = platform_style
		_add(lp)
	for mv: Array in stage.get("moving", []):
		var mp := ENTITIES.LogPlatform.new()
		mp.position = Vector2(float(mv[0]), float(mv[1]))
		mp.width = float(mv[2])
		mp.move = Vector2(float(mv[3]), float(mv[4]))
		mp.period = maxf(1.6, float(mv[5]))
		mp.style = platform_style
		_add(mp)
	for fp: Array in stage.get("falling", []):
		var f := ENTITIES.FallingPlatform.new()
		f.position = Vector2(float(fp[0]), float(fp[1]))
		f.width = float(fp[2])
		_add(f)
	for lv: Array in stage.get("lava", []):
		var lava := ENTITIES.Lava.new()
		lava.position = Vector2(float(lv[0]), float(lv[1]))
		lava.size = Vector2(float(lv[2]), float(lv[3]))
		_add(lava)
	for sp: Array in stage.get("spikes", []):
		var spikes := ENTITIES.Spikes.new()
		spikes.position = Vector2(float(sp[0]), float(sp[1]))
		spikes.width = float(sp[2])
		_add(spikes)
	for b: Array in stage.get("blocks", []):
		var block := ENTITIES.Block.new()
		block.position = Vector2(float(b[0]), float(b[1]))
		block.kind = str(b[2])
		block.content = str(b[3])
		block.bumped.connect(_on_block_bumped)
		block.broken.connect(_on_brick_broken)
		_add(block)
	for sg: Array in stage.get("springs", []):
		var spring := ENTITIES.Spring.new()
		spring.position = _p(sg)
		_add(spring)
	for cn: Array in stage.get("cannons", []):
		var cannon := ENTITIES.Cannon.new()
		cannon.position = _p(cn)
		cannon.interval = maxf(1.6, float(cn[2]))
		cannon.speed_scale = enemy_speed_scale
		cannon.fired.connect(func(ball: Node): _spawn_enemy_node(ball))
		_add(cannon)
	for c: Array in stage.get("coins", []):
		_spawn_pickup("coin", _p(c))
	for it: Array in stage.get("items", []):
		_spawn_pickup(str(it[2]), Vector2(float(it[0]), float(it[1])))
	var medal_list: Array = stage.get("medals", [])
	for i in medal_list.size():
		_spawn_pickup("medal", _p(medal_list[i]), i)
	for e: Array in stage.get("enemies", []):
		_spawn_enemy(str(e[0]), Vector2(float(e[1]), float(e[2])))
	spawn_point = _p(stage.spawn)
	checkpoint_point = _p(stage.checkpoint)
	var cp := ENTITIES.Checkpoint.new()
	cp.name = "Checkpoint"
	cp.position = checkpoint_point
	cp.reached.connect(_on_checkpoint)
	_add(cp)
	goal = ENTITIES.Goal.new()
	goal.position = _p(stage.goal)
	goal.reached.connect(_on_goal_reached)
	_add(goal)
	if stage.has("boss"):
		var bd: Dictionary = stage.boss
		boss = ENTITIES.Golem.new()
		boss.position = Vector2(float(bd.x), float(bd.y))
		boss.hp = int(bd.hp)
		boss.max_hp = int(bd.hp)
		boss.world = int(stage.world)
		boss.arena = Vector2(float(bd.arena[0]), float(bd.arena[1]))
		boss.damaged.connect(_on_boss_damaged)
		boss.defeated.connect(_on_boss_defeated)
		boss.slammed.connect(_on_boss_slam)
		boss.fireball_spawned.connect(func(ball: Node): add_child(ball))
		_add(boss)
		goal.locked = true
	# Invisible side walls keep the hero inside the course.
	for x in [-40.0, world_width]:
		var wall := StaticBody2D.new()
		wall.collision_layer = 1
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(40, 3000)
		shape.shape = rect
		shape.position = Vector2(20, -600)
		wall.add_child(shape)
		wall.position = Vector2(x, 0)
		_add(wall)


func _spawn_pickup(kind: String, pos: Vector2, index: int = -1) -> Node:
	var p := ENTITIES.Pickup.new()
	p.kind = kind
	p.index = index
	p.position = pos
	p.collected.connect(_on_pickup)
	_add(p)
	return p


func _spawn_enemy(kind: String, pos: Vector2) -> void:
	var e: Node
	match kind:
		"bat": e = ENTITIES.Bat.new()
		"ghost": e = ENTITIES.Ghost.new()
		"fire_spirit":
			var f := ENTITIES.FireSpirit.new()
			f.position = pos
			f.period = maxf(2.2, 3.4 - float(stage.get("difficulty", 0.5)))
			f.defeated.connect(_on_enemy_defeated)
			_add(f)
			return
		_:
			e = ENTITIES.Walker.new()
	e.kind = kind
	e.position = pos + (Vector2(0, -1) if e is ENTITIES.Walker else Vector2.ZERO)
	e.speed_scale = enemy_speed_scale
	_spawn_enemy_node(e)


func _spawn_enemy_node(e: Node) -> void:
	if e.has_signal("defeated") and not e.defeated.is_connected(_on_enemy_defeated):
		e.defeated.connect(_on_enemy_defeated)
	add_child(e)


func spawn_player(pos: Vector2) -> void:
	player = PLAYER.new()
	player.name = "Player"
	player.position = pos - Vector2(0, PLAYER.FOOT_Y + 2.0)
	add_child(player)
	touch = TOUCH.new()
	player.touch = touch
	player.died.connect(_on_player_died)
	player.hurt_taken.connect(_on_player_hurt)
	player.shot_requested.connect(_on_shot_requested)
	player.out_of_eggs.connect(func(): GameAudio.play(&"invalid"))
	player.stomped.connect(_on_stomped)
	player.jumped.connect(_on_player_jumped)
	player.landed.connect(_on_player_landed)
	player.trail_requested.connect(func(p: Vector2): visual_effects.spawn_run_dust(p))
	player.flutter_started.connect(func(): GameAudio.play(&"flutter"))
	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = TuningStore.get_value("camera_smoothing")
	camera.drag_vertical_enabled = true
	camera.drag_top_margin = 0.55
	camera.drag_bottom_margin = 0.15
	camera.limit_left = 0
	camera.limit_right = int(world_width)
	player.add_child(camera)
	backdrop.camera = camera
	if not get_viewport().size_changed.is_connected(update_camera_bounds):
		get_viewport().size_changed.connect(update_camera_bounds)
	update_camera_bounds()
	camera.reset_smoothing()


func update_camera_bounds() -> void:
	if camera == null:
		return
	camera.zoom = Vector2.ONE * TuningStore.get_value("camera_zoom") * ViewportPolicy.world_scale()
	var vertical_extra := maxf(0.0, get_viewport_rect().size.y / camera.zoom.y - BASE_VIEWPORT_HEIGHT)
	camera.limit_top = -420
	camera.limit_bottom = ceili(BASE_VIEWPORT_HEIGHT + vertical_extra * 0.5)


# ------------------------------------------------------------------ HUD -------------------
func _chip() -> PanelContainer:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.12, 0.25, 0.62)
	style.border_color = Color(1, 1, 1, 0.75)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left = 10
	style.content_margin_right = 12
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	chip.add_theme_stylebox_override("panel", style)
	return chip


func _icon(texture: Texture2D, size: float) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = texture
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(size, size)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _hud_label(text: String, size: int = 20) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", MENU_STYLE.BOLD)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.15, 0.95))
	label.add_theme_constant_override("outline_size", 6)
	return label


func _chip_with(parent: Control, items: Array) -> HBoxContainer:
	var chip := _chip()
	parent.add_child(chip)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 4)
	chip.add_child(row)
	for item in items:
		row.add_child(item)
	return row


func build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HudLayer"
	layer.layer = 10
	add_child(layer)
	hud_root = Control.new()
	hud_root.name = "Hud"
	hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud_root)
	hud_root.add_child(touch)
	var top := HBoxContainer.new()
	top.name = "TopBar"
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 10
	top.offset_right = -10
	top.offset_top = 8
	top.add_theme_constant_override("separation", 8)
	hud_root.add_child(top)
	# Stage label
	var stage_label := _hud_label("%s" % stage.label, 20)
	_chip_with(top, [stage_label])
	# Hearts
	heart_row = _chip_with(top, [])
	# Eggs / coins / lives
	egg_label = _hud_label("×3")
	_chip_with(top, [_icon(ICON_EGG, 26), egg_label])
	coin_label = _hud_label("×00")
	_chip_with(top, [_icon(ICON_COIN, 26), coin_label])
	life_label = _hud_label("×5")
	_chip_with(top, [_icon(ICON_HERO, 30), life_label])
	var medal_row := _chip_with(top, [])
	for i in 3:
		var m := _icon(ICON_MEDAL, 24)
		m.modulate = Color(0.25, 0.25, 0.35, 0.8)
		medal_row.add_child(m)
		medal_icons.append(m)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	score_label = _hud_label("0")
	_chip_with(top, [_hud_label("スコア", 14), score_label])
	time_label = _hud_label("300")
	_chip_with(top, [_hud_label("タイム", 14), time_label])
	var pause_button := Button.new()
	pause_button.name = "PauseButton"
	pause_button.text = "Ⅱ"
	pause_button.tooltip_text = "ポーズ"
	pause_button.custom_minimum_size = Vector2(46, 42)
	pause_button.focus_mode = Control.FOCUS_NONE
	pause_button.add_theme_font_override("font", MENU_STYLE.BOLD)
	pause_button.add_theme_font_size_override("font_size", 20)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.9, 0.25, 0.2, 0.9)
	ps.border_color = Color.WHITE
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(12)
	pause_button.add_theme_stylebox_override("normal", ps)
	pause_button.add_theme_stylebox_override("hover", ps)
	pause_button.add_theme_stylebox_override("pressed", ps)
	pause_button.pressed.connect(toggle_pause)
	top.add_child(pause_button)
	# Boss HP bar (hidden until the fight starts)
	boss_panel = _chip()
	boss_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	boss_panel.offset_top = 62
	boss_panel.offset_left = -170
	boss_panel.offset_right = 170
	boss_panel.visible = false
	hud_root.add_child(boss_panel)
	var boss_row := HBoxContainer.new()
	boss_row.add_theme_constant_override("separation", 8)
	boss_panel.add_child(boss_row)
	boss_row.add_child(_hud_label("マグマゴーレム", 15))
	boss_bar = ProgressBar.new()
	boss_bar.show_percentage = false
	boss_bar.custom_minimum_size = Vector2(170, 18)
	boss_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.05, 0.05, 0.8)
	bg.set_corner_radius_all(8)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#ff5a36")
	fill.set_corner_radius_all(8)
	boss_bar.add_theme_stylebox_override("background", bg)
	boss_bar.add_theme_stylebox_override("fill", fill)
	boss_row.add_child(boss_bar)
	cloud_label = _hud_label("", 13)
	cloud_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	cloud_label.offset_left = 12
	cloud_label.offset_top = -30
	cloud_label.offset_bottom = -8
	hud_root.add_child(cloud_label)
	get_viewport().size_changed.connect(_layout_hud)
	_layout_hud()
	update_hud()


func _layout_hud() -> void:
	if not is_instance_valid(hud_root):
		return
	var size := get_viewport_rect().size
	var compact := size.x < 900
	for label in [egg_label, coin_label, life_label, score_label, time_label]:
		label.add_theme_font_size_override("font_size", 15 if compact else 20)
	var top: HBoxContainer = hud_root.get_node("TopBar")
	top.add_theme_constant_override("separation", 4 if compact else 8)
	# Medal chip is the first to go on narrow screens.
	medal_icons[0].get_parent().get_parent().visible = size.x >= 760


func update_hud() -> void:
	if heart_row == null or player == null:
		return
	var hearts: int = player.hearts
	if heart_row.get_child_count() != player.max_hearts:
		for c in heart_row.get_children():
			c.queue_free()
		for i in player.max_hearts:
			heart_row.add_child(_icon(ICON_HEART, 24))
	for i in heart_row.get_child_count():
		(heart_row.get_child(i) as CanvasItem).modulate = Color.WHITE if i < hearts else Color(0.2, 0.2, 0.3, 0.7)
	egg_label.text = "×%d" % player.eggs
	coin_label.text = "×%02d" % coins
	life_label.text = "×%d" % lives
	score_label.text = "%d" % stage_score
	time_label.text = "%03d" % ceili(maxf(time_left, 0.0))
	time_label.add_theme_color_override("font_color", Color("#ff6b5a") if time_left < 60.0 else Color.WHITE)
	for i in 3:
		medal_icons[i].modulate = Color.WHITE if medals[i] else Color(0.25, 0.25, 0.35, 0.8)


func _on_cloud_status(status: String, _detail: String) -> void:
	if not is_instance_valid(cloud_label):
		return
	match status:
		"syncing": cloud_label.text = "クラウドにセーブ中…"
		"synced": cloud_label.text = "クラウドにセーブしました"
		"error": cloud_label.text = "クラウドセーブに失敗（この端末には保存済み）"
		"expired": cloud_label.text = "ログインが切れました（この端末には保存済み）"
		_: cloud_label.text = ""
	if status == "synced":
		var tween := cloud_label.create_tween()
		cloud_label.modulate.a = 1.0
		tween.tween_interval(2.0)
		tween.tween_property(cloud_label, "modulate:a", 0.0, 0.6)
	else:
		cloud_label.modulate.a = 1.0


func _show_intro() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(box)
	var world_label := _hud_label("ワールド %s  %s" % [stage.label, stage.world_name], 26)
	world_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(world_label)
	var name_label := Label.new()
	name_label.text = str(stage.name)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MENU_STYLE.display(name_label, 52, Color("#fff4c2"), Color("#3a1d0f"), 12)
	box.add_child(name_label)
	if stage_index == 0:
		var hint := _hud_label("←→ いどう ／ スペース ジャンプ（長おしでフワフワ） ／ X タマゴ投げ" if not touch.touch_seen else "左側をスライドでいどう ／ ジャンプ長おしでフワフワ ／ タマゴボタンで投げる", 17)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(hint)
	box.position -= box.get_combined_minimum_size() * 0.5
	box.reset_size()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	var tween := box.create_tween()
	tween.tween_interval(2.2 if stage_index > 0 else 4.0)
	tween.tween_property(box, "modulate:a", 0.0, 0.5)
	tween.tween_callback(layer.queue_free)


# ------------------------------------------------------------------ loop ------------------
func _process(delta: float) -> void:
	if player == null:
		return
	if shake_time > 0.0 and camera != null:
		shake_time = maxf(0.0, shake_time - delta)
		camera.offset = Vector2(randf_range(-7, 7), randf_range(-5, 5)) * (shake_time / 0.45)
	elif camera != null:
		camera.offset = Vector2.ZERO
	if finished or resetting:
		return
	if player.alive:
		time_left -= delta
		if time_left <= 0.0:
			time_left = 0.0
			player.kill()
	if boss != null and is_instance_valid(boss) and not boss_active and player.global_position.x > boss.arena.x + 150.0:
		_start_boss_fight()
	update_hud()


func _start_boss_fight() -> void:
	boss_active = true
	boss.activate()
	boss_panel.visible = true
	boss_bar.max_value = boss.max_hp
	boss_bar.value = boss.hp
	camera.limit_left = int(boss.arena.x - 40.0)
	boss_wall = StaticBody2D.new()
	boss_wall.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(40, 2400)
	shape.shape = rect
	boss_wall.add_child(shape)
	boss_wall.position = Vector2(boss.arena.x - 60.0, -300)
	add_child.call_deferred(boss_wall)
	GameAudio.select_track(&"boss")


# ------------------------------------------------------------------ events ----------------
func _float_text(text: String, pos: Vector2, color: Color = Color.WHITE) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", MENU_STYLE.BOLD)
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.1))
	label.add_theme_constant_override("outline_size", 6)
	label.position = pos + Vector2(-30, -40)
	label.z_index = 30
	add_child(label)
	var tween := label.create_tween()
	tween.tween_property(label, "position:y", label.position.y - 46.0, 0.7).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.7).set_delay(0.35)
	tween.tween_callback(label.queue_free)


func _add_score(points: int, pos: Vector2) -> void:
	stage_score += points
	_float_text(str(points), pos)


func _add_coins(amount: int, pos: Vector2) -> void:
	coins += amount
	stage_score += 100 * amount
	GameAudio.play(&"coin")
	while coins >= 100:
		coins -= 100
		_one_up(pos)


func _one_up(pos: Vector2) -> void:
	lives = mini(99, lives + 1)
	GameAudio.play(&"one_up")
	_float_text("1UP", pos, Color("#7dff7a"))


func _on_pickup(kind: String, pos: Vector2, index: int) -> void:
	if finished:
		return
	match kind:
		"coin":
			_add_coins(1, pos)
			visual_effects.spawn_collect_sparkle(pos)
		"medal":
			if index >= 0 and index < 3:
				medals[index] = true
			_add_score(1000, pos)
			GameAudio.play(&"medal")
			visual_effects.spawn_checkpoint_burst(pos)
		"heart":
			if player.hearts < player.max_hearts:
				player.heal(1)
			else:
				_add_score(1000, pos)
			GameAudio.play(&"powerup")
		"apple":
			_one_up(pos)
		"star":
			player.give_star()
			_add_score(1000, pos)
			GameAudio.play(&"powerup")
		"egg":
			player.add_eggs(3)
			GameAudio.play(&"powerup")
			_float_text("タマゴ+3", pos, Color("#fff2a8"))
	update_hud()


func _on_block_bumped(block: Node, content: String, pos: Vector2) -> void:
	GameAudio.play(&"bump")
	match content:
		"coin":
			_coin_pop(pos)
			_add_coins(1, pos)
		"coins":
			for i in 5:
				_coin_pop(pos + Vector2((i - 2) * 16, 0))
			_add_coins(5, pos)
		"", "none":
			pass
		_:
			var p := _spawn_pickup(content, pos + Vector2(0, -8))
			p.pop_out()
	update_hud()


func _coin_pop(pos: Vector2) -> void:
	var s := Sprite2D.new()
	s.texture = ICON_COIN
	s.scale = Vector2.ONE * (34.0 / ICON_COIN.get_size().y)
	s.position = pos + Vector2(0, -30)
	s.z_index = 20
	add_child(s)
	var tween := s.create_tween()
	tween.tween_property(s, "position:y", s.position.y - 70.0, 0.28).set_ease(Tween.EASE_OUT)
	tween.tween_property(s, "modulate:a", 0.0, 0.18)
	tween.tween_callback(s.queue_free)


func _on_brick_broken(pos: Vector2) -> void:
	stage_score += 50
	visual_effects.spawn_stomp_impact(pos)


func _on_enemy_defeated(kind: String, pos: Vector2, points: int) -> void:
	if finished:
		return
	_add_score(points, pos + Vector2(0, -30))
	if kind != "fire_spirit":
		visual_effects.spawn_stomp_impact(pos + Vector2(0, -20))
	update_hud()


func _on_stomped(pos: Vector2, combo: int) -> void:
	GameAudio.play(&"stomp")
	player.add_eggs(1)
	if combo >= 2:
		var bonus := mini(2000, 100 * int(pow(2.0, combo - 1)))
		if combo >= 7:
			_one_up(pos)
		else:
			_add_score(bonus, pos + Vector2(0, -60))
	update_hud()


func _on_shot_requested(pos: Vector2, direction: float) -> void:
	if finished or resetting or get_tree().paused:
		return
	if get_tree().get_nodes_in_group("egg_projectile").size() >= MAX_EGGS_IN_FLIGHT:
		player.add_eggs(1)
		return
	var egg := EGG.new()
	egg.position = pos
	egg.direction = direction
	egg.speed = TuningStore.get_value("yarn_speed")
	egg.lifetime = TuningStore.get_value("yarn_lifetime")
	egg.enemy_hit.connect(func(_p: Vector2): GameAudio.play(&"kick"))
	egg.block_hit.connect(_on_egg_block)
	add_child(egg)
	GameAudio.play(&"attack")
	update_hud()


func _on_checkpoint(pos: Vector2) -> void:
	if checkpoint_active:
		return
	checkpoint_active = true
	GameAudio.play(&"checkpoint")
	visual_effects.spawn_checkpoint_burst(pos + Vector2(0, -60))
	_float_text("中間ポイント！", pos + Vector2(0, -120), Color("#fff2a8"))
	player.heal(player.max_hearts)
	update_hud()


func _mark_checkpoint_active() -> void:
	var cp := get_node_or_null("Checkpoint")
	if cp != null:
		cp.active = true


func _on_player_hurt(_hearts: int) -> void:
	GameAudio.play(&"hurt")
	shake_time = 0.25
	update_hud()


func _on_boss_damaged(hp: int, max_hp: int) -> void:
	boss_bar.max_value = max_hp
	boss_bar.value = hp
	shake_time = 0.3
	_add_score(500, boss.global_position + Vector2(0, -200))


func _on_boss_slam(pos: Vector2) -> void:
	shake_time = 0.45
	GameAudio.play(&"bump")
	visual_effects.spawn_land_dust(pos)
	# Grounded heroes near the impact get knocked by the shockwave.
	if player.alive and player.is_on_floor() and absf(player.global_position.x - pos.x) < 140.0:
		player.hurt(pos.x)


func _on_boss_defeated(pos: Vector2) -> void:
	boss_bar.value = 0
	_add_score(5000, pos + Vector2(0, -220))
	visual_effects.spawn_finish_confetti(pos + Vector2(0, -120))
	shake_time = 0.6
	goal.locked = false
	GameAudio.play(&"powerup")
	var tween := create_tween()
	tween.tween_interval(1.2)
	tween.tween_callback(func(): boss_panel.visible = false)
	for node in get_tree().get_nodes_in_group("enemy"):
		if node != boss and node.has_method("knock_off") and bool(node.get("alive")):
			node.knock_off(1.0)


# ------------------------------------------------------------------ outcomes --------------
func _on_player_died() -> void:
	if finished or resetting:
		return
	resetting = true
	GameAudio.play(&"death")
	GameAudio.hold_music(true)
	visual_effects.spawn_death_burst(player.global_position)
	touch.clear_input()
	lives -= 1
	var tween := create_tween()
	tween.tween_interval(1.6)
	if lives <= 0:
		SaveStore.game_over_reset()
		tween.tween_callback(_show_game_over)
	else:
		SaveStore.store_run_state(coins, lives)
		respawn_stage = stage_id
		respawn_checkpoint = checkpoint_active
		tween.tween_callback(_reload_stage)


func _reload_stage() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_goal_reached() -> void:
	if finished or resetting or not player.alive:
		return
	finished = true
	player.input_locked = true
	player.velocity.x = 0.0
	touch.clear_input()
	touch.enabled = false
	GameAudio.hold_music(true)
	GameAudio.play(&"stage_clear")
	visual_effects.spawn_finish_confetti(player.global_position + Vector2(0, -90))
	var time_bonus := ceili(time_left) * 20
	var medal_count := medals.count(true)
	var medal_bonus := 2000 if medal_count == 3 else 0
	stage_score += time_bonus + medal_bonus
	var result := SaveStore.record_clear(stage_id, stage_index, stage_score, medals, coins, lives, CATALOG.stage_count())
	update_hud()
	var tween := create_tween()
	tween.tween_interval(1.4)
	tween.tween_callback(_show_clear.bind(time_bonus, medal_bonus, medal_count, bool(result.new_best)))


func _go_next_stage() -> void:
	var next_index := stage_index + 1
	if next_index < CATALOG.stage_count():
		SaveStore.selected_stage = CATALOG.stages()[next_index]
	_reload_stage()


func _on_player_jumped(p: Vector2) -> void:
	GameAudio.play(&"jump")
	visual_effects.spawn_jump_dust(p)


func _on_player_landed(p: Vector2) -> void:
	GameAudio.play(&"land")
	visual_effects.spawn_land_dust(p)


func _on_egg_block(b: Node) -> void:
	if is_instance_valid(b) and b.has_method("bump"):
		b.bump(null)


func _panel_layer() -> VBoxContainer:
	if is_instance_valid(message_layer):
		message_layer.queue_free()
	message_layer = CanvasLayer.new()
	message_layer.layer = 40
	message_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(message_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.05, 0.15, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	message_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	message_layer.add_child(center)
	var card := PanelContainer.new()
	MENU_STYLE.felt_card(card, MENU_STYLE.CREAM, 26)
	center.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(minf(460.0, get_viewport_rect().size.x - 40.0), 0)
	card.add_child(box)
	return box


func _row(box: VBoxContainer, left: String, right: String, highlight: bool = false) -> void:
	var row := HBoxContainer.new()
	box.add_child(row)
	var l := MENU_STYLE.label(left, 20)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var r := MENU_STYLE.label(right, 20)
	if highlight:
		r.add_theme_color_override("font_color", MENU_STYLE.ACCENT)
	row.add_child(r)


func _show_clear(time_bonus: int, medal_bonus: int, medal_count: int, new_best: bool) -> void:
	var box := _panel_layer()
	var title := MENU_STYLE.heading("コースクリア！", 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := MENU_STYLE.label("%s  %s" % [stage.label, stage.name], 18)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	_row(box, "タイムボーナス", "+%d" % time_bonus)
	_row(box, "メダル", "%d / 3%s" % [medal_count, "  (+%d)" % medal_bonus if medal_bonus > 0 else ""])
	_row(box, "スコア", "%d" % stage_score, true)
	if new_best:
		var best := MENU_STYLE.label("ベストスコア更新！", 20)
		best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		best.add_theme_color_override("font_color", MENU_STYLE.ACCENT)
		box.add_child(best)
	var saved := MENU_STYLE.label("セーブしました" + ("（クラウド）" if not SaveStore.is_guest() else "（この端末）"), 15)
	saved.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(saved)
	var next_index := stage_index + 1
	var first: Button = null
	if next_index < CATALOG.stage_count():
		first = _result_button(box, "つぎのステージへ", _go_next_stage, true)
	else:
		var end := MENU_STYLE.label("全ステージクリア！ おめでとう！", 22)
		end.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(end)
	var map_button := _result_button(box, "ワールドマップへ", return_to_map, first == null)
	_result_button(box, "もう一度あそぶ", restart_stage, false)
	(first if first != null else map_button).grab_focus()


func _show_game_over() -> void:
	GameAudio.play(&"game_over")
	var box := _panel_layer()
	var title := MENU_STYLE.heading("ゲームオーバー", 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := MENU_STYLE.label("クリアしたステージとメダルは残っています。\n残り人数は5にもどります。", 17)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	var retry := _result_button(box, "もう一度ちょうせん", restart_stage, true)
	_result_button(box, "ワールドマップへ", return_to_map, false)
	retry.grab_focus()


func _result_button(box: VBoxContainer, text: String, callback: Callable, primary: bool) -> Button:
	var button := MENU_STYLE.button(text, primary)
	button.custom_minimum_size = Vector2(0, 52)
	button.pressed.connect(callback)
	box.add_child(button)
	return button


func restart_stage() -> void:
	respawn_checkpoint = false
	respawn_stage = ""
	if not finished and not resetting:
		SaveStore.store_run_state(coins, lives)
	_reload_stage()


func return_to_map() -> void:
	if not finished and not resetting:
		SaveStore.store_run_state(coins, lives)
	GameAudio.stop_game()
	TuningStore.end_run()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/world_map.tscn")


func toggle_pause() -> void:
	if finished or resetting or pause_menu == null:
		return
	touch.clear_input()
	pause_menu.toggle_menu()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if finished:
			return_to_map()
		else:
			toggle_pause()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	GameAudio.stop_game()
