extends BaseLevel
## Two placed actors for isolated flight/contact checks; the stream has its own sandbox.


func _ready() -> void:
	super()
	for actor in world_objects.get_children():
		if actor is FlyingCheepCheep:
			if not try_claim_spawn_slot(&"enemy", actor):
				actor.queue_free()
