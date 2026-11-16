class_name Springboard
extends BaseEntity
## The spring occupies a fixed terrain cell. Its compression moves only the rider and art.

const DRAW_ORDER := preload("res://scenes/components/presentation/draw_order.gd")
const FRAMES := [1, 2, 1, 0]
const BOUNCE_SPEED := -420.0
const BOOST_SPEED := -720.0

var _level: BaseLevel
var _rider: Mario
var _previous_feet_y := INF
var _spring_tick := 0
var _boosted := false

@onready var _body: StaticBody2D = $Body


func _ready() -> void:
	_level = BaseLevel.containing(self)
	DRAW_ORDER.apply(sprite, DRAW_ORDER.ENEMY)
	super()


func _physics_process(_delta: float) -> void:
	var player := _level.player as Mario if is_instance_valid(_level) else null
	if player == null or player.is_dead or player.is_shutdown:
		_reset_spring()
		_previous_feet_y = INF
		return
	var feet := player.body.global_position
	var top := global_position.y
	if _body.collision_layer == 0:
		if player != _rider or (not _rider_has_motion() and feet.y <= top):
			_reset_spring()
	elif player.can_read_controller_input() and not player.scripted_motion_step.is_valid():
		if (
			player.body.velocity.y >= 0.0
			and _previous_feet_y <= top
			and feet.y >= top - player.body.safe_margin
			and _feet_over_spring(feet.x)
		):
			_start_compression(player)
	_previous_feet_y = player.body.global_position.y


func _feet_over_spring(center_x: float) -> bool:
	var local_x := floorf(center_x - global_position.x)
	for offset: Vector2 in MarioTerrain.FEET:
		if local_x + offset.x >= 0.0 and local_x + offset.x < 16.0:
			return true
	return false


func _start_compression(player: Mario) -> void:
	_rider = player
	_spring_tick = 0
	_boosted = false
	_body.collision_layer = 0
	player.body.global_position.y = global_position.y
	player.jump_action.end(player.motion_values)
	player.body.velocity.y = 0.0
	player.stomp_chain = 0
	player.scripted_motion_step = _compress
	_compress(0.0)


func _compress(_delta: float) -> void:
	var phase := _spring_tick >> 2
	sprite.frame = FRAMES[phase]
	if phase > 0 and _rider.can_read_controller_input() and ControllerHandler.input_primary_just_pressed:
		_boosted = true
	_rider.body.global_position.y += 2.0 if phase < 2 else -2.0
	if phase == FRAMES.size() - 1:
		_rider.state_machine.change_state(_rider.get_node("StateMachine/Jump"))
		_rider.jump_action.launch_with_falling_gravity(
			_rider.motion_values, BOOST_SPEED if _boosted else BOUNCE_SPEED
		)
		_rider.scripted_motion_step = _hold_launch
		return
	_spring_tick += 1


func _hold_launch(_delta: float) -> void:
	# The NES waits one more update before moving at the launch speed.
	_rider.scripted_motion_step = Callable()


func _rider_has_motion() -> bool:
	return (
		is_instance_valid(_rider)
		and (_rider.scripted_motion_step == _compress or _rider.scripted_motion_step == _hold_launch)
	)


func _reset_spring() -> void:
	if _rider_has_motion():
		_rider.scripted_motion_step = Callable()
	_rider = null
	_body.collision_layer = 1
	sprite.frame = 0


func shutdown() -> void:
	if not is_shutdown and is_node_ready():
		_reset_spring()
	super()
