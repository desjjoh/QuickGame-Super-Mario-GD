extends Node

const SANDBOX := preload("res://tests/fixtures/whirlpool_sandbox.tscn")
const STAGE := preload("res://scenes/levels/worlds/world 2/2-2.tscn")
const TRACE := "res://tests/fixtures/swimming_reference/whirlpool_mesen.csv"
const STEP := 1.0 / 60.0
const X_OFFSET := 8 - 912
const Y_OFFSET := 32
const SEEDS := {
	"center_idle": [72, 0, -1, false, true],
	"center_tap": [110, 0, 0, false, true],
	"center_hold": [110, 0, 0, true, true],
	"entry_stroke": [110, 0, 0, false, false],
	"deep_left": [168, -1, 0, false, true],
	"deep_right": [168, 1, 0, false, true],
	"deep_early": [168, 1, 20, false, true],
	"deep_delayed": [168, 1, 24, false, true],
	"last_input_row": [207, 1, 0, false, true],
	"first_locked_row": [208, 1, 0, false, true],
}


func _ready() -> void:
	ControllerHandler.set_physics_process(false)
	var trace := FileAccess.open(TRACE, FileAccess.READ)
	assert(trace != null)
	trace.get_csv_line()
	var cases := {}
	while not trace.eof_reached():
		var row := trace.get_csv_line()
		if row.size() < 20:
			continue
		if not cases.has(row[0]):
			cases[row[0]] = []
		cases[row[0]].append(row)
	var checked := _compare_pull(cases)
	var matches := true
	for label: String in SEEDS:
		matches = (await _compare_swim(label, cases[label])) and matches
	ControllerHandler._clear_input()
	await _compare_stage_ceiling()
	await _compare_stage_wall()
	await _compare_wall_camera()
	ControllerHandler.set_physics_process(true)
	assert(matches and checked > 2000)
	print("PASS: Whirlpool matches %d Mesen frames, ten swim replays, and the 2-2 head and side contacts." % checked)
	await preload("res://tests/fixtures/finish_test.gd").finish(get_tree())


func _compare_pull(cases: Dictionary) -> int:
	var level := SANDBOX.instantiate() as BaseLevel
	add_child(level)
	var player := level.player as Mario
	var whirlpool := level.get_node("Areas/MainArea/Whirlpool") as Whirlpool
	var checked := 0
	for rows: Array in cases.values():
		for row: PackedStringArray in rows:
			if int(row[4]) < 0:
				continue
			var x := int(row[4]) + X_OFFSET
			var active := whirlpool.contains_player_x(x)
			assert(active == (row[16] == "1"))
			if active:
				var dx := whirlpool.horizontal_step(x, int(row[2]), (int(row[9]) & 1) != 0)
				assert(x + dx == int(row[10]) + X_OFFSET)
				player.body.global_position.y = int(row[5]) + Y_OFFSET
				player.body.velocity.y = (int(row[6]) * 256 + int(row[7])) / 256.0 * 60.0
				player.vertical_movement.reset_fraction()
				player.vertical_movement.position_fraction = int(row[8])
				player.vertical_movement.apply_extra_step(
					player.motion_values, Whirlpool.DOWN_FORCE, Whirlpool.DOWN_LIMIT
				)
				assert(posmod(roundi(player.body.global_position.y) - Y_OFFSET, 256) == int(row[11]))
				assert(player.vertical_movement.integer_speed == int(row[13]))
				assert(player.vertical_movement.speed_fraction == int(row[14]))
				assert(player.vertical_movement.position_fraction == int(row[15]))
			checked += 1
	level.free()
	return checked


func _compare_swim(label: String, rows: Array) -> bool:
	var level := SANDBOX.instantiate() as BaseLevel
	level.player_start_configuration = null
	var seed: Array = SEEDS[label]
	var spawn := level.get_node("Players/PlayerSpawn") as Marker2D
	spawn.position = Vector2(1088 + X_OFFSET, int(seed[0]) + Y_OFFSET)
	add_child(level)
	level.set_physics_process(false)
	var player := level.player as Mario
	player.set_physics_process(false)
	var swim := player.state_machine.current_state as MarioSwimState
	assert(swim != null)
	if seed[1] == -1:
		player.face_direction(-1.0)
		swim._moving_direction = -1
	swim._in_whirlpool = seed[4]
	await get_tree().physics_frame
	await get_tree().physics_frame
	var previous_jump := false
	var matched := true
	for row: PackedStringArray in rows:
		if int(row[4]) < 0 or int(row[12]) != 1:
			break
		var tick := int(row[1])
		var first_press := int(seed[2])
		var jump: bool = first_press >= 0 and tick >= first_press and (
			seed[3] or (tick - first_press) % 8 == 0
		)
		if label in ["center_tap", "entry_stroke"]:
			jump = tick == 0
		ControllerHandler.input_primary = jump
		ControllerHandler.input_primary_just_pressed = jump and not previous_jump
		ControllerHandler.input_right = float(seed[1] == 1)
		ControllerHandler.input_left = float(seed[1] == -1)
		GameHandler.animation_clock.tick_count = int(row[2])
		player._physics_process(STEP)
		var expected := Vector2(int(row[10]) + X_OFFSET, int(row[11]) + Y_OFFSET)
		var actual := player.body.global_position
		var expected_speed := int(row[13]) * 256 + int(row[14])
		if (
			actual.distance_to(expected) >= 0.15
			or swim._in_whirlpool != (row[16] == "1")
			or swim._stroke_ticks != int(row[17])
			or roundi(player.body.velocity.x * 16.0 / 60.0) != int(row[18])
			or roundi(player.body.velocity.y * 256.0 / 60.0) != expected_speed
		):
			push_error("%s tick %d expected %s, got %s (stroke timer %d, expected %s)" % [
				label, tick, expected, actual, swim._stroke_ticks, row[17],
			])
			matched = false
			break
		if row[16] == "0" and seed[1] != 0:
			break
		previous_jump = jump
		await get_tree().physics_frame
	level.queue_free()
	await get_tree().process_frame
	return matched


func _compare_stage_ceiling() -> void:
	# Start at the end of Mesen tick 74 under the second whirlpool's left ceiling.
	var stage := await _spawn_stage(Vector2(2110, 63))
	var area := stage.active_area
	var player := stage.player as Mario
	var swim := player.state_machine.current_state as MarioSwimState
	assert(swim != null)
	swim._in_whirlpool = true
	swim._stroke_ticks = 30
	swim._stroke_origin_y = player.body.global_position.y + 16
	swim._vertical_force = 9
	swim._sink_force = 9
	player.vertical_movement.position_fraction = 152
	player.body.velocity.y = -186.0 / 256.0 * 60.0

	# At probe Y80 the center is in water. At Y79 the integer speed becomes +1.
	var expected := [Vector3i(62, -161, 45), Vector3i(62, 376, 244)]
	for index in expected.size():
		GameHandler.animation_clock.tick_count = 179 + index
		player._physics_process(STEP)
		var sample: Vector3i = expected[index]
		assert(absf(player.body.global_position.y - area.global_position.y - Y_OFFSET - sample.x) < 0.01)
		assert(roundi(player.body.velocity.y / 60.0 * 256.0) == sample.y)
		assert(player.vertical_movement.position_fraction == sample.z)
		await get_tree().physics_frame

	stage.queue_free()
	await get_tree().process_frame


func _compare_stage_wall() -> void:
	var stage := await _spawn_stage(Vector2(2086, 88))
	var player := stage.player as Mario
	var swim := player.state_machine.current_state as MarioSwimState
	assert(swim != null)
	swim._in_whirlpool = true
	swim._moving_direction = -1
	player.face_direction(-1.0)
	ControllerHandler.input_left = 1.0
	for tick in range(30):
		var stroke := tick % 8 == 0
		ControllerHandler.input_primary = stroke
		ControllerHandler.input_primary_just_pressed = stroke
		GameHandler.animation_clock.tick_count = 60 + tick
		var before_x := player.body.global_position.x
		var before_correction := player.camera_correction_x
		player._physics_process(STEP)
		if tick == 19:
			# A rightward pull cancels a leftward swim step in world X only.
			assert(player.body.global_position.x == before_x)
			assert(player.camera_correction_x - before_correction == 1.0)
		if tick == 23:
			# The right wall blocks the odd-tick pull without stopping leftward motion.
			assert(swim._blocked_direction == 1)
			assert(player.body.global_position.x - stage.active_area.global_position.x == 2085 + 8)
			assert(roundi(player.body.velocity.x / 60.0 * 16.0) == -15)
		assert(swim._in_whirlpool == (tick < 29))
		await get_tree().physics_frame
	ControllerHandler._clear_input()
	stage.queue_free()
	await get_tree().process_frame


func _compare_wall_camera() -> void:
	var stage := await _spawn_stage(Vector2(507, 176))
	var player := stage.player as Mario
	var swim := player.state_machine.current_state as MarioSwimState
	var camera := stage.active_area.get_node("Camera2D") as LevelCamera
	camera.snap_to_arrival(player.body, 155)
	ControllerHandler.input_right = 1.0
	var blocked_ticks := 0
	for tick in range(140):
		var before := player.body.global_position.x
		var camera_x := camera.global_position.x
		player._physics_process(STEP)
		camera.follow_target(player.body)
		stage.clamp_player_to_camera()
		if swim._blocked_direction == 1 and player.body.global_position.x <= before:
			assert(camera.global_position.x == camera_x, "Blocked reef contact scrolled the camera.")
			blocked_ticks += 1
		await get_tree().physics_frame
	assert(blocked_ticks > 10, "Mario must repeatedly reach the reef under held Right.")

	var camera_at_wall := camera.global_position.x
	var camera_at_clear := NAN
	var reef_right := stage.active_area.global_position.x + 544.0
	for tick in range(220):
		var stroke := tick % 8 == 0
		ControllerHandler.input_primary = stroke
		ControllerHandler.input_primary_just_pressed = stroke
		player._physics_process(STEP)
		camera.follow_target(player.body)
		stage.clamp_player_to_camera()
		if player.body.global_position.x > reef_right and is_nan(camera_at_clear):
			camera_at_clear = camera.global_position.x
		if player.body.global_position.x > reef_right + 8.0:
			break
		await get_tree().physics_frame
	assert(not is_nan(camera_at_clear) and camera_at_clear > camera_at_wall)
	assert(camera.global_position.x > camera_at_clear, "Scrolling must continue after clearing the reef.")
	print("Reef camera: zero drift on %d blocked ticks, then %.1f px of scroll after clearing." % [
		blocked_ticks, camera.global_position.x - camera_at_clear,
	])

	ControllerHandler._clear_input()
	stage.queue_free()
	await get_tree().process_frame


func _spawn_stage(nes_position: Vector2) -> BaseLevel:
	var stage := STAGE.instantiate() as BaseLevel
	stage.entry_mode = BaseLevel.EntryMode.RESPAWN
	stage.timer_enabled = false
	stage.player_start_configuration = null
	var area := stage.get_node("Areas/MainArea") as BaseLevelArea
	var spawn := stage.get_node("Players/PlayerSpawn") as Marker2D
	spawn.position = area.position + nes_position + Vector2(8, Y_OFFSET)
	add_child(stage)
	stage.set_physics_process(false)
	stage.player.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return stage
