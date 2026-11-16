extends EntityState

const BOUNCING_MOVEMENT := preload("res://scenes/components/motion/bouncing_movement.gd")
const FIRST_WING_FRAME := 2
const HOP_GRAVITY := 28.0 / 256.0 * 3600.0
const HOP_FALL_LIMIT := 180.0
const TRAVEL_SPEED := 30.0

var _bounce: BOUNCING_MOVEMENT
var _motion: MotionValues
var _vertical: VerticalMovementComponent


func enter() -> void:
	var enemy := entity as BaseEnemy
	if _motion == null:
		_motion = MotionValues.new()
		_motion.body = enemy.body
		_motion.base_gravity = HOP_GRAVITY
		_motion.base_max_fall_speed = HOP_FALL_LIMIT
		add_child(_motion)
		_vertical = VerticalMovementComponent.new()
		add_child(_vertical)
	enemy.body.velocity = Vector2.ZERO
	_vertical.reset_fraction()
	_bounce = BOUNCING_MOVEMENT.new(_motion, _vertical, TRAVEL_SPEED, -1.0)
	_update_wings(enemy)


func exit() -> void:
	(entity as BaseEnemy).body.velocity.y = 0.0


func process_physics(delta: float) -> BaseState:
	var enemy := entity as BaseEnemy
	var level := enemy._level
	var player := level.player if is_instance_valid(level) else null
	var area := level.active_area if is_instance_valid(level) else null
	var grid_origin_y := area.global_position.y if is_instance_valid(area) else 0.0
	var excluded_bodies: Array[RID] = []
	if is_instance_valid(player):
		excluded_bodies.append(player.body.get_rid())
	# Normal enemies check terrain before movement. Starman checks after movement.
	_bounce.check_terrain(enemy, excluded_bodies, grid_origin_y)
	_bounce.move(delta, grid_origin_y)
	_update_wings(enemy)
	return null


func _update_wings(enemy: BaseEnemy) -> void:
	var tick := GameHandler.animation_clock.tick_count
	enemy.sprite.frame = FIRST_WING_FRAME + ((tick >> 3) & 1)
	enemy.sprite.flip_h = enemy.body.velocity.x > 0.0
