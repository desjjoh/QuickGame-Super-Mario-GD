class_name SwimBubbleEmitter
extends Node2D
## Three reusable world-space sprites, driven by the underwater bubble routine.

const BUBBLE := preload("res://assets/items/bubble.png")
const DRAW_ORDER := preload("res://scenes/components/presentation/draw_order.gd")
const SLOT_COUNT := 3
const HUD_CUTOFF := 33.0  # NES object Y $20 plus the OAM draw offset.
const RIGHT_OFFSET := Vector2(1, -23)
const LEFT_OFFSET := Vector2(-8, -23)

var player: BasePlayer
var area: BaseLevelArea
var _slots: Array[Sprite2D] = []
var _rise_fractions := PackedInt32Array([0, 0, 0])
var _spawn_ticks := 0
# The first four bytes of the NES generator are enough for all three slots.
var _random_register := 0xa5000000


func _ready() -> void:
	for index in range(SLOT_COUNT):
		var bubble := Sprite2D.new()
		bubble.name = "Bubble%d" % index
		bubble.texture = BUBBLE
		bubble.centered = false
		bubble.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		bubble.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		bubble.hide()
		DRAW_ORDER.apply(bubble, DRAW_ORDER.REWARD_EFFECT)
		add_child(bubble)
		_slots.append(bubble)


func _physics_process(_delta: float) -> void:
	if (
		not is_instance_valid(player)
		or not is_instance_valid(area)
		or player.is_dead
		or player.is_shutdown
		or player.gameplay_suspended
		or player.activity_suspended
		or not area.is_active
		or area.actors_suspended
	):
		return
	# Bubbles already in the water keep rising while Mario enters a pipe.
	var can_emit := (
		player.arrival_control_ticks_remaining <= 0
		and player.state_machine.current_state is MarioSwimState
	)
	if can_emit or _slots.any(func(slot: Sprite2D) -> bool: return slot.visible):
		_advance(can_emit)


func _advance(can_emit: bool) -> void:
	var feedback := ((_random_register >> 25) ^ (_random_register >> 17)) & 1
	_random_register = (_random_register >> 1) | (feedback << 31)
	if can_emit:
		_spawn_ticks = maxi(_spawn_ticks - 1, 0)
	var area_origin := area.global_position
	for index in range(SLOT_COUNT - 1, -1, -1):
		var bit := (_random_register >> ((SLOT_COUNT - 1 - index) * 8)) & 1
		var bubble := _slots[index]
		if not bubble.visible:
			if not can_emit or _spawn_ticks != 0:
				continue
			var feet := player.body.global_position - area_origin
			var origin := area_origin + Vector2(floorf(feet.x), roundf(feet.y))
			bubble.global_position = origin + (LEFT_OFFSET if player.sprite.flip_h else RIGHT_OFFSET)
			_spawn_ticks = 64 if bit == 0 else 32
			bubble.show()
		var fraction := _rise_fractions[index] - (0xff if bit == 0 else 0x50)
		_rise_fractions[index] = fraction & 0xff
		if fraction < 0:
			bubble.global_position.y -= 1.0
		if bubble.global_position.y - area_origin.y < HUD_CUTOFF:
			bubble.hide()
