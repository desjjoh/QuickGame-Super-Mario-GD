class_name SubmergedCheepCheep
extends SwimmingCheepCheep
## The original bridge course's below-screen swimming enemy entry.


func _physics_process(delta: float) -> void:
	if is_shutdown or gameplay_suspended or activity_suspended or is_queued_for_deletion():
		return
	var origin_y := body.global_position.y - _level.active_area.global_position.y - BODY_OFFSET.y
	if origin_y >= 256.0:
		remove_offscreen()
		return
	super(delta)


func is_outside_vertical_cleanup(_top: float, _bottom: float) -> bool:
	# The NES draw step retires at the next vertical page, rather than a buffer.
	return false
