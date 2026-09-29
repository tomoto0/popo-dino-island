extends CharacterBody2D
## Thrown egg: arcs forward, bounces twice on the ground and defeats most enemies.

signal enemy_hit(position: Vector2)
signal block_hit(block: Node)

const MAX_BOUNCES := 2
const TEXTURE = preload("res://assets/game/items/egg.webp")
var direction := 1.0
var speed := 640.0
var lifetime := 1.6
var gravity := 900.0
var launch_speed := 240.0
var vertical_speed := 0.0
var spent := false
var spin := 0.0
var bounce_count := 0


func _ready() -> void:
	vertical_speed = -launch_speed
	add_to_group("egg_projectile")
	collision_layer = 0
	collision_mask = 1 | 4
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 10.0
	shape.shape = circle
	add_child(shape)
	queue_redraw()


func _physics_process(delta: float) -> void:
	if spent:
		return
	lifetime -= delta
	if lifetime <= 0.0 or global_position.y > 900.0:
		_finish()
		return
	spin += direction * delta * 14.0
	var travel_y := vertical_speed * delta + 0.5 * gravity * delta * delta
	vertical_speed += gravity * delta
	var hit := move_and_collide(Vector2(direction * speed * delta, travel_y))
	if hit != null:
		var body := hit.get_collider()
		if body != null and body.is_in_group("enemy") and bool(body.get("alive")):
			if body.has_method("hit_by_egg") and body.hit_by_egg():
				enemy_hit.emit(global_position)
			_finish()
		elif body != null and body.is_in_group("block") and hit.get_normal().y > 0.55:
			block_hit.emit(body)
			_finish()
		elif hit.get_normal().y < -0.65 and vertical_speed > 0.0:
			if bounce_count >= MAX_BOUNCES:
				_finish()
			else:
				bounce_count += 1
				vertical_speed = -maxf(160.0, vertical_speed * 0.6)
				speed *= 0.85
				position += hit.get_normal() * 0.5
				lifetime = maxf(lifetime, 2.0 * absf(vertical_speed) / maxf(gravity, 1.0) + 0.2)
		else:
			_finish()
	queue_redraw()


func _finish() -> void:
	if spent:
		return
	spent = true
	collision_mask = 0
	queue_free()


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, spin)
	draw_texture_rect(TEXTURE, Rect2(-13, -16, 26, 32), false)
