class_name SwimmingCheepCheep
extends BaseEnemy
## Swimming variants use signed displacement on the NES 1/256-pixel grid.

const RED_ART := preload("res://assets/enemies/red-cheep.png")
const BODY_OFFSET := Vector2(8, 16)
const VERTICAL_STEP := 0x20
const BOB_RANGE := 15
const BOB_SLOT := 2

@export var red := false
var initial_bob_down := false

@onready var _knocked_out: EnemyDefeatedState = $StateMachine/KnockedOut

var _slot := -1
var _origin_y := 0.0
var _origin_raw_y := 0
var _x_fraction := 0
var _y_fraction := 0
var _bob_direction := -1


func _ready() -> void:
	if red:
		sprite.texture = RED_ART
	super()
	_origin_y = body.global_position.y
	_bob_direction = 1 if initial_bob_down else -1
	if _level != null:
		_slot = _level.spawn_registry.get_slot(&"enemy", self)
		_origin_raw_y = roundi(_level.active_area.to_local(body.global_position).y - BODY_OFFSET.y) & 0xff
	_show_swim_pose()


func _physics_process(delta: float) -> void:
	if _defeated:
		super(delta)
		return
	_show_swim_pose()
	super(delta)
	if _defeated or is_shutdown or gameplay_suspended or activity_suspended:
		return
	var before := body.position
	_swim_tick()
	# The reference draws the live pose before advancing the body.
	sprite.position += before - body.position


func _swim_tick() -> void:
	var x_units := _x_fraction - (0x80 if red else 0x40)
	_x_fraction = x_units & 0xff
	body.position.x += x_units >> 8
	if _slot < BOB_SLOT:
		return
	var y_units := _y_fraction + _bob_direction * VERTICAL_STEP
	_y_fraction = y_units & 0xff
	body.position.y += y_units >> 8
	var height := body.global_position.y - _origin_y
	if absf(height) >= BOB_RANGE:
		_bob_direction = -1 if height > 0.0 else 1


func _show_swim_pose() -> void:
	sprite.frame = int((GameHandler.animation_clock.tick_count & 8) == 0)
	sprite.position = Vector2(0, 1)


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
	_knocked_out.launch_speed_fraction = _origin_raw_y
	_knocked_out.launch_position_fraction = _y_fraction
	_knocked_out.fireball_launch = hit.maneuver == &"fireball"
	_knocked_out.star_launch = hit.maneuver == &"star"
	if not state_machine.change_state(_knocked_out):
		return false
	mark_defeated(hit)
	if not is_shutdown and not is_queued_for_deletion():
		award_smack_defeat(200, reward_position)
	return true
