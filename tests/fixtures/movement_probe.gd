extends Mario
## Count actual body integration calls without changing production motion.
var body_steps: int = 0


func move_body(gravity_after_motion: bool = false) -> bool:
	body_steps += 1
	return super(gravity_after_motion)
