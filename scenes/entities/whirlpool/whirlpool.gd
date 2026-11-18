@tool
class_name Whirlpool
extends Node2D
## Place at the left edge of the current. The pull spans the full water column.

const GROUP := &"whirlpools"
const PLAYER_CENTER_OFFSET := 8
const DOWN_FORCE := 0x10
const DOWN_LIMIT := 1

@export_range(1, 1024, 1, "or_greater") var width := 96:
	set(value):
		width = value
		queue_redraw()


func _ready() -> void:
	add_to_group(GROUP)


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	const TILE_SIZE := 16.0
	var guide := Color(0.25, 0.85, 1.0, 0.9)
	var center := width * 0.5
	var center_tile_right := (floorf(center / TILE_SIZE) + 1.0) * TILE_SIZE
	# The inclusive cutoff belongs to the final tile shown by the guide.
	var last_tile_right := (floorf(width / TILE_SIZE) + 1.0) * TILE_SIZE
	draw_line(Vector2.ZERO, Vector2(last_tile_right, 0), guide, 2.0)
	for x: float in [0.0, center, last_tile_right]:
		draw_line(Vector2(x, -6), Vector2(x, 6), guide, 2.0)
	if center_tile_right < last_tile_right:
		draw_line(Vector2(center_tile_right, -6), Vector2(center_tile_right, 6), guide, 2.0)


func contains_player_x(body_x: float) -> bool:
	var x := _player_origin_x(body_x)
	return x >= 0 and x <= width


func horizontal_step(body_x: float, tick: int, right_clear: bool) -> int:
	if (tick & 1) == 0:
		return 0
	if _player_origin_x(body_x) > (width >> 1):
		return -1
	return int(right_clear)


func pull(player: Mario, tick: int, right_clear: bool) -> void:
	var body := player.body
	var dx := horizontal_step(body.global_position.x, tick, right_clear)
	body.global_position.x += dx
	player.camera_correction_x += dx
	player.vertical_movement.apply_extra_step(player.motion_values, DOWN_FORCE, DOWN_LIMIT)


func _player_origin_x(body_x: float) -> int:
	return floori(body_x - global_position.x) - PLAYER_CENTER_OFFSET
