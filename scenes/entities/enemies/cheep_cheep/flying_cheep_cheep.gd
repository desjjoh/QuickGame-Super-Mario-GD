class_name FlyingCheepCheep
extends BaseEnemy
## Ballistic enemy flight on the NES integer/fractional grid.

signal flight_finished(fractions: Vector2i)

const BODY_OFFSET := Vector2(8, 16)
# The reference indexes through PRandomSubtracter and its following ROM bytes.
const ARC_CORRECTIONS := [248, 160, 112, 189, 0, 32, 32, 32, 0, 0, 181, 30, 41, 32, 240, 8]

## Initial velocity in pixels per 60 Hz physics tick.
@export var launch_velocity := Vector2(0.875, -5.0)
## Position fractions can be retained by a source when it reuses an enemy slot.
@export_range(0, 255) var initial_horizontal_fraction := 0
@export_range(0, 255) var initial_vertical_fraction := 0

@onready var vertical: VerticalMovementComponent = $VerticalMovement
@onready var _knocked_out: EnemyDefeatedState = $StateMachine/KnockedOut

var _area: BaseLevelArea
var _x_fraction := 0
var _speed_units := 0
var _last_flight_tick := -1


func _ready() -> void:
	super()
	var ancestor := get_parent()
	while ancestor != null and not ancestor is BaseLevelArea:
		ancestor = ancestor.get_parent()
	_area = ancestor as BaseLevelArea
	_x_fraction = initial_horizontal_fraction
	vertical.position_fraction = initial_vertical_fraction
	_speed_units = roundi(launch_velocity.y * 256.0)
	_show_flight_pose()


func _physics_process(delta: float) -> void:
	if is_shutdown or gameplay_suspended or activity_suspended or is_queued_for_deletion():
		return
	# The ROM retires at its draw step, before advancing this frame's flight.
	if _origin_y() >= 256.0:
		var fractions := movement_fractions()
		# EraseEnemyObject falls through to one final ordinary horizontal step.
		if not _defeated:
			fractions.x = (fractions.x + roundi(launch_velocity.x * 256.0)) & 0xff
		flight_finished.emit(fractions)
		remove_offscreen()
		return
	if not _defeated:
		_show_flight_pose()
	super(delta)
	if _defeated or is_shutdown or gameplay_suspended or activity_suspended:
		return
	var before := body.position
	_fly_tick()
	# Enemy graphics precede movement in the reference.
	sprite.position += before - body.position


func _fly_tick() -> void:
	_last_flight_tick = Engine.get_physics_frames()
	var horizontal := _x_fraction + roundi(launch_velocity.x * 256.0)
	_x_fraction = horizontal & 0xff
	body.position.x += horizontal >> 8
	body.position.y += vertical.consume_displacement(_speed_units)
	_speed_units += 13
	if _speed_units >= 5 * 256 and (_speed_units & 0xff) >= 128:
		_speed_units = 5 * 256
	var fraction := _speed_units & 0xff
	var difference := (floori(_origin_y()) - int(ARC_CORRECTIONS[fraction >> 4])) & 0xff
	if difference >= 128:
		difference = 256 - difference
	if difference < 8:
		# This byte addition deliberately does not carry into the integer speed.
		_speed_units = (_speed_units & ~0xff) | ((fraction + 16) & 0xff)
	body.velocity = Vector2(launch_velocity.x * 60.0, _speed_units / 256.0 * 60.0)


func movement_fractions() -> Vector2i:
	return Vector2i(
		_x_fraction,
		_knocked_out._position_fraction if _defeated else vertical.position_fraction
	)


func _origin_y() -> float:
	var origin := _area.global_position.y if is_instance_valid(_area) else 0.0
	return body.global_position.y - origin - BODY_OFFSET.y


func _show_flight_pose() -> void:
	sprite.flip_h = launch_velocity.x > 0.0
	sprite.frame = int((GameHandler.animation_clock.tick_count & 8) == 0)
	sprite.position = Vector2(0, 1)


func _can_hurt_player() -> bool:
	return not _defeated


func _can_stomp(player: BasePlayer) -> bool:
	var player_origin := floorf(player.body.global_position.y - 32.0)
	var enemy_origin := floorf(body.global_position.y - BODY_OFFSET.y)
	return floori(player.body.velocity.y / 60.0) > 0 or player_origin + 12.0 < enemy_origin


func _apply_stomp_rebound(player: BasePlayer) -> void:
	var speed := player.vertical_movement.speed_with_integer(
		player.motion_values, roundi(stomp_rebound / 60.0)
	)
	player.jump_action.launch_with_falling_gravity(player.motion_values, speed)


func _can_follow_stomp(player: BasePlayer) -> bool:
	return _can_stomp(player)


func is_outside_horizontal_cleanup(_left: float, _right: float) -> bool:
	return false


func is_outside_vertical_cleanup(_top: float, _bottom: float) -> bool:
	return false


func _accept_hit(hit: EntityHit) -> bool:
	if hit.maneuver not in [&"stomp", &"fireball", &"star", &"shell"]:
		return false
	var stomp := hit.maneuver == &"stomp"
	var reward_position := reward_popup_position(not stomp)
	_knocked_out.launch_speed = 0.0 if stomp else -180.0
	_knocked_out.launch_speed_fraction = 0 if stomp else _speed_units & 0xff
	_knocked_out.launch_position_fraction = vertical.position_fraction
	_knocked_out.defer_launch_step = (
		hit.maneuver == &"shell" and _last_flight_tick == Engine.get_physics_frames()
	)
	var player := _level.player if is_instance_valid(_level) else null
	_knocked_out.launch_direction = (
		-1.0 if is_instance_valid(player) and body.global_position.x < player.body.global_position.x
		else 1.0
	)
	_knocked_out.stomp_launch = stomp
	_knocked_out.fireball_launch = hit.maneuver in [&"fireball", &"shell"]
	_knocked_out.star_launch = hit.maneuver == &"star"
	if not _knocked_out.defer_launch_step:
		sprite.position = Vector2(0, 1)
	if not state_machine.change_state(_knocked_out):
		return false
	mark_defeated(hit)
	if not is_shutdown and not is_queued_for_deletion():
		if stomp:
			award_score(200, reward_position, 5)
		elif hit.maneuver != &"shell":
			award_smack_defeat(200, reward_position)
	return true
