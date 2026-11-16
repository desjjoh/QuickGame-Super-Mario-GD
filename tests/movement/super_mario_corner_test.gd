extends Node
signal stepped
var pending: Callable
var p: Mario


func _physics_process(_d: float) -> void:
	if pending.is_valid():
		var c := pending
		pending = Callable()
		c.call()
		stepped.emit()


func step(c: Callable) -> void:
	pending = c
	await stepped


func _ready() -> void:
	process_physics_priority = 200
	ControllerHandler.set_physics_process(false)
	var level := load("res://tests/fixtures/sandbox_level.tscn").instantiate() as BaseLevel
	level.player_start_configuration = load("res://assets/player/forms/super.tres")
	level.entity_layout.clear()
	level.get_node("Areas/MainArea/Layouts/EnemyLayout").clear()
	var floor := level.get_node("Areas/MainArea/Layouts/GroundLayout") as TileMapLayer
	floor.clear()
	for x in range(24):
		floor.set_cell(Vector2i(x, 13), 0, Vector2i.ZERO)
	add_child(level)
	level.set_physics_process(false)
	level.active_area.set_physics_process(false)
	p = level.player as Mario
	p.set_physics_process(false)
	var question_scene := (
		load("res://scenes/entities/blocks/question/question_block.tscn") as PackedScene
	)
	var block := question_scene.instantiate() as BaseBlock
	block.position = Vector2(128, 128)
	level.world_objects.add_child(block)
	block.state_machine.change_state(block.get_node("StateMachine/Inactive"))
	await get_tree().physics_frame
	await get_tree().process_frame
	for direction in [-1.0, 1.0]:
		for mode in ["corner", "last_upward_tick"]:
			for phase in range(24):
				var y: float = (
					(172.0 + phase * 0.125) if mode == "corner" else (187.8 + phase * 0.0625)
				)
				await step(
					func():
						p.bonk_action.reset_reaction_gate()
						p.vertical_movement.reset_fraction()
						p.state_machine.stop(false)
						p.body.global_position = Vector2(
							(122.0 if direction > 0 else 150.0) if mode == "corner" else 136.0, y
						)
						p.body.velocity = Vector2.ZERO
						p.body.move_and_slide()
						p.jump_action.active = true
						p.jump_action.falling_gravity = 2025
						p.jump_action.set("_released", mode == "last_upward_tick")
						p.jump_action.set("_rise", 450.0)
						p.state_machine.change_state(p.get_node("StateMachine/Jump"))
						p.body.velocity = Vector2(
							150 * direction if mode == "corner" else 0,
							-30 if mode == "corner" else -240
						)
						ControllerHandler.input_right = (
							1 if direction > 0 and mode == "corner" else 0
						)
						ControllerHandler.input_left = (
							1 if direction < 0 and mode == "corner" else 0
						)
						ControllerHandler.input_primary = mode == "corner"
						ControllerHandler.input_primary_just_pressed = false
				)
				for i in range(14):
					await step(func(): p._physics_process(1.0 / 60.0))
					var head := p.get_head_position()
					var inside := (
						head.y < 143.999 and head.y > 128 and head.x > 128 and head.x < 144
					)
					assert(
						(
							mode == "corner"
							or not inside
							or p.body.velocity.y >= 0
							or posmod(int(floorf(p.body.global_position.y)), 16) < 4
						),
						(
							"Overlapping head must reverse: %s direction=%s height=%s tick=%s"
							% [mode, direction, y, i]
						)
					)
				assert(
					(
						p.get_head_position().y >= 144
						or p.get_head_position().x < 128
						or p.get_head_position().x >= 144
					),
					"Head must clear naturally"
				)
	# Side entry remains non-offensive on either side of the head phase threshold.
	block.free()
	for direction in [-1.0, 1.0]:
		for feet_y in [163.0, 164.0]:
			var question := question_scene.instantiate() as QuestionBlock
			question.position = Vector2(128, 128)
			level.world_objects.add_child(question)
			await get_tree().physics_frame
			var coins := GameHandler.player_status.coins as int
			var x := 129.0 if direction > 0 else 143.0
			await step(
				func():
					p.bonk_action.reset_reaction_gate()
					p.state_machine.change_state(p.get_node("StateMachine/Jump"))
					p.body.global_position = Vector2(x, feet_y)
					p.body.velocity = Vector2(150 * direction, -60)
					p.terrain.resolve(p, Vector2(x - 2 * direction, feet_y + 1), true, false)
			)
			assert(p.body.velocity.x == 0, "Upper side contact must stop sideways momentum")
			assert(
				is_equal_approx(p.body.global_position.x, x - direction),
				"Side contact nudges one pixel"
			)
			assert(p.body.global_position.y == feet_y, "Head response must not snap")
			assert(p.body.velocity.y == -60 and not question._bounce_reward_claimed)
			assert(GameHandler.player_status.coins == coins)
			await step(
				func():
					assert(p.terrain.filter_air_direction(direction) == 0.0)
					assert(p.terrain.filter_air_direction(0.0) == 0.0)
					assert(p.terrain.filter_air_direction(-direction) == -direction)
			)
			await step(func(): assert(p.terrain.filter_air_direction(direction) == direction))
			question.free()
	# A thin upper obstruction is above the short support body. Both diagonal
	# entry directions must still resolve, even with next-tick downward velocity.
	var thin := StaticBody2D.new()
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(16, 2)
	collision.shape = rectangle
	collision.position = Vector2(8, 1)
	thin.add_child(collision)
	thin.position = Vector2(128, 128)
	level.world_objects.add_child(thin)
	await get_tree().physics_frame
	for direction in [-1.0, 1.0]:
		await step(
			func():
				p.bonk_action.reset_reaction_gate()
				p.body.global_position = Vector2(136, 157)
				p.body.velocity = Vector2(150 * direction, 3.75)
				p.terrain.resolve(p, Vector2(136 - 2 * direction, 158.5), true, false)
		)
		assert(is_equal_approx(p.get_head_position().y, 129), "Bonk must not snap position")
		assert(p.body.velocity.y == 63.75, "Thin upper-body ceiling must reverse velocity")
	thin.free()
	ControllerHandler.input_left = 0
	ControllerHandler.input_right = 0
	ControllerHandler.input_primary = false
	level.free()
	await check_painted_question_corner()
	if not (await check_crouched_question_corners() and await check_jump_after_uncrouching()):
		get_tree().quit(1)
		return
	ControllerHandler.set_physics_process(true)
	print("super_mario_corner_test: PASS")
	await preload("res://tests/fixtures/finish_test.gd").finish(get_tree())


func check_painted_question_corner() -> void:
	var level := preload("res://scenes/levels/worlds/world 1/1-2.tscn").instantiate() as BaseLevel
	level.opening_presentation = null
	level.player_start_configuration = preload("res://assets/player/forms/super.tres")
	var area := level.get_node("Areas/MainArea") as BaseLevelArea
	area.get_node("Layouts/EnemyLayout").clear()
	add_child(level)
	level.set_physics_process(false)
	area.set_physics_process(false)
	p = level.player as Mario
	p.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await step(
		func():
			p.body.global_position = area.to_global(Vector2(18, 208))
			p.body.velocity = Vector2.ZERO
			ControllerHandler.input_secondary = true
			ControllerHandler.input_right = 1.0
	)
	for tick in range(73):
		await step(func(): p._physics_process(1.0 / 60.0))
	var first_block := level.area_content.find_layout_entity(area, &"question_block", Vector2i(10, 9))
	assert(is_equal_approx(p.body.velocity.x, 150.0))
	ControllerHandler.input_primary = true
	ControllerHandler.input_primary_just_pressed = true
	for tick in range(5):
		await step(func(): p._physics_process(1.0 / 60.0))
		ControllerHandler.input_primary_just_pressed = false
		assert((p.bonk_action.reaction_ticks_remaining > 0) == (tick == 4))
	# On the Mesen contact frame the head crosses the bottom edge into the first tile.
	assert(p.body.velocity.y >= 0.0)
	assert(is_equal_approx(area.to_local(p.body.global_position).y, 184.0))
	assert(is_equal_approx(p.body.velocity.x, 150.0))
	assert(first_block != null and (first_block as QuestionBlock)._bounce_reward_claimed)
	ControllerHandler.input_primary = false
	ControllerHandler.input_secondary = false
	ControllerHandler.input_right = 0
	level.shutdown()
	level.queue_free()
	await get_tree().process_frame

func check_crouched_question_corners() -> bool:
	var mismatches: Array[String] = []
	for direction in [1.0, -1.0]:
		var level := preload("res://scenes/levels/worlds/world 1/1-2.tscn").instantiate() as BaseLevel
		level.opening_presentation = null
		level.player_start_configuration = preload("res://assets/player/forms/super.tres")
		var area := level.get_node("Areas/MainArea") as BaseLevelArea
		area.get_node("Layouts/EnemyLayout").clear()
		add_child(level)
		level.set_physics_process(false)
		area.set_physics_process(false)
		p = level.player as Mario
		p.set_physics_process(false)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var column := 10 if direction > 0.0 else 14
		var block := level.area_content.find_layout_entity(
			area, &"question_block", Vector2i(column, 9)
		) as QuestionBlock
		assert(block != null and not block._bounce_reward_claimed)
		await step(
			func():
				p.body.global_position = area.to_global(
					Vector2(158.75 if direction > 0.0 else 241.25, 176)
				)
				p.body.velocity = Vector2.ZERO
				p.body.move_and_slide()
				p.form_controller.set_crouched(true)
				p.state_machine.change_state(p.get_node("StateMachine/Jump"))
				p.jump_action.active = true
				p.jump_action.falling_gravity = 2025
				p.jump_action.set("_released", false)
				p.jump_action.set("_rise", 562.5)
				p.body.velocity = Vector2(direction * 150.0, -240.0)
				ControllerHandler.input_secondary = true
				ControllerHandler.input_primary = true
				ControllerHandler.input_down = 1.0
				ControllerHandler.input_right = float(direction > 0.0)
				ControllerHandler.input_left = float(direction < 0.0)
				p._physics_process(1.0 / 60.0)
		)
		var feet_y := area.to_local(p.body.global_position).y
		# Mesen reacts on the first step at Y172 from either end of the row.
		if not block._bounce_reward_claimed or not is_equal_approx(feet_y, 172.0):
			mismatches.append(
				"direction %s: tick-0 bonk=%s, feet Y=%s" %
				[direction, block._bounce_reward_claimed, feet_y]
			)
		for tick in range(5):
			if not is_equal_approx(p.body.velocity.x, direction * 150.0):
				mismatches.append("direction %s: lost running speed on tick %s" % [direction, tick])
			if tick < 3 and not is_equal_approx(area.to_local(p.body.global_position).y, 172.0):
				mismatches.append("direction %s: snapped away from the block on tick %s" % [direction, tick])
			await step(func(): p._physics_process(1.0 / 60.0))
		level.shutdown()
		level.queue_free()
		await get_tree().process_frame
	ControllerHandler.input_primary = false
	ControllerHandler.input_secondary = false
	ControllerHandler.input_down = 0.0
	ControllerHandler.input_right = 0.0
	ControllerHandler.input_left = 0.0
	if not mismatches.is_empty():
		push_error("\n".join(mismatches))
	return mismatches.is_empty()

func check_jump_after_uncrouching() -> bool:
	var mismatches: Array[String] = []
	for scene: PackedScene in [
		preload("res://scenes/entities/blocks/brick/brick_block.tscn"),
		preload("res://scenes/entities/blocks/question/question_block.tscn"),
	]:
		for delay in [0, 3]:
			var level := preload("res://tests/fixtures/sandbox_level.tscn").instantiate() as BaseLevel
			level.entity_layout.clear()
			level.get_node("Areas/MainArea/Layouts/EnemyLayout").clear()
			level.player_start_configuration = MarioFormPresentation.SUPER
			add_child(level)
			level.set_physics_process(false)
			var block := scene.instantiate() as BaseBlock
			block.position = Vector2(64, 176)
			level.world_objects.add_child(block)
			p = level.player as Mario
			p.set_physics_process(false)
			await get_tree().physics_frame
			await step(func(): p.body.global_position = Vector2(48, 208))
			ControllerHandler.input_down = 1.0
			for tick in range(4):
				await step(func(): p._physics_process(1.0 / 60.0))
			assert(p.form_controller.is_crouched and p.has_floor_support())
			await step(func(): p.body.global_position.x = 72.0)
			ControllerHandler.input_down = 0.0
			for tick in range(delay):
				await step(func(): p._physics_process(1.0 / 60.0))
			assert(p.body.global_position.round() == Vector2(72.0 + delay, 208.0), str(p.body.global_position))
			ControllerHandler.input_primary = true
			ControllerHandler.input_primary_just_pressed = true
			await step(func(): p._physics_process(1.0 / 60.0))
			ControllerHandler.input_primary = false
			ControllerHandler.input_primary_just_pressed = false
			var question := block as QuestionBlock
			var reacted := (
				question._bounce_reward_claimed if question != null
				else block.state_machine.current_state.name == &"Broken"
			)
			if not reacted or not is_equal_approx(p.body.global_position.y, 204.0):
				mismatches.append(
					"%s, %s push-out ticks: reacted=%s, feet Y=%s"
					% [block.name, delay, reacted, p.body.global_position.y]
				)
			if reacted and ((p.body.velocity.y < 0.0) != (question == null)):
				mismatches.append("%s: unexpected vertical response" % block.name)
			if reacted and question == null:
				ControllerHandler.input_primary = true
				for expected_y in [202.0, 200.0, 198.0]:
					await step(func(): p._physics_process(1.0 / 60.0))
					if not is_equal_approx(p.body.global_position.y, expected_y):
						mismatches.append(
							"Brick, %s push-out ticks: feet Y=%s, Mesen Y=%s"
							% [delay, p.body.global_position.y, expected_y]
						)
				ControllerHandler.input_primary = false
			level.shutdown()
			level.queue_free()
			await get_tree().process_frame
	if not mismatches.is_empty():
		push_error("\n".join(mismatches))
	return mismatches.is_empty()
