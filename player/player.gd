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
var _has_synced: bool = false
var _last_synced_pos: Vector3 = Vector3.ZERO
var _last_synced_vel: Vector3 = Vector3.ZERO
var _sync_timer: float = 0.0

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
		var input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		
		# Derive ground movement vectors dynamically from the active camera
		var cam = get_viewport().get_camera_3d()
		var move_dir := Vector3.ZERO
		if cam:
			var cam_right = cam.global_basis.x
			var cam_forward = -cam.global_basis.z
			var ground_right = Vector3(cam_right.x, 0.0, cam_right.z).normalized()
			var ground_forward = Vector3(cam_forward.x, 0.0, cam_forward.z).normalized()
			# input_dir.x: +1 is Right (D), -1 is Left (A)
			# input_dir.y: -1 is Up (W), +1 is Down (S)
			move_dir = ground_right * input_dir.x - ground_forward * input_dir.y
		else:
			move_dir = Vector3(input_dir.x, 0.0, input_dir.y)
			
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
			
		# Broadcast state to other peers once all players have loaded the game scene
		if NetworkManager.is_match_ready and multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
			_sync_timer += delta
			var moved = not global_position.is_equal_approx(_last_synced_pos) or not velocity.is_equal_approx(_last_synced_vel)
			if moved or _sync_timer >= 0.2:
				_sync_timer = 0.0
				_last_synced_pos = global_position
				_last_synced_vel = velocity
				sync_state.rpc(global_position, velocity)
	else:
		# Remote player interpolation
		if _has_synced:
			global_position = global_position.lerp(target_position, clampf(18.0 * delta, 0.0, 1.0))
			if target_velocity.length() > 0.1:
				var target_angle = atan2(target_velocity.x, target_velocity.z)
				visual_root.rotation.y = lerp_angle(visual_root.rotation.y, target_angle, 15.0 * delta)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func sync_state(pos: Vector3, vel: Vector3) -> void:
	target_position = pos
	target_velocity = vel
	_has_synced = true

