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
var _growth_tick_origin := 0
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


func start_growth(align_growth_to_spawn: bool = false) -> void:
	if align_growth_to_spawn:
		_growth_tick_origin = GameHandler.animation_clock.tick_count
	SoundHandler.play_reward(&"vine_grow")
	_grow(GameHandler.animation_clock.tick_count - _growth_tick_origin)


func _physics_process(_delta: float) -> void:
	_grow(GameHandler.animation_clock.tick_count - _growth_tick_origin)


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


func requires_live_contact() -> bool:
	return true


func attachment_y(feet_y: float) -> float:
	return feet_y


func attachment_fraction(player: BasePlayer, _from_feet: Vector2, to_feet: Vector2) -> float:
	if not is_available() or player.is_dead or player.is_shutdown:
		return -1.0
	if not has_nes_side_alignment(to_feet.x):
		return -1.0
	# The NES stamps a climbable tile using the tip position plus 16 pixels.
	var bottom := global_position.y
	var top := bottom + floorf((TILE_SIZE - growth) / float(TILE_SIZE)) * TILE_SIZE
	for height in player.get_side_probe_heights():
		var probe_y := roundf(to_feet.y) + height
		if probe_y >= top and probe_y < bottom:
			return 1.0
	return -1.0


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
