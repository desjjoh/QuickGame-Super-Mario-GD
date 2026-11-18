extends Node

const STAGE := preload("res://scenes/levels/worlds/world 2/2-1.tscn")
const VINE := preload("res://scenes/entities/climbables/vine/growing_vine.gd")
const STEP := 1.0 / 60.0

signal stepped


func _physics_process(_delta: float) -> void:
	stepped.emit()


func _ready() -> void:
	process_physics_priority = 200
	var level := STAGE.instantiate() as BaseLevel
	level.timer_enabled = false
	add_child(level)
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

	var grab_pose := area.to_global(Vector2(1329, 72))
	for age in range(197):
		if age > 0:
			await stepped
		assert(vine.is_visible_in_tree() == (age >= 13))
		player.body.global_position = grab_pose
		assert(vine.can_attach(player) == (age >= 61))
		if age == 13:
			assert(vine.growth == 8)
		if age == 61:
			assert(vine.growth == 32)
			# The next player update is the first that can use the new climb band.
			player.set_physics_process(true)
		if age == 62:
			assert(player.state_machine.current_state is MarioClimbState)
			assert(player.climbing.get_surface() == vine)
			player.set_physics_process(false)
		if age == 93:
			assert(vine.growth == 48)
	assert(vine.growth == VINE.FULL_HEIGHT)
	assert(brick.state_machine.current_state.name == &"Inactive")
	assert(GameHandler.player_status.coins == coins)
	var progress := brick.capture_area_state()
	assert(progress.get("vine_growth") == vine.growth)
	var restored := load("res://scenes/entities/blocks/question/reward_brick.tscn").instantiate() as QuestionBlock
	var reward := BlockReward.new()
	reward.kind = BlockReward.Kind.VINE
	restored.configure_reward(reward)
	restored.restore_area_state(progress)
	restored.visual_theme = preload("res://assets/themes/underground.tres")
	add_child(restored)
	var restored_vine := restored.get_node("GrowingVine") as VINE
	assert(restored_vine.growth == vine.growth and restored_vine.is_visible_in_tree())
	assert(restored_vine._art.resource_path == "res://assets/palettes/underground/misc/vine.png")
	var castle_vine := preload("res://assets/themes/castle.tres").resolve_texture(VINE.ART)
	assert(castle_vine.resource_path == "res://assets/palettes/castle/misc/vine.png")
	restored.free()
	for form in [player.small_form, player.super_form, player.fire_form]:
		player.form_controller.configure(player, form)
		for side in [-1.0, 1.0]:
			assert(await _check_walk_in_and_release(player, vine, side))
			assert(await _check_step_off(player, vine, side))
	level.shutdown()
	level.queue_free()
	await get_tree().process_frame
	print("PASS: Mesen vine reveal, climb threshold, neutral grab, grounded walk-in and midair/ground exits from both sides with all three forms, and progress restoration.")
	await preload("res://tests/fixtures/finish_test.gd").finish(get_tree())


func _check_step_off(player: Mario, vine: GrowingVine, side: float) -> bool:
	var move := player.climb_state.move_state
	player.state_machine.change_state(move)
	var bottom := vine.climb_bottom.global_position
	# Leave the detection region between approaches to clear detach suppression.
	player.body.global_position = bottom + Vector2(-48.0, -8.0)
	player.body.velocity = Vector2.ZERO
	player.set_physics_process(true)
	await stepped
	player.body.global_position = bottom + Vector2(side * 6.5, -9.0)
	player.body.velocity = Vector2.ZERO
	player.vertical_movement.reset_fraction(player.body)
	await stepped
	assert(player.climbing.get_surface() == vine)
	Input.action_press("ui_down")
	for tick in range(12):
		await stepped
	Input.action_release("ui_down")
	assert(player.climbing.get_surface() == vine)
	var start := player.body.global_position
	assert(absf(start.y - bottom.y) <= player.body.safe_margin, str(start))
	var action := "ui_left" if side < 0.0 else "ui_right"
	Input.action_press(action)
	await stepped
	assert(player.state_machine.current_state == move)
	assert(player.climbing.get_surface() == null)
	assert(player.body.global_position.is_equal_approx(start + Vector2(side * 4.0, 0.0)))
	# Grounded acceleration can take seven ticks to produce another pixel to the right.
	for tick in range(7):
		await stepped
	Input.action_release(action)
	assert(player.climbing.get_surface() == null)
	assert((player.body.global_position.x - start.x) * side > 4.0)
	assert(absf(player.body.global_position.y - bottom.y) <= player.body.safe_margin)
	return true


func _check_walk_in_and_release(player: Mario, vine: GrowingVine, side: float) -> bool:
	var move := player.climb_state.move_state
	var bottom := vine.climb_bottom.global_position
	player.state_machine.change_state(move)
	player.body.global_position = bottom + Vector2(side * 30.0, 0.0)
	player.body.velocity = Vector2.ZERO
	player.vertical_movement.reset_fraction(player.body)
	player.set_physics_process(true)
	for tick in range(8):
		await stepped
	assert(player.has_floor_support())
	var inward := "ui_right" if side < 0.0 else "ui_left"
	Input.action_press(inward)
	for tick in range(50):
		await stepped
		if player.climbing.get_surface() == vine:
			break
	Input.action_release(inward)
	assert(player.climbing.get_surface() == vine)
	assert(is_equal_approx(player.body.global_position.y, bottom.y))

	var climb_frames := player.form_controller.current_form.climb
	var saw_second_pose := false
	Input.action_press("ui_up")
	for tick in range(16):
		await stepped
		if player.sprite.texture == climb_frames[1]:
			saw_second_pose = true
	Input.action_release("ui_up")
	assert(saw_second_pose, "Held Up must reach the second climb pose.")
	await stepped
	assert(player.sprite.texture == climb_frames[0])
	var before := player.body.global_position
	assert(absf(before.y - (bottom.y - 14.0)) <= player.body.safe_margin, str(before))

	var outward := "ui_left" if side < 0.0 else "ui_right"
	Input.action_press(outward)
	await stepped
	Input.action_release(outward)
	assert(player.climbing.get_surface() == null)
	assert(player.state_machine.current_state == move)
	assert(player.body.global_position.is_equal_approx(before + Vector2(side * 4.0, 0.0)))
	for tick in range(8):
		await stepped
	assert(player.climbing.get_surface() == null)
	assert(player.body.global_position.y > before.y)
	return true
