extends Node

signal tick_finished

const SANDBOX := preload("res://tests/fixtures/flying_cheep_cheep_spawner_sandbox.tscn")
const STAGE := preload("res://scenes/levels/worlds/world 2/2-3.tscn")
const STEP := 1.0 / 60.0
const REFERENCE := "res://tests/fixtures/flying_cheep_reference/"
var _attempt_slot := -1
var _sample := PackedByteArray([0, 0, 0])
var _submerged_sample := 0


func _physics_process(_delta: float) -> void:
	tick_finished.emit()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 200
	var spawns := _compare_spawn_choices()
	var ticks := _compare_stream("normal", 0)
	ticks += _compare_stream("halfway", 1792)
	ticks += _compare_stream("normal", 0, STAGE)
	ticks += _compare_stream("halfway", 1792, STAGE)
	ticks += _compare_stream("fast", 0)
	ticks += _compare_stream("fast", 0, STAGE)
	_check_slots()
	_check_lifecycle()
	_check_submerged_entry()
	await _check_runtime()
	await _check_submerged_runtime()
	print("PASS: Flying Cheep Cheep stream matches %d Mesen launch choices and %d route ticks; shared slots, pause, stop and restart verified." % [spawns, ticks])
	await preload("res://tests/fixtures/finish_test.gd").finish(get_tree())


func _fixture(left := 0, scene: PackedScene = SANDBOX) -> FlyingCheepCheepSpawner:
	var level := scene.instantiate() as BaseLevel
	if scene == STAGE and left == 1792:
		level.entry_mode = BaseLevel.EntryMode.HALFWAY_RESPAWN
	level.fall_death_enabled = false
	level.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(level)
	level.player.set_physics_process(false)
	level.active_area.set_physics_process(false)
	level.player.body.global_position = Vector2(136, 32)
	var camera := level.active_area.get_node("Camera2D") as LevelCamera
	camera.position.x = left + 128
	var source := level.world_objects.get_node("FlyingCheepCheepSpawner") as FlyingCheepCheepSpawner
	source.set_physics_process(false)
	source.get_node("TriggerClock").set_physics_process(false)
	source.random_samples = _random_bytes
	source.submerged_random_sample = func(_slot: int) -> int: return _submerged_sample
	return source


func _random_bytes(slot: int) -> PackedByteArray:
	_attempt_slot = slot
	return _sample


func _reserve(level: BaseLevel) -> Node:
	var actor := Node.new()
	assert(level.try_claim_spawn_slot(&"enemy", actor))
	level.add_child(actor)
	return actor


func _compare_spawn_choices() -> int:
	var rows := _rows("spawn_mesen.csv", 9)
	for row: PackedStringArray in rows:
		var source := _fixture()
		source._level.player.motion_values.velocity.x = int(row[1]) / 16.0 * 60.0
		assert(source._try_spawn(0, PackedByteArray([int(row[2]), int(row[3]), int(row[4])])))
		var fish: FlyingCheepCheep = source._fish_slots.keys()[0]
		assert(fish.global_position == Vector2(int(row[5]), int(row[6])), row[0])
		assert(fish.launch_velocity == Vector2(int(row[7]) / 16.0, -5), row[0])
		assert(source._remaining == int(row[8]), row[0])
		assert(not fish.is_physics_processing())
		source._finish_tick()
		assert(fish.is_physics_processing())
		source._level.free()
	return rows.size()


func _compare_stream(route: String, left: int, scene: PackedScene = SANDBOX) -> int:
	var source := _fixture(left, scene)
	if scene == STAGE:
		assert(source.start_column == 26 and source.stop_column == 197)
		assert(source.restart_columns == PackedInt32Array([137]))
		assert(source._area.get_node("Camera2D").area_right == 3808.0)
	source.start_column = 26
	source.restart_columns = PackedInt32Array([137])
	source.stop_column = 197
	source.submerged_swimmer_origin = Vector2(2304, 248)
	var rows := _rows("stream_%s_mesen.csv" % route, 32)
	var spawns := 0
	var hidden_ticks := 0
	for row: PackedStringArray in rows:
		var frame := "%s frame %s" % [route, row[0]]
		var player := source._level.player
		player.body.global_position = Vector2(int(row[2]) + 8, -68)
		player.motion_values.velocity.x = int(row[3]) / 16.0 * 60.0
		var camera := source._area.get_node("Camera2D") as LevelCamera
		camera.position.x = int(row[1]) + 128
		var previous := source._fish_slots.keys()
		for fish: FlyingCheepCheep in previous:
			fish._physics_process(STEP)
		if is_instance_valid(source._submerged):
			source._submerged._physics_process(STEP)
		_attempt_slot = -1
		_sample = PackedByteArray([int(row[14]), int(row[15]), int(row[16])])
		_submerged_sample = int(row[29])
		source._physics_process(STEP)
		assert(_attempt_slot == int(row[13]), "%s attempt: %d != %s" % [frame, _attempt_slot, row[13]])
		if int(row[17]) >= 0:
			assert(not source._new_fish.is_empty(), frame)
			var fish := source._new_fish.back() as FlyingCheepCheep
			assert(source._fish_slots[fish] == int(row[17]), frame)
			assert(fish.global_position == Vector2(int(row[18]), int(row[19])), "%s spawn position %s" % [frame, fish.global_position])
			assert(fish.launch_velocity.x == int(row[20]) / 16.0, frame)
			assert(fish.sprite.flip_h == (fish.launch_velocity.x > 0.0), frame)
			assert(fish.movement_fractions() == Vector2i(int(row[21]), int(row[22])), "%s fractions %s" % [frame, fish.movement_fractions()])
			spawns += 1
		else:
			for actor in source._new_fish:
				assert(not actor is FlyingCheepCheep, frame)
		source._area.update_camera_activity()
		source._finish_tick()
		assert(source._clock.task == int(row[4]), frame)
		assert(source._clock._scroll == int(row[5]), frame)
		assert(source._clock.column == int(row[6]), frame)
		assert(source._pending == int(row[7]), "%s queued command %d" % [frame, source._pending])
		assert(source._active == (row[8] == "1"), "%s active" % frame)
		assert(source._remaining == int(row[9]), "%s cooldown %d != %s" % [frame, source._remaining, row[9]])
		for slot in range(5):
			var occupied := source._fish_slots.values().has(slot) or source._submerged_slot == slot
			var expected := row[10 + slot] if slot < 3 else row[27 + slot]
			assert(occupied == (expected == "1"), "%s slot %d" % [frame, slot])
		if int(row[23]) >= 0:
			var hidden := source._submerged
			assert(is_instance_valid(hidden) and source._submerged_slot == int(row[23]), frame)
			assert(hidden.body.global_position == Vector2(int(row[24]), int(row[25])) + SwimmingCheepCheep.BODY_OFFSET, "%s submerged position %s" % [frame, hidden.body.global_position])
			assert(hidden.movement_fractions() == Vector2i(int(row[26]), int(row[27])), frame)
			assert(hidden._bob_direction == (-1 if int(row[28]) == 0 else 1), frame)
			hidden.set_physics_process(false)
			hidden_ticks += 1
		else:
			assert(not is_instance_valid(source._submerged), frame)
		for fish: FlyingCheepCheep in source._fish_slots:
			fish.set_physics_process(false)
	assert(spawns == (24 if route == "normal" else 14 if route == "fast" else 3))
	assert(hidden_ticks == (65 if route == "normal" else 137 if route == "fast" else 0))
	source._level.free()
	return rows.size()


func _check_slots() -> void:
	var source := _fixture()
	var level := source._level
	var first := _reserve(level)
	var second := _reserve(level)
	_reserve(level)
	_sample = PackedByteArray([0, 1, 0])
	source._physics_process(STEP)
	assert(source._active and source._remaining == 96)
	assert(_attempt_slot == 3 and source._fish_slots.is_empty())
	# No global slot means no attempt, even when the stream cooldown expires.
	_reserve(level)
	_reserve(level)
	for _tick in range(100):
		source._physics_process(STEP)
	assert(source._remaining == 0 and source._fish_slots.is_empty())
	second.free()
	source._physics_process(STEP)
	assert(source._fish_slots.values() == [1])
	assert(level.spawn_registry.get_slot(&"enemy", first) == 0)
	# Immediate release is idempotent, including a later exit by the old actor.
	var fish: FlyingCheepCheep = source._fish_slots.keys()[0]
	fish.body.position.y = 272
	fish._physics_process(STEP)
	source._finish_tick()
	assert(level.spawn_registry.get_next_free_slot(&"enemy") == 1)
	var replacement := _reserve(level)
	fish.free()
	assert(level.spawn_registry.get_slot(&"enemy", replacement) == 1)
	level.free()
	for limit in [0, 1, 2, 10]:
		source = _fixture()
		source._level.spawn_registry.enemy_limit = limit
		for _tick in range(200):
			source._physics_process(STEP)
		assert(source._fish_slots.size() == mini(limit, 3))
		source._level.free()


func _check_lifecycle() -> void:
	var source := _fixture()
	source._physics_process(STEP)
	assert(source._fish_slots.size() == 1)
	source._finish_tick()
	var remaining := source._remaining
	var level := source._level
	for flag in ["death_in_progress", "completion_in_progress", "transition_in_progress", "is_shutdown"]:
		level.set(flag, true)
		source._physics_process(STEP)
		source._finish_tick()
		assert(source._remaining == remaining)
		level.set(flag, false)
	for flag in ["is_active", "actors_initialized", "runtime_loaded", "actors_suspended"]:
		var original: bool = source._area.get(flag)
		source._area.set(flag, not original)
		source._physics_process(STEP)
		assert(source._remaining == remaining)
		source._area.set(flag, original)
	level.set_physics_process(false)
	source._physics_process(STEP)
	assert(source._remaining == remaining)
	level.set_physics_process(true)
	# Stop spawning without deleting already flying fish.
	source.stop_column = 1
	source._queue_column(1)
	source._physics_process(STEP)
	assert(not source._active and source._fish_slots.size() == 1)
	level.free()
	# A fresh checkpoint fixture has no retained stream state or slot fractions.
	source = _fixture(1792)
	source.start_column = 26
	source.restart_columns = PackedInt32Array([137])
	source._physics_process(STEP)
	assert(not source._active and source._fish_slots.is_empty())
	assert(source._slot_fractions == [Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO])
	source._level.free()


func _check_runtime() -> void:
	var source := _fixture()
	var level := source._level
	# Verify the regular scene-tree process order, not only manual stepping.
	level.player.body.position = Vector2(136, 32)
	source.set_physics_process(true)
	source.get_node("TriggerClock").set_physics_process(true)
	var seen := {}
	for tick in range(400):
		await tick_finished
		assert(source._fish_slots.size() <= 3)
		for fish: FlyingCheepCheep in source._fish_slots:
			assert(not fish.activity_suspended)
			seen[fish.get_instance_id()] = true
		if tick == 0:
			var newborn: FlyingCheepCheep = source._fish_slots.keys()[0]
			assert(newborn.body.global_position.y == 264.0)
		elif tick == 1:
			var newborn: FlyingCheepCheep = source._fish_slots.keys()[0]
			assert(newborn.body.global_position.y == 259.0)
		var before := source._remaining
		if tick == 60:
			get_tree().paused = true
			var position: Vector2 = source._fish_slots.keys()[0].body.global_position
			for _tick in range(5):
				await tick_finished
			assert(source._remaining == before)
			assert(source._fish_slots.keys()[0].body.global_position == position)
			get_tree().paused = false
	assert(seen.size() > 3)
	level.free()


func _check_submerged_entry() -> void:
	var source := _fixture(2000)
	source.submerged_swimmer_origin = Vector2(2304, 248)
	_submerged_sample = 0
	source._slot_fractions[0] = Vector2i(192, 196)
	source._physics_process(STEP)
	assert(not is_instance_valid(source._submerged))
	source._area.get_node("Camera2D").position.x = 2001 + 128
	source._physics_process(STEP)
	var fish := source._submerged
	assert(source._submerged_slot == 0)
	assert(fish.body.global_position == Vector2(2304, 248) + SwimmingCheepCheep.BODY_OFFSET)
	assert(fish.movement_fractions() == Vector2i(192, 196))
	source._finish_tick()
	fish._physics_process(STEP)
	assert(fish.movement_fractions() == Vector2i(128, 196))
	# The ordinary bound is inclusive until the next pixel, not a lifetime timer.
	var origin_x := fish.body.global_position.x - SwimmingCheepCheep.BODY_OFFSET.x
	source._area.get_node("Camera2D").position.x = origin_x + 73 + 128
	source._area.update_camera_activity()
	assert(not fish.is_queued_for_deletion())
	source._area.get_node("Camera2D").position.x += 1
	source._area.update_camera_activity()
	assert(fish.is_queued_for_deletion())
	source._finish_tick()
	assert(not is_instance_valid(source._submerged))
	assert(source._level.spawn_registry.get_next_free_slot(&"enemy") == 0)
	assert(source._slot_fractions[0] == Vector2i(128, 196))
	source._area.get_node("Camera2D").position.x = 2001 + 128
	source._physics_process(STEP)
	assert(not is_instance_valid(source._submerged))
	source._level.free()
	# A full registry delays the ordinary entry until an eligible slot is free.
	source = _fixture(2001)
	source.submerged_swimmer_origin = Vector2(2304, 248)
	var occupied: Array[Node] = []
	for _slot in range(5):
		occupied.append(_reserve(source._level))
	source._physics_process(STEP)
	assert(not source._submerged_attempted)
	occupied[3].free()
	source._physics_process(STEP)
	assert(source._submerged_slot == 3)
	source._level.free()
	# Passing the visible right edge consumes a missed entry without a late spawn.
	source = _fixture(2050)
	source.submerged_swimmer_origin = Vector2(2304, 248)
	source._physics_process(STEP)
	assert(source._submerged_attempted and not is_instance_valid(source._submerged))
	source._level.free()


func _check_submerged_runtime() -> void:
	var source := _fixture(2001)
	source.submerged_swimmer_origin = Vector2(2304, 248)
	_submerged_sample = 0x10
	for _slot in range(3):
		_reserve(source._level)
	source._area.set_physics_process(true)
	source.set_physics_process(true)
	source.get_node("TriggerClock").set_physics_process(true)
	await tick_finished
	assert(source._submerged_slot == 3)
	var fish := source._submerged
	for _tick in range(20):
		await tick_finished
	var position := fish.body.global_position
	var fractions := fish.movement_fractions()
	get_tree().paused = true
	for _tick in range(5):
		await tick_finished
	assert(fish.body.global_position == position and fish.movement_fractions() == fractions)
	get_tree().paused = false
	for _tick in range(50):
		await tick_finished
	assert(not is_instance_valid(fish) and not is_instance_valid(source._submerged))
	assert(source._submerged_attempted)
	assert(source._level.spawn_registry.get_next_free_slot(&"enemy") == 3)
	source._level.free()


func _rows(filename: String, columns: int) -> Array[PackedStringArray]:
	var file := FileAccess.open(REFERENCE + filename, FileAccess.READ)
	assert(file != null)
	file.get_csv_line()
	var rows: Array[PackedStringArray] = []
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() == columns:
			rows.append(row)
	assert(not rows.is_empty())
	return rows
