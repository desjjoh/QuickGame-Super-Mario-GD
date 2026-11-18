@tool
extends RefCounted

const COLOR := Color(0.35, 0.85, 1.0, 0.75)
const SURFACE_COLOR := Color(0.35, 0.85, 1.0, 0.4)


static func draw_path(item: Node2D, start: Vector2, finish: Vector2, width: float) -> void:
	var right_offset := Vector2(width, 0)
	if is_equal_approx(start.y, finish.y):
		var left_edge := Vector2(minf(start.x, finish.x), start.y)
		var right_edge := Vector2(maxf(start.x, finish.x) + width, start.y)
		item.draw_line(left_edge, right_edge, COLOR, 1.0)
	else:
		item.draw_line(start, finish, COLOR, 1.0)
		item.draw_line(start + right_offset, finish + right_offset, COLOR, 1.0)
	draw_surface(item, start, width)
	draw_surface(item, finish, width)


static func draw_surface(item: Node2D, origin: Vector2, width: float) -> void:
	var right_edge := origin + Vector2(width, 0)
	var tick := Vector2(0, 2)
	item.draw_line(origin, right_edge, SURFACE_COLOR, 1.0)
	item.draw_line(origin - tick, origin + tick, COLOR, 1.0)
	item.draw_line(right_edge - tick, right_edge + tick, COLOR, 1.0)
