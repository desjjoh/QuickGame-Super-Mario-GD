extends Node

const GAME := preload("res://scenes/main/game.tscn")
const STAGE := preload("res://scenes/levels/worlds/world 2/2-2.tscn")
const MARIO := "res://scenes/player/mario/mario.tscn"
const LUIGI := "res://scenes/player/luigi/luigi.tscn"

signal tick_finished


func _physics_process(_delta: float) -> void:
	tick_finished.emit()


func _ready() -> void:
	process_physics_priority = 200
	await _check_route(GameHandler.PlayerCharacter.MARIO, MARIO)
	await _check_route(GameHandler.PlayerCharacter.LUIGI, LUIGI)
	print("PASS: Mario and Luigi sink during the 2-2 arrival lock, then swim, emerge, and jump on land.")
	await preload("res://tests/fixtures/finish_test.gd").finish(get_tree())


func _check_route(character: GameHandler.PlayerCharacter, player_path: String) -> void:
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
	assert(player.arrival_control_ticks_remaining == BasePlayer.ARRIVAL_CONTROL_TICKS)
	Input.action_press(ControllerHandler.right_action)
	Input.action_press(ControllerHandler.primary_action)
	var previous_y := arrival.global_position.y
	var sank_during_lock := false
	for frame in range(180):
		if player.arrival_control_ticks_remaining == 0:
			break
		assert(not player.can_read_controller_input())
		var position := player.body.global_position
		assert(is_equal_approx(position.x, arrival.global_position.x))
		assert(position.y >= previous_y)
		sank_during_lock = sank_during_lock or position.y > previous_y
		previous_y = position.y
		assert(bubbles._spawn_ticks == 0)
		await tick_finished
	Input.action_release(ControllerHandler.right_action)
	Input.action_release(ControllerHandler.primary_action)
	assert(sank_during_lock and player.arrival_control_ticks_remaining == 0)
	for frame in range(4):
		if player.state_machine.current_state is MarioSwimState:
			break
		await tick_finished
	assert(player.state_machine.current_state is MarioSwimState)
	assert(player.can_read_controller_input())

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

	# Start from the shelf at the actual exit and let floor contact and entry run normally.
	var pipe := water.find_transport_entity(&"surface_entrance") as PipeEntrance
	player.body.global_position = pipe.entry_position() - Vector2(6, 0)
	player.body.velocity = Vector2.ZERO
	(water.get_node("Camera2D") as LevelCamera).snap_to_arrival(player.body)
	Input.action_press(ControllerHandler.right_action)
	for frame in range(80):
		if player.state_machine.current_state == player.pipe_enter_state:
			break
		await tick_finished
	Input.action_release(ControllerHandler.right_action)
	assert(player.state_machine.current_state == player.pipe_enter_state)
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
