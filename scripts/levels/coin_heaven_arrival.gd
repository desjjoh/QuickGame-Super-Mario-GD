class_name CoinHeavenArrival
extends Node
## Owns the scripted climb from one reward vine and the arrival in a cloud area.

const VINE_SCENE := preload("res://scenes/entities/climbables/vine/growing_vine.tscn")
const CLIMB_SPEED := 0.875  # Pixels per NES tick.
const EXIT_CONFIRM_TICKS := 3
const AREA_SETUP_TICKS := 24
const VINE_BOTTOM_OFFSET := Vector2(0, -32)
const ARRIVAL_CLIMB_HEIGHT := 88.0
const WALK_OFF_TICKS := 25

enum Phase { WATCH, ASCEND, COVER, TRANSFER, GROW, ARRIVAL_CLIMB, WALK_OFF }

@export var source_area: BaseLevelArea
@export var source_cell: Vector2i
@export var destination_area: BaseLevelArea
@export var arrival: AreaEndpoint
@export var auto_climb_y := 64.0
@export var exit_y := 4.0

@onready var _level := get_parent().get_parent() as BaseLevel

var _phase := Phase.WATCH
var _player: BasePlayer
var _vine: GrowingVine
var _ticks := 0
var _exit_delay := 0
var _start_y := 0.0
var _cover: CanvasLayer
var _animation_speed := 1.0


func _ready() -> void:
	# The handoff observes the feet after Mario's manual climbing update.
	process_physics_priority = 1
	_cover = CanvasLayer.new()
	_cover.layer = 100
	_cover.hide()
	add_child(_cover)
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cover.add_child(black)


func _physics_process(_delta: float) -> void:
	if (
		_phase != Phase.WATCH
		or not is_instance_valid(source_area)
		or not is_instance_valid(destination_area)
		or not is_instance_valid(arrival)
		or _level.active_area != source_area
		or not _level.can_transport()
		or is_instance_valid(_level.player_presentation)
	):
		return
	var player := _level.player
	if (
		not is_instance_valid(player)
		or player.is_dead
		or player.is_shutdown
		or player.activity_suspended
		or player.gameplay_suspended
		or player.scripted_motion_step.is_valid()
		or player.state_machine.current_state != player.climb_state
		or source_area.to_local(player.body.global_position).y >= auto_climb_y
	):
		return
	var vine := player.climbing.get_surface() as GrowingVine
	if vine == null or vine.get_parent() != _level.area_content.find_layout_entity(
		source_area, &"reward_brick", source_cell
	):
		return
	_player = player
	_level.player_presentation = self
	_player.opening_control_locked = true
	_player.scripted_motion_step = _advance
	_player.body.velocity = Vector2.ZERO
	_animation_speed = _player.animation_player.speed_scale
	_play_climb()
	_phase = Phase.ASCEND
	_exit_delay = 0


func _advance(_delta: float) -> void:
	_ticks += 1
	match _phase:
		Phase.ASCEND:
			_advance_exit()
		Phase.COVER:
			if _ticks == AREA_SETUP_TICKS:
				_phase = Phase.TRANSFER
				_transfer.call_deferred()
		Phase.GROW:
			if _vine.growth == GrowingVine.FULL_HEIGHT:
				_phase = Phase.ARRIVAL_CLIMB
				_ticks = 1
				_advance_arrival_climb()
		Phase.ARRIVAL_CLIMB:
			_advance_arrival_climb()
		Phase.WALK_OFF:
			_advance_walk_off()


func _advance_exit() -> void:
	if _exit_delay > 0:
		_exit_delay -= 1
		if _exit_delay == 0:
			_cover.show()
			MusicHandler.stop_area(_level)
			_phase = Phase.COVER
			_ticks = 0
		return
	_player.body.global_position.y -= CLIMB_SPEED
	if roundf(source_area.to_local(_player.body.global_position).y) < exit_y:
		_exit_delay = EXIT_CONFIRM_TICKS


func _transfer() -> void:
	if _phase != Phase.TRANSFER or _level.is_shutdown:
		return
	# Area loading retires the current presentation. The scripted player lock
	# stays held across the commit, then this presentation claims the new area.
	_level.player_presentation = null
	var destination := TransportDestination.create(
		destination_area.area_id, arrival.get_endpoint_id()
	)
	if not _level.area_transport.begin(_player, destination, null, false, false):
		cancel()
		return
	_finish_transfer.call_deferred()


func _finish_transfer() -> void:
	if _phase != Phase.TRANSFER:
		return
	if _level.is_shutdown or _level.active_area != destination_area:
		cancel()
		return
	_level.player_presentation = self
	_player.clear_arrival_control_lock()
	_player.face_direction(1.0)
	_play_climb()
	_player.animation_player.pause()
	_start_y = _player.body.global_position.y
	_vine = VINE_SCENE.instantiate() as GrowingVine
	_vine.name = &"ArrivalVine"
	_vine.visual_theme = destination_area.theme
	var world := destination_area.get_node("WorldObjects") as Node2D
	_vine.position = world.to_local(arrival.global_position + VINE_BOTTOM_OFFSET)
	world.add_child(_vine)
	_vine.start_growth(true)
	_phase = Phase.GROW
	_ticks = 0
	_cover.hide()


func _advance_arrival_climb() -> void:
	if _ticks == 1:
		_play_climb()
	# NES signed fixed-point movement takes the integer (high) byte.
	var ascent := minf(ARRIVAL_CLIMB_HEIGHT, ceilf(_ticks * CLIMB_SPEED))
	_player.body.global_position.y = _start_y - ascent
	if ascent == ARRIVAL_CLIMB_HEIGHT:
		_player.animation_player.pause()
		_phase = Phase.WALK_OFF
		_ticks = 0


func _advance_walk_off() -> void:
	# EntrMode2 first applies the vine's side change, then waits for the
	# climb-side timer before the last outward step hands control back.
	if _ticks == 1:
		_player.body.global_position.x += 15.0
		_player.face_direction(-1.0)
		_player.climb_state.hold_pose()
		_player.body.reset_physics_interpolation()
	elif _ticks == WALK_OFF_TICKS:
		_player.body.global_position.x += 4.0
		_player.face_direction(1.0)
		_player.body.velocity = Vector2.ZERO
		_player.vertical_movement.reset_fraction(_player.body)
		_player.state_machine.stop(false)
		_player.state_machine.start()
		cancel()


func _play_climb() -> void:
	var animation := _player.animation_player
	animation.speed_scale = _player.climb_state.upward_animation_speed
	animation.play(_player.climb_state.animation_name)


func cancel() -> void:
	if is_instance_valid(_player) and _player.scripted_motion_step == _advance:
		_player.scripted_motion_step = Callable()
		_player.opening_control_locked = false
		_player.animation_player.speed_scale = _animation_speed
	if is_instance_valid(_level) and _level.player_presentation == self:
		_level.player_presentation = null
	_cover.hide()
	_player = null
	_vine = null
	_phase = Phase.WATCH
