extends Node

const LEVEL := preload("res://tests/fixtures/sandbox_level.tscn")
const HOPPER := preload("res://scenes/entities/enemies/koopa/green_parakoopa.tscn")
const WORLD_TWO_ONE := preload("res://scenes/levels/worlds/world 2/2-1.tscn")
const STEP := 1.0 / 60.0

signal physics_finished


func _physics_process(_delta: float) -> void:
	physics_finished.emit()


func _ready() -> void:
	process_physics_priority = 2000
	await check_hopping(false)
	await check_hopping(true)
	await check_first_stomp()
	await check_painted_spawns()
	print("PASS: Green Parakoopa Mesen landing, bounce apex, wall reversal, first stomp, and 2-1 single spawns.")
	await preload("res://tests/fixtures/finish_test.gd").finish(get_tree())


func check_hopping(wall: bool) -> void:
	var enemy := await spawn_hopper(Vector2(144, 192) if wall else Vector2(140, 128), wall)
	# Mesen samples after movement, using the sprite anchor and integer speed registers.
	var expected := (
		{64: Vector4i(111, 182, -8, 3), 65: Vector4i(112, 185, 8, 3),
		66: Vector4i(112, 181, 8, -3)}
		if wall else
		{0: Vector4i(139, 120, -8, 0), 35: Vector4i(122, 186, -8, 3),
		36: Vector4i(121, 181, -8, -3), 60: Vector4i(109, 142, -8, -1),
		63: Vector4i(108, 142, -8, 0), 92: Vector4i(93, 181, -8, -3)}
	)
	for tick in range(67 if wall else 93):
		enemy._physics_process(STEP)
		var body := enemy.body
		if expected.has(tick):
			var sample := Vector4i(
				floori(body.global_position.x - 8.0),
				roundi(body.global_position.y - 16.0),
				roundi(body.velocity.x / 60.0 * 16.0),
				floori(body.velocity.y / 60.0)
			)
			assert(sample == expected[tick], "Tick %s: %s" % [tick, sample])
		assert(enemy.sprite.frame in [2, 3])
		assert(enemy.sprite.flip_h == (body.velocity.x > 0))
	await finish_case(enemy._level)


func check_first_stomp() -> void:
	var enemy := await spawn_hopper(Vector2(136, 192), false)
	if Engine.get_physics_frames() % 2 != 0:
		await get_tree().physics_frame
	var player := enemy._level.player
	player.body.global_position = Vector2(143, 196)
	player.body.velocity.y = 180.0
	var score := GameHandler.player_status.score
	enemy._physics_process(STEP)
	assert(enemy.state_machine.current_state == enemy.get_node("StateMachine/Walking"))
	assert(enemy.body.global_position == Vector2(144.5, 200.0))
	assert(enemy.body.velocity == Vector2(30, 0) and player.body.velocity.y == -240.0)
	assert(enemy.sprite.frame in [0, 1])
	player.body.global_position = Vector2(40, 208)
	for tick in range(1, 6):
		await get_tree().physics_frame
		await physics_finished
		assert(GameHandler.player_status.score == score + (400 if tick == 5 else 0))
	await finish_case(enemy._level)


func check_painted_spawns() -> void:
	var level := WORLD_TWO_ONE.instantiate() as BaseLevel
	add_child(level)
	level.set_physics_process(false)
	level.player.set_physics_process(false)
	var area := level.active_area
	area.set_physics_process(false)
	var camera := area.get_node("Camera2D") as LevelCamera
	camera.follow_enabled = false
	await get_tree().physics_frame
	await get_tree().physics_frame
	for column: int in [151, 169, 171]:
		var spawner := (
			level.world_objects.get_node("green_parakoopa_spawner_%d_12" % column)
			as EntitySpawner
		)
		assert(spawner.actor_offsets == [Vector2.ZERO])
		var trigger_right := area.to_global(Vector2(column * 16 - 48, 0)).x
		camera.global_position.x += trigger_right - 1.0 - area.get_enemy_group_origin_x()
		spawner.update_activity(
			area.get_enemy_spawn_region(), area.get_activity_region(true), area.theme
		)
		assert(spawner.get_node_or_null("GreenParakoopa") == null)
		camera.global_position.x += 1.0
		spawner.update_activity(
			area.get_enemy_spawn_region(), area.get_activity_region(true), area.theme
		)
		var enemy := spawner.get_node("GreenParakoopa") as BaseEnemy
		var start := Vector2(column * 16 + 8, 200)
		assert(area.to_local(enemy.body.global_position) == start)
		assert(level.spawn_registry.get_slot(&"enemy", enemy) >= 0)
		# Mesen stage layout, with speed and fractions initialized at slot allocation.
		for tick in range(1, 19):
			enemy._physics_process(STEP)
			if tick == 11:
				assert(enemy.body.velocity.y < -170.0)
		assert(area.to_local(enemy.body.global_position) == start + Vector2(-9, -21))
	await finish_case(level)


func spawn_hopper(position: Vector2, wall: bool) -> BaseEnemy:
	var level := LEVEL.instantiate() as BaseLevel
	level.entity_layout.clear()
	level.get_node("Areas/MainArea/Layouts/EnemyLayout").clear()
	var terrain := level.get_node("Areas/MainArea/Layouts/GroundLayout") as TileMapLayer
	terrain.clear()
	for x in range(16):
		for row in [13, 14]:
			terrain.set_cell(Vector2i(x, row), 0, Vector2i.ZERO)
	if wall:
		for row in range(5, 13):
			terrain.set_cell(Vector2i(6, row), 0, Vector2i.ZERO)
	add_child(level)
	level.set_physics_process(false)
	level.active_area.set_physics_process(false)
	level.player.set_physics_process(false)
	level.player.body.global_position = Vector2(40, 208)
	var enemy := HOPPER.instantiate() as BaseEnemy
	enemy.position = position
	level.world_objects.add_child(enemy)
	enemy.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return enemy


func finish_case(level: BaseLevel) -> void:
	level.shutdown()
	level.queue_free()
	await get_tree().process_frame
