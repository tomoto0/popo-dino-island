extends CharacterBody2D
## Popo the dino: responsive run/jump (coyote time, jump buffer, variable height), flutter
## hover (hold jump while falling), egg throwing, hearts with invulnerability, star power.

signal died
signal hurt_taken(hearts: int)
signal shot_requested(position: Vector2, direction: float)
signal out_of_eggs
signal stomped(position: Vector2, combo: int)
signal jumped(position: Vector2)
signal landed(position: Vector2)
signal trail_requested(position: Vector2)
signal flutter_started

const HITBOX_RADIUS := 18.0
const HITBOX_HEIGHT := 56.0
const FOOT_Y := HITBOX_HEIGHT * 0.5
const SPRITE_HEIGHT := 84.0
const FLUTTER_TIME := 0.85
const FLUTTER_TARGET := -70.0
const FLUTTER_ACCEL := 3400.0
const SPRING_POWER := 1180.0
const SPRING_BOOST := 1320.0
const INVULN_TIME := 1.6
const STAR_TIME := 8.0
const MAX_EGGS := 6

const TEX_IDLE = preload("res://assets/game/hero/idle.webp")
const TEX_WALK_1 = preload("res://assets/game/hero/walk_1.webp")
const TEX_WALK_2 = preload("res://assets/game/hero/walk_2.webp")
const TEX_JUMP = preload("res://assets/game/hero/jump.webp")
const TEX_FLUTTER = preload("res://assets/game/hero/flutter.webp")
const TEX_THROW = preload("res://assets/game/hero/throw.webp")

var alive := true
var facing := 1.0
var spawn_position := Vector2.ZERO
var coyote_time := 0.0
var jump_buffer := 0.0
var anim_time := 0.0
var touch: Node = null
var was_on_floor := false
var attack_cooldown_left := 0.0
var throw_flash := 0.0
var stomp_grace := 0.0
var trail_timer := 0.0
var suppress_actions_until_release := false
var hearts := 3
var max_hearts := 3
var eggs := 3
var invuln := 0.0
var star_time := 0.0
var flutter_left := FLUTTER_TIME
var fluttering := false
var combo := 0
var input_locked := false
var landing_squash := 0.0


func _ready() -> void:
	add_to_group("player")
	add_to_group("transient_input")
	collision_layer = 2
	collision_mask = 1 | 4
	floor_snap_length = 8.0
	spawn_position = global_position
	var shape := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = HITBOX_RADIUS
	capsule.height = HITBOX_HEIGHT
	shape.shape = capsule
	add_child(shape)
	queue_redraw()


func star_active() -> bool:
	return star_time > 0.0


func is_invulnerable() -> bool:
	return invuln > 0.0 or star_time > 0.0


func _touch_value(name: String, fallback: Variant) -> Variant:
	if touch == null:
		return fallback
	return touch.get(name)


func _physics_process(delta: float) -> void:
	stomp_grace = maxf(0.0, stomp_grace - delta)
	attack_cooldown_left = maxf(0.0, attack_cooldown_left - delta)
	throw_flash = maxf(0.0, throw_flash - delta)
	landing_squash = maxf(0.0, landing_squash - delta * 5.0)
	invuln = maxf(0.0, invuln - delta)
	star_time = maxf(0.0, star_time - delta)
	collision_mask = 1 if invuln > 0.0 else (1 | 4)
	var gravity := TuningStore.get_value("gravity")
	if not alive:
		velocity.y += gravity * delta
		position += velocity * delta
		queue_redraw()
		return

	anim_time += delta
	var on_floor := is_on_floor()
	if on_floor:
		coyote_time = TuningStore.get_value("coyote_time")
		flutter_left = FLUTTER_TIME
		combo = 0
	else:
		coyote_time = maxf(coyote_time - delta, 0.0)
		velocity.y += gravity * delta

	var touch_jump_held := bool(_touch_value("jump_held", false))
	var touch_jump_pressed := bool(touch.consume_jump()) if touch != null else false
	var touch_attack := bool(touch.consume_attack()) if touch != null else false
	var jump_held := Input.is_action_pressed("jump") or touch_jump_held
	if suppress_actions_until_release and not jump_held and not Input.is_action_pressed("attack"):
		suppress_actions_until_release = false
	var jump_started := not input_locked and not suppress_actions_until_release and (Input.is_action_just_pressed("jump") or touch_jump_pressed)
	var jump_released := not jump_held

	if jump_started:
		jump_buffer = TuningStore.get_value("jump_buffer")
	else:
		jump_buffer = maxf(jump_buffer - delta, 0.0)

	var direction := 0.0 if input_locked else Input.get_axis("move_left", "move_right")
	if absf(direction) <= 0.05 and not input_locked:
		direction = float(_touch_value("move_x", 0.0))
	var top_speed := TuningStore.get_value("move_speed") * (0.85 if fluttering else 1.0)
	if absf(direction) > 0.05:
		velocity.x = move_toward(velocity.x, direction * top_speed, TuningStore.get_value("acceleration") * delta)
		facing = signf(direction)
	else:
		velocity.x = move_toward(velocity.x, 0.0, TuningStore.get_value("friction") * delta)

	if not input_locked and not suppress_actions_until_release and (Input.is_action_just_pressed("attack") or touch_attack):
		try_attack()

	if jump_buffer > 0.0 and coyote_time > 0.0:
		velocity.y = -TuningStore.get_value("jump_power")
		jump_buffer = 0.0
		coyote_time = 0.0
		fluttering = false
		jumped.emit(global_position + Vector2(0, FOOT_Y))
	var jump_release_speed := TuningStore.get_value("jump_release_speed")
	if jump_released and velocity.y < -jump_release_speed and not fluttering:
		velocity.y = -jump_release_speed

	# Flutter: hold jump while falling to hover briefly (once per airtime budget).
	var can_flutter := not on_floor and jump_held and not suppress_actions_until_release and flutter_left > 0.0 and velocity.y > -40.0
	if can_flutter:
		if not fluttering:
			fluttering = true
			flutter_started.emit()
		velocity.y = move_toward(velocity.y, FLUTTER_TARGET, FLUTTER_ACCEL * delta)
		flutter_left -= delta
	elif fluttering and (not jump_held or flutter_left <= 0.0 or on_floor):
		fluttering = false

	var feet_before_move := global_position.y + FOOT_Y
	var vertical_speed_before_move := velocity.y
	move_and_slide()
	var now_on_floor := is_on_floor()
	if not was_on_floor and now_on_floor and vertical_speed_before_move > 140.0:
		landed.emit(global_position + Vector2(0, FOOT_Y))
		landing_squash = 1.0
	was_on_floor = now_on_floor
	trail_timer = maxf(0.0, trail_timer - delta)
	if now_on_floor and absf(velocity.x) > 90.0 and trail_timer <= 0.0:
		trail_timer = 0.16
		trail_requested.emit(global_position + Vector2(0, FOOT_Y))
	_resolve_contacts(feet_before_move, vertical_speed_before_move, jump_held)
	if star_time > 0.0:
		_star_sweep()
	if global_position.y > 860.0:
		kill()
	queue_redraw()


func _resolve_contacts(feet_before_move: float, vertical_speed_before_move: float, jump_held: bool) -> void:
	var enemy_contacts: Array = []
	var stomped_any := false
	var hurt_from := INF
	for index in get_slide_collision_count():
		var hit := get_slide_collision(index)
		var collider := hit.get_collider()
		if collider == null:
			continue
		if collider.is_in_group("enemy"):
			if not bool(collider.get("alive")):
				if collider.has_method("on_side_touch"):
					collider.on_side_touch(self)
				continue
			var from_above := hit.get_normal().y < -0.45
			if collider.has_method("stomp_top_y"):
				from_above = from_above or feet_before_move <= float(collider.stomp_top_y()) + 8.0
			if star_time > 0.0 and collider.has_method("hit_by_star"):
				collider.hit_by_star(global_position.x)
				continue
			if vertical_speed_before_move >= 0.0 and from_above and collider.has_method("on_stomp"):
				var result: String = collider.on_stomp(self)
				if result == "bounce":
					stomped_any = true
					combo += 1
					stomped.emit(collider.global_position, combo)
				elif result == "hurt":
					hurt_from = collider.global_position.x
				continue
			enemy_contacts.append(collider)
		elif collider.is_in_group("block") and hit.get_normal().y > 0.55:
			collider.bump(self)
		elif collider.is_in_group("spring") and hit.get_normal().y < -0.55:
			collider.compress()
			velocity.y = -(SPRING_BOOST if jump_held else SPRING_POWER)
			flutter_left = FLUTTER_TIME
			fluttering = false
			jumped.emit(global_position + Vector2(0, FOOT_Y))
		elif collider.is_in_group("falling_platform") and hit.get_normal().y < -0.55:
			collider.stood_on()
	if stomped_any:
		var bounce := TuningStore.get_value("stomp_bounce")
		velocity.y = -(bounce * 1.75 if jump_held else bounce)
		stomp_grace = 0.14
		flutter_left = FLUTTER_TIME
	if hurt_from != INF:
		hurt(hurt_from)
	elif stomp_grace <= 0.0:
		for collider in enemy_contacts:
			if not is_instance_valid(collider) or not bool(collider.get("alive")):
				continue
			if collider.has_method("on_side_touch") and collider.on_side_touch(self):
				continue
			if bool(collider.get("harmful")):
				hurt(collider.global_position.x)
				break


func _star_sweep() -> void:
	for node in get_tree().get_nodes_in_group("enemy"):
		if node.has_method("hit_by_star") and bool(node.get("alive")) and node.global_position.distance_to(global_position) < 58.0:
			node.hit_by_star(global_position.x)


func hurt(from_x: float) -> void:
	if not alive or is_invulnerable():
		return
	hearts -= 1
	if hearts <= 0:
		hearts = 0
		kill()
		return
	invuln = INVULN_TIME
	var away := signf(global_position.x - from_x)
	velocity = Vector2((away if away != 0.0 else -facing) * 280.0, -360.0)
	fluttering = false
	hurt_taken.emit(hearts)


func kill() -> void:
	if not alive:
		return
	alive = false
	hearts = 0
	collision_mask = 0
	collision_layer = 0
	velocity = Vector2(0, -620)
	fluttering = false
	died.emit()


func heal(amount: int = 1) -> void:
	hearts = mini(max_hearts, hearts + amount)


func add_eggs(amount: int) -> void:
	eggs = clampi(eggs + amount, 0, MAX_EGGS)


func give_star() -> void:
	star_time = STAR_TIME


func try_attack() -> bool:
	if not alive or get_tree().paused or attack_cooldown_left > 0.0:
		return false
	TuningStore.apply_boundary("NEXT_ACTION")
	attack_cooldown_left = maxf(0.18, TuningStore.get_value("attack_cooldown"))
	if eggs <= 0:
		out_of_eggs.emit()
		return false
	eggs -= 1
	throw_flash = 0.22
	shot_requested.emit(global_position + Vector2(facing * 20.0, -10.0), facing)
	return true


func current_sprite_texture() -> Texture2D:
	if not alive:
		return TEX_JUMP
	if throw_flash > 0.0:
		return TEX_THROW
	if not is_on_floor():
		return TEX_FLUTTER if fluttering else TEX_JUMP
	if absf(velocity.x) > 40.0:
		var frame := int(anim_time * (8.0 + absf(velocity.x) / 40.0)) % 4
		return [TEX_WALK_1, TEX_IDLE, TEX_WALK_2, TEX_IDLE][frame]
	return TEX_IDLE


func _draw() -> void:
	if alive and invuln > 0.0 and int(invuln * 14.0) % 2 == 0:
		return
	var texture := current_sprite_texture()
	var size := texture.get_size()
	var s := SPRITE_HEIGHT / size.y
	var squash := Vector2.ONE
	if alive:
		squash = Vector2(1.0 + landing_squash * 0.12, 1.0 - landing_squash * 0.12)
		if fluttering:
			squash.y += sin(anim_time * 50.0) * 0.03
		elif is_on_floor() and absf(velocity.x) > 40.0:
			squash.y += sin(anim_time * 18.0) * 0.02
	var draw_size := size * s * squash
	var tint := Color.WHITE
	if star_time > 0.0:
		tint = Color.from_hsv(fmod(anim_time * 2.5, 1.0), 0.45, 1.0)
	var rot := 0.0 if alive else PI
	draw_set_transform(Vector2(0, 0 if alive else -10), rot, Vector2(facing, 1.0))
	draw_texture_rect(texture, Rect2(Vector2(-draw_size.x * 0.5, FOOT_Y - draw_size.y + 2.0), draw_size), false, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func clear_input() -> void:
	jump_buffer = 0.0
	suppress_actions_until_release = true
	if touch != null and touch.has_method("clear_input"):
		touch.clear_input()
