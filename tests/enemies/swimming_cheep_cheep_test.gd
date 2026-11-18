extends Node

const SANDBOX := preload("res://tests/fixtures/cheep_cheep_sandbox.tscn")
const TRACE_FOLDER := "res://tests/fixtures/swimming_reference/"
const STEP := 1.0 / 60.0


func _ready() -> void:
	var source := _spawn_fixture()
	_check_slot_limit(source)
	source._level.free()

	source = _spawn_fixture()
	_check_cadence(source)
	source._level.free()

	source = _spawn_fixture()
	var spawn_frames := _compare_spawns(source)
	source._level.free()
	var motion_frames := _compare_movement()
	assert(spawn_frames == 10 and motion_frames == 1100)
	await _check_runtime_swim()
	print("PASS: 32-tick cadence, shared slots 1 through 3, %d Mesen spawns, and %d motion ticks." % [
		spawn_frames, motion_frames,
	])
	await preload("res://tests/fixtures/finish_test.gd").finish(get_tree())


func _spawn_fixture() -> SwimmingCheepCheepSpawner:
	var level := SANDBOX.instantiate() as BaseLevel
	level.player_start_configuration = null
	add_child(level)
	level.player.set_physics_process(false)
	level.active_area.set_physics_process(false)
	var source := level.world_objects.get_node("SwimmingCheepCheepSpawner") as SwimmingCheepCheepSpawner
	source.set_physics_process(false)
	return source


func _reserve_slot(level: BaseLevel) -> Node:
	var actor := Node.new()
	assert(level.try_claim_spawn_slot(&"enemy", actor))
	level.add_child(actor)
	return actor


func _check_slot_limit(source: SwimmingCheepCheepSpawner) -> void:
	var level := source._level
	_reserve_slot(level)
	var second := _reserve_slot(level)
	_reserve_slot(level)
	assert(level.has_spawn_capacity(&"enemy"))
	for _tick in range(64):
		source._physics_process(STEP)
		assert(source.get_child_count() == 0 and source._remaining == 0)
	second.free()
	source._physics_process(STEP)
	assert(source.get_child_count() == 1 and source._remaining == 32)
	assert(level.spawn_registry.get_slot(&"enemy", source.get_child(0)) == 1)


func _check_cadence(source: SwimmingCheepCheepSpawner) -> void:
	source.position.x = 1.0
	source._physics_process(STEP)
	assert(source.get_child_count() == 0)
	source.position.x = 0.0
	var heights := {}
	for tick in range(289):
		source._physics_process(STEP)
		assert(source.get_child_count() == int(tick % 32 == 0))
		if source.get_child_count() != 0:
			var fish := source.get_child(0) as SwimmingCheepCheep
			if tick < 256:
				assert(not heights.has(fish.position.y))
				heights[fish.position.y] = true
			fish.free()
	assert(heights.size() == 8)


func _compare_spawns(source: SwimmingCheepCheepSpawner) -> int:
	var count := 0
	for row: PackedStringArray in _rows("cheep_spawn_mesen.csv", 8):
		var view := Rect2(0, 0, int(row[5]) + 1, 240)
		assert(source._try_spawn(view, int(row[7])))
		var fish := source.get_child(0) as SwimmingCheepCheep
		assert(fish.global_position == Vector2(int(row[3]), int(row[4])))
		assert(fish.red == (row[2] == "11"))
		assert(fish.initial_bob_down == ((int(row[7]) & 0x10) != 0))
		assert(source._used_heights == int(row[6]))
		assert(fish.projectile_target_bounds().size == Vector2(10, 6))
		var expected_art := (
			"/enemies/red-cheep.png" if fish.red else "/underwater/enemies/green-cheep.png"
		)
		assert(fish.sprite.texture.resource_path.ends_with(expected_art))
		count += 1
		fish.free()
	return count


func _compare_movement() -> int:
	var source: SwimmingCheepCheepSpawner
	var fish: SwimmingCheepCheep
	var count := 0
	for row: PackedStringArray in _rows("cheep_swim_mesen.csv", 9):
		var label := row[0]
		if row[1] == "0":
			if is_instance_valid(source):
				source._level.free()
			source = _spawn_fixture()
			for slot in range(int(row[2])):
				_reserve_slot(source._level)
			var sample := 5 if row[3] == "10" else 0xad
			if label.ends_with("_down") or label == "grey_slot0":
				sample |= 0x10
			assert(source._try_spawn(Rect2(0, 0, 189, 240), sample))
			fish = source.get_child(0) as SwimmingCheepCheep
			assert(fish._slot == int(row[2]))
			assert(fish.global_position == Vector2(220, 104))
		fish._swim_tick()
		var expected := Vector2(int(row[4]), int(row[5])) + SwimmingCheepCheep.BODY_OFFSET
		assert(fish.body.global_position == expected, "%s tick %s" % [label, row[1]])
		assert(fish._x_fraction == int(row[6]) and fish._y_fraction == int(row[7]))
		assert(fish._bob_direction == (1 if row[8] == "16" else -1))
		count += 1
	source._level.free()
	return count


func _check_runtime_swim() -> void:
	var level := SANDBOX.instantiate() as BaseLevel
	add_child(level)
	var source := level.world_objects.get_node("SwimmingCheepCheepSpawner") as SwimmingCheepCheepSpawner
	for _tick in range(3):
		await get_tree().physics_frame
	assert(source.get_child_count() == 1)
	var fish := source.get_child(0) as SwimmingCheepCheep
	var start_x := fish.body.global_position.x
	for _tick in range(8):
		await get_tree().physics_frame
	assert(fish.body.global_position.x == start_x - (4.0 if fish.red else 2.0))
	level.free()


func _rows(filename: String, columns: int) -> Array[PackedStringArray]:
	var file := FileAccess.open(TRACE_FOLDER + filename, FileAccess.READ)
	assert(file != null)
	file.get_csv_line()
	var rows: Array[PackedStringArray] = []
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() == columns:
			rows.append(row)
	return rows
