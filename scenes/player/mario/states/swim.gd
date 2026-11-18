class_name MarioSwimState
extends PlayerState

const MOTION_PROFILE := &"swim"
const STROKE_TICKS := 32
# Convert the NES actor Y threshold of 20 to the player body's feet origin.
const NES_FEET_OFFSET := 32
const SURFACE_FEET_Y := NES_FEET_OFFSET + 20.0
const INPUT_CUTOFF_Y := NES_FEET_OFFSET + 208
const STROKE_FORCE := 0x0d
const SINK_FORCE := 0x0a
const ENTRY_SINK_FORCE := 0x28
const WHIRLPOOL_STROKE_FORCE := 0x04
const WHIRLPOOL_SINK_FORCE := 0x09
const SURFACE_FORCE := 0x18
const HORIZONTAL_FORCE := 0x98

var _area: BaseLevelArea
var _in_whirlpool := false
var _blocked_direction := 0
var _sink_force := SINK_FORCE
var _entry_handoff_pending := false
var _stroke_ticks := 0
var _stroke_origin_y := 0.0
var _previous_jump := false
var _vertical_force := SINK_FORCE
var _moving_direction := 1
var _surface_y := SURFACE_FEET_Y


func enter() -> void:
	var player := get_player()
	var level := BaseLevel.containing(player)
	_area = level.active_area
	_surface_y = _area.global_position.y + SURFACE_FEET_Y
	_in_whirlpool = false
	_blocked_direction = 0
	var endpoint := level.active_endpoint
	_entry_handoff_pending = (
		is_instance_valid(endpoint) and endpoint.swim_entry_drop
		and player.arrival_control_ticks_remaining > 0
	)
	_sink_force = ENTRY_SINK_FORCE if _entry_handoff_pending else SINK_FORCE
	_stroke_ticks = 0
	_stroke_origin_y = player.body.global_position.y
	_previous_jump = false
	_vertical_force = SINK_FORCE
	var facing := -1 if player.sprite.flip_h else 1
	# A water entrance faces right before the first sideways input sets a movement direction.
	_moving_direction = 0 if _entry_handoff_pending else facing
	player.horizontal_movement.reset_fractional_step()


func exit() -> void:
	get_player().motion_values.remove_modifier(MOTION_PROFILE)


func get_moving_direction() -> int:
	return _moving_direction


func accepts_depth_input() -> bool:
	if not is_instance_valid(_area):
		return true
	var feet_y := roundi(get_player().body.global_position.y - _area.global_position.y)
	return feet_y >= NES_FEET_OFFSET and feet_y < INPUT_CUTOFF_Y


func process_physics(delta: float) -> BaseState:
	var player := get_player() as Mario
	if _entry_handoff_pending and player.arrival_control_ticks_remaining == 1:
		# The entrance routine spends its last tick handing over control.
		return null
	var previous_speed := player.body.velocity.x
	var direction := int(signf(get_movement_axis().x))
	var grounded := player.has_floor_support()
	var controls := controller_controls_available()
	var jump := controls and ControllerHandler.input_primary
	var jump_pressed := ControllerHandler.input_primary_just_pressed
	if _entry_handoff_pending and controls:
		# Suppressed inputs leave Jump unpressed until the first controllable tick.
		jump_pressed = jump_pressed or jump
		_entry_handoff_pending = false
	var near_surface := player.body.global_position.y < _surface_y
	_stroke_ticks = maxi(_stroke_ticks - 1, 0)
	if (
		controls and jump_pressed
		and (grounded or _stroke_ticks > 0 or player.body.velocity.y >= 0.0)
	):
		_stroke_ticks = STROKE_TICKS
		_stroke_origin_y = player.body.global_position.y
		_vertical_force = WHIRLPOOL_STROKE_FORCE if _in_whirlpool else STROKE_FORCE
		_sink_force = WHIRLPOOL_SINK_FORCE if _in_whirlpool else SINK_FORCE
		player.vertical_movement.reset_fraction()
		if _in_whirlpool:
			player.body.velocity.y = 0.0 if near_surface else -60.0
		else:
			player.body.velocity.y = 30.0 if near_surface else -90.0
		player.play_sound_effect(SoundHandler.get_sound(&"stomp"))
		grounded = false
	if not grounded:
		player.form_controller.set_crouched(false)
		if (
			player.body.velocity.y >= 0.0
			or (
				not (jump and _previous_jump)
				and _stroke_origin_y - player.body.global_position.y >= 1.0
			)
		):
			_vertical_force = _sink_force
		if near_surface:
			_vertical_force = SURFACE_FORCE
		player.motion_values.set_modifier(
			MOTION_PROFILE,
			{&"gravity": _vertical_force * 3600.0 / 256.0, &"max_fall_speed": 240.0},
			300
		)
	_previous_jump = jump
	_move(player, grounded, direction, delta)
	if _sink_force == ENTRY_SINK_FORCE and player.has_floor_support():
		_sink_force = SINK_FORCE
	_apply_whirlpool(player)
	if player.form_controller.is_crouched and not player.has_floor_support():
		player.form_controller.set_crouched(false)
	_update_pose(player, direction, jump, previous_speed)
	return null


func _move(player: Mario, grounded: bool, direction: int, delta: float) -> void:
	var body := player.body
	var facing := -1 if player.sprite.flip_h else 1
	var force := HORIZONTAL_FORCE if facing == _moving_direction else HORIZONTAL_FORCE * 2
	# The NES chooses friction before its low-speed reversal resets the speed byte.
	if direction != 0 and direction != _moving_direction and absf(body.velocity.x) < 11 * 60.0 / 16.0:
		_moving_direction = facing
		body.velocity.x = 0.0
		player.horizontal_movement.reset_fractional_step(false)
	var acceleration_direction := 0 if direction == _blocked_direction else direction
	if acceleration_direction == 0 and (grounded or direction != 0):
		acceleration_direction = -int(signf(body.velocity.x))
	var limit := 0x10 if grounded else 0x18
	var speed := player.horizontal_movement.prepare_fractional_step(
		body, acceleration_direction, force, limit, delta
	)
	var start_x := body.global_position.x
	var attempted_x := body.velocity.x * delta
	var target_x := start_x + attempted_x
	var correction_before_move := player.camera_correction_x
	player.face_direction(direction)
	player.move_body(not grounded)
	if absf(body.global_position.x - target_x) < 0.5:
		body.velocity.x = speed
	if not is_zero_approx(body.velocity.x):
		_moving_direction = int(signf(body.velocity.x))
	_blocked_direction = player.terrain.swim_wall_direction(player)
	# The bit blocks steering even when Mario is already moving away from this wall.
	if _blocked_direction != 0 and body.velocity.x * _blocked_direction >= 0.0:
		body.velocity.x = 0.0
		body.global_position.x -= _blocked_direction
		# Count only attempted movement that survives the wall response.
		var resolved_x := body.global_position.x - start_x
		var accepted_x := clampf(resolved_x, minf(0.0, attempted_x), maxf(0.0, attempted_x))
		player.camera_correction_x = correction_before_move + resolved_x - accepted_x


func _apply_whirlpool(player: Mario) -> void:
	_in_whirlpool = false
	for candidate in player.get_tree().get_nodes_in_group(Whirlpool.GROUP):
		var whirlpool := candidate as Whirlpool
		if (
			_area.is_ancestor_of(whirlpool)
			and whirlpool.contains_player_x(player.body.global_position.x)
		):
			whirlpool.pull(player, GameHandler.animation_clock.tick_count, _blocked_direction != 1)
			_in_whirlpool = true
			return


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
