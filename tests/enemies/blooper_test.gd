extends Node

const SANDBOX := preload("res://tests/fixtures/swim_sandbox.tscn")
const SHOT := preload("res://scenes/entities/projectiles/fireball.tscn")
const SUPER := preload("res://assets/player/forms/super.tres")
const STEP := 1.0 / 60.0
const PLAYER_OFFSET := Vector2(8, 32)
const MARKER := Vector2i(9, 7)
const SEEDS := {
	"burst_drift": Vector2(183, 127),
	"high_player": Vector2(207, 112),
	"surface": Vector2(174, 36),
	"even_slot_turn": Vector2(167, 105),
	"odd_slot_turn": Vector2(167, 105),
	"reef": Vector2(164, 184),
}


func _ready() -> void:
	var movement := _read_traces("blooper_mesen.csv", 13)
	var defeats := _read_traces("blooper_defeat_mesen.csv", 5)
	assert(movement.size() == 6 and defeats.size() == 2)
	for label: String in movement:
		await _compare_swim(label, movement[label])
	for label: String in defeats:
		await _compare_defeat(label, defeats[label])
	await _check_player_contact(Vector2(134, 118), Vector2(128, 110), 0.0, true)
	await _check_player_contact(Vector2(134, 118), Vector2(128, 110), 0.0)
	await _check_player_contact(Vector2(131, 110), Vector2(128, 93), 180.0)
	await _check_player_contact(Vector2(128, 130), Vector2(128, 141), -120.0)
	print("PASS: Blooper spawns with its themed art, matches Mesen movement and defeats, and matches player contact.")
	await preload("res://tests/fixtures/finish_test.gd").finish(get_tree())


func _read_traces(filename: String, columns: int) -> Dictionary:
	var file := FileAccess.open("res://tests/fixtures/swimming_reference/" + filename, FileAccess.READ)
	assert(file != null)
	file.get_csv_line()
	var cases := {}
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() == columns:
			if not cases.has(row[0]):
				cases[row[0]] = []
			cases[row[0]].append(row)
	return cases


func _spawn_blooper(odd_slot := false, configuration: Resource = null) -> Blooper:
	var level := SANDBOX.instantiate() as BaseLevel
	level.player_start_configuration = configuration
	var area := level.get_node("Areas/MainArea") as BaseLevelArea
	var enemies := area.get_node("Layouts/EnemyLayout") as TileMapLayer
	enemies.set_cell(MARKER, 8, Vector2i.ZERO)
	var ground := area.get_node("Layouts/GroundLayout") as TileMapLayer
	for y in range(10, 13):
		ground.set_cell(Vector2i(11, y), 5, Vector2i(3, 1))
	if odd_slot:
		var occupied := Node.new()
		level.add_child(occupied)
		var registry := level.get_node("Systems/LevelSpawnRegistry") as LevelSpawnRegistry
		assert(registry.try_claim(&"enemy", occupied))
	add_child(level)
	level.set_physics_process(false)
	area.set_physics_process(false)
	level.player.set_physics_process(false)
	area.update_camera_activity()
	var marker := area.get_node("WorldObjects/blooper_spawner_9_7") as EntitySpawner
	var blooper := marker.get_node("Blooper") as Blooper
	blooper.set_physics_process(false)
	assert(blooper.body.global_position == Vector2(MARKER * 16) + Vector2(0, 8) + Blooper.BODY_OFFSET)
	assert(blooper.sprite.texture.resource_path.ends_with("/underwater/enemies/blooper.png"))
	assert(level.spawn_registry.get_slot(&"enemy", blooper) == int(odd_slot))
	assert(blooper.projectile_target_bounds().size == Vector2(10, 6))
	return blooper


func _compare_swim(label: String, rows: Array) -> void:
	var blooper := _spawn_blooper(label == "odd_slot_turn")
	blooper.body.global_position = SEEDS[label] + Blooper.BODY_OFFSET
	if label == "reef":
		blooper._direction = 1
	var player := blooper._level.player as Mario
	var swim := player.state_machine.current_state as MarioSwimState
	assert(swim != null)
	var checked := 0
	for row: PackedStringArray in rows:
		player.body.global_position = Vector2(int(row[3]), int(row[4])) + PLAYER_OFFSET
		swim._moving_direction = 1 if int(row[5]) == 1 else -1
		if int(row[11]) < blooper._drift_intervals:
			player.damage.interval_elapsed.emit()
		blooper._swim_tick(int(row[2]), int(row[12]))
		assert(
			blooper.body.global_position == Vector2(int(row[6]), int(row[7])) + Blooper.BODY_OFFSET
			and blooper._direction == (1 if int(row[8]) == 1 else -1)
			and blooper._speed == int(row[9])
			and blooper._phase == int(row[10])
			and blooper._drift_intervals == int(row[11]),
			"%s tick %s" % [label, row[1]],
		)
		checked += 1
	assert(checked == rows.size())
	await _retire(blooper)


func _compare_defeat(label: String, rows: Array) -> void:
	var blooper := _spawn_blooper()
	var player := blooper._level.player as Mario
	player.body.global_position = Vector2(128, 111) + PLAYER_OFFSET
	var original_score := GameHandler.player_status.score
	var star := label == "star"
	if star:
		blooper.body.global_position = Vector2(134, 119) + Blooper.BODY_OFFSET
		player.starman.intervals_remaining = 60
		while Engine.get_physics_frames() % 2 != 0:
			await get_tree().physics_frame
		blooper._physics_process(STEP)
	else:
		blooper.body.global_position = Vector2(162, 111) + Blooper.BODY_OFFSET
		blooper._speed = 1
		var shot := SHOT.instantiate() as Fireball
		blooper._level.world_objects.add_child(shot)
		shot.set_physics_process(false)
		shot._area = blooper._level.active_area
		shot._shooter = player
		shot._spawn_registry = blooper._level.spawn_registry
		shot.global_position = blooper.projectile_target_bounds().get_center()
		shot._hit_enemies(Rect2(0, 0, 256, 240))
		assert(shot.burst_tick == 0)
	assert(blooper.is_defeated())
	assert(blooper.sprite.flip_v != star)
	for row: PackedStringArray in rows:
		assert(
			blooper.body.global_position == Vector2(int(row[2]), int(row[3])) + Blooper.BODY_OFFSET,
			"%s defeat tick %s" % [label, row[1]],
		)
		assert(GameHandler.player_status.score == original_score + int(row[4]))
		if int(row[1]) > 0:
			assert(blooper.sprite.flip_v)
		await get_tree().physics_frame
		await get_tree().process_frame
		blooper._physics_process(STEP)
	await _retire(blooper)


func _check_player_contact(
	enemy_nes_position: Vector2, player_nes_position: Vector2, vertical_speed: float, small := false
) -> void:
	var blooper := _spawn_blooper(false, null if small else SUPER)
	var player := blooper._level.player as Mario
	blooper.body.global_position = enemy_nes_position + Blooper.BODY_OFFSET
	player.body.global_position = player_nes_position + PLAYER_OFFSET
	player.body.velocity.y = vertical_speed
	var lives := GameHandler.player_status.lives
	while Engine.get_physics_frames() % 2 != 0:
		await get_tree().physics_frame
	blooper._physics_process(STEP)
	if small:
		assert(player.is_dead and GameHandler.player_status.lives == lives - 1)
		GameHandler.set_lives(lives)
	else:
		assert(player.form_presentation.active and player.damage.is_protected())
	assert(not blooper.is_defeated() and player.body.velocity.y != BaseEnemy.STOMP_REBOUND)
	await _retire(blooper)


func _retire(blooper: Blooper) -> void:
	blooper._level.queue_free()
	await get_tree().process_frame
