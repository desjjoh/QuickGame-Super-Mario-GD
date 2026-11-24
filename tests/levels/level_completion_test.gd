extends Node

var notifications: int = 0


func ticks(count: int = 1) -> void:
	for frame in range(count):
		await get_tree().physics_frame
		await get_tree().process_frame


func wait_idle() -> void:
	for frame in range(300):
		if not GameHandler.transitions.busy:
			return
		await ticks()
	assert(false, "Completion transition did not finish.")


func notified(level: BaseLevel) -> void:
	notifications += 1
	assert(level.completion_in_progress)
	assert(not level.on_complete())
	assert(not level.on_death(level.player))
	assert(not level.can_transport())


func make_game(animated: bool, sandbox_scene: PackedScene) -> Node:
	var game: Node = load("res://scenes/main/game.tscn").instantiate()
	game.stages.assign([load("res://scenes/levels/worlds/world 1/1-1.tscn"), sandbox_scene])
	game.start_with_title = false
	game.start_stage_override = null
	game.transitions_enabled = animated
	return game


func replace_on_completion(sandbox_scene: PackedScene) -> void:
	assert(GameHandler.load_level(sandbox_scene))


func _ready() -> void:
	var director: TransitionCoordinator = GameHandler.transitions
	var definition := director.get_definition(&"level")
	definition.minimum_frames = 2
	for stage in definition.stages:
		stage.minimum_frames = 2
	director.get_definition(&"finish").minimum_frames = 2
	var sandbox_scene := load("res://tests/fixtures/sandbox_level.tscn") as PackedScene
	for animated in [false, true]:
		GameHandler.clear_session()
		var game := make_game(animated, sandbox_scene)
		add_child(game)
		await wait_idle()
		assert(GameHandler.current_stage_index == 0)
		var level := GameHandler.current_level
		assert(not level.completion_in_progress)
		if animated:
			# A rejected coordinator transaction must leave the same level playable.
			definition.minimum_frames = 0
			assert(not level.on_complete())
			assert(not level.completion_in_progress and GameHandler.current_stage_index == 0)
			assert(GameHandler.flow == GameHandler.GameFlow.PLAYING)
			definition.minimum_frames = 2
			assert(level.on_complete())
			assert(GameHandler.flow == GameHandler.GameFlow.COMPLETING)
			assert(level.player.gameplay_suspended and not ControllerHandler.enabled)
			director.cancel()
			await ticks()
			assert(GameHandler.current_level == level and GameHandler.current_stage_index == 0)
			assert(GameHandler.flow == GameHandler.GameFlow.PLAYING)
			assert(not level.completion_in_progress and not level.player.gameplay_suspended)
		GameHandler.set_top_score(987654)
		GameHandler.set_session_value(&"run_probe", "clear me on title")
		GameHandler.set_score(1234)
		GameHandler.set_coins(7)
		GameHandler.set_lives(1)
		GameHandler.set_player_form(PlayerStatus.PowerupForm.SUPER)
		var key := level._progress_key
		GameHandler.store_area_progress(key, &"probe", {"used": true}, level)
		level.completion_started.connect(notified.bind(level))
		assert(level.on_complete())
		await wait_idle()
		assert(GameHandler.current_stage_index == 1)
		assert(GameHandler.flow == GameHandler.GameFlow.PLAYING)
		assert(
			GameHandler.current_level.scene_file_path == "res://tests/fixtures/sandbox_level.tscn"
		)
		assert(GameHandler.player_status.score == 1234 and GameHandler.player_status.coins == 7)
		var arrived := GameHandler.current_player as Mario
		assert(arrived.form_controller.current_form == arrived.super_form)
		assert(
			(
				GameHandler.player_status.lives == 1
				and GameHandler.player_status.powerup_form == PlayerStatus.PowerupForm.SUPER
			)
		)
		assert(GameHandler.get_area_progress(key, &"probe").is_empty())
		assert(GameHandler.time_remaining == GameHandler.current_level.starting_time)
		assert(not GameHandler.current_player.gameplay_suspended)
		level = GameHandler.current_level
		var last_key := level._progress_key
		GameHandler.store_area_progress(last_key, &"probe", {"used": true}, level)
		assert(level.on_complete())
		await wait_idle()
		assert(
			GameHandler.flow == GameHandler.GameFlow.TITLE and GameHandler.current_stage_index == -1
		)
		assert(GameHandler.get_area_progress(last_key, &"probe").is_empty())
		assert(GameHandler.player_status.score == 0 and GameHandler.player_status.coins == 0)
		assert(GameHandler.player_status.lives == 2)
		assert(GameHandler.player_status.powerup_form == PlayerStatus.PowerupForm.SMALL)
		assert(GameHandler.top_score == 987654)
		assert(GameHandler.get_session_value(&"run_probe", null) == null)
		assert(GameHandler.title_flow.starting_stage == null)
		assert(not GameHandler.current_level.on_complete())
		assert(GameHandler.current_player.gameplay_suspended)
		assert(not GameHandler.current_level.is_physics_processing())
		assert(GameHandler.start_new_game())
		await wait_idle()
		assert(GameHandler.current_stage_index == 0 and GameHandler.player_status.score == 0)
		game.free()
		await ticks(2)
	assert(notifications == 2)
	# Warp skips completion presentation, but keeps the destination intro.
	var warp_game := make_game(true, sandbox_scene)
	add_child(warp_game)
	await wait_idle()
	var warp_source := GameHandler.current_level
	assert(not warp_source.on_complete(null, BaseLevel.CompletionMode.WARP))
	assert(warp_source.on_complete(warp_game.stages[1], BaseLevel.CompletionMode.WARP))
	assert(warp_source.completion_mode == BaseLevel.CompletionMode.WARP)
	assert(director._definition.id == &"level")
	await wait_idle()
	assert(GameHandler.current_stage_index == 1)
	assert(GameHandler.current_level.on_complete())
	await wait_idle()
	assert(GameHandler.flow == GameHandler.GameFlow.TITLE)
	warp_game.free()
	await ticks(2)
	# Reusing one scene in adjacent entries still advances and clears its old visit.
	var repeated := make_game(false, sandbox_scene)
	repeated.stages[1] = repeated.stages[0]
	add_child(repeated)
	var repeated_key := GameHandler.current_level._progress_key
	GameHandler.store_area_progress(
		repeated_key, &"probe", {"used": true}, GameHandler.current_level
	)
	assert(GameHandler.current_level.on_complete())
	assert(GameHandler.current_stage_index == 1)
	assert(GameHandler.get_area_progress(repeated_key, &"probe").is_empty())
	assert(GameHandler.current_level.on_complete())
	assert(GameHandler.flow == GameHandler.GameFlow.TITLE)
	repeated.free()
	await ticks(2)
	# An unlisted override has no implicit next stage.
	var game := make_game(false, sandbox_scene)
	game.start_with_title = true
	game.stages.resize(1)
	add_child(game)
	assert(GameHandler.start_new_game(sandbox_scene))
	assert(GameHandler.current_stage_index == -1)
	assert(GameHandler.current_level.on_complete())
	assert(GameHandler.flow == GameHandler.GameFlow.TITLE)
	assert(GameHandler.start_new_game())
	var source := GameHandler.current_level
	source.completion_started.connect(replace_on_completion.bind(sandbox_scene))
	assert(not source.on_complete())
	assert(GameHandler.flow == GameHandler.GameFlow.PLAYING)
	assert(GameHandler.current_level.scene_file_path == "res://tests/fixtures/sandbox_level.tscn")
	game.free()
	await ticks(2)
	await _check_registered_world_two_handoff()
	print(
		"PASS: stage order, duplicate/death/transport gates, cancellation recovery, carried player status, progress reset, final/unlisted title return and stale observer safety."
	)
	await preload("res://tests/fixtures/finish_test.gd").finish(get_tree())


func _check_registered_world_two_handoff() -> void:
	var game: Node = load("res://scenes/main/game.tscn").instantiate()
	var source := load("res://scenes/levels/worlds/world 2/2-2.tscn") as PackedScene
	var destination := load("res://scenes/levels/worlds/world 2/2-3.tscn") as PackedScene
	var source_index: int = game.stages.find(source)
	var destination_index: int = game.stages.find(destination)
	assert(source_index >= 0 and destination_index == source_index + 1)
	game.start_with_title = false
	game.start_stage_override = destination
	game.transitions_enabled = false
	add_child(game)
	var level := GameHandler.current_level
	assert(level.stage_label == "2-3" and level.active_area.area_id == &"main")
	assert(level.active_area.theme.display_name == "Overworld")
	assert(not level.active_area.swimming_enabled)
	var ending := level.ending_presentation as FlagpoleEndingPresentation
	var castle := level.world_objects.get_node("large_castle_230_2") as CastleEntity
	var pole := level.world_objects.get_node("flagpole_224_2") as FlagpoleEntity
	assert(ending != null and ending._castle == castle)
	assert(pole.climb_top.global_position.x == 3608.0)
	assert(castle.doorway.global_position.y == 208.0)
	assert(GameHandler.time_remaining == level.starting_time)
	await ticks(2)
	assert(level.player.body.global_position.is_equal_approx(level.player_spawn.global_position))
	assert(GameHandler.load_level(source, true, source_index, BaseLevel.EntryMode.RESPAWN))
	assert(GameHandler.current_level.on_complete())
	assert(GameHandler.current_stage_index == destination_index)
	assert(GameHandler.current_level.scene_file_path == destination.resource_path)
	assert(GameHandler.current_level.active_area.area_id == &"main")
	game.free()
	await ticks(2)
