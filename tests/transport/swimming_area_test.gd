extends Node

const GAME := preload("res://scenes/main/game.tscn")
const STAGE := preload("res://scenes/levels/worlds/world 2/2-2.tscn")
const ENTRY_TRACE := "res://tests/fixtures/swimming_reference/swim_entry_drop_mesen.csv"
const HANDOFF_TICK := 34
const MARIO := "res://scenes/player/mario/mario.tscn"
const LUIGI := "res://scenes/player/luigi/luigi.tscn"

signal tick_finished


func _physics_process(_delta: float) -> void:
	tick_finished.emit()


func _ready() -> void:
	process_physics_priority = 200
	await _check_route(GameHandler.PlayerCharacter.MARIO, MARIO, true)
	await _check_route(GameHandler.PlayerCharacter.LUIGI, LUIGI, false)
	print("PASS: 2-2 entry drop, held controls, surface exit bubbles, and Cheep Cheep stream.")
	await preload("res://tests/fixtures/finish_test.gd").finish(get_tree())


func _check_route(
	character: GameHandler.PlayerCharacter, player_path: String, hold_through_handoff: bool
) -> void:
	var game := GAME.instantiate()
	game.start_stage_override = null
	game.start_with_title = true
	add_child(game)
	for frame in range(240):
		if GameHandler.flow == GameHandler.GameFlow.TITLE and not GameHandler.transitions.busy:
			break
		await tick_finished
	assert(GameHandler.title_flow.start_new_game(STAGE, character))
	for frame in range(240):
		if is_instance_valid(GameHandler.current_level) and GameHandler.current_level.stage_label == "2-2":
			break
		await tick_finished
	var level := GameHandler.current_level as BaseLevel
	assert(level.stage_label == "2-2" and level.active_area.area_id == &"intro")
	var player := level.player as Mario
	assert(player.scene_file_path == player_path)
	assert(player.form_controller.current_form == player.small_form)
	assert(not level.active_area.swimming_enabled)
	assert(not player.state_machine.current_state is MarioSwimState)
	for frame in range(600):
		if level.active_area.area_id == &"main":
			break
		await tick_finished
	var water := level.active_area
	assert(water.area_id == &"main" and water.swimming_enabled)
	var arrival := water.get_node("Arrival") as AreaEndpoint
	var bubbles := water.get_node("WorldObjects/SwimBubbles") as SwimBubbleEmitter
	assert(player.arrival_control_ticks_remaining == HANDOFF_TICK)
	await _check_entry_drop(player, arrival, bubbles, hold_through_handoff)

	var bubble_seen := false
	for frame in range(150):
		bubble_seen = bubbles._slots.any(func(slot: Sprite2D) -> bool: return slot.visible)
		if bubble_seen and player.body.global_position.y > arrival.global_position.y + 40.0:
			break
		await tick_finished
	assert(bubble_seen)
	var swim := player.state_machine.current_state as MarioSwimState
	Input.action_press(ControllerHandler.primary_action)
	await tick_finished
	Input.action_release(ControllerHandler.primary_action)
	assert(swim._stroke_ticks == 32 and player.body.velocity.y < 0.0)
	await tick_finished

	var stream := water.get_node("WorldObjects/SwimmingCheepCheepSpawner") as SwimmingCheepCheepSpawner
	assert(stream.get_child_count() == 0)
	if character == GameHandler.PlayerCharacter.MARIO:
		await _check_cheep_cheep_stream(water, player, stream)

	# Settle on the exit shelf before pressing Right into the pipe.
	var pipe := water.find_transport_entity(&"surface_entrance") as PipeEntrance
	var shape := pipe.get_node("Body/CollisionShape2D") as CollisionShape2D
	assert((shape.shape as RectangleShape2D).size == Vector2(16, 32))
	assert(water.to_local(pipe.entry_position()) == Vector2(3018, 144))
	assert((pipe.sprite.texture as AtlasTexture).region == Rect2(96, 32, 16, 32))
	player.body.global_position = pipe.entry_position() - Vector2(6, 2)
	player.body.velocity = Vector2.ZERO
	player.horizontal_movement.reset_fractional_step()
	player.vertical_movement.reset_fraction(player.body)
	(water.get_node("Camera2D") as LevelCamera).snap_to_arrival(player.body)
	for frame in range(24):
		await tick_finished
		if player.has_floor_support():
			break
	assert(player.has_floor_support(), "Expected to settle on the surface pipe shelf.")
	Input.action_press(ControllerHandler.right_action)
	for frame in range(80):
		if player.state_machine.current_state == player.pipe_enter_state:
			break
		await tick_finished
	Input.action_release(ControllerHandler.right_action)
	assert(
		player.state_machine.current_state == player.pipe_enter_state,
		"%s missed the surface pipe at offset %s" % [
			player.name, player.body.global_position - pipe.entry_position(),
		]
	)
	await _check_exit_bubbles(player, bubbles, pipe)
	for frame in range(360):
		if (
			level.active_area.area_id == &"surface"
			and level.can_transport()
			and player.can_read_controller_input()
			and not GameHandler.transitions.busy
		):
			break
		await tick_finished
	assert(level.active_area.area_id == &"surface" and not level.active_area.swimming_enabled)
	assert(level.active_target_id == &"surface_exit")
	assert(not is_instance_valid(bubbles))
	assert(not is_instance_valid(stream))
	assert(not level.active_area.has_node("WorldObjects/SwimBubbles"))
	assert(level.player == player and not player.state_machine.current_state is MarioSwimState)
	assert(player.can_read_controller_input())
	var exit := level.active_area.find_transport_entity(&"surface_exit") as PipeEntrance
	assert(player.body.global_position.distance_to(exit.exit_position()) < 1.0)

	Input.action_press(ControllerHandler.primary_action)
	await tick_finished
	Input.action_release(ControllerHandler.primary_action)
	assert(player.state_machine.current_state is MarioJumpState and player.body.velocity.y < 0.0)
	game.free()
	await get_tree().process_frame


func _check_exit_bubbles(player: Mario, bubbles: SwimBubbleEmitter, pipe: PipeEntrance) -> void:
	# Place an existing bubble close enough to reach the HUD during the pipe animation.
	for slot in bubbles._slots:
		slot.hide()
	var bubble := bubbles._slots[2]
	bubble.global_position = Vector2(
		pipe.global_position.x - 24.0,
		bubbles.area.global_position.y + SwimBubbleEmitter.HUD_CUTOFF + 2.0
	)
	bubble.show()
	bubbles._spawn_ticks = 0
	var start_y := bubble.global_position.y
	for _tick in range(12):
		await tick_finished
		assert(player.state_machine.current_state == player.pipe_enter_state)
		assert(
			not bubbles._slots[0].visible and not bubbles._slots[1].visible,
			"A new bubble appeared during pipe entry."
		)
	assert(bubble.global_position.y < start_y, "An existing bubble froze during pipe entry.")
	assert(not bubble.visible, "An existing bubble did not release at the HUD cutoff.")


func _check_entry_drop(
	player: Mario, arrival: AreaEndpoint, bubbles: SwimBubbleEmitter, hold_through_handoff: bool
) -> void:
	Input.action_press(ControllerHandler.right_action)
	Input.action_press(ControllerHandler.primary_action)
	for frame in range(120):
		if player.state_machine.current_state is MarioSwimState:
			break
		await tick_finished
	var swim := player.state_machine.current_state as MarioSwimState
	assert(swim != null)
	var trace := FileAccess.open(ENTRY_TRACE, FileAccess.READ)
	assert(trace != null)
	trace.get_csv_line()
	for frame in range(1, 66):
		var row := trace.get_csv_line()
		assert(row.size() == 3 and int(row[0]) == frame)
		assert(player.arrival_control_ticks_remaining == maxi(0, HANDOFF_TICK - frame))
		if frame < HANDOFF_TICK:
			assert(not player.can_read_controller_input() and bubbles._spawn_ticks == 0)
		else:
			assert(player.can_read_controller_input())
		var offset := player.body.global_position - arrival.global_position
		var speed_units := roundi(player.body.velocity.y * 256.0 / 60.0)
		assert(
			absf(offset.x) < 0.1 and absf(offset.y - float(row[1])) < 0.1,
			"2-2 drop tick %d at %s, expected Y%s" % [frame, offset, row[1]]
		)
		assert(speed_units == int(row[2]), "2-2 drop speed at tick %d" % frame)
		assert(swim._stroke_ticks == 0)
		if frame == HANDOFF_TICK:
			if hold_through_handoff:
				await _check_held_handoff(player, swim, arrival)
				return
			Input.action_release(ControllerHandler.right_action)
			Input.action_release(ControllerHandler.primary_action)
		if frame != 65:
			await tick_finished
	assert(player.has_floor_support() and swim._sink_force == MarioSwimState.SINK_FORCE)


func _check_held_handoff(player: Mario, swim: MarioSwimState, arrival: AreaEndpoint) -> void:
	await tick_finished
	assert(not ControllerHandler.input_primary_just_pressed)
	assert(swim._stroke_ticks == MarioSwimState.STROKE_TICKS)
	assert(player.body.global_position.y - arrival.global_position.y == 47.0)
	assert(roundi(player.body.velocity.y * 256.0 / 60.0) == -371)
	assert(player.body.velocity.x == 60.0 / 16.0)
	assert(player.horizontal_movement._speed_fraction == 48)
	assert(player.horizontal_movement._position_fraction == 16)
	assert(player.body.global_position.x == arrival.global_position.x)
	await tick_finished
	assert(swim._stroke_ticks == MarioSwimState.STROKE_TICKS - 1)
	assert(player.body.velocity.x > 0.0)
	Input.action_release(ControllerHandler.right_action)
	Input.action_release(ControllerHandler.primary_action)


func _check_cheep_cheep_stream(
	water: BaseLevelArea, player: Mario, stream: SwimmingCheepCheepSpawner
) -> void:
	const START_X := 931.0
	const STOP_X := 2723.0
	var camera := water.get_node("Camera2D") as LevelCamera
	camera.follow_enabled = false
	player.set_physics_process(false)

	_set_camera_left(camera, water, START_X - 1.0)
	await tick_finished
	assert(stream.get_child_count() == 0)
	_set_camera_left(camera, water, START_X)
	await tick_finished
	assert(stream.get_child_count() == 1)
	var first := stream.get_child(0) as SwimmingCheepCheep
	assert(first.global_position.x - water.global_position.x == 1218.0)
	var spawn_y := roundi(water.to_local(first.global_position).y)
	assert(spawn_y in SwimmingCheepCheepSpawner.HEIGHTS, "Unexpected spawn height %s" % spawn_y)

	# A new fish can still spawn one pixel before the stop marker.
	_set_camera_left(camera, water, STOP_X - 1.0)
	for _tick in range(SwimmingCheepCheepSpawner.COOLDOWN):
		await tick_finished
	assert(not is_instance_valid(first))
	assert(stream.get_child_count() == 1)
	var last := stream.get_child(0) as SwimmingCheepCheep
	var start_x := last.body.global_position.x
	_set_camera_left(camera, water, STOP_X)
	for _tick in range(SwimmingCheepCheepSpawner.COOLDOWN + 1):
		await tick_finished
	assert(stream.get_child_count() == 1 and stream.get_child(0) == last)
	assert(last.body.global_position.x < start_x)

	# The exit check repositions Mario into the stream's last fish lanes.
	last.queue_free()
	await get_tree().process_frame
	camera.follow_enabled = true
	player.set_physics_process(true)


func _set_camera_left(camera: LevelCamera, water: BaseLevelArea, local_x: float) -> void:
	var half_width := camera.get_viewport_rect().size.x / camera.zoom.x / 2.0
	camera.global_position.x = water.global_position.x + local_x + half_width
	camera.force_update_scroll()
