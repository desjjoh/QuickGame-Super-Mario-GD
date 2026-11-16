extends RefCounted
## Steps an actor using the NES jumping-enemy terrain response.

const TERRAIN_PROBE := preload("res://scenes/components/interactions/terrain_probe.gd")
const BOUNCE_SPEED := -180.0

var _motion: MotionValues
var _vertical: VerticalMovementComponent
var _travel_speed: float
var _direction: float
var _probe := PhysicsPointQueryParameters2D.new()


func _init(
	motion: MotionValues,
	vertical: VerticalMovementComponent,
	travel_speed: float,
	initial_direction: float
) -> void:
	_motion = motion
	_vertical = vertical
	_travel_speed = travel_speed
	_direction = initial_direction
	_probe.collision_mask = motion.body.collision_mask


func advance(item: CanvasItem, delta: float, excluded_bodies: Array[RID]) -> void:
	move(delta)
	check_terrain(item, excluded_bodies)


func move(delta: float, grid_origin_y := 0.0) -> void:
	var body := _motion.body
	body.velocity.x = _travel_speed * _direction
	var next_speed := _vertical.prepare_step(_motion, delta, grid_origin_y)
	body.global_position += body.velocity * delta
	_vertical.finish_step(_motion, next_speed)


func check_terrain(item: CanvasItem, excluded_bodies: Array[RID], grid_origin_y := 0.0) -> void:
	var body := _motion.body
	_probe.exclude = excluded_bodies
	# The reference compares the low byte of speed plus two before checking support.
	var can_bounce := ((_vertical.integer_speed + 2) & 0xff) >= 3
	if can_bounce and _solid_at(item, body.global_position + Vector2(0, 8)):
		var relative_y := body.global_position.y - grid_origin_y
		body.global_position.y = grid_origin_y + floorf(relative_y / 16.0) * 16.0 + 8.0
		body.velocity.y = BOUNCE_SPEED
	if _solid_at(item, body.global_position + Vector2(8 * _direction, 4)):
		_direction = -_direction
		body.velocity.x = _travel_speed * _direction


func _solid_at(item: CanvasItem, point: Vector2) -> bool:
	_probe.position = point + Vector2(0.01, 0.01)
	return TERRAIN_PROBE.hits_terrain(item, _probe)
