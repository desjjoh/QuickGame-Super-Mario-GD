class_name HorizontalMovementComponent
extends Node
## Prepares horizontal movement. The state owns when the body moves.

var _speed_fraction := 0
var _position_fraction := 0


func reset_fractional_step(reset_position: bool = true) -> void:
	_speed_fraction = 0
	if reset_position:
		_position_fraction = 0


## NES horizontal speed has four fractional bits. Acceleration and position have separate bytes.
func prepare_fractional_step(
	body: CharacterBody2D, direction: int, force: int, speed_limit: int, delta: float
) -> float:
	var speed := roundi(body.velocity.x / 60.0 * 16.0)
	var acceleration := _speed_fraction + direction * force
	speed += acceleration >> 8
	_speed_fraction = acceleration & 0xff
	if direction > 0:
		speed = mini(speed, speed_limit)
	elif direction < 0:
		speed = maxi(speed, -speed_limit)
	var displacement := _position_fraction + speed * 16
	_position_fraction = displacement & 0xff
	body.velocity.x = (displacement >> 8) / delta
	return speed * 60.0 / 16.0



func apply(body: CharacterBody2D, values: MotionValues, direction: float, delta: float) -> void:
	var target := clampf(direction, -1.0, 1.0) * values.max_speed
	var rate := values.deceleration if is_zero_approx(direction) else values.acceleration

	if not is_zero_approx(direction) and body.velocity.x * direction < 0.0:
		rate *= values.reversal_multiplier

	body.velocity.x = move_toward(body.velocity.x, target, rate * delta)

	# Directional acceleration clamps only its own side, as ImposeFriction does.
	# Neutral input must coast; opposing momentum belongs to the Slide action.
	if direction > 0.0:
		body.velocity.x = minf(body.velocity.x, values.max_speed)
	elif direction < 0.0:
		body.velocity.x = maxf(body.velocity.x, -values.max_speed)
