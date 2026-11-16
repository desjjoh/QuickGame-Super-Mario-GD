class_name Starman
extends PowerUp

const DELAYED_REWARD := preload("res://scenes/components/interactions/delayed_reward.gd")
const RISING_REWARD_POPUP := preload("res://scenes/components/presentation/rising_reward_popup.gd")
const BOUNCING_MOVEMENT := preload("res://scenes/components/motion/bouncing_movement.gd")
const TRAVEL_SPEED := 60.0

var _bounce: BOUNCING_MOVEMENT

@onready var _motion: MotionValues = $Motion


func _ready() -> void:
	super()
	_bounce = BOUNCING_MOVEMENT.new(_motion, $Motion/VerticalMovement, TRAVEL_SPEED, 1.0)
	$Presentation/PaletteAnimation.set_enabled(true)


func _emergence_clearance() -> float:
	return 1.0


func _advance_available(delta: float) -> void:
	var player := _level.player if is_instance_valid(_level) else null
	var excluded_bodies: Array[RID] = []
	if is_instance_valid(player):
		excluded_bodies.append(player.body.get_rid())
	_bounce.advance(self, delta, excluded_bodies)


func _grant_reward(player: BasePlayer) -> void:
	var mario := player as Mario
	if mario != null:
		mario.starman.begin()
	RISING_REWARD_POPUP.show_score(get_parent(), 1000, reward_popup_position())
	DELAYED_REWARD.schedule(self, GameHandler.add_score.bind(1000), 5)
	SoundHandler.play_reward(&"power_up_grab")
