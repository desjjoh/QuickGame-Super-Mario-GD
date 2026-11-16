@tool
class_name AreaEndpoint
extends Marker2D
## Feet position after arrival; optional emergence ends exactly here.

enum ExitDirection { UP, DOWN, LEFT, RIGHT }

@export var animate_exit: bool = false
## Reference upward emergence travels 0xf0 -> 0x90: 96 pixels at 60 pixels/second.
@export_range(1.0, 256.0, 1.0) var exit_distance: float = 96.0
@export var endpoint_id: StringName = &""
@export var exit_direction: ExitDirection = ExitDirection.UP
## Horizontal screen position of Mario's sprite. -1 uses default camera framing.
@export_range(-1.0, 256.0, 1.0) var camera_sprite_x: float = -1.0
## Physics ticks before manual control resumes.
@export_range(0, 120) var control_lock_ticks := BasePlayer.ARRIVAL_CONTROL_TICKS
## Apply the re-entry spawn cutoff before activating the destination area.
@export var skip_passed_enemies: bool = false


func get_endpoint_id() -> StringName:
	return endpoint_id if endpoint_id != &"" else StringName(name)


func get_exit_vector() -> Vector2:
	return [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT][exit_direction]
