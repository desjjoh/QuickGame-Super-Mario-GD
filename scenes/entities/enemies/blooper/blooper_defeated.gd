extends EnemyDefeatedState


func _apply_launch_pose() -> void:
	(entity as Blooper)._show_pose(true)
	super()
