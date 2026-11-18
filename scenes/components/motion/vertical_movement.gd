class_name VerticalMovementComponent
extends Node
## NES airborne integration at 60Hz. Body velocity publishes the encoded speed.
var integer_speed := 0
var speed_fraction := 0
var position_fraction := 0
var _published := NAN
var _fixed_step := false
var _target_y := 0.0


func reset_fraction(body: CharacterBody2D = null) -> void:
	position_fraction = 0
	if body != null:
		body.global_position.y = roundf(body.global_position.y)
	_published = NAN


func apply_gravity(values: MotionValues, delta: float) -> void:
	var velocity := values.velocity
	velocity.y = speed_after_gravity(values, delta)
	values.velocity = velocity


func speed_after_gravity(values: MotionValues, delta: float) -> float:
	return minf(values.velocity.y + values.gravity * values.weight * delta, values.max_fall_speed)


## Consume a step in 1/256-pixel units and retain the position remainder.
func consume_displacement(units: int) -> int:
	var accumulated := position_fraction + units
	position_fraction = posmod(accumulated, 256)
	return floori(accumulated / 256.0)


## Prepare integer displacement and next speed without moving the body twice.
## A launch can keep its fractional world position by supplying its own grid origin.
func prepare_step(values: MotionValues, delta: float, grid_origin: float = 0.0) -> float:
	var force := values.gravity * values.weight / 3600.0 * 256.0
	_fixed_step = (
		is_equal_approx(delta, 1.0 / 60.0)
		and force >= 0
		and force <= 255
		and is_equal_approx(force, roundf(force))
		and is_equal_approx(values.max_fall_speed / 60.0, roundf(values.max_fall_speed / 60.0))
	)
	if not _fixed_step:
		return speed_after_gravity(values, delta)
	var displacement := _advance(values.velocity.y, int(roundf(force)), int(roundf(values.max_fall_speed / 60.0)), false)
	_target_y = grid_origin + roundf(values.body.global_position.y - grid_origin) + displacement
	values.body.velocity.y = (_target_y - values.body.global_position.y) / delta
	return _encoded_speed()


## Apply a second NES integration step after the normal terrain pass.
func apply_extra_step(values: MotionValues, force: int, limit: int) -> void:
	values.body.global_position.y += _advance(values.velocity.y, force, limit, true)
	var velocity := values.velocity
	velocity.y = _encoded_speed()
	values.velocity = velocity
	_published = velocity.y


func _advance(current: float, force: int, limit: int, check_fraction_byte: bool) -> int:
	var units := integer_speed * 256 + speed_fraction
	if is_nan(_published) or not is_equal_approx(current, _published):
		units = roundi(current / 60.0 * 256.0)
	var displacement := consume_displacement(units)
	var next_units := units + force
	# ImposeGravity tests the integer byte and fractional high bit independently.
	var cap_fraction := posmod(next_units, 256) if check_fraction_byte else next_units - limit * 256
	if next_units >= limit * 256 and cap_fraction >= 128:
		next_units = limit * 256
	integer_speed = floori(next_units / 256.0)
	speed_fraction = posmod(next_units, 256)
	return displacement


func _encoded_speed() -> float:
	return (integer_speed * 256 + speed_fraction) / 256.0 * 60.0


func finish_step(values: MotionValues, next_speed: float) -> void:
	finish_step_on_support(values, next_speed, values.body.is_on_floor())


func finish_step_on_support(values: MotionValues, next_speed: float, supported: bool) -> void:
	# Keep integer NES position when Godot applies a subpixel safe-margin recovery.
	# Never override an actual floor/ceiling collision or a larger obstruction.
	if _fixed_step and not supported and not values.body.is_on_ceiling():
		if absf(values.body.global_position.y - _target_y) < 0.5:
			values.body.global_position.y = _target_y
	var velocity := values.velocity
	velocity.y = 0.0 if supported else next_speed
	values.velocity = velocity
	_published = velocity.y
	if supported:
		integer_speed = 0
		speed_fraction = 0


## A collision writes only the integer speed byte; both fractional registers survive.
func speed_with_integer(values: MotionValues, speed: int) -> float:
	var units := int(roundf(values.velocity.y / 60.0 * 256.0))
	return (speed * 256 + posmod(units, 256)) / 256.0 * 60.0
