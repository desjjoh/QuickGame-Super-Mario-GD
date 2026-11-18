@tool
class_name SwimmingCheepCheepSpawner
extends Node2D
## Shared camera-relative stream for both swimming variants.

const FISH := preload("res://scenes/entities/enemies/cheep_cheep/swimming_cheep_cheep.tscn")
const COOLDOWN := 32
const SLOT_END := 3
const HEIGHTS := [72, 56, 152, 88, 40, 104, 168, 120]

## Horizontal camera travel after the marker activates. Zero keeps the stream active.
@export_range(0.0, 10000.0, 1.0, "or_greater", "suffix:px") var active_distance := 0.0:
	set(value):
		active_distance = value
		if Engine.is_editor_hint():
			queue_redraw()
## Worlds outside World 2 reverse the default color bias.
@export var favor_red := false

var _level: BaseLevel
var _area: BaseLevelArea
var _remaining := 0
var _used_heights := 0


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
	# Let the camera and painted spawners update before filling any free slots.
	process_physics_priority = 115


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint() or not is_instance_valid(_area):
		return
	var height := float(ProjectSettings.get_setting("display/window/size/viewport_height", 240))
	_draw_boundary(global_position.x, height, "Cheep Cheep start", Color(0.35, 1.0, 0.65))
	if active_distance > 0.0:
		_draw_boundary(
			global_position.x + active_distance, height, "Cheep Cheep stop", Color(1.0, 0.66, 0.35)
		)


func _draw_boundary(world_x: float, height: float, label: String, color: Color) -> void:
	var world_top := Vector2(world_x, _area.global_position.y)
	var top := to_local(world_top)
	var bottom := to_local(world_top + Vector2.DOWN * height)
	var area_x := _area.to_local(world_top).x
	draw_dashed_line(top, bottom, color, 1.0, 8.0)
	draw_string(
		ThemeDB.fallback_font,
		top + Vector2(4.0, 12.0),
		"%s X%s (camera left)" % [label, snappedf(area_x, 0.1)],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		10,
		color
	)


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_area) or not _area.is_active or not _area.runtime_loaded:
		_remaining = 0
		_used_heights = 0
		return
	if (
		not _area.swimming_enabled or not _area.actors_initialized or _area.actors_suspended
		or _level.is_shutdown or _level.death_in_progress or _level.completion_in_progress
		or _level.transition_in_progress or _level.area_transport.enemy_spawns_held
		or not _level.is_physics_processing()
	):
		return
	var mario := _level.player as Mario
	if is_instance_valid(mario) and mario.form_presentation.active:
		return
	_remaining = maxi(0, _remaining - 1)
	if _remaining > 0:
		return
	var view := _area.get_activity_region(false).grow(-_area.activation_buffer)
	var left := floorf(view.position.x)
	if (
		left < global_position.x
		or (active_distance > 0.0 and left >= global_position.x + active_distance)
	):
		return
	_try_spawn(view, randi() & 0xff)


func _try_spawn(view: Rect2, sample: int) -> bool:
	# The registry allocates the lowest free slot. Check before instantiating so
	# a full stream can wait without creating and freeing scenes each tick.
	if not _level.spawn_registry.has_enemy_slot_before(SLOT_END):
		return false
	var fish := FISH.instantiate() as SwimmingCheepCheep
	if not _level.try_claim_spawn_slot(&"enemy", fish):
		fish.free()
		return false
	fish.red = (sample >= 0xaa) != favor_red
	fish.initial_bob_down = (sample & 0x10) != 0
	fish.visual_theme = _area.theme
	var height := _next_height(sample)
	var x := floorf(view.end.x) + 31.0
	fish.position = to_local(Vector2(x, _area.to_global(Vector2(0, height)).y))
	add_child(fish)
	fish.reset_physics_interpolation()
	_remaining = COOLDOWN
	return true


func _next_height(sample: int) -> int:
	if _used_heights == 0xff:
		_used_heights = 0
	var lane := sample & 7
	while (_used_heights & (1 << lane)) != 0:
		lane = (lane + 1) & 7
	_used_heights |= 1 << lane
	return HEIGHTS[lane]
