extends SceneTree
## Developer capture: renders stage snapshots to /tmp/popo_shots for visual QA.
## Run (needs a display): godot --path . --audio-driver Dummy --script test/capture_worlds.gd

const OUT := "/tmp/popo_shots"
const SHOTS := [["w1_2", 0.35], ["w2_2", 0.5], ["w3_2", 0.45], ["w4_2", 0.4], ["w5_2", 0.5], ["w6_2", 0.45], ["w3_4", -1.0], ["w6_4", -1.0]]


func _initialize() -> void:
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size = Vector2i(1280, 720)
	var save: Node = root.get_node("SaveStore")
	save.play_as_guest()
	for shot: Array in SHOTS:
		save.selected_stage = shot[0]
		var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
		root.add_child(game)
		current_scene = game
		await _frames(20)
		var player: Node2D = game.player
		player.invuln = 999.0
		if float(shot[1]) >= 0.0:
			var stage: Dictionary = game.stage
			player.global_position = Vector2(float(stage.world_width) * float(shot[1]), 200.0)
		else:
			player.global_position = Vector2(game.boss.arena.x + 200.0, 300.0)
		await _frames(150)
		var image := root.get_texture().get_image()
		image.save_png("%s/%s.png" % [OUT, shot[0]])
		print("shot ", shot[0])
		game.queue_free()
		current_scene = null
		await _frames(3)
	var map: Node = (load("res://scenes/world_map.tscn") as PackedScene).instantiate()
	root.add_child(map)
	await _frames(30)
	root.get_texture().get_image().save_png(OUT + "/map.png")
	map.queue_free()
	await _frames(3)
	root.get_node("GameAudio").stop_game()
	quit(0)
