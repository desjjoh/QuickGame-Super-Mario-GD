extends Node

const GAME := preload("res://tests/fixtures/silent_game.tscn")
const TEST_FLOOR := preload("res://tests/fixtures/test_floor.gd")
const TRACE := "res://tests/fixtures/ground_reference/grounded_start_mesen.csv"
const SPEED_BANDS := [9, 16, 25, 28]
const LAUNCH_SPEEDS := [240.0, 240.0, 240.0, 300.0, 300.0]
const RISE_FORCES := [32, 32, 30, 40, 40]
const FALL_GRAVITIES := [1575.0, 1575.0, 1350.0, 2025.0, 2025.0]
const START_X := 112.0

signal tick_finished


func _physics_process(_delta: float) -> void:
	tick_finished.emit()


func _ready() -> void:
	process_physics_priority = 200
	var traces := _load_traces()
	assert(traces.size() == 4)
	var starts := 0
	var takeoffs := 0
	for label: String in traces:
		var rows: Array = traces[label]
		await _check_start(label, rows, rows.size())
		starts += rows.size()
		for threshold: int in SPEED_BANDS:
			for index in range(rows.size()):
				var row: PackedStringArray = rows[index]
				if absi(int(row[3])) >= threshold:
					await _check_start(label, rows, index, true)
					await _check_start(label, rows, index + 1, true)
					takeoffs += 2
					break
	assert(starts == 167 and takeoffs == 24)
	print("PASS: %d Mesen grounded start ticks and %d takeoffs around jump speed bands." % [
		starts, takeoffs,
	])
	await preload("res://tests/fixtures/finish_test.gd").finish(get_tree())


func _load_traces() -> Dictionary:
	var source := FileAccess.open(TRACE, FileAccess.READ)
	assert(source != null)
	source.get_csv_line()
	var cases := {}
	while not source.eof_reached():
		var row := source.get_csv_line()
		if row.size() == 6:
			cases.get_or_add(row[0], []).append(row)
	return cases


func _check_start(label: String, rows: Array, steps: int, jump := false) -> void:
	var game := GAME.instantiate()
	add_child(game)
	TEST_FLOOR.extend_floor(game)
	var player := GameHandler.current_level.player as Mario
	player.body.global_position.x = START_X
	for frame in range(8):
		await tick_finished
	assert(player.has_floor_support() and is_zero_approx(player.body.velocity.x))
	var direction := ControllerHandler.left_action if label.contains("left") else ControllerHandler.right_action
	Input.action_press(direction)
	if label.ends_with("run"):
		Input.action_press(ControllerHandler.secondary_action)
	for index in range(steps):
		await tick_finished
		var row: PackedStringArray = rows[index]
		assert(int(row[1]) == index + 1)
		_check_ground_tick(player, row)
	if jump:
		var prior: PackedStringArray = rows[steps - 1]
		await _check_takeoff(player, absi(int(prior[3])))
	Input.action_release(direction)
	Input.action_release(ControllerHandler.secondary_action)
	game.free()
	await get_tree().process_frame


func _check_ground_tick(player: Mario, row: PackedStringArray) -> void:
	var motion := player.horizontal_movement
	var actual := Vector4(
		player.body.global_position.x - START_X,
		player.body.velocity.x * 16.0 / 60.0,
		motion._speed_fraction,
		motion._position_fraction
	)
	var expected := Vector4(int(row[2]), int(row[3]), int(row[4]), int(row[5]))
	assert(actual == expected, "%s tick %s got %s, expected %s" % [
		row[0], row[1], actual, expected,
	])
	assert(player.has_floor_support())


func _check_takeoff(player: Mario, speed: int) -> void:
	var band := 0
	for threshold: int in SPEED_BANDS:
		band += int(speed >= threshold)
	var start_y := player.body.global_position.y
	Input.action_press(ControllerHandler.primary_action)
	await tick_finished
	Input.action_release(ControllerHandler.primary_action)
	assert(player.state_machine.current_state is MarioJumpState)
	assert(absf(start_y - player.body.global_position.y - LAUNCH_SPEEDS[band] / 60.0) < 0.01)
	assert(
		roundi(player.body.velocity.y * 256.0 / 60.0)
		== roundi(-LAUNCH_SPEEDS[band] * 256.0 / 60.0) + RISE_FORCES[band]
	)
	assert(player.jump_action.falling_gravity == FALL_GRAVITIES[band])
