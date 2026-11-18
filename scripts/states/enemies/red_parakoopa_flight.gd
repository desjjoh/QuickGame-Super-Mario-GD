extends EntityState

const OSCILLATION := preload("res://scenes/entities/enemies/koopa/red_parakoopa_motion.gd")
const FIRST_WING_FRAME := 2

var _motion: OSCILLATION
var _origin_y: float
var _center_y: int


func enter() -> void:
	var enemy := entity as BaseEnemy
	enemy.body.velocity = Vector2.ZERO
	_origin_y = enemy.body.global_position.y
	var ancestor := enemy.get_parent()
	while ancestor != null and not ancestor is BaseLevelArea:
		ancestor = ancestor.get_parent()
	var area := ancestor as BaseLevelArea
	var area_y := area.global_position.y if area != null else 0.0
	_center_y = OSCILLATION.center_for(_origin_y - area_y)
	_motion = OSCILLATION.new()
	_update_wings(GameHandler.animation_clock.tick_count)


func process_physics(_delta: float) -> BaseState:
	var body := (entity as BaseEnemy).body
	var y := roundi(body.global_position.y - _origin_y)
	var tick := GameHandler.animation_clock.tick_count
	body.global_position.y += _motion.step(y, 0, _center_y, tick)
	_update_wings(tick)
	return null


func _update_wings(tick: int) -> void:
	entity.sprite.frame = FIRST_WING_FRAME + ((tick >> 3) & 1)
