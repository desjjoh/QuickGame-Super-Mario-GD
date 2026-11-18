class_name MarioMoveState
extends PlayerState
## Walk/run and passive falling. Deliberate jumps use MarioJumpState.

@export var idle_state: PlayerState
@export var slide_state: PlayerState
@export var jump_state: PlayerState

var _previous_animation_speed: float = 1.0
var _falling: bool = false
var _defer_transformation_vertical := false
var _start_direction := 0
var _moving_direction := 0


func defer_transformation_fall_step() -> void:
	_defer_transformation_vertical = true


func enter() -> void:
	_falling = false
	var mario := get_player() as Mario
	_previous_animation_speed = mario.animation_player.speed_scale
	mario.walk_animation.begin(mario.animation_player)


func exit() -> void:
	_defer_transformation_vertical = false
	_start_direction = 0
	if _falling:
		get_player().air_movement.end(get_player().motion_values)
		get_player().motion_values.remove_modifier(&"passive_fall")
		_falling = false
	get_player().animation_player.speed_scale = _previous_animation_speed


func process_physics(delta: float) -> BaseState:
	var player := get_player()
	var previous_speed := player.body.velocity.x
	var direction := prepare_horizontal_motion()
	var next := ground_transition(jump_state, self)
	if next != null:
		return continue_physics(next, delta)
	if not player.has_floor_support():
		return _process_falling(player, direction, delta)

	if player.slide_action.can_start(player.body, direction):
		return continue_physics(slide_state, delta)

	_move_on_ground(player, direction, delta)
	if player.scripted_motion_step.is_valid():
		return null

	var mario := player as Mario
	if not mario.form_controller.is_crouched:
		mario.walk_animation.advance_pose(mario.animation_player, previous_speed)
	else:
		mario.walk_animation.pose_index = 0

	if is_zero_approx(direction) and is_zero_approx(player.body.velocity.x):
		return idle_state

	return null


func _move_on_ground(player: BasePlayer, direction: float, delta: float) -> void:
	var body := player.body
	var opposite := player.slide_action.is_opposing(body, direction)
	# Low-speed reversal finishes immediately instead of entering a visible skid.
	if opposite:
		body.velocity.x = 0.0
	var speed := _prepare_ground_start(player, direction, delta, opposite)
	if is_nan(speed):
		player.horizontal_movement.apply(body, player.motion_values, direction, delta)
	var target_x := body.global_position.x + body.velocity.x * delta
	player.face_direction(direction)
	body.velocity.y = 0.0
	player.move_body()

	if not is_nan(speed):
		# Use the physics result for blocked movement. Publish the speed byte
		# after an unobstructed step so a jump inherits speed, not displacement.
		var reached_target := absf(body.global_position.x - target_x) < 0.01
		if reached_target:
			body.velocity.x = speed
		if not reached_target or not player.has_floor_support():
			_start_direction = 0
	if not is_zero_approx(body.velocity.x):
		_moving_direction = int(signf(body.velocity.x))


func _prepare_ground_start(
	player: BasePlayer, direction: float, delta: float, opposite: bool
) -> float:
	var body := player.body
	var movement := player.horizontal_movement
	var values := player.motion_values
	if (
		absf(direction) != 1.0 or opposite or not is_equal_approx(delta, 1.0 / 60.0)
		or player.scripted_motion_step.is_valid()
	):
		_start_direction = 0
		return NAN
	if _start_direction != int(direction):
		_start_direction = 0
		if not is_zero_approx(body.velocity.x):
			return NAN
		movement.reset_fractional_step()
		_start_direction = int(direction)

	var facing := -1 if player.sprite.flip_h else 1
	var acceleration := values.acceleration
	var max_speed := values.max_speed
	if _moving_direction != _start_direction:
		# Run is eligible once input agrees with the stored movement direction.
		acceleration = values.base_acceleration
		max_speed = values.base_max_speed
		if _moving_direction != facing:
			acceleration *= 2.0
		_moving_direction = facing
		movement.reset_fractional_step(false)
	var force := roundi(acceleration * (256.0 * 16.0 / (60.0 * 60.0)))
	var limit := floori(max_speed * 16.0 / 60.0)
	if limit <= 0 or force <= 0:
		_start_direction = 0
		return NAN
	var speed := movement.prepare_fractional_step(body, _start_direction, force, limit, delta)
	if absf(speed) >= limit * 60.0 / 16.0:
		_start_direction = 0
	return speed


func _process_falling(player: BasePlayer, direction: float, delta: float) -> BaseState:
	var previous_speed := player.body.velocity.x
	if not _falling:
		player.air_movement.begin(
			player.motion_values,
			-1.0 if player.sprite != null and player.sprite.flip_h else 1.0,
			player.run_action.running_history
		)
		_falling = true
		player.motion_values.set_modifier(
			&"passive_fall", {&"gravity": player.jump_action.falling_gravity}, 250
		)
	player.air_movement.apply(player.motion_values, direction, delta)
	if _defer_transformation_vertical:
		# The NES runs one ground-control tick after transforming, then detects the fall.
		# Retain upward momentum; vertical integration starts on the next tick.
		_defer_transformation_vertical = false
		var vertical_speed := player.body.velocity.y
		player.body.velocity.y = 0.0
		player.move_body()
		player.body.velocity.y = vertical_speed
	else:
		player.move_body(true)
	if player.scripted_motion_step.is_valid():
		return null
	var mario := player as Mario
	if player.has_floor_support():
		mario.walk_animation.advance_pose(mario.animation_player, previous_speed)
		player.air_movement.end(player.motion_values)
		player.motion_values.remove_modifier(&"passive_fall")
		_falling = false
		if is_zero_approx(direction) and is_zero_approx(player.body.velocity.x):
			return idle_state
	else:
		mario.walk_animation.show_pose(mario.animation_player)
	return null
