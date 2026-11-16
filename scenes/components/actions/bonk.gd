class_name BonkAction
extends Node
## Resolves regular ceiling contacts and underside crossings on hidden blocks.

const HIDDEN_BLOCK_PROBE_MASK := 1 << 31

var response_velocity_y: float = NAN
var suppress_ceiling_sound := false
var reaction_ticks_remaining := 0
var shattered_ceiling: Node
var _reaction_tick := -1
var _bonk_recovery_body: CharacterBody2D
var _bonk_recovery_shape: CollisionShape2D
var _bonk_original_shape: RectangleShape2D
var _bonk_original_offset: Vector2
var _bonk_clearance_y: float


func _physics_process(_delta: float) -> void:
	if (
		is_instance_valid(_bonk_recovery_body)
		and _bonk_recovery_body.global_position.y >= _bonk_clearance_y
	):
		_restore_bonk_recovery_shape()
	if Engine.get_physics_frames() != _reaction_tick:
		reaction_ticks_remaining = maxi(0, reaction_ticks_remaining - 1)
		_reaction_tick = Engine.get_physics_frames()


func reset_reaction_gate() -> void:
	reaction_ticks_remaining = 0
	shattered_ceiling = null
	_restore_bonk_recovery_shape()


@export var enabled: bool = false
@export var strength: float = 1.0


func deliver_hidden(player: BasePlayer, previous_position: Vector2) -> bool:
	response_velocity_y = NAN
	suppress_ceiling_sound = false
	if not enabled or player.is_shutdown:
		return false
	var shape := player.collision_shape.shape as RectangleShape2D
	if shape == null or player.body.global_position.y >= previous_position.y:
		return false
	var head := player.get_head_position() + Vector2(0.0001, 0)
	var previous_head := head + previous_position - player.body.global_position
	var query := PhysicsRayQueryParameters2D.create(
		previous_head + Vector2(0, 0.001), head, HIDDEN_BLOCK_PROBE_MASK
	)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := player.body.get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.normal.y < 0.5:
		return false
	var block := _find_block(hit.collider as Node) as HiddenQuestionBlock
	if block == null or not _deliver_block(player, block):
		return false
	player.body.global_position.y += hit.position.y - head.y
	return true


## Returns true for a confirmed underside contact, even on an inert ceiling.
func check_ceiling(
	player: BasePlayer, previous_position: Vector2, intended_motion: Vector2
) -> bool:
	response_velocity_y = NAN
	suppress_ceiling_sound = false
	if player.is_shutdown or not player.body.is_on_ceiling():
		return false
	var head := player.get_head_position() + Vector2(0.001, 0)
	var shape := player.collision_shape.shape as RectangleShape2D
	if shape == null:
		return false
	var body_top := player.collision_shape.global_position.y - shape.size.y / 2.0
	var previous_head := head + previous_position - player.body.global_position
	if head.y < body_top - 0.001:
		# Ordinary standing head crossings are resolved by MarioTerrain.
		return _try_standing_under_block(player, previous_head, intended_motion, body_top)
	var query := PhysicsRayQueryParameters2D.create(
		head + Vector2(0, 0.5),
		head - Vector2(0, 0.5),
		player.body.collision_mask,
		[player.body.get_rid()]
	)
	var space := player.body.get_world_2d().direct_space_state
	if player is Mario and player.form_controller.is_crouched:
		if _try_crouched_block(player, previous_head, intended_motion, query, space):
			return true
		query.from = head + Vector2(0, 0.5)
		query.to = head - Vector2(0, 0.5)
	var hit := space.intersect_ray(query)
	if hit.is_empty() or hit.normal.y < 0.5 or previous_head.y + 0.001 < hit.position.y:
		return false
	if not is_zero_approx(intended_motion.x):
		# The rectangle can catch first and then slide under the brick in X.
		# The center must have reached the same underside on its approach.
		var margin := intended_motion.normalized() * 0.001
		query.from = previous_head - margin
		query.to = previous_head + intended_motion + margin
		var approach := space.intersect_ray(query)
		if approach.is_empty() or approach.normal.y < 0.5 or approach.collider != hit.collider:
			return false
	deliver_at(player, hit.collider)
	return true


func _try_standing_under_block(
	player: BasePlayer, previous_head: Vector2, intended_motion: Vector2, body_top: float
) -> bool:
	var body := player.body
	var center_x := body.global_position.x + 0.001
	var query := PhysicsRayQueryParameters2D.create(
		Vector2(center_x, body_top + 0.5),
		Vector2(center_x, body_top - 0.5),
		body.collision_mask,
		[body.get_rid()]
	)
	var space := body.get_world_2d().direct_space_state
	var underside := space.intersect_ray(query)
	if underside.is_empty() or underside.normal.y < 0.5:
		return false
	# This low ceiling was already directly overhead before the step.
	# Starting outside its footprint remains a side entry.
	query.from = previous_head
	query.to = previous_head - Vector2(0.0, 0.001)
	query.hit_from_inside = true
	var overhead := space.intersect_ray(query)
	if overhead.get("collider") != underside.collider or overhead.get("normal") != Vector2.ZERO:
		return false
	var short_head_offset := body_top - body.global_position.y
	var previous_feet_y := previous_head.y - MarioTerrain.STANDING_HEAD.y
	var intended_feet_y := previous_feet_y + intended_motion.y
	var underside_y: float = underside.position.y - short_head_offset
	if previous_feet_y < underside_y or intended_feet_y > underside_y:
		return false
	if not deliver_at(player, underside.collider):
		return false
	_commit_ceiling_height(player, intended_feet_y, underside_y)
	var marker := shattered_ceiling as StaticBody2D
	if suppress_ceiling_sound and marker != null:
		# The short body already overlaps this brick at the reference height.
		# Retire its solid marker before the next sweep can push Mario down.
		marker.collision_layer = 0
	return true


func _try_crouched_block(
	player: BasePlayer,
	previous_head: Vector2,
	intended_motion: Vector2,
	query: PhysicsRayQueryParameters2D,
	space: PhysicsDirectSpaceState2D
) -> bool:
	var end_y := previous_head.y + intended_motion.y
	query.from.y = previous_head.y
	query.to.y = end_y
	var hit := space.intersect_ray(query)
	if hit.is_empty() or hit.normal.y < 0.5 or _find_block(hit.collider) == null:
		return false
	if previous_head.y - hit.position.y <= 0.001:
		return false
	# Reject a side entry, while allowing a direct crossing at the corner.
	var crossing: float = (hit.position.y - previous_head.y) / intended_motion.y
	var x: float = previous_head.x - 0.001 + intended_motion.x * crossing
	x += signf(intended_motion.x) * 0.001
	query.from = Vector2(x, hit.position.y + 0.001)
	query.to = Vector2(x, hit.position.y - 0.001)
	if space.intersect_ray(query).get("collider") != hit.collider:
		return false
	if not deliver_at(player, hit.collider):
		return false
	# The body sweep stops at its margin. Keep the reference movement into
	# the underside on the reaction tick, capped at two pixels of overlap.
	if suppress_ceiling_sound:
		return true
	var underside_y: float = hit.position.y - MarioTerrain.SHORT_HEAD.y
	_commit_ceiling_height(player, end_y - MarioTerrain.SHORT_HEAD.y, underside_y)
	return true


func _commit_ceiling_height(player: BasePlayer, intended_y: float, underside_y: float) -> void:
	player.body.global_position.y = maxf(intended_y, underside_y - 2.0)
	if suppress_ceiling_sound:
		return
	var recovery := underside_y + player.body.safe_margin - player.body.global_position.y
	if recovery > 0.0:
		# Keep the feet and side width fixed while clearing the underside. The
		# short body otherwise recovers into the struck block or its neighbor.
		_restore_bonk_recovery_shape()
		_bonk_recovery_body = player.body
		_bonk_recovery_shape = player.collision_shape
		_bonk_original_shape = player.collision_shape.shape as RectangleShape2D
		_bonk_original_offset = player.collision_shape.position
		_bonk_clearance_y = underside_y + player.body.safe_margin
		var shortened := _bonk_original_shape.duplicate() as RectangleShape2D
		shortened.size.y -= recovery
		_bonk_recovery_shape.shape = shortened
		_bonk_recovery_shape.position.y += recovery * 0.5


func _restore_bonk_recovery_shape() -> void:
	if is_instance_valid(_bonk_recovery_shape):
		_bonk_recovery_shape.shape = _bonk_original_shape
		_bonk_recovery_shape.position = _bonk_original_offset
	_bonk_recovery_body = null
	_bonk_recovery_shape = null
	_bonk_original_shape = null


## Reference head-probe contacts can occur above the short floor-support body.
func deliver_at(player: BasePlayer, collider: Node) -> bool:
	response_velocity_y = NAN
	suppress_ceiling_sound = false
	if not enabled or player.is_shutdown or collider == null:
		return false
	var target := _find_block(collider)
	if target == null or not _deliver_block(player, target):
		return false
	if suppress_ceiling_sound:
		shattered_ceiling = collider
	return true


func _find_block(collider: Node) -> BaseBlock:
	var ancestor := collider
	while ancestor != null and not ancestor is BaseBlock:
		ancestor = ancestor.get_parent()
	return ancestor as BaseBlock


func _deliver_block(player: BasePlayer, target: BaseBlock) -> bool:
	if (
		reaction_ticks_remaining > 0
		or not target.receive_hit(EntityHit.new(player, &"bonk", Vector2.UP, strength))
	):
		return false
	response_velocity_y = target.bonk_velocity_y
	suppress_ceiling_sound = not is_nan(response_velocity_y) and response_velocity_y < 0.0
	if not is_nan(response_velocity_y):
		response_velocity_y = player.vertical_movement.speed_with_integer(
			player.motion_values, int(response_velocity_y / 60.0)
		)
	reaction_ticks_remaining = 16
	_reaction_tick = Engine.get_physics_frames()
	return true
