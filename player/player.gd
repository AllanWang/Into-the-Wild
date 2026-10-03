extends CharacterBody3D

const SPEED: float = 6.0
const ACCELERATION: float = 25.0

@export var grass_displacement_size: float = 0.6

@onready var visual_root: Node3D = $VisualRoot
@onready var visual: MeshInstance3D = $VisualRoot/Visual
@onready var visor: MeshInstance3D = $VisualRoot/Visor
@onready var name_tag: Label3D = $NameTag

var target_position: Vector3 = Vector3.ZERO
var target_velocity: Vector3 = Vector3.ZERO

# Isometric camera basis vectors projected to (X, Z) ground plane
var cam_right: Vector3 = Vector3(0.582123, 0.0, -0.753894).normalized()
var cam_up: Vector3 = Vector3(0.7917, 0.0, 0.6108).normalized()

func _ready() -> void:
	target_position = global_position
	# Setup visual material
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.albedo_color = Color(0.25, 0.6, 1.0)
	visual.material_override = mat

	var visor_mat = StandardMaterial3D.new()
	visor_mat.albedo_color = Color(0.1, 0.12, 0.16)
	visor.material_override = visor_mat

func setup(peer_id: int, info: Dictionary) -> void:
	name = str(peer_id)
	set_multiplayer_authority(peer_id)
	
	var is_local = is_multiplayer_authority()
	
	# Apply distinct color and name
	var color = info.get("color", Color(0.25, 0.6, 1.0))
	if visual and visual.material_override is StandardMaterial3D:
		visual.material_override.albedo_color = color
		
	if name_tag:
		var display_name = info.get("name", "Player %d" % peer_id)
		if is_local:
			display_name += " [YOU]"
		name_tag.text = display_name

func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		var input_x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
		var input_y = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
		
		var move_dir = (cam_right * input_x - cam_up * input_y)
		if move_dir.length() > 1.0:
			move_dir = move_dir.normalized()
			
		var target_vel = move_dir * SPEED
		velocity.x = move_toward(velocity.x, target_vel.x, ACCELERATION * delta)
		velocity.z = move_toward(velocity.z, target_vel.z, ACCELERATION * delta)
		velocity.y = 0.0 # Stay on ground
		
		move_and_slide()
		
		# Rotate visual towards moving direction smoothly
		if move_dir.length() > 0.1:
			var target_angle = atan2(move_dir.x, move_dir.z)
			visual_root.rotation.y = lerp_angle(visual_root.rotation.y, target_angle, 15.0 * delta)
			
		# Broadcast state to other peers
		if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
			sync_state.rpc(global_position, velocity)
	else:
		# Remote player interpolation
		if target_position != Vector3.ZERO:
			global_position = global_position.lerp(target_position, clampf(18.0 * delta, 0.0, 1.0))
			if target_velocity.length() > 0.1:
				var target_angle = atan2(target_velocity.x, target_velocity.z)
				visual_root.rotation.y = lerp_angle(visual_root.rotation.y, target_angle, 15.0 * delta)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func sync_state(pos: Vector3, vel: Vector3) -> void:
	target_position = pos
	target_velocity = vel
