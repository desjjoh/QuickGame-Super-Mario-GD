extends Node

const SANDBOX := preload("res://tests/fixtures/swim_sandbox.tscn")
const TRACE := "res://tests/fixtures/swimming_reference/swimming_bubbles_mesen.csv"
const PLAYER_OFFSET := Vector2(8, 32)


func _ready() -> void:
	var level := SANDBOX.instantiate() as BaseLevel
	level.position = Vector2(128, 64)
	add_child(level)
	level.set_physics_process(false)
	var player := level.player
	player.set_physics_process(false)
	var emitter := level.world_objects.get_node("SwimBubbles") as SwimBubbleEmitter
	emitter.set_physics_process(false)
	var trace := FileAccess.open(TRACE, FileAccess.READ)
	assert(trace != null)
	trace.get_csv_line()
	var origin := level.active_area.global_position
	var ticks := 0
	while not trace.eof_reached():
		var row := trace.get_csv_line()
		if row.size() != 15:
			continue
		var tick := int(row[0])
		player.body.global_position = origin + PLAYER_OFFSET + Vector2(int(row[1]), int(row[2]))
		player.face_direction(-1.0 if int(row[3]) == 2 else 1.0)
		if not row[5].is_empty():
			emitter._random_register = int(row[5])
			emitter._spawn_ticks = 0
			for slot: Sprite2D in emitter._slots:
				slot.hide()
			emitter._rise_fractions.fill(0)
		if tick == 35:
			_check_pause(player, emitter)
		emitter._physics_process(1.0 / 60.0)
		assert(emitter._spawn_ticks == int(row[4]), "Spawn timer on tick %d" % tick)
		assert(emitter.get_child_count() == 3)
		for index in range(3):
			var slot := emitter._slots[index]
			var column := 6 + index * 3
			var raw_y := int(row[column + 1])
			assert(emitter._rise_fractions[index] == int(row[column + 2]), "Rise fraction on tick %d" % tick)
			assert(slot.visible == (raw_y != 248), "Slot %d visibility on tick %d" % [index, tick])
			if slot.visible:
				var expected := origin + Vector2(int(row[column]), raw_y + 1)
				assert(slot.global_position == expected, "Slot %d position on tick %d" % [index, tick])
				assert(slot.z_index < level.players.z_index)
		ticks += 1
	assert(ticks == 355)
	level.queue_free()
	await get_tree().process_frame
	print("PASS: 355 Mesen bubble ticks, both facings, slot reuse, HUD cutoff and pause.")
	await preload("res://tests/fixtures/finish_test.gd").finish(get_tree())


func _check_pause(player: BasePlayer, emitter: SwimBubbleEmitter) -> void:
	var timer := emitter._spawn_ticks
	var random_register := emitter._random_register
	var position := emitter._slots[2].global_position
	player.set_gameplay_suspended(true)
	emitter._physics_process(1.0 / 60.0)
	assert(emitter._spawn_ticks == timer)
	assert(emitter._random_register == random_register)
	assert(emitter._slots[2].global_position == position)
	player.set_gameplay_suspended(false)
