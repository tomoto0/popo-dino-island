extends Node
class_name PopoEntities
## Gameplay entities for Popo's Dino Island. Every entity is built in code; art comes from
## res://assets/game/** (AI-generated originals). Physics layers:
##   1 = world solids, 2 = player, 4 = enemies. Areas detect the player through mask 2.

const TEX := {
	"acorn": [preload("res://assets/game/acorn/walk_1.webp"), preload("res://assets/game/acorn/walk_2.webp")],
	"acorn_flat": preload("res://assets/game/acorn/flat.webp"),
	"beetle": [preload("res://assets/game/beetle/walk_1.webp"), preload("res://assets/game/beetle/walk_2.webp")],
	"beetle_shell": preload("res://assets/game/beetle/shell.webp"),
	"bat": [preload("res://assets/game/bat/fly_1.webp"), preload("res://assets/game/bat/fly_2.webp")],
	"hedgehog": [preload("res://assets/game/hedgehog/walk_1.webp"), preload("res://assets/game/hedgehog/walk_2.webp")],
	"ghost": preload("res://assets/game/ghost/chase.webp"),
	"ghost_shy": preload("res://assets/game/ghost/shy.webp"),
	"skeleton": [preload("res://assets/game/skeleton/walk_1.webp"), preload("res://assets/game/skeleton/walk_2.webp")],
	"skeleton_pile": preload("res://assets/game/skeleton/pile.webp"),
	"fire_spirit": preload("res://assets/game/fire_spirit/idle.webp"),
	"cannonball": preload("res://assets/game/cannonball/fly.webp"),
	"cannon": preload("res://assets/game/cannon/idle.webp"),
	"golem": preload("res://assets/game/golem/idle.webp"),
	"golem_stomp": preload("res://assets/game/golem/stomp.webp"),
	"golem_hurt": preload("res://assets/game/golem/hurt.webp"),
	"boss_fireball": preload("res://assets/game/boss_fireball/fly.webp"),
	"coin": preload("res://assets/game/items/coin.webp"),
	"medal": preload("res://assets/game/items/medal.webp"),
	"heart": preload("res://assets/game/items/heart.webp"),
	"apple": preload("res://assets/game/items/apple.webp"),
	"star": preload("res://assets/game/items/star.webp"),
	"egg": preload("res://assets/game/items/egg.webp"),
	"spring": preload("res://assets/game/items/spring.webp"),
	"block_item": preload("res://assets/game/blocks/item.webp"),
	"block_used": preload("res://assets/game/blocks/used.webp"),
	"block_brick": preload("res://assets/game/blocks/brick.webp"),
	"block_crate": preload("res://assets/game/blocks/crate.webp"),
	"goal": preload("res://assets/game/props/goal.webp"),
	"checkpoint": preload("res://assets/game/props/checkpoint.webp"),
	"log": preload("res://assets/game/props/log_platform.webp"),
	"rock": preload("res://assets/game/props/rock_platform.webp"),
	"spikes": preload("res://assets/game/props/spikes.webp"),
}

## Display height (world px) of each enemy sprite canvas.
const ENEMY_HEIGHT := {"acorn": 58.0, "beetle": 56.0, "bat": 58.0, "hedgehog": 56.0, "ghost": 74.0, "skeleton": 82.0, "cannonball": 46.0}
## Hitbox size (w, h); walkers have their origin at the feet.
const ENEMY_BOX := {"acorn": Vector2(40, 38), "beetle": Vector2(46, 34), "bat": Vector2(44, 30), "hedgehog": Vector2(44, 34), "ghost": Vector2(48, 50), "skeleton": Vector2(40, 58), "cannonball": Vector2(38, 38)}
const ENEMY_SPEED := {"acorn": 1.0, "beetle": 0.9, "hedgehog": 0.75, "skeleton": 0.85}
const POINTS := {"acorn": 100, "beetle": 200, "bat": 200, "hedgehog": 300, "ghost": 400, "skeleton": 300, "cannonball": 200, "fire_spirit": 500}


## Draw a texture scaled to `height`, anchored at the bottom centre (or centre), optionally mirrored.
static func draw_sprite(ci: CanvasItem, texture: Texture2D, height: float, flip: bool = false, bottom_anchor: bool = true, offset: Vector2 = Vector2.ZERO, tint: Color = Color.WHITE, squash: Vector2 = Vector2.ONE) -> void:
	if texture == null:
		return
	var size := texture.get_size()
	var s := height / size.y
	var draw_size := size * s * squash
	var origin := Vector2(-draw_size.x * 0.5, -draw_size.y if bottom_anchor else -draw_size.y * 0.5) + offset
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1.0 if flip else 1.0, 1.0))
	if flip:
		origin.x = -draw_size.x * 0.5 - offset.x
	ci.draw_texture_rect(texture, Rect2(origin, draw_size), false, tint)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _rect_shape(node: CollisionObject2D, size: Vector2, offset: Vector2, one_way: bool = false) -> CollisionShape2D:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	shape.position = offset
	shape.one_way_collision = one_way
	node.add_child(shape)
	return shape


static func _player() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.get_first_node_in_group("player") if tree != null else null


# ------------------------------------------------------------------------------------------
# Enemies
# ------------------------------------------------------------------------------------------
class Enemy:
	extends CharacterBody2D
	signal defeated(kind: String, position: Vector2, points: int)
	var kind := "acorn"
	var alive := true
	var harmful := true
	var spiky := false        # stomping hurts the player
	var egg_proof := false
	var t := 0.0
	var direction := -1.0
	var speed_scale := 1.0
	var tint := Color.WHITE
	var knocked := false
	var knock_velocity := Vector2.ZERO
	var knock_spin := 0.0
	var box := Vector2(40, 38)

	func _ready() -> void:
		add_to_group("enemy")
		collision_layer = 4
		collision_mask = 1
		box = ENEMY_BOX.get(kind, Vector2(40, 38))
		PopoEntities._rect_shape(self, box, Vector2(0, -box.y * 0.5))
		t = randf() * 3.0

	func stomp_top_y() -> float:
		return global_position.y - box.y

	## Called by the player when landing on top. Returns "bounce", "hurt" or "none".
	func on_stomp(_player: Node) -> String:
		if spiky:
			return "hurt"
		defeat_squash()
		return "bounce"

	## Side contact that is harmless (e.g. kicking an idle shell). True = handled.
	func on_side_touch(_player: Node) -> bool:
		return false

	func hit_by_egg() -> bool:
		if not alive or egg_proof:
			return false
		knock_off(1.0 if randf() < 0.5 else -1.0)
		return true

	func hit_by_star(from_x: float) -> void:
		if alive:
			knock_off(signf(global_position.x - from_x) if global_position.x != from_x else 1.0)

	func points() -> int:
		return POINTS.get(kind, 100)

	func defeat_squash() -> void:
		if not alive:
			return
		alive = false
		harmful = false
		collision_layer = 0
		collision_mask = 0
		defeated.emit(kind, global_position, points())
		var tween := create_tween()
		tween.tween_property(self, "modulate:a", 0.0, 0.35).set_delay(0.25)
		tween.tween_callback(queue_free)
		queue_redraw()

	func knock_off(dir: float) -> void:
		if knocked:
			return
		var was_alive := alive
		alive = false
		harmful = false
		knocked = true
		collision_layer = 0
		collision_mask = 0
		knock_velocity = Vector2(dir * 160.0, -520.0)
		if was_alive:
			defeated.emit(kind, global_position, points())

	func _physics_process(delta: float) -> void:
		t += delta
		if knocked:
			knock_velocity.y += 1600.0 * delta
			position += knock_velocity * delta
			knock_spin += delta * 9.0
			if global_position.y > 1100.0:
				queue_free()
			queue_redraw()
			return
		if alive:
			_behave(delta)
		queue_redraw()

	func _behave(_delta: float) -> void:
		pass

	func current_texture() -> Texture2D:
		var frames: Variant = TEX.get(kind)
		if frames is Array:
			return frames[int(t * 6.0) % (frames as Array).size()]
		return frames

	func _draw() -> void:
		var tex := current_texture()
		var h: float = ENEMY_HEIGHT.get(kind, 56.0)
		if knocked:
			draw_set_transform(Vector2(0, -h * 0.5), knock_spin, Vector2.ONE)
			var size := tex.get_size() * (h / tex.get_size().y)
			draw_texture_rect(tex, Rect2(-size * 0.5, size), false, tint)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			return
		_draw_body(tex, h)

	func _draw_body(tex: Texture2D, h: float) -> void:
		# Source art faces left; mirror when walking right.
		PopoEntities.draw_sprite(self, tex, h, direction > 0.0, true, Vector2(0, 2), tint)


class Walker:
	extends Enemy
	enum { WALK, SHELL_IDLE, SHELL_MOVE, PILE }
	var state := WALK
	var floor_probe: RayCast2D
	var base_speed := 90.0
	var state_time := 0.0
	var squash := 1.0

	func _ready() -> void:
		super._ready()
		spiky = kind == "hedgehog"
		floor_probe = RayCast2D.new()
		floor_probe.collision_mask = 1
		floor_probe.target_position = Vector2(direction * 24.0, 12.0)
		floor_probe.position = Vector2(0, -4)
		add_child(floor_probe)

	func _speed() -> float:
		return TuningStore.get_value("enemy_speed") * speed_scale * float(ENEMY_SPEED.get(kind, 1.0))

	func _behave(delta: float) -> void:
		state_time += delta
		if not is_on_floor():
			velocity.y += TuningStore.get_value("enemy_gravity") * delta
		match state:
			WALK:
				velocity.x = direction * _speed()
				if is_on_floor():
					floor_probe.target_position.x = direction * 24.0
					floor_probe.force_raycast_update()
					if not floor_probe.is_colliding():
						direction *= -1.0
						velocity.x = direction * _speed()
			SHELL_IDLE:
				velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
			SHELL_MOVE:
				velocity.x = direction * 520.0
			PILE:
				velocity.x = 0.0
				if state_time > 3.6:
					state = WALK
					harmful = true
					state_time = 0.0
					var player := PopoEntities._player()
					if player != null:
						direction = signf(player.global_position.x - global_position.x)
		move_and_slide()
		if is_on_wall():
			direction *= -1.0
		if state == SHELL_MOVE:
			for i in get_slide_collision_count():
				var other := get_slide_collision(i).get_collider()
				if other is Enemy and other != self and other.alive:
					other.knock_off(direction)
			# Shells also knock enemies they overlap while sliding.
			for node in get_tree().get_nodes_in_group("enemy"):
				if node != self and node is Enemy and node.alive and absf(node.global_position.x - global_position.x) < 34.0 and absf(node.global_position.y - global_position.y) < 40.0:
					node.knock_off(direction)
		if global_position.y > 1000.0:
			queue_free()

	func on_stomp(player: Node) -> String:
		if spiky and state == WALK:
			return "hurt"
		match kind:
			"beetle":
				if state == WALK or state == SHELL_MOVE:
					_to_shell_idle()
				else:
					_kick(signf(global_position.x - player.global_position.x))
				return "bounce"
			"skeleton":
				if state == WALK:
					state = PILE
					state_time = 0.0
					harmful = false
					defeated.emit(kind, global_position, points())
					return "bounce"
				return "none"
		defeat_squash()
		return "bounce"

	func on_side_touch(player: Node) -> bool:
		if state == SHELL_IDLE:
			_kick(signf(global_position.x - player.global_position.x))
			return true
		if state == PILE:
			return true
		return false

	func hit_by_egg() -> bool:
		if not alive:
			return false
		knock_off(1.0)
		return true

	func _to_shell_idle() -> void:
		if state == WALK:
			defeated.emit(kind, global_position, points())
		state = SHELL_IDLE
		harmful = false
		state_time = 0.0
		box = Vector2(44, 30)
		kind = "beetle"

	func _kick(dir: float) -> void:
		state = SHELL_MOVE
		direction = dir if dir != 0.0 else 1.0
		harmful = true
		GameAudio.play(&"kick")

	func defeat_squash() -> void:
		if not alive:
			return
		if kind == "acorn":
			alive = false
			harmful = false
			collision_layer = 0
			collision_mask = 0
			defeated.emit(kind, global_position, points())
			squash = 1.0
			var tween := create_tween()
			tween.tween_interval(0.45)
			tween.tween_property(self, "modulate:a", 0.0, 0.2)
			tween.tween_callback(queue_free)
			return
		super.defeat_squash()

	func current_texture() -> Texture2D:
		if kind == "acorn" and not alive and not knocked:
			return TEX["acorn_flat"]
		if state == SHELL_IDLE or state == SHELL_MOVE:
			return TEX["beetle_shell"]
		if state == PILE:
			return TEX["skeleton_pile"]
		return super.current_texture()

	func _draw_body(tex: Texture2D, h: float) -> void:
		if state == SHELL_IDLE or state == SHELL_MOVE:
			PopoEntities.draw_sprite(self, tex, 40.0, false, true, Vector2(0, 2), tint)
			return
		if state == PILE:
			var wobble := 0.0 if state_time < 2.8 else sin(state_time * 40.0) * 2.0
			PopoEntities.draw_sprite(self, tex, 34.0, direction > 0.0, true, Vector2(wobble, 2), tint)
			return
		if kind == "acorn" and not alive:
			PopoEntities.draw_sprite(self, tex, 30.0, false, true, Vector2(0, 2), tint)
			return
		var bob := Vector2(1.0, 1.0 + sin(t * 12.0) * 0.03)
		PopoEntities.draw_sprite(self, tex, h, direction > 0.0, true, Vector2(0, 2), tint, bob)


class Bat:
	extends Enemy
	var origin := Vector2.ZERO
	var range_x := 150.0

	func _ready() -> void:
		kind = "bat"
		super._ready()
		origin = position
		collision_mask = 0

	func _behave(delta: float) -> void:
		var speed := 0.9 * speed_scale
		var phase := t * speed
		var new_pos := origin + Vector2(sin(phase) * range_x, sin(phase * 2.3) * 34.0)
		direction = signf(new_pos.x - position.x) if new_pos.x != position.x else direction
		position = new_pos

	func _draw_body(tex: Texture2D, h: float) -> void:
		PopoEntities.draw_sprite(self, tex, h, direction > 0.0, false, Vector2(0, -box.y * 0.5), tint)


class Ghost:
	extends Enemy
	var shy := false

	func _ready() -> void:
		kind = "ghost"
		super._ready()
		spiky = true
		collision_mask = 0
		tint = Color(1, 1, 1, 0.92)

	func _behave(delta: float) -> void:
		var player := PopoEntities._player()
		if player == null or not player.alive:
			return
		var to_player: Vector2 = player.global_position - global_position
		if to_player.length() > 900.0:
			shy = false
			return
		# Hides its face when the hero looks at it; creeps closer otherwise.
		shy = signf(float(player.get("facing"))) == -signf(to_player.x) and absf(to_player.x) > 4.0
		if not shy:
			position += to_player.normalized() * 70.0 * speed_scale * delta
			direction = signf(to_player.x)
		tint.a = 0.72 if shy else 0.95

	func current_texture() -> Texture2D:
		return TEX["ghost_shy"] if shy else TEX["ghost"]

	func _draw_body(tex: Texture2D, h: float) -> void:
		PopoEntities.draw_sprite(self, tex, h, direction > 0.0, false, Vector2(0, -box.y * 0.5 + sin(t * 3.0) * 4.0), tint)


class Cannonball:
	extends Enemy
	var life := 9.0

	func _ready() -> void:
		kind = "cannonball"
		super._ready()
		collision_mask = 0

	func _behave(delta: float) -> void:
		life -= delta
		position.x += direction * 230.0 * speed_scale * delta
		if life <= 0.0:
			queue_free()

	func on_stomp(_player: Node) -> String:
		knock_off(direction)
		return "bounce"

	func _draw_body(tex: Texture2D, h: float) -> void:
		PopoEntities.draw_sprite(self, tex, h, direction > 0.0, false, Vector2(0, -box.y * 0.5), tint)


# ------------------------------------------------------------------------------------------
# Hazard areas (spikes, lava, fire spirits, boss fireballs)
# ------------------------------------------------------------------------------------------
class HurtZone:
	extends Area2D
	var lethal := false
	var active := true

	func _ready() -> void:
		collision_layer = 0
		collision_mask = 2
		monitoring = true

	func _physics_process(_delta: float) -> void:
		if not active:
			return
		for body in get_overlapping_bodies():
			if body.is_in_group("player") and body.alive:
				if lethal:
					body.kill()
				else:
					body.hurt(global_position.x)


class Spikes:
	extends HurtZone
	var width := 80.0

	func _ready() -> void:
		super._ready()
		PopoEntities._rect_shape(self, Vector2(width - 12.0, 18.0), Vector2(0, -10))

	func _draw() -> void:
		var tex: Texture2D = TEX["spikes"]
		var h := 30.0
		var tile_w := tex.get_size().x * (h / tex.get_size().y)
		var x := -width * 0.5
		while x < width * 0.5 - 1.0:
			var w := minf(tile_w, width * 0.5 - x)
			var src := Rect2(0, 0, tex.get_size().x * (w / tile_w), tex.get_size().y)
			draw_texture_rect_region(tex, Rect2(x, -h + 2, w, h), src)
			x += w


class Lava:
	extends HurtZone
	var size := Vector2(200, 200)
	var t := 0.0
	var fill_tex: Texture2D
	var top_tex: Texture2D

	func _ready() -> void:
		super._ready()
		lethal = true
		PopoEntities._rect_shape(self, size - Vector2(0, 16), size * 0.5 + Vector2(0, 8))
		fill_tex = load("res://assets/game/terrain/lava_fill.webp")
		top_tex = load("res://assets/game/terrain/lava_top.webp")
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		z_index = 2

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var s := 0.35
		draw_set_transform(Vector2(fmod(t * 14.0, 256.0 * s) - 256.0 * s, 0), 0.0, Vector2(s, s))
		var w := (size.x + 256.0 * s * 2.0) / s
		draw_texture_rect(top_tex, Rect2(0, 0, w, 256), true)
		draw_texture_rect(fill_tex, Rect2(0, 256 - 8, w, (size.y) / s), true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


class FireSpirit:
	extends HurtZone
	signal defeated(kind: String, position: Vector2, points: int)
	var base_y := 0.0
	var t := 0.0
	var period := 3.2
	var jump_height := 330.0
	var alive := true

	func _ready() -> void:
		super._ready()
		add_to_group("fire_spirit")
		base_y = position.y
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 18.0
		shape.shape = circle
		add_child(shape)
		t = randf() * period
		z_index = 1

	func _physics_process(delta: float) -> void:
		t += delta
		var phase := fmod(t, period)
		var air := 1.5
		if phase < air:
			var u := phase / air
			position.y = base_y - jump_height * 4.0 * u * (1.0 - u)
			active = true
		else:
			position.y = base_y + 40.0
			active = false
		var player := PopoEntities._player()
		if active and player != null and player.alive and bool(player.call("star_active")):
			if global_position.distance_to(player.global_position) < 48.0:
				alive = false
				defeated.emit("fire_spirit", global_position, POINTS["fire_spirit"])
				queue_free()
				return
		super._physics_process(delta)
		queue_redraw()

	func _draw() -> void:
		if not active:
			return
		var phase := fmod(t, period) / 1.5
		var flip: bool = phase > 0.5
		PopoEntities.draw_sprite(self, TEX["fire_spirit"], 54.0, false, false, Vector2.ZERO, Color.WHITE, Vector2(1.0, -1.0 if flip else 1.0))


class Fireball:
	extends HurtZone
	var velocity := Vector2.ZERO
	var life := 4.0
	var spin := 0.0

	func _ready() -> void:
		super._ready()
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 16.0
		shape.shape = circle
		add_child(shape)

	func _physics_process(delta: float) -> void:
		velocity.y += 900.0 * delta
		position += velocity * delta
		life -= delta
		spin += delta * 8.0
		if life <= 0.0 or global_position.y > 900.0:
			queue_free()
			return
		super._physics_process(delta)
		queue_redraw()

	func _draw() -> void:
		PopoEntities.draw_sprite(self, TEX["boss_fireball"], 44.0, velocity.x > 0.0, false)


# ------------------------------------------------------------------------------------------
# Cannon
# ------------------------------------------------------------------------------------------
class Cannon:
	extends StaticBody2D
	signal fired(ball: Node)
	var interval := 3.0
	var timer := 1.5
	var speed_scale := 1.0
	var recoil := 0.0

	func _ready() -> void:
		collision_layer = 1
		collision_mask = 0
		PopoEntities._rect_shape(self, Vector2(60, 50), Vector2(0, -25))
		timer = interval * 0.5

	func _physics_process(delta: float) -> void:
		recoil = maxf(0.0, recoil - delta * 4.0)
		var player := PopoEntities._player()
		if player == null or not player.alive:
			return
		var dx: float = player.global_position.x - global_position.x
		if absf(dx) > 1000.0 or absf(dx) < 90.0:
			return
		timer -= delta
		if timer <= 0.0:
			timer = interval
			var ball := Cannonball.new()
			ball.direction = signf(dx)
			ball.speed_scale = speed_scale
			ball.position = position + Vector2(ball.direction * 38.0, -8.0)
			fired.emit(ball)
			recoil = 1.0
			GameAudio.play(&"bump")
		queue_redraw()

	func _draw() -> void:
		var player := PopoEntities._player()
		var flip: bool = player != null and player.global_position.x > global_position.x
		PopoEntities.draw_sprite(self, TEX["cannon"], 62.0, flip, true, Vector2(recoil * 6.0 * (-1.0 if flip else 1.0), 0))


# ------------------------------------------------------------------------------------------
# Pickups
# ------------------------------------------------------------------------------------------
class Pickup:
	extends Area2D
	signal collected(kind: String, position: Vector2, index: int)
	var kind := "coin"
	var index := -1
	var consumed := false
	var t := 0.0
	var pop := 0.0
	var fixed := true

	func _ready() -> void:
		add_to_group("pickup")
		collision_layer = 0
		collision_mask = 2
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 18.0 if kind == "coin" else 24.0
		shape.shape = circle
		add_child(shape)
		body_entered.connect(_on_body)
		t = randf() * 3.0

	## Rise out of a block before becoming collectable.
	func pop_out() -> void:
		pop = 1.0
		monitoring = false
		var tween := create_tween()
		tween.tween_property(self, "position:y", position.y - 56.0, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_callback(_popped)

	func _popped() -> void:
		monitoring = true
		pop = 0.0

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _on_body(body: Node) -> void:
		if consumed or not body.is_in_group("player") or not body.alive:
			return
		consumed = true
		collected.emit(kind, global_position, index)
		queue_free()

	func _draw() -> void:
		match kind:
			"coin":
				var sx := absf(cos(t * 3.2))
				PopoEntities.draw_sprite(self, TEX["coin"], 34.0, false, false, Vector2.ZERO, Color.WHITE, Vector2(maxf(0.18, sx), 1.0))
			"medal":
				PopoEntities.draw_sprite(self, TEX["medal"], 58.0, false, false, Vector2(0, sin(t * 2.4) * 5.0), Color.WHITE, Vector2(maxf(0.25, absf(cos(t * 1.8))), 1.0))
			"star":
				var hue := Color.from_hsv(fmod(t * 0.6, 1.0), 0.25, 1.0)
				PopoEntities.draw_sprite(self, TEX["star"], 46.0, false, false, Vector2(0, sin(t * 6.0) * 4.0), hue)
			_:
				PopoEntities.draw_sprite(self, TEX.get(kind, TEX["coin"]), 40.0, false, false, Vector2(0, sin(t * 3.0) * 3.0))


# ------------------------------------------------------------------------------------------
# Blocks, springs and platforms
# ------------------------------------------------------------------------------------------
class Block:
	extends StaticBody2D
	signal bumped(block: Node, content: String, position: Vector2)
	signal broken(position: Vector2)
	var kind := "item"       # item | brick | crate
	var content := "coin"
	var used := false
	var bump_offset := 0.0:
		set(value):
			bump_offset = value
			queue_redraw()

	func _ready() -> void:
		add_to_group("block")
		collision_layer = 1
		collision_mask = 0
		PopoEntities._rect_shape(self, Vector2(52, 52), Vector2.ZERO)

	func bump(_player: Node) -> void:
		if kind == "crate":
			return
		if kind == "brick":
			broken.emit(global_position)
			GameAudio.play(&"bump")
			queue_free()
			return
		if used:
			GameAudio.play(&"bump")
			return
		used = true
		bumped.emit(self, content, global_position)
		var tween := create_tween()
		tween.tween_property(self, "bump_offset", -12.0, 0.08)
		tween.tween_property(self, "bump_offset", 0.0, 0.1)

	func _draw() -> void:
		var tex: Texture2D
		match kind:
			"brick": tex = TEX["block_brick"]
			"crate": tex = TEX["block_crate"]
			_: tex = TEX["block_used"] if used else TEX["block_item"]
		draw_texture_rect(tex, Rect2(-26, -26 + bump_offset, 52, 52), false)


class Spring:
	extends StaticBody2D
	var squash := 0.0

	func _ready() -> void:
		add_to_group("spring")
		collision_layer = 1
		collision_mask = 0
		PopoEntities._rect_shape(self, Vector2(46, 30), Vector2(0, -15))

	func compress() -> void:
		squash = 1.0
		GameAudio.play(&"spring")

	func _process(delta: float) -> void:
		if squash > 0.0:
			squash = maxf(0.0, squash - delta * 4.0)
			queue_redraw()

	func _draw() -> void:
		PopoEntities.draw_sprite(self, TEX["spring"], 46.0, false, true, Vector2(0, 2), Color.WHITE, Vector2(1.0 + squash * 0.15, 1.0 - squash * 0.4))


class LogPlatform:
	extends AnimatableBody2D
	var width := 180.0
	var style := "log"
	var move := Vector2.ZERO
	var period := 3.0
	var origin := Vector2.ZERO
	var t := 0.0

	func _ready() -> void:
		add_to_group("platform")
		collision_layer = 1
		collision_mask = 0
		sync_to_physics = move != Vector2.ZERO
		PopoEntities._rect_shape(self, Vector2(width, 18), Vector2(0, 9), true)
		origin = position

	func _physics_process(delta: float) -> void:
		if move == Vector2.ZERO:
			return
		t += delta
		var u := 0.5 - 0.5 * cos(t * TAU / period)
		position = origin + move * u

	func _draw() -> void:
		var tex: Texture2D = TEX["rock"] if style == "rock" else TEX["log"]
		var size := tex.get_size()
		var h := width * size.y / size.x
		draw_texture_rect(tex, Rect2(-width * 0.5 - 6.0, -h * 0.22, width + 12.0, h), false)


class FallingPlatform:
	extends AnimatableBody2D
	var width := 150.0
	var origin := Vector2.ZERO
	var state := 0   # 0 idle, 1 shaking, 2 falling, 3 gone
	var timer := 0.0
	var fall_speed := 0.0

	func _ready() -> void:
		add_to_group("falling_platform")
		collision_layer = 1
		collision_mask = 0
		sync_to_physics = false
		PopoEntities._rect_shape(self, Vector2(width, 18), Vector2(0, 9), true)
		origin = position

	func stood_on() -> void:
		if state == 0:
			state = 1
			timer = 0.45

	func _physics_process(delta: float) -> void:
		match state:
			1:
				timer -= delta
				queue_redraw()
				if timer <= 0.0:
					state = 2
					fall_speed = 0.0
			2:
				fall_speed = minf(fall_speed + 1400.0 * delta, 900.0)
				position.y += fall_speed * delta
				if position.y > origin.y + 700.0:
					state = 3
					timer = 2.4
					visible = false
					collision_layer = 0
			3:
				timer -= delta
				if timer <= 0.0:
					state = 0
					position = origin
					visible = true
					collision_layer = 1
					queue_redraw()

	func _draw() -> void:
		var tex: Texture2D = TEX["rock"]
		var size := tex.get_size()
		var h := width * size.y / size.x
		var shake := Vector2(randf_range(-2.5, 2.5), 0) if state == 1 else Vector2.ZERO
		draw_texture_rect(tex, Rect2(Vector2(-width * 0.5 - 6.0, -h * 0.2) + shake, Vector2(width + 12.0, h)), false)


# ------------------------------------------------------------------------------------------
# Checkpoint and goal
# ------------------------------------------------------------------------------------------
class Checkpoint:
	extends Area2D
	signal reached(position: Vector2)
	var active := false
	var t := 0.0

	func _ready() -> void:
		collision_layer = 0
		collision_mask = 2
		PopoEntities._rect_shape(self, Vector2(60, 140), Vector2(0, -70))
		body_entered.connect(func(body: Node):
			if not active and body.is_in_group("player") and body.alive:
				active = true
				reached.emit(global_position)
				queue_redraw())

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var tint := Color.WHITE if active else Color(0.62, 0.62, 0.7)
		var sway := Vector2(1.0 + (sin(t * 5.0) * 0.03 if active else 0.0), 1.0)
		PopoEntities.draw_sprite(self, TEX["checkpoint"], 120.0, false, true, Vector2(0, 4), tint, sway)


class Goal:
	extends Area2D
	signal reached
	var locked := false:
		set(value):
			locked = value
			visible = not value
			set_deferred("monitoring", not value)
	var t := 0.0

	func _ready() -> void:
		collision_layer = 0
		collision_mask = 2
		PopoEntities._rect_shape(self, Vector2(80, 240), Vector2(0, -120))
		body_entered.connect(func(body: Node):
			if not locked and body.is_in_group("player") and body.alive:
				reached.emit())

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		PopoEntities.draw_sprite(self, TEX["goal"], 230.0, false, true, Vector2(0, 6))


# ------------------------------------------------------------------------------------------
# Boss: Magma Golem
# ------------------------------------------------------------------------------------------
class Golem:
	extends CharacterBody2D
	signal damaged(hp: int, max_hp: int)
	signal defeated(position: Vector2)
	signal slammed(position: Vector2)
	signal fireball_spawned(ball: Node)
	enum { SLEEP, WALK, WINDUP, JUMP, HURT, DEAD }
	var hp := 3
	var max_hp := 3
	var world := 1
	var arena := Vector2(0, 1500)
	var state := SLEEP
	var state_time := 0.0
	var direction := -1.0
	var alive := true
	var harmful := true
	var spiky := false
	var t := 0.0
	var flash := 0.0
	var attack_timer := 2.5
	const BOX := Vector2(110, 160)

	func _ready() -> void:
		add_to_group("enemy")
		add_to_group("boss")
		collision_layer = 4
		collision_mask = 1
		PopoEntities._rect_shape(self, BOX, Vector2(0, -BOX.y * 0.5))

	func activate() -> void:
		if state == SLEEP:
			state = WALK
			state_time = 0.0
			attack_timer = 1.6

	func stomp_top_y() -> float:
		return global_position.y - BOX.y

	func on_stomp(_player: Node) -> String:
		if state == HURT or state == DEAD or state == SLEEP:
			return "bounce"
		_take_damage()
		return "bounce"

	func on_side_touch(_player: Node) -> bool:
		return state == DEAD or state == SLEEP

	func hit_by_egg() -> bool:
		if state == HURT or state == DEAD or state == SLEEP:
			return state != DEAD
		_take_damage()
		return true

	func hit_by_star(_from_x: float) -> void:
		if state != HURT and state != DEAD and state != SLEEP:
			_take_damage()

	func _take_damage() -> void:
		hp -= 1
		flash = 1.0
		GameAudio.play(&"boss_hit")
		damaged.emit(hp, max_hp)
		if hp <= 0:
			state = DEAD
			alive = false
			harmful = false
			collision_layer = 0
			state_time = 0.0
			defeated.emit(global_position)
			return
		state = HURT
		state_time = 0.0
		velocity = Vector2(-direction * 180.0, -260.0)

	func _physics_process(delta: float) -> void:
		t += delta
		state_time += delta
		flash = maxf(0.0, flash - delta * 2.0)
		if not is_on_floor():
			velocity.y += 1500.0 * delta
		var player := PopoEntities._player()
		var speed := 60.0 + world * 12.0
		match state:
			SLEEP:
				velocity.x = 0.0
			WALK:
				if player != null:
					direction = signf(player.global_position.x - global_position.x)
				velocity.x = direction * speed
				attack_timer -= delta
				if attack_timer <= 0.0 and is_on_floor():
					state = WINDUP
					state_time = 0.0
			WINDUP:
				velocity.x = 0.0
				if state_time > maxf(0.35, 0.7 - world * 0.05):
					state = JUMP
					state_time = 0.0
					var target_dx := 0.0
					if player != null:
						target_dx = clampf(player.global_position.x - global_position.x, -420.0, 420.0)
					velocity = Vector2(target_dx * 1.1, -760.0)
			JUMP:
				if state_time > 0.15 and is_on_floor():
					_slam()
			HURT:
				velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
				if state_time > 1.1:
					state = WALK
					state_time = 0.0
					attack_timer = maxf(1.0, 2.6 - world * 0.22)
			DEAD:
				velocity.x = 0.0
				modulate.a = maxf(0.0, 1.0 - state_time / 1.6)
				if state_time > 1.7:
					queue_free()
		move_and_slide()
		global_position.x = clampf(global_position.x, arena.x + 70.0, arena.y - 70.0)
		queue_redraw()

	func _slam() -> void:
		state = WALK
		state_time = 0.0
		attack_timer = maxf(1.1, 3.0 - world * 0.25)
		slammed.emit(global_position)
		var count := 2 + int(world / 2.0)
		for i in count:
			var ball := Fireball.new()
			var side := -1.0 if i % 2 == 0 else 1.0
			var tier := float(int(i / 2.0))
			ball.velocity = Vector2(side * (180.0 + tier * 110.0), -620.0 - tier * 80.0)
			ball.position = position + Vector2(side * 40.0, -150.0)
			fireball_spawned.emit(ball)

	func _draw() -> void:
		var tex: Texture2D = TEX["golem"]
		if state == WINDUP or state == JUMP:
			tex = TEX["golem_stomp"]
		elif state == HURT or state == DEAD:
			tex = TEX["golem_hurt"]
		var tint := Color(1, 1, 1).lerp(Color(1, 0.45, 0.45), flash)
		if state == HURT and int(state_time * 12.0) % 2 == 0:
			tint.a = 0.55
		var shake := Vector2(sin(t * 60.0) * 3.0, 0) if state == WINDUP else Vector2.ZERO
		var breath := Vector2(1.0, 1.0 + sin(t * 3.0) * 0.015)
		PopoEntities.draw_sprite(self, tex, 190.0, direction > 0.0, true, Vector2(0, 4) + shake, tint, breath)
