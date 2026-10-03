extends CharacterBody2D

const SPEED: float = 260.0

@onready var visual: ColorRect = $Visual
@onready var name_tag: Label = $NameTag
@onready var camera_2d: Camera2D = $Camera2D

var target_position: Vector2 = Vector2.ZERO
var target_velocity: Vector2 = Vector2.ZERO

func _ready() -> void:
	target_position = global_position

func setup(peer_id: int, info: Dictionary) -> void:
	name = str(peer_id)
	set_multiplayer_authority(peer_id)
	
	var is_local = is_multiplayer_authority()
	camera_2d.enabled = is_local
	
	# Apply distinct color and name
	if visual:
		visual.color = info.get("color", Color(0.25, 0.6, 1.0))
	if name_tag:
		var display_name = info.get("name", "Player %d" % peer_id)
		if is_local:
			display_name += " [YOU]"
		name_tag.text = display_name

func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		var input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		velocity = input_dir * SPEED
		move_and_slide()
		
		# Broadcast state to all other peers via RPC
		if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
			sync_state.rpc(global_position, velocity)
	else:
		# Smoothly interpolate position for remote players
		if target_position != Vector2.ZERO:
			global_position = global_position.lerp(target_position, clampf(18.0 * delta, 0.0, 1.0))

@rpc("any_peer", "call_remote", "unreliable_ordered")
func sync_state(pos: Vector2, vel: Vector2) -> void:
	target_position = pos
	target_velocity = vel
