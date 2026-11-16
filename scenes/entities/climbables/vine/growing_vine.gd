class_name GrowingVine
extends BaseClimbable

const ART := preload("res://assets/palettes/overworld/misc/vine.png")
const DRAW_ORDER := preload("res://scenes/components/presentation/draw_order.gd")
const REVEAL_HEIGHT := 8
const CLIMB_HEIGHT := 32
const FULL_HEIGHT := 96
const TILE_SIZE := 16

var growth := 0
var _last_growth_step := -1
var _art: Texture2D


func _ready() -> void:
	_art = resolve_texture(ART)
	DRAW_ORDER.apply(self, DRAW_ORDER.BEHIND_WORLD)
	super()
	set_physics_process(growth < FULL_HEIGHT and not activity_suspended)
	_update_growth_pose()


func set_activity_suspended(suspended: bool) -> void:
	super(suspended)
	if not suspended and not is_shutdown and not gameplay_suspended:
		set_physics_process(growth < FULL_HEIGHT)


func start_growth() -> void:
	SoundHandler.play_reward(&"vine_grow")
	_grow(GameHandler.animation_clock.tick_count)


func _physics_process(_delta: float) -> void:
	_grow(GameHandler.animation_clock.tick_count)


func _grow(tick: int) -> void:
	if tick == _last_growth_step or (tick & 2) == 0 or growth >= FULL_HEIGHT:
		return
	_last_growth_step = tick
	growth += 1
	_update_growth_pose()
	if growth == FULL_HEIGHT:
		set_physics_process(false)


func _update_growth_pose() -> void:
	climb_top.position.y = -growth
	visible = growth >= REVEAL_HEIGHT
	queue_redraw()


func is_available() -> bool:
	return growth >= CLIMB_HEIGHT and super()


func attachment_fraction(player: BasePlayer, from_feet: Vector2, to_feet: Vector2) -> float:
	if not is_available() or player.is_dead or player.is_shutdown:
		return -1.0
	# The NES publishes climbable cells as its growing tip enters them.
	var first_row := global_position.y + floorf((4.0 - growth) / TILE_SIZE) * TILE_SIZE
	var last_row := global_position.y - TILE_SIZE
	var center := climb_top.global_position.x
	var low := Vector2(center - attachment_tolerance, first_row)
	var high := Vector2(center + attachment_tolerance - 0.001, last_row - 0.001)
	var earliest := INF
	for height in player.get_side_probe_heights():
		for side in [-6.0, 5.0]:
			var offset := Vector2(side, height)
			var fraction := _sweep_fraction(from_feet + offset, to_feet + offset, low, high)
			if fraction >= 0.0:
				earliest = minf(earliest, fraction)
	return earliest if is_finite(earliest) else -1.0


func _draw() -> void:
	if growth < REVEAL_HEIGHT:
		return
	for distance in range(0, growth, TILE_SIZE):
		var height := mini(TILE_SIZE, growth - distance)
		draw_texture_rect_region(
			_art,
			Rect2(0, 1 - growth + distance, TILE_SIZE, height),
			Rect2(0 if distance == 0 else TILE_SIZE, 0, TILE_SIZE, height)
		)
