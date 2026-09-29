extends Node2D

signal effect_spawned(effect_name: String, amount: int)

const MAX_ACTIVE_BURSTS := 12
const MAX_PARTICLES_PER_BURST := 48

var spawn_counts: Dictionary = {}
var active_bursts: Array[CPUParticles2D] = []
var filter_layer: CanvasLayer
var filter_rect: ColorRect
var feedback_rect: ColorRect
var feedback_time := 0.0
var soft_texture: Texture2D
var sparkle_texture: Texture2D


func _ready() -> void:
	z_index = 8
	soft_texture = _make_soft_circle_texture(16)
	sparkle_texture = _make_diamond_texture(16)
	_build_filter()
	TuningStore.value_changed.connect(func(_key, _value): _update_filter())
	_update_filter()


func _build_filter() -> void:
	filter_layer = CanvasLayer.new()
	filter_layer.layer = 5
	add_child(filter_layer)
	filter_rect = ColorRect.new()
	filter_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	filter_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	filter_layer.add_child(filter_rect)
	feedback_rect = ColorRect.new()
	feedback_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	feedback_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feedback_rect.color = Color(1.0, 0.86, 0.6, 0.0)
	filter_layer.add_child(feedback_rect)


func _update_filter() -> void:
	if filter_rect == null:
		return
	filter_rect.visible = TuningStore.get_value("filter_enabled") > 0.0
	filter_rect.color = Color(0.9, 0.52, 0.18, TuningStore.get_value("filter_intensity"))


func _process(delta: float) -> void:
	feedback_time = maxf(0.0, feedback_time - delta)
	if feedback_rect != null:
		feedback_rect.color.a = 0.0 if TuningStore.get_value("reduced_motion") > 0.0 else feedback_time * 0.5


func reset_effects() -> void:
	for particles in active_bursts:
		if is_instance_valid(particles):
			particles.queue_free()
	active_bursts.clear()
	feedback_time = 0.0
	if feedback_rect != null:
		feedback_rect.color.a = 0.0


func spawn_run_dust(world_position: Vector2) -> void:
	_spawn_burst("trail", world_position, Color("#e9d6a7"), 4, 0.35, Vector2.UP, 65.0, 10.0, 35.0, Vector2(0, 80), 0.22, 0.4, 5.0, soft_texture)


func spawn_jump_dust(world_position: Vector2) -> void:
	_spawn_burst("jump", world_position, Color("#e9d6a7"), 9, 0.42, Vector2.UP, 72.0, 38.0, 92.0, Vector2(0, 420), 0.32, 0.72, 7.0, soft_texture)


func spawn_land_dust(world_position: Vector2) -> void:
	_spawn_burst("land", world_position, Color("#d8c28f"), 14, 0.5, Vector2.UP, 105.0, 45.0, 125.0, Vector2(0, 460), 0.38, 0.9, 12.0, soft_texture)


func spawn_collect_sparkle(world_position: Vector2) -> void:
	_spawn_burst("collect", world_position, Color("#ffe45f"), 16, 0.55, Vector2.UP, 180.0, 80.0, 170.0, Vector2(0, 130), 0.4, 0.9, 8.0, sparkle_texture)


func spawn_stomp_impact(world_position: Vector2) -> void:
	_spawn_burst("stomp", world_position, Color("#ff9f43"), 18, 0.48, Vector2.UP, 180.0, 95.0, 210.0, Vector2(0, 280), 0.42, 1.0, 10.0, sparkle_texture)


func spawn_death_burst(world_position: Vector2) -> void:
	_spawn_burst("death", world_position, Color("#ff654d"), 26, 0.85, Vector2.UP, 180.0, 110.0, 250.0, Vector2(0, 520), 0.45, 1.15, 12.0, sparkle_texture)


func spawn_checkpoint_burst(world_position: Vector2) -> void:
	_spawn_burst("checkpoint", world_position, Color("#7af4cf"), 24, 0.9, Vector2.UP, 180.0, 75.0, 190.0, Vector2(0, 80), 0.38, 1.0, 16.0, sparkle_texture)


func spawn_finish_confetti(world_position: Vector2) -> void:
	_spawn_burst("finish", world_position, Color("#8de8ff"), 48, 1.5, Vector2.UP, 82.0, 180.0, 360.0, Vector2(0, 520), 0.5, 1.25, 22.0, sparkle_texture)


func get_spawn_count(effect_name: String) -> int:
	return int(spawn_counts.get(effect_name, 0))


func _spawn_burst(
	effect_name: String,
	world_position: Vector2,
	base_color: Color,
	amount: int,
	lifetime: float,
	direction: Vector2,
	spread: float,
	velocity_min: float,
	velocity_max: float,
	gravity: Vector2,
	scale_min: float,
	scale_max: float,
	emission_radius: float,
	particle_texture: Texture2D,
) -> void:
	active_bursts = active_bursts.filter(func(item): return is_instance_valid(item) and not item.is_queued_for_deletion())
	if active_bursts.size() >= MAX_ACTIVE_BURSTS:
		return
	var density := TuningStore.get_value("particles_density")
	if density <= 0.0:
		return
	var reduced := TuningStore.get_value("reduced_motion") > 0.0
	if reduced and effect_name == "trail":
		return
	var particles := CPUParticles2D.new()
	particles.name = effect_name.capitalize().replace(" ", "") + "Particles"
	particles.position = world_position
	particles.z_index = 8
	particles.texture = particle_texture
	particles.amount = clampi(roundi(amount * density), 1, MAX_PARTICLES_PER_BURST)
	if reduced:
		particles.amount = mini(particles.amount, 4)
	particles.lifetime = lifetime
	particles.one_shot = true
	particles.explosiveness = 0.92
	particles.randomness = 0.55
	particles.direction = direction
	particles.spread = spread
	particles.gravity = Vector2.ZERO if reduced else gravity
	particles.initial_velocity_min = 0.0 if reduced else velocity_min
	particles.initial_velocity_max = 0.0 if reduced else velocity_max
	particles.scale_amount_min = scale_min
	particles.scale_amount_max = scale_max
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = emission_radius
	particles.color_ramp = _make_fade_ramp(base_color)
	particles.finished.connect(func():
		active_bursts.erase(particles)
		particles.queue_free()
	)
	active_bursts.append(particles)
	add_child(particles)
	spawn_counts[effect_name] = get_spawn_count(effect_name) + 1
	effect_spawned.emit(effect_name, particles.amount)
	if effect_name in ["stomp", "death", "checkpoint", "finish"]:
		feedback_time = 0.18
	particles.restart()


func _make_fade_ramp(base_color: Color) -> Gradient:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.68, 1.0])
	gradient.colors = PackedColorArray([
		base_color.lightened(0.16),
		base_color,
		Color(base_color.r, base_color.g, base_color.b, 0.0),
	])
	return gradient


func _make_soft_circle_texture(size: int) -> Texture2D:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size - 1, size - 1) * 0.5
	var radius := float(size) * 0.5
	for y in range(size):
		for x in range(size):
			var distance := Vector2(x, y).distance_to(center) / radius
			var alpha := pow(clampf(1.0 - distance, 0.0, 1.0), 0.7)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)


func _make_diamond_texture(size: int) -> Texture2D:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size - 1, size - 1) * 0.5
	var radius := float(size) * 0.5
	for y in range(size):
		for x in range(size):
			var distance := (absf(float(x) - center.x) + absf(float(y) - center.y)) / radius
			var alpha := clampf(1.0 - distance, 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)
