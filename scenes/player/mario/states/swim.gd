class_name MarioSwimState
extends PlayerState

const MOTION_PROFILE := &"swim"
const STROKE_TICKS := 32
# Convert the NES actor Y threshold of 20 to the player body's feet origin.
const SURFACE_FEET_Y := 52.0
const STROKE_FORCE := 0x0d
const SINK_FORCE := 0x0a
const SURFACE_FORCE := 0x18
const HORIZONTAL_FORCE := 0x98

var _stroke_ticks := 0
var _stroke_origin_y := 0.0
var _previous_jump := false
var _vertical_force := SINK_FORCE
var _moving_direction := 1
var _surface_y := SURFACE_FEET_Y


func enter() -> void:
	var player := get_player()
	var level := BaseLevel.containing(player)
	_surface_y = level.active_area.global_position.y + SURFACE_FEET_Y
	_stroke_ticks = 0
	_stroke_origin_y = player.body.global_position.y
	_previous_jump = false
	_vertical_force = SINK_FORCE
	_moving_direction = -1 if player.sprite.flip_h else 1
	player.horizontal_movement.reset_fractional_step()


func exit() -> void:
	get_player().motion_values.remove_modifier(MOTION_PROFILE)


func process_physics(delta: float) -> BaseState:
	var player := get_player() as Mario
	var previous_speed := player.body.velocity.x
	var direction := int(signf(get_movement_axis().x))
	var grounded := player.has_floor_support()
	var controls := controller_controls_available()
	var jump := controls and ControllerHandler.input_primary
	var near_surface := player.body.global_position.y < _surface_y
	_stroke_ticks = maxi(_stroke_ticks - 1, 0)
	if (
		controls and ControllerHandler.input_primary_just_pressed
		and (grounded or _stroke_ticks > 0 or player.body.velocity.y >= 0.0)
	):
		_stroke_ticks = STROKE_TICKS
		_stroke_origin_y = player.body.global_position.y
		_vertical_force = STROKE_FORCE
		player.vertical_movement.reset_fraction()
		player.body.velocity.y = 30.0 if near_surface else -90.0
		player.play_sound_effect(SoundHandler.get_sound(&"stomp"))
		grounded = false
	if not grounded:
		if (
			player.body.velocity.y >= 0.0
			or (
				not (jump and _previous_jump)
				and _stroke_origin_y - player.body.global_position.y >= 1.0
			)
		):
			_vertical_force = SINK_FORCE
		if near_surface:
			_vertical_force = SURFACE_FORCE
		player.motion_values.set_modifier(
			MOTION_PROFILE,
			{&"gravity": _vertical_force * 3600.0 / 256.0, &"max_fall_speed": 240.0},
			300
		)
	_previous_jump = jump
	_move(player, grounded, direction, delta)
	_update_pose(player, direction, jump, previous_speed)
	return null


func _move(player: BasePlayer, grounded: bool, direction: int, delta: float) -> void:
	var body := player.body
	var facing := -1 if player.sprite.flip_h else 1
	var force := HORIZONTAL_FORCE if facing == _moving_direction else HORIZONTAL_FORCE * 2
	# The NES chooses friction before its low-speed reversal resets the speed byte.
	if direction != 0 and direction != _moving_direction and absf(body.velocity.x) < 11 * 60.0 / 16.0:
		_moving_direction = facing
		body.velocity.x = 0.0
		player.horizontal_movement.reset_fractional_step(false)
	var acceleration_direction := direction
	if grounded and direction == 0:
		acceleration_direction = -int(signf(body.velocity.x))
	var limit := 0x10 if grounded else 0x18
	var speed := player.horizontal_movement.prepare_fractional_step(
		body, acceleration_direction, force, limit, delta
	)
	var target_x := body.global_position.x + body.velocity.x * delta
	player.face_direction(direction)
	player.move_body(not grounded)
	if absf(body.global_position.x - target_x) < 0.5:
		body.velocity.x = speed
	if not is_zero_approx(body.velocity.x):
		_moving_direction = int(signf(body.velocity.x))


func _update_pose(player: Mario, direction: int, jump: bool, previous_speed: float) -> void:
	var cadence := player.walk_animation
	var form := player.form_controller.current_form
	if player.has_floor_support():
		if player.form_controller.is_crouched:
			player.sprite.texture = form.crouch
			cadence.pose_index = 0
		elif direction == 0 and is_zero_approx(player.body.velocity.x):
			player.sprite.texture = form.idle
			cadence.pose_index = 0
		elif (
			absf(player.body.velocity.x) >= 9 * 60.0 / 16.0
			and (player.body.velocity.x < 0.0) != player.sprite.flip_h
		):
			player.sprite.texture = form.skid
			cadence.pose_index = 0
		else:
			player.sprite.texture = form.walk[cadence.walk_frame_index()]
			cadence.advance_cycle(previous_speed)
		return

	if form.swim.size() == 6:
		var kick := int((GameHandler.animation_clock.tick_count & 4) == 0)
		player.sprite.texture = form.swim[cadence.pose_index * 2 + kick]
	else:
		player.sprite.texture = form.jump
	if _stroke_ticks > 0 or cadence.pose_index != 0 or jump:
		cadence.advance_cycle(previous_speed)
