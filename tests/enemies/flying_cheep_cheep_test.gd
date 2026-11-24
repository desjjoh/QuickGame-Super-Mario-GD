extends Node

signal tick_finished

const SANDBOX := preload("res://tests/fixtures/flying_cheep_cheep_sandbox.tscn")
const FISH := preload("res://scenes/entities/enemies/cheep_cheep/flying_cheep_cheep.tscn")
const KOOPA := preload("res://scenes/entities/enemies/koopa/green_koopa.tscn")
const SUPER := preload("res://assets/player/forms/super.tres")
const FIRE := preload("res://assets/player/forms/fire.tres")
const STEP := 1.0 / 60.0
const PLAYER_OFFSET := Vector2(8, 32)
const REFERENCE := "res://tests/fixtures/flying_cheep_reference/"


func _physics_process(_delta: float) -> void:
	tick_finished.emit()


func _ready() -> void:
	process_physics_priority = 200
	var flight := _rows("flight_mesen.csv", 9)
	var defeats := _rows("defeat_mesen.csv", 14)
	var fractions := _rows("fractions_mesen.csv", 6)
	var compared := 0
	for label: String in flight:
		compared += await _compare_flight(label, flight[label])
	for label: String in fractions:
		compared += await _compare_fractions(label, fractions[label])
	for label: String in defeats:
		compared += await _compare_defeat(label, defeats[label])
	for form in [null, SUPER, FIRE]:
		await _check_damage(form)
	for descending in [false, true]:
		await _check_double_stomp(descending)
	await _check_pause_and_cleanup()
	await _check_star_priority()
	await _check_pose_phases()
	await _check_live_facing()
	await _check_knockout_facing()
	await _check_runtime_sandbox()
	print(
		"PASS: Flying Cheep Cheep matches %d Mesen ticks, damage, double stomps, pause, slot release and cleanup."
		% compared
	)
	await preload("res://tests/fixtures/finish_test.gd").finish(get_tree())


func _fixture(configuration: Resource = null, bridge := false) -> BaseLevel:
	var level := SANDBOX.instantiate() as BaseLevel
	level.player_start_configuration = configuration
	var area := level.get_node("Areas/MainArea") as BaseLevelArea
	for actor in area.get_node("WorldObjects").get_children():
		actor.free()
	if not bridge:
		var ground := area.get_node("Layouts/GroundLayout") as TileMapLayer
		for cell in ground.get_used_cells():
			if cell.y < 13:
				ground.erase_cell(cell)
	add_child(level)
	level.set_physics_process(false)
	area.set_physics_process(false)
	level.player.set_physics_process(false)
	return level


func _fish(
	level: BaseLevel, origin: Vector2, velocity: Vector2, x_fraction := 0, y_fraction := 0
) -> FlyingCheepCheep:
	var fish := FISH.instantiate() as FlyingCheepCheep
	fish.position = origin
	fish.launch_velocity = velocity
	fish.initial_horizontal_fraction = x_fraction
	fish.initial_vertical_fraction = y_fraction
	assert(level.try_claim_spawn_slot(&"enemy", fish))
	level.world_objects.add_child(fish)
	fish.set_physics_process(false)
	assert(fish.projectile_target_bounds().size == Vector2(10, 6))
	assert(fish.sprite.texture.resource_path.ends_with("/enemies/red-cheep.png"))
	return fish


func _even_tick() -> void:
	while Engine.get_physics_frames() % 2 != 0:
		await tick_finished


func _next_tick() -> void:
	await tick_finished


func _retire(level: BaseLevel) -> void:
	level.queue_free()
	await get_tree().process_frame


func _compare_flight(label: String, rows: Array) -> int:
	var level := _fixture(null, true)
	var left := label.contains("left")
	var far := label.begins_with("far")
	var origin := Vector2(-128 if left else 600, 80) if far else Vector2(128, 248)
	var velocity := Vector2.ZERO if far else Vector2(-2 if left else 2, -5)
	var fish := _fish(level, origin, velocity)
	for row: PackedStringArray in rows:
		var before := fish.body.global_position
		fish._physics_process(STEP)
		assert(fish.sprite.flip_h == (velocity.x > 0.0), label)
		level.active_area.update_camera_activity()
		if row[2] == "0":
			assert(fish.is_queued_for_deletion(), "%s cleanup tick %s" % [label, row[1]])
			continue
		assert(not fish.is_queued_for_deletion() and not fish.activity_suspended)
		assert(fish.body.global_position == Vector2(int(row[3]), int(row[4])) + FlyingCheepCheep.BODY_OFFSET,
			"%s flight tick %s: %s" % [label, row[1], fish.body.global_position])
		assert(fish._speed_units >> 8 == int(row[6]))
		assert((fish._speed_units & 0xff) == int(row[7]))
		assert(fish.vertical.position_fraction == int(row[8]))
		assert(fish.sprite.global_position == before + Vector2(0, 1))
	await get_tree().process_frame
	assert(level.spawn_registry.has_enemy_slot_before(1) == not far)
	await _retire(level)
	return rows.size()


func _compare_fractions(label: String, rows: Array) -> int:
	var level := _fixture()
	var retained := label.begins_with("retained")
	var fish := _fish(level, Vector2(80, 248), Vector2(1.75, -5),
		127 if retained else 0, 208 if retained else 0)
	for row: PackedStringArray in rows:
		fish._physics_process(STEP)
		assert(fish.body.global_position == Vector2(int(row[2]), int(row[3])) + FlyingCheepCheep.BODY_OFFSET)
		assert(fish._x_fraction == int(row[4]) and fish.vertical.position_fraction == int(row[5]))
	await _retire(level)
	return rows.size()


func _compare_defeat(label: String, rows: Array) -> int:
	GameHandler.set_score(0)
	var configuration := SUPER if label == "stomp_form1" else FIRE if label == "stomp_form2" else null
	var level := _fixture(configuration)
	var star := label.begins_with("star")
	var fire := label == "fireball"
	var top := label == "star_knockout_above_screen"
	var shell := label == "shell_same_height"
	var origin := Vector2(128, 17 if top else 148 if star else 160)
	if fire or shell:
		origin = Vector2(160 if shell else 152, 184)
	var fish := _fish(level, origin, Vector2.ZERO, 0, 39 if shell else 78 if fire else 0)
	fish._speed_units = 39 if shell else 68 if fire else 0
	var player := level.player as Mario
	player.stomp_chain = 4 if label == "stomp_chain4" else 0
	await _even_tick()
	GameHandler.animation_clock.tick_count = 8
	fish._show_flight_pose()
	var saved_pose := fish.sprite.global_position
	if shell:
		fish._physics_process(STEP)
		var attacker := KOOPA.instantiate() as BaseEnemy
		assert(level.try_claim_spawn_slot(&"enemy", attacker))
		level.world_objects.add_child(attacker)
		attacker.set_physics_process(false)
		var moving := attacker.get_node("StateMachine/ShellMoving")
		assert(attacker.state_machine.change_state(moving))
		moving._on_enemy_contact(fish)
		assert(fish.is_defeated())
	elif star or fire:
		assert(fish.receive_hit(EntityHit.new(player, &"star" if star else &"fireball", Vector2.ZERO)))
	else:
		player.body.global_position = Vector2(128, int(rows[0][10])) + PLAYER_OFFSET
		var integer_speed := -1 if label == "above_rising" else 0 if label == "above_stationary" else 1
		player.jump_action.falling_gravity = 2025.0
		player.jump_action.launch_with_falling_gravity(
			player.motion_values, (integer_speed + 144.0 / 256.0) * 60.0
		)
		fish._physics_process(STEP)
		assert(floori(player.body.velocity.y / 60.0) == -3)
		assert(player.stomp_chain == (4 if label == "stomp_chain4" else 0))
	for row: PackedStringArray in rows:
		assert(fish.body.global_position == Vector2(int(row[3]), int(row[4])) + FlyingCheepCheep.BODY_OFFSET,
			"%s defeat tick %s: %s" % [label, row[1], fish.body.global_position])
		assert(fish._knocked_out._speed_units >> 8 == int(row[5]))
		assert((fish._knocked_out._speed_units & 0xff) == int(row[6]))
		assert(fish._knocked_out._position_fraction == int(row[7]))
		assert(
			GameHandler.player_status.score == int(row[8]),
			"%s score tick %s: got %s, expected %s"
			% [label, row[1], GameHandler.player_status.score, row[8]]
		)
		assert(fish.sprite.flip_v == (row[9] == "True"))
		if row[1] == "0" and not fire:
			assert(fish.sprite.global_position == saved_pose)
		if row[1] != "0":
			assert(fish.sprite.frame == 0)
		if label in ["stomp_form0", "stomp_held_jump"] and int(row[1]) < 8:
			assert(player.body.global_position.y == int(row[10]) + PLAYER_OFFSET.y)
			assert(floori(player.body.velocity.y / 60.0) == int(row[11]))
		await _next_tick()
		if label in ["stomp_form0", "stomp_held_jump"] and int(row[1]) < 7:
			player.jump_action.update(player.motion_values, label == "stomp_held_jump")
			player.move_body(true)
		fish._physics_process(STEP)
	await _retire(level)
	return rows.size()


func _check_damage(configuration: Resource) -> void:
	var level := _fixture(configuration)
	var fish := _fish(level, Vector2(128, 148), Vector2.ZERO)
	var player := level.player as Mario
	player.body.global_position = Vector2(128, 144) + PLAYER_OFFSET
	player.body.velocity.y = 144.0 / 256.0 * 60.0
	await _even_tick()
	fish._physics_process(STEP)
	assert(not fish.is_defeated())
	if configuration == null:
		assert(player.is_dead)
	else:
		assert(player.form_presentation.active and player.damage.is_protected())
	await _retire(level)


func _check_double_stomp(descending: bool) -> void:
	GameHandler.set_score(0)
	var level := _fixture()
	var first := _fish(level, Vector2(128, 160), Vector2.ZERO)
	var second := _fish(level, Vector2(130, 160), Vector2.ZERO)
	var player := level.player as Mario
	player.body.global_position = Vector2(128, 145 if descending else 144) + PLAYER_OFFSET
	player.body.velocity.y = (1.0 if descending else 0.0) * 60.0 + 144.0 / 256.0 * 60.0
	await _even_tick()
	first._physics_process(STEP)
	second._physics_process(STEP)
	assert(first.is_defeated() and second.is_defeated())
	for _tick in range(5):
		await _next_tick()
	assert(GameHandler.player_status.score == 400 and player.stomp_chain == 0)
	await _retire(level)


func _check_pause_and_cleanup() -> void:
	var level := _fixture()
	level.active_area.position = Vector2(1024, 240)
	var fish := _fish(level, Vector2(600, -40), Vector2(1, -3))
	level.active_area.update_camera_activity()
	assert(not fish.activity_suspended and not fish.is_queued_for_deletion())
	fish.set_gameplay_suspended(true)
	var before := fish.body.global_position
	fish._physics_process(STEP)
	assert(fish.body.global_position == before)
	fish.set_gameplay_suspended(false)
	fish._physics_process(STEP)
	assert(fish.body.global_position != before)
	fish.body.global_position.y = level.active_area.global_position.y + 256 + FlyingCheepCheep.BODY_OFFSET.y
	level.active_area.update_camera_activity()
	assert(not fish.is_queued_for_deletion())
	fish._physics_process(STEP)
	assert(fish.is_queued_for_deletion())
	await get_tree().process_frame
	assert(level.spawn_registry.has_enemy_slot_before(1))
	var replacement := _fish(level, Vector2(128, 248), Vector2.ZERO)
	assert(level.spawn_registry.get_slot(&"enemy", replacement) == 0)
	await _retire(level)


func _rows(filename: String, columns: int) -> Dictionary:
	var file := FileAccess.open(REFERENCE + filename, FileAccess.READ)
	assert(file != null)
	file.get_csv_line()
	var rows := {}
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() == columns:
			if not rows.has(row[0]):
				rows[row[0]] = []
			rows[row[0]].append(row)
	return rows


func _check_star_priority() -> void:
	var level := _fixture()
	var fish := _fish(level, Vector2(128, 160), Vector2.ZERO)
	var player := level.player as Mario
	player.body.global_position = Vector2(128, 145) + PLAYER_OFFSET
	player.body.velocity.y = 60.0
	player.starman.begin()
	await _even_tick()
	fish._physics_process(STEP)
	assert(fish.is_defeated() and fish._knocked_out.star_launch)
	assert(not fish._knocked_out.stomp_launch and player.body.velocity.y == 60.0)
	await _retire(level)


func _check_runtime_sandbox() -> void:
	var level := SANDBOX.instantiate() as BaseLevel
	add_child(level)
	level.set_physics_process(false)
	level.player.set_physics_process(false)
	level.player.body.position = Vector2(-200, -400)
	var right := level.world_objects.get_node("RightFish") as FlyingCheepCheep
	var left := level.world_objects.get_node("LeftFish") as FlyingCheepCheep
	assert(level.spawn_registry.get_slot(&"enemy", right) == 0)
	assert(level.spawn_registry.get_slot(&"enemy", left) == 1)
	assert(right.sprite.flip_h and not left.sprite.flip_h)
	for _tick in range(190):
		await _next_tick()
	assert(not is_instance_valid(right) and not is_instance_valid(left))
	assert(level.spawn_registry.has_enemy_slot_before(1))
	await _retire(level)


func _check_live_facing() -> void:
	for horizontal in [-2.0, 2.0]:
		var level := _fixture()
		var fish := _fish(level, Vector2(128, 160), Vector2(horizontal, -5))
		var frames := {}
		for phase in [0, 8]:
			GameHandler.animation_clock.tick_count = phase
			fish._show_flight_pose()
			assert(fish.sprite.flip_h == (horizontal > 0.0))
			frames[fish.sprite.frame] = true
		assert(frames.size() == 2)
		await _retire(level)


func _check_knockout_facing() -> void:
	var file := FileAccess.open(REFERENCE + "facing_hits_mesen.csv", FileAccess.READ)
	assert(file != null)
	file.get_csv_line()
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() != 5:
			continue
		# The atlas is mirrored relative to native unflipped CHR graphics.
		var held_facing := (int(row[3]) & 0x40) == 0
		var knockout_facing := (int(row[4]) & 0x40) == 0
		for maneuver in [&"star", &"fireball", &"stomp"]:
			var level := _fixture()
			var fish := _fish(level, Vector2(128, 148), Vector2(float(row[1]), 0))
			level.player.body.global_position = Vector2(float(row[2]), 144) + PLAYER_OFFSET
			assert(fish.sprite.flip_h == held_facing, row[0])
			assert(fish.receive_hit(EntityHit.new(level.player, maneuver, Vector2.ZERO)))
			assert(fish.sprite.flip_h == (knockout_facing if maneuver == &"fireball" else held_facing), row[0])
			await _next_tick()
			fish._physics_process(STEP)
			assert(fish.sprite.flip_h == knockout_facing, row[0])
			await _retire(level)


func _check_pose_phases() -> void:
	for phase in [0, 8]:
		for maneuver in [&"stomp", &"star", &"fireball"]:
			var level := _fixture()
			var fish := _fish(level, Vector2(128, 160), Vector2.ZERO)
			GameHandler.animation_clock.tick_count = phase
			fish._show_flight_pose()
			var frame := fish.sprite.frame
			var position := fish.sprite.global_position
			assert(fish.receive_hit(EntityHit.new(level.player, maneuver, Vector2.ZERO)))
			if maneuver == &"fireball":
				assert(fish.sprite.flip_v and fish.sprite.frame == 0)
			else:
				assert(not fish.sprite.flip_v and fish.sprite.frame == frame)
				assert(fish.sprite.global_position == position)
			await _next_tick()
			fish._physics_process(STEP)
			assert(fish.sprite.flip_v and fish.sprite.frame == 0)
			await _retire(level)
