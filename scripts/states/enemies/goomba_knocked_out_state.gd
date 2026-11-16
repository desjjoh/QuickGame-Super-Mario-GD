extends EnemyDefeatedState
## Goomba's block defeat moves the body before revealing the launch pose.

const LAUNCH_SPRITE_Y := 2.0

var block_launch := false
var _launch_presentation := (
	preload("res://scenes/components/presentation/block_launch_presentation.gd").new()
)


func enter() -> void:
	var was_flipped := entity.sprite.flip_v
	super.enter()
	if not block_launch:
		return

	_launch_presentation.capture(entity.sprite)
	var body := (entity as BaseEnemy).body
	# Two reference position corrections, followed by the first launch step.
	body.position.y -= 4.0
	super.process_physics(1.0 / 60.0)
	entity.sprite.flip_v = was_flipped
	_launch_presentation.hold_after_motion(entity.sprite, body)


func _apply_launch_pose() -> void:
	super()
	if fireball_launch:
		entity.sprite.position.y = LAUNCH_SPRITE_Y
	elif star_launch:
		entity.sprite.position = Vector2(_star_pose.original_position.x, LAUNCH_SPRITE_Y)
	if not block_launch:
		entity.sprite.frame = 0


func process_physics(delta: float) -> BaseState:
	if _launch_presentation.is_holding():
		if _launch_presentation.is_hit_tick():
			return null
		entity.sprite.frame = 0
		entity.sprite.flip_v = true
		# The reference inverted artwork sits two pixels below the body's launch lift.
		_launch_presentation.reveal(
			entity.sprite, Vector2(_launch_presentation.original_position.x, LAUNCH_SPRITE_Y)
		)
	return super.process_physics(delta)


func exit() -> void:
	super.exit()
	if _launch_presentation.is_holding():
		_launch_presentation.cancel(entity.sprite)
	elif block_launch:
		entity.sprite.position = _launch_presentation.original_position
