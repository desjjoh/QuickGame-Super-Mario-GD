extends Node

const STAGE := preload("res://scenes/levels/worlds/world 2/2-1.tscn")
const FINISH := preload("res://tests/fixtures/finish_test.gd")
const SPRING := preload("res://scenes/entities/platforms/springboard.gd")
const CELL := Vector2i(188, 11)
const MESEN_SPRING_FRAMES := [1, 2, 1, 0]

signal stepped


func _physics_process(_delta: float) -> void:
	stepped.emit()


func _ready() -> void:
	process_physics_priority = 200
	ControllerHandler.set_physics_process(false)
	for press_tick in [-2, -1, 1, 4, 8, 12]:
		await _check_bounce(press_tick, false)
	await _check_bounce(4, true)
	ControllerHandler.set_physics_process(true)
	print("PASS: 2-1 painted spring, Mesen compression and launch, solid brick base, and boosted wall crossing.")
	await FINISH.finish(get_tree())


func _check_bounce(press_tick: int, clear_wall: bool) -> void:
	var level := STAGE.instantiate() as BaseLevel
	level.timer_enabled = false
	add_child(level)
	level.spawn_registry.enemy_limit = 0
	var area := level.active_area
	var spring := level.area_content.find_layout_entity(area, &"springboard", CELL) as SPRING
	assert(spring != null and area.to_local(spring.global_position) == Vector2(3008, 176))
	var base := spring.get_node("BrickBase") as StaticBody2D
	var base_shape := base.get_node("CollisionShape2D") as CollisionShape2D
	var base_sprite := base.get_node("Sprite") as Sprite2D
	assert(area.to_local(base.global_position) == Vector2(3008, 200))
	assert(base.collision_layer == 1 and base_shape.shape.get_rect().size == Vector2(16, 8))
	var ground := area.get_node("Layouts/GroundLayout") as TileMapLayer
	var floor_cell := Vector2i(188, 13)
	assert(ground.get_cell_source_id(floor_cell) >= 0)
	var floor_top := ground.to_global(ground.map_to_local(floor_cell) - Vector2(8, 8))
	assert(base_sprite.global_position + base_sprite.get_rect().end.y * Vector2.DOWN == floor_top)
	assert(ground.get_cell_source_id(Vector2i(190, 3)) >= 0)
	assert(ground.get_cell_source_id(Vector2i(191, 3)) >= 0)
	var camera := area.get_node("Camera2D") as LevelCamera
	camera.follow_enabled = false
	camera.global_position.x = spring.global_position.x + 64.0
	area.update_camera_activity()
	var player := level.player as Mario
	player.body.global_position = spring.global_position + Vector2(8, -16)
	player.state_machine.change_state(player.get_node("StateMachine/Jump"))
	player.jump_action.falling_gravity = 1575.0
	player.jump_action.launch_with_falling_gravity(player.motion_values, 120.0)
	player.vertical_movement.reset_fraction(player.body)

	assert(spring.sprite.frame == 0)
	var landing := -1
	var launch := -1
	var apex := INF
	var crossed := false
	var crossed_wall_face := false
	for tick in range(105):
		var elapsed := tick - landing
		var fresh_press := landing >= 0 and press_tick >= 0 and elapsed == press_tick
		ControllerHandler.input_primary_just_pressed = fresh_press
		ControllerHandler.input_primary = press_tick == -2 or fresh_press
		ControllerHandler.input_right = 1.0 if clear_wall and launch >= 0 else 0.0
		ControllerHandler.input_secondary = clear_wall and launch >= 0
		await stepped
		assert(base_sprite.is_visible_in_tree() and base_sprite.global_position.y + 8 == floor_top.y)
		assert(base.collision_layer == 1 and not base_shape.disabled)
		var feet := area.to_local(player.body.global_position)
		if landing < 0 and spring._spring_tick > 0:
			landing = tick
		if landing >= 0:
			var bounce_tick := tick - landing
			if bounce_tick <= 12:
				assert(spring.sprite.frame == MESEN_SPRING_FRAMES[bounce_tick >> 2])
				if bounce_tick == 7:
					assert(feet.y == 192.0)
		if landing >= 0 and launch < 0 and player.body.velocity.y < 0.0:
			launch = tick
			assert(launch - landing == 12 and feet.y == 182.0)
			assert(player.body.velocity.y == (-720.0 if press_tick >= 4 else -420.0))
		if launch >= 0:
			apex = minf(apex, feet.y)
			if clear_wall:
				if feet.x >= 3040.0 and not crossed_wall_face:
					assert(feet.y <= 48.0)
					crossed_wall_face = true
				if feet.x > 3078.0:
					crossed = true
					break
			elif player.body.velocity.y >= 0.0:
				break
	assert(launch >= 0)
	if clear_wall:
		assert(crossed, "Mario must cross the far side of the wall during the boosted jump.")
	else:
		assert(apex == (11.0 if press_tick >= 4 else 123.0), "Mesen apex, press %s: %s" % [press_tick, apex])

	ControllerHandler.input_primary = false
	ControllerHandler.input_primary_just_pressed = false
	ControllerHandler.input_right = 0.0
	ControllerHandler.input_secondary = false
	level.shutdown()
	level.queue_free()
	await get_tree().process_frame
