extends Node

const GAME := preload("res://scenes/main/game.tscn")
const STAGE := preload("res://scenes/levels/worlds/world 2/2-1.tscn")
const VINE := preload("res://scenes/entities/climbables/vine/growing_vine.gd")

signal stepped


func _physics_process(_delta: float) -> void:
	stepped.emit()


func _ready() -> void:
	process_physics_priority = 200
	var game := GAME.instantiate()
	game.start_with_title = false
	game.start_stage_override = null
	game.stages.assign([STAGE])
	add_child(game)
	while GameHandler.transitions.busy:
		await stepped
	assert(GameHandler.transitions.available())
	var level: BaseLevel = GameHandler.current_level
	level.timer_enabled = false
	var enemy_limit := level.spawn_registry.enemy_limit
	level.spawn_registry.enemy_limit = 0
	var area := level.active_area
	var brick := level.area_content.find_layout_entity(area, &"reward_brick", Vector2i(83, 5)) as QuestionBlock
	assert(brick != null and brick.reward_kind == BlockReward.Kind.VINE)
	var player := level.player as Mario
	player.set_physics_process(false)
	player.form_controller.configure(player, player.super_form)
	var camera := area.get_node("Camera2D") as LevelCamera
	camera.follow_enabled = false
	camera.global_position.x = 1312.0
	area.update_camera_activity()
	await stepped
	while (GameHandler.animation_clock.tick_count & 3) != 2:
		await stepped
	var coins := GameHandler.player_status.coins
	player.body.global_position = area.to_global(Vector2(1336, 126))
	player.state_machine.change_state(player.get_node("StateMachine/Jump"))
	player.jump_action.launch_with_falling_gravity(player.motion_values, -240.0)
	player.vertical_movement.reset_fraction(player.body)
	player.move_body(true)
	var vine := brick.get_node_or_null("GrowingVine") as VINE
	assert(vine != null and vine.growth == 1)
	assert(GameHandler.player_status.coins == coins)
	assert(SoundHandler.get_sound(&"vine_grow") != null)

	var cloud := level.get_node("Areas/CoinHeaven") as BaseLevelArea
	var presentation := level.get_node("Presentations/CoinHeavenArrival") as CoinHeavenArrival
	player.body.global_position = area.to_global(Vector2(1329, 72))
	for age in range(1, 62):
		await stepped
	player.set_physics_process(true)
	await stepped
	assert(player.climbing.get_surface() == vine)
	Input.action_press("ui_up")
	# Mesen loses contact for two ticks before the next climbable tile is published.
	for expected_y in [71.0, 70.0]:
		await stepped
		assert(player.climbing.get_surface() == null)
		assert(is_equal_approx(area.to_local(player.body.global_position).y, expected_y))
	await stepped
	assert(player.climbing.get_surface() == vine)
	assert(is_equal_approx(area.to_local(player.body.global_position).y, 69.0))
	for tick in range(7):
		await stepped
	Input.action_release("ui_up")
	assert(player.scripted_motion_step.is_valid())
	assert(not player.can_read_controller_input())
	assert(is_equal_approx(area.to_local(player.body.global_position).y, 63.0))
	Input.action_press("ui_down")
	for tick in range(71):
		await stepped
	assert(not presentation._cover.visible)
	assert(area.to_local(player.body.global_position).y < 4.0)
	await stepped
	assert(presentation._cover.visible)
	assert(level.active_area == area)

	# The reference holds the cover until the destination vine is initialized.
	for tick in range(24):
		await stepped
	await get_tree().process_frame
	assert(level.active_area == cloud)
	assert(GameHandler.get_session_value(&"current_area_id") == &"coin_heaven")
	assert(cloud.background_music == MusicHandler.Track.COIN_HEAVEN)
	assert(MusicHandler._voice.stream == MusicHandler._loops[MusicHandler.STARMAN_TRACK])
	assert(not player.starman.is_active())
	assert(not GameHandler.transitions.busy)
	assert(not presentation._cover.visible)
	assert(cloud.to_local(player.body.global_position) == Vector2(64, 272))
	var arrival_vine := cloud.get_node("WorldObjects/ArrivalVine") as GrowingVine
	assert(arrival_vine.growth == 0)
	Input.action_release("ui_down")
	var cloud_spawner := cloud.get_node("WorldObjects/CloudPlatform") as EntitySpawner
	var lift := cloud_spawner.get_node("MovingLift") as MovingLift
	assert(cloud.to_local(lift.global_position) == Vector2(256, 160))
	assert(lift.get_activity_rect().size == Vector2(48, 8))
	assert(level.spawn_registry.get_slot(&"enemy", lift) == -1)
	var cloud_camera := cloud.get_node("Camera2D") as LevelCamera
	assert(is_equal_approx(cloud_camera.global_position.x - cloud.global_position.x, 128.0))
	# Mesen locks the final screen at X992 through X1247.
	assert(cloud_camera.advance_scripted_scroll(2000.0))
	assert(is_equal_approx(cloud_camera.global_position.x - cloud.global_position.x, 1120.0))
	cloud_camera.snap_to_arrival(player.body)

	for tick in range(190):
		await stepped
	assert(arrival_vine.growth == 95)
	await stepped
	assert(arrival_vine.growth == 96)
	assert(cloud.to_local(player.body.global_position) == Vector2(64, 272))
	assert(not player.can_read_controller_input())
	for tick in range(100):
		await stepped
	assert(cloud.to_local(player.body.global_position) == Vector2(64, 184))
	var climb_sprite_x := player.sprite.global_position.x
	assert(not player.sprite.flip_h)
	await stepped
	assert(player.sprite.flip_h)
	assert(is_equal_approx(player.sprite.global_position.x, climb_sprite_x + 15.0))
	assert(player.sprite.texture == player.super_form.climb[0])
	assert(cloud.to_local(player.body.global_position) == Vector2(79, 184))
	for tick in range(23):
		await stepped
	assert(not player.can_read_controller_input())
	assert(cloud.to_local(player.body.global_position) == Vector2(79, 184))
	await stepped
	assert(player.can_read_controller_input())
	assert(not player.scripted_motion_step.is_valid())
	assert(not player.sprite.flip_h)
	assert(is_equal_approx(player.sprite.global_position.x, climb_sprite_x + 19.0))
	assert(cloud.to_local(player.body.global_position) == Vector2(83, 184))

	for tick in range(25):
		await stepped
	assert(player.has_floor_support())
	assert(is_equal_approx(cloud.to_local(player.body.global_position).y, 208.0))
	assert(await _check_cloud_platform(player, cloud, cloud_camera, cloud_spawner, lift))
	level.spawn_registry.enemy_limit = enemy_limit
	var lives := GameHandler.player_status.lives
	Input.action_press("ui_right")
	for tick in range(950):
		await stepped
		if GameHandler.transitions.busy:
			break
	Input.action_release("ui_right")
	assert(GameHandler.transitions.busy)
	assert(not level.death_in_progress)
	assert(GameHandler.player_status.lives == lives)
	while GameHandler.transitions.busy:
		await stepped
	assert(level.active_area == area)
	assert(level.active_target_id == &"coin_heaven_return")
	assert(GameHandler.get_session_value(&"current_area_id") == &"main")
	assert(MusicHandler._voice.stream == MusicHandler._loops[MusicHandler.Track.OVERWORLD])
	var returned_camera := area.get_node("Camera2D") as LevelCamera
	var half_width := returned_camera.get_viewport_rect().size.x / (2.0 * returned_camera.zoom.x)
	assert(is_equal_approx(returned_camera.global_position.x - half_width, 2560.0))
	assert(area.to_local(player.body.global_position) == Vector2(2608, 32))
	assert(not player.can_read_controller_input())
	for tick in range(26):
		assert(not player.can_read_controller_input())
		await stepped
	assert(player.can_read_controller_input())
	assert(area.to_local(player.body.global_position) == Vector2(2608, 82), str(area.to_local(player.body.global_position)))
	assert(not player.has_floor_support() and player.body.velocity.y > 0.0)
	for tick in range(30):
		assert(not player.has_floor_support())
		await stepped
	assert(player.has_floor_support())
	assert(is_equal_approx(area.to_local(player.body.global_position).y, 208.0))
	assert(is_equal_approx(returned_camera.global_position.x - half_width, 2560.0))
	assert(GameHandler.player_status.lives == lives and not level.death_in_progress)
	var layout := area.get_node("Layouts/EnemyLayout") as TileMapLayer
	for cell in [Vector2i(165, 12), Vector2i(169, 12), Vector2i(171, 12)]:
		var tile := layout.get_cell_tile_data(cell)
		var entity_id := StringName(tile.get_custom_data("entity_id"))
		var spawner := level.area_content.find_layout_entity(area, entity_id, cell) as EntitySpawner
		assert(spawner._attempted)
		assert(spawner.find_children("*", "BaseEnemy", true, false).is_empty())

	# The first marker beyond the arrival screen can still activate when we scroll.
	var ahead := level.area_content.find_layout_entity(
		area, &"green_koopa_spawner", Vector2i(185, 12)
	) as EntitySpawner
	assert(not ahead._attempted)
	returned_camera.global_position.x += 128.0
	area.update_camera_activity()
	assert(ahead.find_children("*", "BaseEnemy", true, false).size() == 1)
	level.shutdown()
	game.queue_free()
	await get_tree().process_frame
	print("PASS: Coin Heaven auto-climb, 340-tick Mesen handoff, cloud platform carry and cleanup, and fall return.")
	await preload("res://tests/fixtures/finish_test.gd").finish(get_tree())


func _check_cloud_platform(
	player: Mario, cloud: BaseLevelArea, camera: LevelCamera, spawner: EntitySpawner, lift: MovingLift
) -> bool:
	var origin := lift.global_position
	Input.action_press("ui_right")
	for tick in range(130):
		await stepped
		assert(lift.global_position == origin)
		if cloud.to_local(player.body.global_position).x >= 198.0:
			break
	assert(cloud.to_local(player.body.global_position).x >= 198.0)
	Input.action_press("primary")
	for tick in range(75):
		await stepped
		assert(lift.global_position == origin)
		if player.is_riding_horizontal_lift():
			break
	Input.action_release("primary")
	Input.action_release("ui_right")
	assert(player.is_riding_horizontal_lift(), str(cloud.to_local(player.body.global_position)))
	assert(player.body.global_position.y == origin.y)
	await stepped
	assert(lift.global_position == origin + Vector2.RIGHT)
	for tick in range(70):
		await stepped
	assert(player.is_riding_horizontal_lift() and is_zero_approx(player.body.velocity.x))
	for tick in range(8):
		var old_feet := player.body.global_position
		var old_platform := lift.global_position
		var old_camera := camera.global_position
		await stepped
		assert(lift.global_position == old_platform + Vector2.RIGHT)
		assert(player.body.global_position == old_feet + Vector2.RIGHT)
		assert(camera.global_position == old_camera + Vector2.RIGHT)

	Input.action_press("ui_right")
	for tick in range(55):
		var old_platform := lift.global_position
		await stepped
		assert(lift.global_position == old_platform + Vector2.RIGHT)
		if not player.is_riding_horizontal_lift():
			break
	Input.action_release("ui_right")
	assert(not player.is_riding_horizontal_lift())
	assert(player.body.velocity.x > 0.0)
	for tick in range(8):
		await stepped
	assert(player.body.global_position.y > origin.y)

	var saved_camera_x := camera.global_position.x
	var half_width := camera.get_viewport_rect().size.x / (2.0 * camera.zoom.x)
	camera.global_position.x = lift.global_position.x - half_width - 71.0
	cloud.update_camera_activity()
	assert(not lift.is_queued_for_deletion())
	camera.global_position.x -= 1.0
	cloud.update_camera_activity()
	assert(lift.is_queued_for_deletion())
	camera.global_position.x = saved_camera_x
	camera.reset_target(player.body)
	await get_tree().process_frame
	cloud.update_camera_activity()
	assert(not is_instance_valid(lift))
	assert(not spawner.has_node("MovingLift"))
	return true
