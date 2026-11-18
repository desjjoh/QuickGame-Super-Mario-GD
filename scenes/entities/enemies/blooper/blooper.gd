class_name Blooper
extends BaseEnemy
## The underwater enemy alternates a diagonal burst with a vertical drift.

const BODY_OFFSET := Vector2(8, 16)
const TOP_LIMIT := 32
const TURN_MASK := 0x3f
const PHASE_RISE := 0
const PHASE_SLOW := 1
const PHASE_DRIFT := 2
const LONG_REGION := Rect2(0, 8, 16, 24)
const SHORT_REGION := Rect2(16, 16, 16, 16)

@onready var _knocked_out: EnemyDefeatedState = $StateMachine/KnockedOut

var _area: BaseLevelArea
var _speed := 0
var _phase := PHASE_RISE
var _drift_intervals := 0
var _direction := -1
var _slot := -1


func _ready() -> void:
	super()
	if _level != null:
		_area = _level.active_area
		_slot = _level.spawn_registry.get_slot(&"enemy", self)
		var mario := _level.player as Mario
		if mario != null:
			mario.damage.interval_elapsed.connect(_on_interval_elapsed)


func _physics_process(delta: float) -> void:
	if not _defeated:
		# The NES draws the current pose before advancing the swimmer.
		_show_pose(_drift_intervals == 1)
		var before := body.global_position
		super(delta)
		if (
			_can_hurt_player() and not is_shutdown and not gameplay_suspended and not activity_suspended
		):
			_swim_tick(GameHandler.animation_clock.tick_count, randi() & 0xff)
			sprite.position += before - body.global_position
		return
	super(delta)


func _swim_tick(tick: int, turn_sample: int) -> void:
	var player := _level.player if is_instance_valid(_level) else null
	var player_body: CharacterBody2D = player.body if is_instance_valid(player) else null
	if player_body != null and (turn_sample & TURN_MASK) == 0:
		if _slot >= 0 and (_slot & 1) != 0:
			_direction = _player_moving_direction(player)
		else:
			_direction = -1 if _nes_x(body, BODY_OFFSET.x) >= _nes_x(player_body, 8.0) else 1

	if _phase == PHASE_DRIFT:
		if (
			_drift_intervals > 0
			or player_body == null
			or _nes_y(body, BODY_OFFSET.y) + 16 < _nes_y(player_body, 32.0)
		):
			if (tick & 1) == 0:
				body.global_position.y += 1.0
		else:
			_phase = PHASE_RISE
		return

	if (tick & 7) == 0:
		if _phase == PHASE_RISE:
			_speed += 1
			if _speed == 2:
				_phase = PHASE_SLOW
		else:
			_speed -= 1
			if _speed == 0:
				_phase = PHASE_DRIFT
				_drift_intervals = 2

	if _nes_y(body, BODY_OFFSET.y) - _speed >= TOP_LIMIT:
		body.global_position.y -= _speed
	body.global_position.x += _direction * _speed


func _player_moving_direction(player: BasePlayer) -> int:
	var swim := player.state_machine.current_state as MarioSwimState
	if swim != null:
		return swim.get_moving_direction()
	if not is_zero_approx(player.body.velocity.x):
		return -1 if player.body.velocity.x < 0.0 else 1
	return -1 if player.sprite.flip_h else 1


func _nes_x(actor: CharacterBody2D, offset: float) -> int:
	return floori(actor.global_position.x - offset)


func _nes_y(actor: CharacterBody2D, offset: float) -> int:
	var area_y := _area.global_position.y if is_instance_valid(_area) else 0.0
	return roundi(actor.global_position.y - area_y - offset)


func _on_interval_elapsed() -> void:
	_drift_intervals = maxi(0, _drift_intervals - 1)


func _show_pose(contracted: bool) -> void:
	sprite.region_rect = SHORT_REGION if contracted else LONG_REGION
	sprite.position = Vector2(0, 1 if contracted else 0)


func _can_hurt_player() -> bool:
	return not _defeated


func _can_stomp(_player: BasePlayer) -> bool:
	return false


func _blocks_enemy_contact() -> bool:
	return false


func _accept_hit(hit: EntityHit) -> bool:
	if hit.maneuver not in [&"fireball", &"star"]:
		return false
	var reward_position := reward_popup_position(true)
	_knocked_out.launch_speed_fraction = _speed
	_knocked_out.fireball_launch = hit.maneuver == &"fireball"
	_knocked_out.star_launch = hit.maneuver == &"star"
	if not state_machine.change_state(_knocked_out):
		return false
	mark_defeated(hit)
	if not is_shutdown and not is_queued_for_deletion():
		award_smack_defeat(200, reward_position)
	return true
