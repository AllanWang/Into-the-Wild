extends CharacterBody3D

const SPEED: float = 6.0
const ACCELERATION: float = 25.0
const DECELERATION_AFTER_DASH: float = 65.0

# Dash tuning parameters
const DASH_SPEED: float = 12.0
const DASH_DURATION: float = 0.21
const DASH_COOLDOWN: float = 2.0
const DASH_BUFFER_WINDOW: float = 0.2

# Attack tuning parameters
const ATTACK_COOLDOWN: float = 0.25
const ATTACK_BUFFER_WINDOW: float = 0.2
const PROJECTILE_SCENE = preload("res://player/projectile.tscn")

@export var grass_displacement_size: float = 0.6

@onready var visual_root: Node3D = $VisualRoot
@onready var visual: MeshInstance3D = $VisualRoot/Visual
@onready var visor: MeshInstance3D = $VisualRoot/Visor
@onready var name_tag: Label3D = $NameTag
@onready var synchronizer: MultiplayerSynchronizer = $MultiplayerSynchronizer

var _move_dir: Vector3 = Vector3.ZERO
var _aim_dir: Vector3 = Vector3.FORWARD
var _target_rotation_y: float = 0.0
var _dash_dir: Vector3 = Vector3.ZERO
var _dash_timer: float = 0.0
var _dash_cooldown_timer: float = 0.0
var _dash_buffer_timer: float = 0.0
var _attack_cooldown_timer: float = 0.0
var _attack_buffer_timer: float = 0.0
var is_dashing: bool = false

func _ready() -> void:
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
	if synchronizer:
		synchronizer.set_multiplayer_authority(peer_id)
	
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

func _process(delta: float) -> void:
	if visual_root and is_multiplayer_authority():
		# Project mouse cursor onto ground plane at character altitude (Y = global_position.y)
		# Only update aim direction if the window is currently focused by the OS
		var cam = get_viewport().get_camera_3d()
		if cam and DisplayServer.window_is_focused():
			var mouse_pos = get_viewport().get_mouse_position()
			var ray_origin = cam.project_ray_origin(mouse_pos)
			var ray_normal = cam.project_ray_normal(mouse_pos)
			var ground_plane = Plane(Vector3.UP, global_position.y)
			var hit_pos = ground_plane.intersects_ray(ray_origin, ray_normal)
			if hit_pos != null:
				var look_vec = (hit_pos as Vector3) - global_position
				look_vec.y = 0.0
				# Deadzone check (0.2m radius) to prevent jitter when cursor is right over player
				if look_vec.length_squared() > 0.04:
					_aim_dir = look_vec.normalized()

		# Continuously face mouse cursor direction at all times
		if _aim_dir.length() > 0.1:
			_target_rotation_y = atan2(_aim_dir.x, _aim_dir.z)
			visual_root.rotation.y = lerp_angle(visual_root.rotation.y, _target_rotation_y, 25.0 * delta)

	# Procedural squash & stretch visual recovery
	if visual_root:
		visual_root.scale = visual_root.scale.lerp(Vector3.ONE, 12.0 * delta)

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	# Tick cooldown and buffer timers
	if _dash_cooldown_timer > 0.0:
		_dash_cooldown_timer = maxf(0.0, _dash_cooldown_timer - delta)

	if _dash_buffer_timer > 0.0:
		_dash_buffer_timer = maxf(0.0, _dash_buffer_timer - delta)

	if _attack_cooldown_timer > 0.0:
		_attack_cooldown_timer = maxf(0.0, _attack_cooldown_timer - delta)

	if _attack_buffer_timer > 0.0:
		_attack_buffer_timer = maxf(0.0, _attack_buffer_timer - delta)

	# Action buffering: capture button presses even during cooldown/dash (only if window is focused)
	if DisplayServer.window_is_focused():
		if Input.is_action_just_pressed("dash"):
			_dash_buffer_timer = DASH_BUFFER_WINDOW

		if Input.is_action_just_pressed("attack"):
			_attack_buffer_timer = ATTACK_BUFFER_WINDOW

	var input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	# Derive ground movement vectors dynamically from the active camera
	var cam = get_viewport().get_camera_3d()
	_move_dir = Vector3.ZERO
	if cam:
		var cam_right = cam.global_basis.x
		var cam_forward = -cam.global_basis.z
		var ground_right = Vector3(cam_right.x, 0.0, cam_right.z).normalized()
		var ground_forward = Vector3(cam_forward.x, 0.0, cam_forward.z).normalized()
		# input_dir.x: +1 is Right (D), -1 is Left (A)
		# input_dir.y: -1 is Up (W), +1 is Down (S)
		_move_dir = ground_right * input_dir.x - ground_forward * input_dir.y
	else:
		_move_dir = Vector3(input_dir.x, 0.0, input_dir.y)
		
	if _move_dir.length() > 1.0:
		_move_dir = _move_dir.normalized()

	# Trigger dash when buffered input is active and cooldown has elapsed
	if _dash_buffer_timer > 0.0 and _dash_cooldown_timer <= 0.0 and not is_dashing:
		_dash_buffer_timer = 0.0
		_dash_cooldown_timer = DASH_COOLDOWN
		_dash_timer = DASH_DURATION
		is_dashing = true
		
		# Hybrid Dash: input direction if moving, otherwise current aim direction
		if _move_dir.length() > 0.1:
			_dash_dir = _move_dir
		else:
			_dash_dir = _aim_dir

		_play_dash_effects.rpc()

	# Combat execution: Paradigm A (shooting locked while dashing, buffered clicks fire on exit)
	if _attack_buffer_timer > 0.0 and _attack_cooldown_timer <= 0.0 and not is_dashing:
		_attack_buffer_timer = 0.0
		_attack_cooldown_timer = ATTACK_COOLDOWN
		_execute_attack()

	# Movement execution
	if is_dashing:
		_dash_timer -= delta
		if _dash_timer <= 0.0:
			is_dashing = false
		velocity.x = _dash_dir.x * DASH_SPEED
		velocity.z = _dash_dir.z * DASH_SPEED
	else:
		var target_vel = _move_dir * SPEED
		var accel = DECELERATION_AFTER_DASH if velocity.length() > SPEED else ACCELERATION
		velocity.x = move_toward(velocity.x, target_vel.x, accel * delta)
		velocity.z = move_toward(velocity.z, target_vel.z, accel * delta)
		
	velocity.y = 0.0 # Stay on ground
	
	move_and_slide()

func _execute_attack() -> void:
	var spawn_pos = global_position + Vector3(0.0, 0.35, 0.0) + _aim_dir * 0.4
	_spawn_projectile.rpc(get_multiplayer_authority(), spawn_pos, _aim_dir)

@rpc("call_local", "reliable")
func _spawn_projectile(p_shooter_id: int, p_pos: Vector3, p_dir: Vector3) -> void:
	var proj = PROJECTILE_SCENE.instantiate()
	get_parent().add_child(proj)
	proj.setup(p_shooter_id, p_pos, p_dir)

@rpc("call_local", "reliable")
func _play_dash_effects() -> void:
	if visual_root:
		visual_root.scale = Vector3(0.75, 0.8, 1.35)

