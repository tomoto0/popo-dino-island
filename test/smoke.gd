extends SceneTree
## End-to-end smoke test for Popo's Dino Island. Prints [SMOKE_PASS] when every check holds.

const CATALOG = preload("res://scripts/stage_catalog.gd")
const AUDIO_CATALOG = preload("res://scripts/audio_catalog.gd")
var ENTITIES: GDScript
const GAME_FONT_PATH := "res://assets/template/fonts/ui_regular.tres"
const JP_TEXT := "ポポのダイノアイランドワールド草原高原洞城天空森コースクリアゲームオーバーセーブ中間ポイントタマゴ、。！？：（）×←→"
var failures := 0
var I18N: Node
var SAVE: Node
var AUDIO: Node


func _initialize() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	failures += 1
	print("[SMOKE_FAIL] ", message)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _press(action: StringName, frames: int) -> void:
	Input.action_press(action)
	await _frames(frames)
	Input.action_release(action)


func _verify_fonts() -> void:
	var label := Label.new()
	root.add_child(label)
	var font := label.get_theme_font("font")
	label.free()
	_check(font != null and font.resource_path == GAME_FONT_PATH, "controls inherit the bundled UI font")
	if font == null:
		return
	var leaks_system := func(f: Font) -> bool: return (f.base_font if f is FontVariation else f).allow_system_fallback
	_check(not font.fallbacks.any(leaks_system), "bundled fonts never fall back to system fonts")
	for path in [GAME_FONT_PATH, "res://assets/template/fonts/ui_bold.tres", "res://assets/template/fonts/ui_medium.tres", "res://assets/template/fonts/display/display_title.tres", "res://assets/template/fonts/display/display_heading.tres", "res://assets/template/fonts/display/display_small.tres"]:
		var f := load(path) as Font
		for ch in JP_TEXT:
			if f == null or not f.has_char(ch.unicode_at(0)):
				_fail("font %s lacks U+%04X" % [path.get_file(), ch.unicode_at(0)])
				break


func _run() -> void:
	root.size = Vector2i(1280, 720)
	I18N = root.get_node("I18n")
	SAVE = root.get_node("SaveStore")
	AUDIO = root.get_node("GameAudio")
	ENTITIES = load("res://scripts/entities.gd")
	await _frames(2)
	_verify_fonts()
	_check(I18N.get_locale() == "ja", "locale pinned to Japanese")
	_check(I18N.t("pause.resume") == "つづける", "Japanese pause copy")
	# Stage catalogue: 24 stages, 6 worlds, boss at every x-4, rising difficulty.
	var ids := CATALOG.stages()
	_check(ids.size() == 24, "24 stages in catalogue (got %d)" % ids.size())
	var last_difficulty := -1.0
	var stage_music: Dictionary[StringName, bool] = {}
	for id: String in ids:
		var stage := CATALOG.load_stage(id)
		_check(not stage.is_empty(), "stage loads: " + id)
		if stage.is_empty():
			continue
		_check(float(stage.difficulty) >= last_difficulty, "difficulty never drops at " + id)
		last_difficulty = float(stage.difficulty)
		_check((stage.medals as Array).size() == 3, "3 medals in " + id)
		_check(stage.has("boss") == (int(stage.index) == 4), "boss only in x-4 stages: " + id)
		var music_key: StringName = StringName(str(stage.get("music", "")))
		_check(AUDIO_CATALOG.BGM_TRACKS.has(music_key), "BGM track registered: " + id)
		var music_path: String = String(AUDIO_CATALOG.BGM_TRACKS.get(music_key, ""))
		_check(load(music_path) is AudioStream, "BGM track loads: " + id)
		stage_music[music_key] = true
	_check(stage_music.size() == ids.size(), "every stage has a different BGM")
	# Guest save starts fresh.
	SAVE.play_as_guest()
	_check(SAVE.is_guest() and SAVE.unlocked_count() == 1 and SAVE.lives() == 5, "fresh guest save")
	# Title screen offers register / login / guest.
	var title: Control = (load("res://scenes/title_screen.tscn") as PackedScene).instantiate()
	root.add_child(title)
	await _frames(3)
	for node_name in ["UsernameField", "PasswordField", "SubmitButton", "GuestButton", "RegisterTab", "LoginTab"]:
		_check(title.find_child(node_name, true, false) != null, "title has " + node_name)
	var submit := title.find_child("SubmitButton", true, false) as Button
	var name_field := title.find_child("UsernameField", true, false) as LineEdit
	if submit != null and name_field != null:
		name_field.text = "ab"
		submit.pressed.emit()
		await _frames(2)
		var status := title.find_child("StatusLabel", true, false) as Label
		_check(status != null and status.text.contains("3〜16"), "title rejects a too-short username")
	title.queue_free()
	await _frames(2)
	# World map shows world 1 with only 1-1 unlocked.
	var map: Control = (load("res://scenes/world_map.tscn") as PackedScene).instantiate()
	root.add_child(map)
	await _frames(3)
	var grid := map.find_child("StageGrid", true, false) as GridContainer
	_check(grid != null and grid.get_child_count() == 4, "world map lists 4 stages")
	if grid != null and grid.get_child_count() == 4:
		_check(not (grid.get_child(0) as Button).disabled and (grid.get_child(1) as Button).disabled, "only 1-1 unlocked at start")
	map.queue_free()
	await _frames(2)
	# Stage 1-1 gameplay.
	SAVE.selected_stage = "w1_1"
	var game := await _start_game()
	var player := game.player as CharacterBody2D
	_check(player != null and player.is_in_group("player"), "player spawned")
	_check(not get_nodes_in_group("enemy").is_empty(), "stage has enemies")
	_check(game.get_node_or_null("PauseMenu") != null and game.get_node_or_null("VisualEffects") != null, "pause menu + VFX exist")
	_check(game.hud_root != null and game.time_label != null, "HUD built")
	await _frames(40)
	_check(player.is_on_floor(), "player lands on the ground")
	var start_x := player.global_position.x
	await _press(&"move_right", 50)
	_check(player.global_position.x > start_x + 120.0, "player runs right (moved %.0f)" % (player.global_position.x - start_x))
	await _frames(30)
	var ground_y := player.global_position.y
	var apex := ground_y
	Input.action_press(&"jump")
	for i in 70:
		await physics_frame
		apex = minf(apex, player.global_position.y)
	Input.action_release(&"jump")
	_check(ground_y - apex >= 170.0, "full jump reaches 170px+ (got %.0f)" % (ground_y - apex))
	await _frames(60)
	# Stomp an acorn.
	var foe: Node2D = ENTITIES.Walker.new()
	foe.kind = "acorn"
	foe.position = player.global_position + Vector2(0, 8)
	foe.defeated.connect(game._on_enemy_defeated)
	game.add_child(foe)
	foe.set_physics_process(false)
	await _frames(2)
	player.global_position = foe.global_position + Vector2(0, -120)
	player.velocity = Vector2(0, 300)
	var score_before: int = game.stage_score
	var eggs_before: int = player.eggs
	await _frames(40)
	_check(not foe.alive, "stomp defeats the acorn")
	_check(game.stage_score > score_before, "stomp awards points")
	_check(player.eggs >= mini(6, eggs_before + 1), "stomp gives an egg")
	_check(player.alive and player.hearts == 3, "stomping does not hurt the hero")
	# Throw an egg.
	await _frames(30)
	player.eggs = 3
	player.attack_cooldown_left = 0.0
	await _press(&"attack", 2)
	await _frames(1)
	_check(not get_nodes_in_group("egg_projectile").is_empty(), "egg projectile spawned")
	_check(player.eggs == 2, "throwing uses an egg (eggs=%d)" % player.eggs)
	# Item block gives coins.
	var coins_before: int = game.coins
	var block: Node = ENTITIES.Block.new()
	block.kind = "item"
	block.content = "coin"
	block.position = player.global_position + Vector2(400, -300)
	block.bumped.connect(game._on_block_bumped)
	game.add_child(block)
	await _frames(1)
	block.bump(null)
	await _frames(2)
	_check(game.coins == coins_before + 1, "item block gives a coin")
	# Getting hurt removes a heart.
	player.invuln = 0.0
	player.star_time = 0.0
	player.hurt(player.global_position.x + 10.0)
	_check(player.hearts == 2, "damage removes a heart")
	player.heal(1)
	# Pause toggles the tree.
	game.toggle_pause()
	await process_frame
	_check(paused, "pause menu pauses the game")
	game.pause_menu.close_menu()
	await process_frame
	_check(not paused, "closing pause resumes")
	# Checkpoint + goal: clear the stage and unlock 1-2.
	player.invuln = 5.0
	player.global_position = game.checkpoint_point + Vector2(0, -60)
	player.velocity = Vector2.ZERO
	await _frames(20)
	_check(game.checkpoint_active, "checkpoint activates")
	player.global_position = game.goal.global_position + Vector2(-10, -60)
	player.velocity = Vector2.ZERO
	await _frames(30)
	_check(game.finished, "goal clears the stage")
	_check(SAVE.unlocked_count() >= 2 and SAVE.stage_record("w1_1").cleared, "clear is saved and unlocks 1-2")
	await _frames(110)
	_check(game.message_layer != null and is_instance_valid(game.message_layer), "clear results shown")
	await _stop_game(game)
	# Losing a life keeps progress and respawns at the checkpoint.
	SAVE.selected_stage = "w1_2"
	game = await _start_game()
	await _frames(20)
	var lives_before: int = SAVE.lives()
	game.checkpoint_active = true
	game.player.kill()
	await _frames(5)
	_check(SAVE.lives() == lives_before - 1, "death costs one life")
	await _frames(130)
	var reloaded: Node = current_scene
	_check(reloaded != null and reloaded != game and reloaded.get("player") != null, "stage reloads after death")
	if reloaded != null and reloaded.get("player") != null:
		await _frames(5)
		_check(reloaded.checkpoint_active and absf(reloaded.player.global_position.x - reloaded.checkpoint_point.x) < 80.0, "respawn at the checkpoint")
		await _stop_game(reloaded)
	# Boss stage: fight starts in the arena; beating the golem unlocks the goal.
	SAVE.selected_stage = "w1_4"
	game = await _start_game()
	_check(game.boss != null and game.goal.locked, "boss stage has a locked goal")
	if game.boss != null:
		game.player.invuln = 30.0
		game.player.global_position = Vector2(game.boss.arena.x + 260.0, 400.0)
		await _frames(20)
		_check(game.boss_active, "boss fight starts in the arena")
		_check(AUDIO.current_track == &"w1_4", "boss arena keeps its course-specific BGM")
		game.boss.hp = 1
		game.boss.flash = 0.0
		game.boss.hit_by_egg()
		await _frames(10)
		_check(not game.boss.alive and not game.goal.locked, "defeating the boss unlocks the goal")
	await _stop_game(game)
	# Every stage builds and spawns the hero above the kill plane.
	for id: String in ids:
		SAVE.selected_stage = id
		var g := await _start_game(4)
		_check(g.player != null and g.goal != null, "stage builds: " + id)
		_check(AUDIO.current_track == StringName(id), "course-specific BGM starts: " + id)
		if g.player != null:
			_check(g.player.global_position.y < 700.0, "spawn above the kill plane: " + id)
		await _stop_game(g)
	# Pause menu returns to the world map.
	SAVE.selected_stage = "w1_1"
	game = await _start_game()
	game.pause_menu.open_menu()
	game.pause_menu._request_main_menu()
	game.pause_menu._confirm_loss()
	await _frames(4)
	_check(current_scene != null and current_scene.scene_file_path == "res://scenes/world_map.tscn", "pause menu returns to the world map")
	AUDIO.stop_game()
	OS.delay_msec(180)
	await process_frame
	if failures == 0:
		print("[SMOKE_PASS] fonts, stages, title/login, map, run/jump, stomp, eggs, blocks, damage, pause, checkpoint, goal save, death respawn, boss, all 24 stages")
	quit(0 if failures == 0 else 1)


func _start_game(settle: int = 10) -> Node:
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	await _frames(settle)
	return game


func _stop_game(game: Node) -> void:
	paused = false
	if is_instance_valid(game):
		game.queue_free()
	current_scene = null
	await _frames(3)
