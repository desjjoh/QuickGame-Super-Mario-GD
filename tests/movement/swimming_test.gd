extends Node

const SANDBOX := preload("res://tests/fixtures/swim_sandbox.tscn")
const LUIGI := preload("res://scenes/player/luigi/luigi.tscn")
const TRACE := "res://tests/fixtures/swimming_reference/swimming_mesen.csv"
const POSE_TRACE := "res://tests/fixtures/swimming_reference/swimming_poses_mesen.csv"
const STEP := 1.0 / 60.0
const NES_BODY_OFFSET := Vector2(8, 32)
const SEEDS := {
	"sink": Vector3(80, 60, 0),
	"tap": Vector3(80, 112, 0),
	"hold": Vector3(80, 112, 0),
	"repeat": Vector3(80, 112, 0),
	"right": Vector3(80, 54, 0),
	"run": Vector3(80, 54, 0),
	"reverse": Vector3(80, 54, 0),
	"reverse_left": Vector3(160, 54, 0),
	"surface_start": Vector3(80, 21, 0),
	"surface_block": Vector3(80, 19, 0),
	"surface_repeat": Vector3(80, 28, 0),
	"expired_up": Vector3(80, 112, -2),
	"right_cap": Vector3(80, 54, 0),
	"left_cap": Vector3(160, 54, 0),
	"seabed": Vector3(80, 176, 0),
	"surface_edge": Vector3(80, 20, 0),
	"sink_cap": Vector3(80, 40, 4),
}


func _ready() -> void:
	ControllerHandler.set_physics_process(false)
	var trace := FileAccess.open(TRACE, FileAccess.READ)
	assert(trace != null)
	trace.get_csv_line()
	var cases := {}
	while not trace.eof_reached():
		var row := trace.get_csv_line()
		if row.size() != 9:
			continue
		if not cases.has(row[0]):
			cases[row[0]] = []
		cases[row[0]].append(row)
	assert(cases.size() == SEEDS.size())
	var matches := true
	for luigi in [false, true]:
		for label: String in cases:
			matches = (await _compare(label, cases[label], luigi)) and matches
	ControllerHandler._clear_input()
	ControllerHandler.set_physics_process(true)
	assert(matches)
	await _compare_poses()
	print("PASS: Both characters match 17 Mesen swim motion traces and all swim form poses.")
	await preload("res://tests/fixtures/finish_test.gd").finish(get_tree())


func _compare(label: String, rows: Array, luigi: bool) -> bool:
	var level := SANDBOX.instantiate() as BaseLevel
	if luigi:
		level.player_scene = LUIGI
	var seed: Vector3 = SEEDS[label]
	var spawn := level.get_node("Players/PlayerSpawn") as Marker2D
	spawn.position = Vector2(seed.x, seed.y) + NES_BODY_OFFSET
	add_child(level)
	level.set_physics_process(false)
	var player := level.player as Mario
	player.set_physics_process(false)
	var swim := player.state_machine.current_state as MarioSwimState
	assert(swim != null)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if label == "seabed":
		player.move_body()
		assert(player.has_floor_support())
	if label in ["left_cap", "reverse_left"]:
		player.face_direction(-1.0)
		swim._moving_direction = -1
	player.body.velocity.y = seed.z * 60.0
	var previous_jump := false
	var matched := true
	for row: PackedStringArray in rows:
		var tick := int(row[1])
		var jump := _jump_held(label, tick)
		ControllerHandler.input_primary = jump
		ControllerHandler.input_primary_just_pressed = jump and not previous_jump
		ControllerHandler.input_right = float(_right_held(label, tick))
		ControllerHandler.input_left = float(
			(label == "left_cap" and tick < 52)
			or (label == "reverse" and tick >= 28 and tick < 55)
			or (label == "reverse_left" and tick < 28)
		)
		ControllerHandler.input_secondary = label == "run" and tick < 36
		player._physics_process(STEP)
		var expected := Vector2(float(row[2]), float(row[3])) + NES_BODY_OFFSET
		var actual := player.body.global_position
		var context := "%s tick %d (%s)" % [label, tick, "Luigi" if luigi else "Mario"]
		var vertical_units := int(row[5]) * 256 + int(row[6])
		if (
			actual.distance_to(expected) >= 0.15
			or roundi(player.body.velocity.x * 16.0 / 60.0) != int(row[4])
			or roundi(player.body.velocity.y * 256.0 / 60.0) != vertical_units
			or swim._stroke_ticks != int(row[7])
			or player.sprite.flip_h != (int(row[8]) == 2)
		):
			push_error("%s expected %s, speeds %s/%s, timer %s; got %s, speeds %s/%s, timer %s" % [
				context, expected, int(row[4]), vertical_units, int(row[7]), actual,
				roundi(player.body.velocity.x * 16.0 / 60.0),
				roundi(player.body.velocity.y * 256.0 / 60.0), swim._stroke_ticks,
			])
			matched = false
			break
		previous_jump = jump
		await get_tree().physics_frame
	level.queue_free()
	await get_tree().process_frame
	return matched


func _jump_held(label: String, tick: int) -> bool:
	match label:
		"tap", "surface_start", "surface_block", "surface_edge", "expired_up":
			return tick == 0
		"hold":
			return tick < 65
		"repeat":
			return tick in [0, 12, 24]
		"surface_repeat":
			return tick % 9 == 0
	return false


func _right_held(label: String, tick: int) -> bool:
	match label:
		"right", "run":
			return tick < 36
		"right_cap", "seabed":
			return tick < 52
		"reverse":
			return tick < 28
		"reverse_left":
			return tick >= 28 and tick < 55
	return false


func _compare_poses() -> void:
	ControllerHandler.set_physics_process(false)
	var clock := GameHandler.animation_clock
	var saved_tick := clock.tick_count
	clock.set_physics_process(false)
	var file := FileAccess.open(POSE_TRACE, FileAccess.READ)
	assert(file != null)
	file.get_csv_line()
	var traces := {"sink": [], "tap": [], "big": []}
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() == 4:
			traces[row[0]].append(row)

	for luigi in [false, true]:
		for form_index in range(3):
			var labels := ["sink", "tap"] if form_index == 0 else ["big"]
			for label: String in labels:
				await _compare_pose_case(traces[label], label, luigi, form_index)
	clock.tick_count = saved_tick
	clock.set_physics_process(true)
	ControllerHandler._clear_input()
	ControllerHandler.set_physics_process(true)


func _compare_pose_case(rows: Array, label: String, luigi: bool, form_index: int) -> void:
	var level := SANDBOX.instantiate() as BaseLevel
	if luigi:
		level.player_scene = LUIGI
	var spawn := level.get_node("Players/PlayerSpawn") as Marker2D
	spawn.position = Vector2(80, 60 if label == "sink" else 112) + NES_BODY_OFFSET
	add_child(level)
	level.set_physics_process(false)
	var player := level.player as Mario
	player.set_physics_process(false)
	var form: MarioForm = [player.small_form, player.super_form, player.fire_form][form_index]
	player.form_controller.configure(player, form)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for row: PackedStringArray in rows:
		var tick := int(row[1])
		var pressed := tick == 0 and label != "sink"
		ControllerHandler.input_primary = pressed
		ControllerHandler.input_primary_just_pressed = pressed
		GameHandler.animation_clock.tick_count = int(row[2])
		player._physics_process(STEP)
		var pose := player.sprite.texture as AtlasTexture
		var columns := [7, 8, 9, 10, 11, 11] if form_index == 0 else [9, 10, 11, 12, 13, 14]
		assert(pose == form.swim[int(row[3])], "%s %s pose at tick %d" % [label, form.display_name, tick])
		assert(pose.region.position.x == columns[int(row[3])] * 16)
		await get_tree().physics_frame
	level.queue_free()
	await get_tree().process_frame
