class_name MarioClimbState
extends PlayerClimbState
## Mario owns this state's presentation; motion is shared by PlayerClimbState.


const VINE_STEP_OFF_DISTANCE := 4.0


func process_physics(delta: float) -> BaseState:
	var player := get_player()
	if (
		player.climbing.get_surface() is GrowingVine
		and player.climbing.try_step_off_bottom(player, get_movement_axis().x, VINE_STEP_OFF_DISTANCE)
	):
		return move_state
	return super(delta)
