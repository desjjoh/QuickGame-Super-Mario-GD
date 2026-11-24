extends EnemyDefeatedState
## Flying fish use the upside-down base frame after the held hit pose.


func _apply_launch_pose() -> void:
	entity.sprite.position = Vector2(0, 1)
	entity.sprite.frame = 0
	entity.sprite.flip_v = true
	entity.sprite.flip_h = launch_direction > 0.0
