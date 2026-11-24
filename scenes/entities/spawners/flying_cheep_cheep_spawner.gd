@tool
class_name FlyingCheepCheepSpawner
extends Node2D
## One placed stream; the registry owns slots and this source owns wave policy.

const FISH := preload("res://scenes/entities/enemies/cheep_cheep/flying_cheep_cheep.tscn")
const SUBMERGED := preload("res://scenes/entities/enemies/cheep_cheep/submerged_cheep_cheep.tscn")
const COLUMN_CLOCK := preload("res://scenes/components/interactions/scrolled_column_clock.gd")
const SLOT_END := 3
const DELAYS := [16, 96, 32, 72]
const SPEEDS := [14, 5, 6, 14, 28, 32, 16, 12, 30, 34, 24, 20]
const OFFSETS := [128, 48, 64, 128, 48, 80, 80, 112, 32, 64, 128, 160, 112, 64, 144, 104]

## Map columns are relative to this marker. One column is 16 pixels.
@export_range(0, 1000) var start_column := 0:
	set(value):
		start_column = value
		queue_redraw()
## -1 leaves the stream running until area exit or the ending starts.
@export_range(-1, 1000) var stop_column := -1:
	set(value):
		stop_column = value
		queue_redraw()
## Additional start commands allow entry beyond the first command after a death.
@export var restart_columns := PackedInt32Array():
	set(value):
		restart_columns = value
		queue_redraw()

## Optional ordinary enemy entry, relative to this marker; negative X disables it.
@export var submerged_swimmer_origin := Vector2(-1, 248)

# Tests can replay the three original random bytes for each attempted slot.
var random_samples: Callable
var submerged_random_sample: Callable
var _level: BaseLevel
var _area: BaseLevelArea
var _clock := COLUMN_CLOCK.new()
var _initialized := false
var _active := false
var _pending := -1
var _remaining := 0
var _fish_slots: Dictionary = {}
var _slot_fractions := [Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO]
var _new_fish: Array[BaseEnemy] = []
var _retiring: Array[BaseEnemy] = []
var _submerged: SwimmingCheepCheep
var _submerged_slot := -1
var _submerged_attempted := false


class TriggerClock extends Node:
	var source: FlyingCheepCheepSpawner

	func _physics_process(_delta: float) -> void:
		source._finish_tick()


func _ready() -> void:
	var ancestor := get_parent()
	while ancestor != null and not ancestor is BaseLevelArea:
		ancestor = ancestor.get_parent()
	_area = ancestor as BaseLevelArea
	if Engine.is_editor_hint():
		set_physics_process(false)
		set_notify_transform(true)
		queue_redraw()
		return
	_level = BaseLevel.containing(self)
	# Keep live actors at 1..3; allocate after the final camera update.
	process_physics_priority = 105
	var trigger_clock := TriggerClock.new()
	trigger_clock.name = "TriggerClock"
	trigger_clock.source = self
	trigger_clock.process_physics_priority = 115
	add_child(trigger_clock)


func _can_advance() -> bool:
	if not is_instance_valid(_area) or not is_instance_valid(_level):
		return false
	if (not _area.is_active or not _area.runtime_loaded or not _area.actors_initialized
		or _area.actors_suspended or _level.is_shutdown or _level.death_in_progress
		or _level.completion_in_progress or _level.transition_in_progress
		or _level.area_transport.enemy_spawns_held or not _level.is_physics_processing()):
		return false
	var mario := _level.player as Mario
	return not is_instance_valid(mario) or not mario.form_presentation.active


func _camera_left() -> int:
	var view := _area.get_activity_region(false).grow(-_area.activation_buffer)
	return floori(view.position.x - _area.global_position.x)


func _initialize() -> void:
	var preloaded := _clock.reset(_camera_left())
	for column in range(preloaded.x, preloaded.y):
		_queue_column(column)
	_initialized = true


func _physics_process(_delta: float) -> void:
	if not _can_advance():
		return
	if not _initialized:
		_initialize()
	_remaining = maxi(0, _remaining - 1)
	# Free enemy slots skip the first graphics task, including a queued start.
	if _clock.task == 7:
		return
	var slot := _level.spawn_registry.get_next_free_slot(&"enemy")
	if slot < 0:
		return
	if _try_submerged_entry(slot):
		slot = _level.spawn_registry.get_next_free_slot(&"enemy")
		if slot < 0:
			return
	if _pending >= 0:
		_active = _pending == 1
		_pending = -1
	if not _active or _remaining > 0:
		return
	var sample := PackedByteArray([randi() & 0xff, randi() & 0xff, randi() & 0xff])
	if random_samples.is_valid():
		sample = random_samples.call(slot)
	_try_spawn(slot, sample)


func _finish_tick() -> void:
	if not _can_advance():
		return
	# A retiring actor cannot reuse its own slot in the same NES enemy pass.
	for actor in _retiring:
		if is_instance_valid(actor):
			_level.spawn_registry.release(&"enemy", actor)
	_retiring.clear()
	if is_instance_valid(_submerged) and _submerged.is_queued_for_deletion():
		_release_submerged()
	for fish in _new_fish:
		if is_instance_valid(fish) and not fish.is_queued_for_deletion():
			fish.set_physics_process(true)
	_new_fish.clear()
	if _initialized:
		_queue_column(_clock.advance(_camera_left()))


func _queue_column(column: int) -> void:
	var offset := floori(_area.to_local(global_position).x / 16.0)
	var local_column := column - offset
	if stop_column >= 0 and local_column == stop_column:
		_pending = 0
	elif local_column == start_column or restart_columns.has(local_column):
		if not _active and _fish_slots.is_empty():
			_pending = 1


func _try_spawn(slot: int, sample: PackedByteArray) -> bool:
	_remaining = DELAYS[sample[1] & 3]
	if slot >= SLOT_END:
		return false
	var player := _level.player
	if not is_instance_valid(player):
		return false
	var speed := roundi(player.motion_values.velocity.x / 60.0 * 16.0) & 0xff
	var group := 0 if speed == 0 else 4 if speed < 25 else 8
	var speed_index: int = group + (sample[0] & 3)
	var position_index := speed_index
	if speed == 0 and (sample[1] & 3) != 0:
		position_index = sample[2] & 15
	var toward_left := speed == 0 and (position_index & 2) != 0
	var horizontal := int(SPEEDS[speed_index]) * (-1 if toward_left else 1)
	var displacement := int(OFFSETS[position_index]) * (1 if (position_index & 2) != 0 else -1)
	var origin := Vector2(floorf(player.body.global_position.x - 8.0) + displacement,
		_area.global_position.y + 248.0)
	var fish := FISH.instantiate() as FlyingCheepCheep
	if not _level.try_claim_spawn_slot(&"enemy", fish):
		fish.free()
		return false
	fish.position = to_local(origin)
	fish.launch_velocity = Vector2(horizontal / 16.0, -5)
	fish.initial_horizontal_fraction = _slot_fractions[slot].x
	fish.initial_vertical_fraction = _slot_fractions[slot].y
	fish.visual_theme = _area.theme
	fish.process_physics_priority = slot + 1
	_fish_slots[fish] = slot
	fish.flight_finished.connect(_on_flight_finished.bind(fish))
	fish.tree_exiting.connect(_on_tree_exiting.bind(fish), CONNECT_ONE_SHOT)
	add_child(fish)
	fish.set_physics_process(false)
	_new_fish.append(fish)
	return true


func _try_submerged_entry(slot: int) -> bool:
	if _submerged_attempted or submerged_swimmer_origin.x < 0.0:
		return false
	var origin := to_global(submerged_swimmer_origin)
	var view := _area.get_activity_region(false).grow(-_area.activation_buffer)
	var right := floorf(view.end.x) - 1.0
	if origin.x < right:
		_submerged_attempted = true
		return false
	if origin.x > floorf((right + BaseLevelArea.ENEMY_SPAWN_LOOKAHEAD) / 16.0) * 16.0:
		return false
	var fish := SUBMERGED.instantiate() as SwimmingCheepCheep
	if not _level.try_claim_spawn_slot(&"enemy", fish):
		fish.free()
		return false
	var fractions: Vector2i = _slot_fractions[slot] if slot < SLOT_END else Vector2i.ZERO
	fish.position = to_local(origin)
	fish.visual_theme = _area.theme
	fish.initial_horizontal_fraction = fractions.x
	fish.initial_vertical_fraction = fractions.y
	var sample := int(submerged_random_sample.call(slot)) if submerged_random_sample.is_valid() else randi()
	fish.initial_bob_down = (sample & 0x10) != 0
	fish.process_physics_priority = slot + 1
	_submerged = fish
	_submerged_slot = slot
	_submerged_attempted = true
	fish.tree_exiting.connect(_release_submerged, CONNECT_ONE_SHOT)
	add_child(fish)
	fish.set_physics_process(false)
	_new_fish.append(fish)
	return true


func _release_submerged() -> void:
	if not is_instance_valid(_submerged):
		return
	if _submerged_slot < SLOT_END:
		_slot_fractions[_submerged_slot] = _submerged.movement_fractions()
	_level.spawn_registry.release(&"enemy", _submerged)
	_submerged = null
	_submerged_slot = -1


func _on_flight_finished(fractions: Vector2i, fish: FlyingCheepCheep) -> void:
	if not _fish_slots.has(fish):
		return
	_slot_fractions[int(_fish_slots[fish])] = fractions
	_fish_slots.erase(fish)
	_retiring.append(fish)


func _on_tree_exiting(fish: FlyingCheepCheep) -> void:
	if _fish_slots.has(fish):
		_on_flight_finished(fish.movement_fractions(), fish)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint() or not is_instance_valid(_area):
		return
	var offset := floori(_area.to_local(global_position).x / 16.0)
	_draw_trigger(start_column + offset, "Flying fish start", Color(0.35, 1.0, 0.65))
	for column in restart_columns:
		_draw_trigger(column + offset, "Flying fish restart", Color(0.35, 0.8, 1.0))
	if stop_column >= 0:
		_draw_trigger(stop_column + offset, "Flying fish stop", Color(1.0, 0.65, 0.35))


func _draw_trigger(column: int, label: String, color: Color) -> void:
	var left := maxi(0, floori(column / 2.0) * 32 - 352)
	var height := float(ProjectSettings.get_setting("display/window/size/viewport_height", 240))
	var top := to_local(_area.to_global(Vector2(left, 0)))
	draw_dashed_line(top, top + Vector2(0, height), color, 1.0, 8.0)
	draw_string(ThemeDB.fallback_font, top + Vector2(4, 12),
		"%s (camera X%d, map column %d)" % [label, left, column],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color)
