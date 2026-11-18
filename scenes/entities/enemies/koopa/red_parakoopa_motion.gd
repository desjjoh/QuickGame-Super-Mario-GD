@tool
extends "res://scenes/components/motion/vertical_oscillation.gd"
## Flight shared by the Red Parakoopa and its editor preview.


func _init() -> void:
	super(3, 6, 2)


static func center_for(body_area_y: float) -> int:
	var reference_y := posmod(roundi(body_area_y) - 16, 256)
	return 48 if reference_y < 128 else -32


func preview_span(body_area_y: float) -> Vector2i:
	var center := center_for(body_area_y)
	var displacement := 0
	var span := Vector2i.ZERO
	# Covers a full oscillation from rest for either center.
	for tick in range(1024):
		displacement += step(displacement, 0, center, tick)
		span = Vector2i(mini(span.x, displacement), maxi(span.y, displacement))
	return span
