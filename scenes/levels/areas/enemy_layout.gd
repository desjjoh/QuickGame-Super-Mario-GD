@tool
extends TileMapLayer
## Shows where painted NES group markers activate and place their members.

const GROUP_SIZES := {
	&"goomba_pair_spawner": 2,
	&"goomba_triplet_spawner": 3,
	&"green_koopa_pair_spawner": 2,
}
const MEMBER_SPACING := 24.0
const TRIGGER_COLOR := Color(1.0, 0.75, 0.30)
const SPAWN_COLOR := Color(0.35, 0.9, 1.0)

@export var show_group_spawn_preview := true:
	set(value):
		show_group_spawn_preview = value
		queue_redraw()


func _ready() -> void:
	if Engine.is_editor_hint() and not changed.is_connected(queue_redraw):
		changed.connect(queue_redraw, CONNECT_DEFERRED)


func _draw() -> void:
	if not Engine.is_editor_hint() or not show_group_spawn_preview or tile_set == null:
		return
	if tile_set.get_custom_data_layer_by_name("entity_id") < 0:
		return
	var tile_size := Vector2(tile_set.tile_size)
	for cell in get_used_cells():
		var tile := get_cell_tile_data(cell)
		if tile == null:
			continue
		var count: int = GROUP_SIZES.get(StringName(tile.get_custom_data("entity_id")), 0)
		if count > 0:
			_draw_group(map_to_local(cell) - tile_size / 2.0, tile_size, count)


func _draw_group(trigger: Vector2, tile_size: Vector2, count: int) -> void:
	# The first member uses the screen's right edge at the earliest possible trigger.
	var origin := trigger - Vector2(BaseLevelArea.ENEMY_SPAWN_LOOKAHEAD, 0)
	var line_offset := Vector2(tile_size.x / 2.0, -2.0)
	draw_dashed_line(origin + line_offset, trigger + line_offset, TRIGGER_COLOR, 1.0, 3.0)
	draw_rect(Rect2(trigger, tile_size), TRIGGER_COLOR, false, 1.0)
	draw_string(
		ThemeDB.fallback_font, trigger + Vector2(0, -5), "Trigger",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 8, TRIGGER_COLOR
	)
	for index in range(count):
		var member_origin := origin + Vector2(index * MEMBER_SPACING, 0)
		var slot := Rect2(member_origin, tile_size).grow(-2.0)
		draw_rect(slot, Color(SPAWN_COLOR, 0.15))
		draw_rect(slot, SPAWN_COLOR, false, 1.0)
		draw_circle(slot.get_center(), 1.2, SPAWN_COLOR)
