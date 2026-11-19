class_name EnemyHazardEffect
extends Node3D

## Pooled multi-mode Enemy Projectile & Ground Hazard node:
## - ENEMY_ORB (0): Enemy ranged bolt / sniper lance / boss volley orb
## - LOB_POOL (1): Arcing mortar globule -> crimson-bordered bubbling corrosive pool
## - GROUND_QUAKE (2): Outward sweeping danger telegraph -> eruption with 3D rock/danger spikes
## - DONUT_AFTERSHOCK (3): Outer-ring danger eruption with safe inner eye & 3D spikes
## - SNIPER_SIGHTLINE (4): Tracking/locked laser line warning before sniper/dash/charge fires

enum HazardMode {
	ENEMY_ORB = 0,
	LOB_POOL = 1,
	GROUND_QUAKE = 2,
	DONUT_AFTERSHOCK = 3,
	SNIPER_SIGHTLINE = 4,
	CLOCK_SECTOR = 5,
	CLOCK_SAFE_CIRCLE = 6
}

const HAZARD_SHADER: Shader = preload("res://shaders/EnemyHazard.gdshader")
const SPIKE_COUNT: int = 8

var _active: bool = false
var _mode: int = HazardMode.ENEMY_ORB
var _players_root: Node3D = null

var _origin_pos: Vector3 = Vector3.ZERO
var _target_pos: Vector3 = Vector3.ZERO
var _dir: Vector3 = Vector3.FORWARD
var _speed: float = 12.0
var _max_range: float = 18.0
var _traveled: float = 0.0

var _radius: float = 2.5
var _inner_radius: float = 0.0
var _damage: float = 8.0
var _telegraph_time: float = 0.75
var _active_duration: float = 4.5
var _elapsed: float = 0.0
var _detonated: bool = false
var _tick_timer: float = 0.0
var _shake_amount: float = 0.0
var _safe_angle: float = 0.0
var _safe_half_width: float = 0.567
var _safe_world_pos: Vector3 = Vector3.ZERO
var _safe_world_radius: float = 4.2
var _is_lance_orb: bool = false

var outer_ring: MeshInstance3D = null
var inner_ring: MeshInstance3D = null
var fill_disc: MeshInstance3D = null
var orb_mesh: MeshInstance3D = null
var beam_mesh: MeshInstance3D = null
var spike_ring_root: Node3D = null
var _spike_meshes: Array[MeshInstance3D] = []

var _ring_mat: StandardMaterial3D = null
var _hazard_mat: ShaderMaterial = null
var _orb_mat: StandardMaterial3D = null

var _ray_query: PhysicsRayQueryParameters3D = null

static var _shared_torus: TorusMesh = null
static var _shared_hazard_plane: PlaneMesh = null
static var _shared_orb: SphereMesh = null
static var _shared_lance: BoxMesh = null
static var _shared_beam: BoxMesh = null
static var _shared_spike_mesh: CylinderMesh = null


static func _ensure_shared() -> void:
	if _shared_torus != null:
		return

	_shared_torus = TorusMesh.new()
	_shared_torus.inner_radius = 0.90
	_shared_torus.outer_radius = 1.0
	_shared_torus.rings = 28
	_shared_torus.ring_segments = 8

	_shared_hazard_plane = PlaneMesh.new()
	_shared_hazard_plane.size = Vector2(2.0, 2.0)

	_shared_orb = SphereMesh.new()
	_shared_orb.radius = 0.24
	_shared_orb.height = 0.48
	_shared_orb.radial_segments = 14
	_shared_orb.rings = 8

	_shared_lance = BoxMesh.new()
	_shared_lance.size = Vector3(0.18, 0.18, 1.35)

	_shared_beam = BoxMesh.new()
	_shared_beam.size = Vector3(0.08, 0.04, 1.0)

	_shared_spike_mesh = CylinderMesh.new()
	_shared_spike_mesh.top_radius = 0.02
	_shared_spike_mesh.bottom_radius = 0.14
	_shared_spike_mesh.height = 0.95
	_shared_spike_mesh.radial_segments = 4


func _ready() -> void:
	_ensure_nodes()
	if not _active:
		visible = false
		set_process(false)
		set_physics_process(false)


func _ensure_nodes() -> void:
	_ensure_shared()
	if outer_ring != null:
		return

	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	_hazard_mat = ShaderMaterial.new()
	_hazard_mat.shader = HAZARD_SHADER
	_hazard_mat.set_shader_parameter("border_danger_color", Color(1.0, 0.12, 0.20, 1.0))

	_orb_mat = StandardMaterial3D.new()
	_orb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	outer_ring = MeshInstance3D.new()
	outer_ring.name = "OuterRing"
	outer_ring.mesh = _shared_torus
	outer_ring.material_override = _ring_mat
	outer_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(outer_ring)

	inner_ring = MeshInstance3D.new()
	inner_ring.name = "InnerRing"
	inner_ring.mesh = _shared_torus
	inner_ring.material_override = _ring_mat
	inner_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inner_ring)

	fill_disc = MeshInstance3D.new()
	fill_disc.name = "FillDisc"
	fill_disc.mesh = _shared_hazard_plane
	fill_disc.material_override = _hazard_mat
	fill_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fill_disc)

	orb_mesh = MeshInstance3D.new()
	orb_mesh.name = "OrbMesh"
	orb_mesh.mesh = _shared_orb
	orb_mesh.material_override = _orb_mat
	orb_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(orb_mesh)

	beam_mesh = MeshInstance3D.new()
	beam_mesh.name = "BeamMesh"
	beam_mesh.mesh = _shared_beam
	beam_mesh.material_override = _ring_mat
	beam_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam_mesh)

	spike_ring_root = Node3D.new()
	spike_ring_root.name = "SpikeRingRoot"
	spike_ring_root.visible = false
	add_child(spike_ring_root)

	_spike_meshes.clear()
	for i in range(SPIKE_COUNT):
		var sp := MeshInstance3D.new()
		sp.name = "Spike_%d" % i
		sp.mesh = _shared_spike_mesh
		sp.material_override = _orb_mat
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spike_ring_root.add_child(sp)
		_spike_meshes.append(sp)

	_ray_query = PhysicsRayQueryParameters3D.new()
	_ray_query.collision_mask = 1 # World walls & VineBarriers only
	_ray_query.collide_with_bodies = true
	_ray_query.collide_with_areas = false


func is_available() -> bool:
	return not _active


func deactivate() -> void:
	_active = false
	_players_root = null
	set_process(false)
	set_physics_process(false)
	visible = false
	if spike_ring_root:
		spike_ring_root.visible = false


func activate_orb(
	p_start: Vector3,
	p_dir: Vector3,
	p_speed: float,
	p_range: float,
	p_damage: float,
	p_color: Color,
	p_is_lance: bool,
	p_players_root: Node3D
) -> void:
	_ensure_nodes()
	_mode = HazardMode.ENEMY_ORB
	_players_root = p_players_root
	_origin_pos = p_start
	_dir = Vector3(p_dir.x, 0.0, p_dir.z).normalized() if Vector2(p_dir.x, p_dir.z).length_squared() > 0.0001 else Vector3.FORWARD
	_speed = maxf(2.0, p_speed)
	_max_range = maxf(2.0, p_range)
	_traveled = 0.0
	_damage = p_damage
	_is_lance_orb = p_is_lance
	_radius = 0.34 if p_is_lance else 0.30
	_elapsed = 0.0
	_active = true

	outer_ring.visible = false
	inner_ring.visible = false
	fill_disc.visible = false
	beam_mesh.visible = false
	spike_ring_root.visible = false
	orb_mesh.visible = true
	orb_mesh.mesh = (_shared_lance as Mesh) if p_is_lance else (_shared_orb as Mesh)
	orb_mesh.position = Vector3.ZERO
	orb_mesh.scale = Vector3.ONE * (1.0 if p_is_lance else 1.18)
	_orb_mat.albedo_color = p_color

	scale = Vector3.ONE
	rotation = Vector3.ZERO
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	if is_inside_tree():
		global_position = p_start
		look_at(global_position + _dir, Vector3.UP)
		reset_physics_interpolation()
	else:
		position = p_start

	visible = true
	set_process(false)
	set_physics_process(true)


func activate_sightline(
	p_origin: Vector3,
	p_dir: Vector3,
	p_length: float,
	p_duration: float,
	p_color: Color
) -> void:
	_ensure_nodes()
	_mode = HazardMode.SNIPER_SIGHTLINE
	_dir = Vector3(p_dir.x, 0.0, p_dir.z).normalized() if Vector2(p_dir.x, p_dir.z).length_squared() > 0.0001 else Vector3.FORWARD
	_max_range = maxf(2.0, p_length)
	_telegraph_time = maxf(0.1, p_duration)
	_elapsed = 0.0
	_active = true

	outer_ring.visible = false
	inner_ring.visible = false
	fill_disc.visible = false
	orb_mesh.visible = false
	spike_ring_root.visible = false
	beam_mesh.visible = true
	beam_mesh.scale = Vector3(1.0, 1.0, _max_range)
	beam_mesh.position = Vector3(0.0, 0.32, -_max_range * 0.5)
	_ring_mat.albedo_color = Color(p_color.r, p_color.g, p_color.b, 0.90)

	scale = Vector3.ONE
	rotation = Vector3.ZERO
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if is_inside_tree():
		global_position = Vector3(p_origin.x, 0.0, p_origin.z)
		look_at(global_position + _dir, Vector3.UP)
		reset_physics_interpolation()
	else:
		position = Vector3(p_origin.x, 0.0, p_origin.z)

	visible = true
	set_physics_process(false)
	set_process(true)


func activate_ground_hazard(
	p_mode: int,
	p_origin: Vector3,
	p_target: Vector3,
	p_radius: float,
	p_inner_radius: float,
	p_damage: float,
	p_telegraph_s: float,
	p_pool_duration_s: float,
	p_color: Color,
	p_shake: float,
	p_players_root: Node3D
) -> void:
	_ensure_nodes()
	_mode = p_mode
	_players_root = p_players_root
	_origin_pos = p_origin
	_target_pos = Vector3(p_target.x, 0.045, p_target.z)
	_radius = maxf(0.8, p_radius)
	_inner_radius = clampf(p_inner_radius, 0.0, _radius - 0.5)
	_damage = p_damage
	_telegraph_time = maxf(0.20, p_telegraph_s)
	_active_duration = maxf(0.22, p_pool_duration_s)
	_shake_amount = p_shake
	_elapsed = 0.0
	_detonated = false
	_tick_timer = 0.0
	_active = true

	rotation = Vector3.ZERO
	scale = Vector3.ONE
	beam_mesh.visible = false
	outer_ring.visible = false
	inner_ring.visible = false
	spike_ring_root.visible = false
	spike_ring_root.rotation = Vector3.ZERO

	var in_ratio: float = (_inner_radius / _radius) if (_mode == HazardMode.DONUT_AFTERSHOCK and _inner_radius > 0.2) else 0.0
	_hazard_mat.set_shader_parameter("hazard_color", p_color)
	_hazard_mat.set_shader_parameter("border_danger_color", Color(1.0, 0.14, 0.22, 1.0))
	_hazard_mat.set_shader_parameter("inner_ratio", in_ratio)
	_hazard_mat.set_shader_parameter("progress", 0.0)
	_hazard_mat.set_shader_parameter("hazard_stage", 0)
	_hazard_mat.set_shader_parameter("fade_out", 1.0)

	fill_disc.visible = true
	fill_disc.scale = Vector3(_radius, 1.0, _radius)

	_orb_mat.albedo_color = p_color.lightened(0.22)
	orb_mesh.visible = (_mode == HazardMode.LOB_POOL)
	if orb_mesh.visible:
		orb_mesh.mesh = _shared_orb as Mesh
		orb_mesh.scale = Vector3.ONE * 1.18

	_layout_spike_ring()

	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if is_inside_tree():
		global_position = _target_pos
		reset_physics_interpolation()
	else:
		position = _target_pos

	visible = true
	set_physics_process(false)
	set_process(true)


func activate_clock_sector(
	p_center: Vector3,
	p_radius: float,
	p_safe_angle: float,
	p_safe_half_width: float,
	p_damage: float,
	p_telegraph_s: float,
	p_color: Color,
	p_shake: float,
	p_players_root: Node3D
) -> void:
	_ensure_nodes()
	_mode = HazardMode.CLOCK_SECTOR
	_players_root = p_players_root
	_origin_pos = p_center
	_target_pos = Vector3(p_center.x, 0.045, p_center.z)
	_radius = maxf(3.0, p_radius)
	_inner_radius = 0.0
	_safe_angle = p_safe_angle
	_safe_half_width = clampf(p_safe_half_width, 0.20, 1.35)
	_damage = p_damage
	_telegraph_time = maxf(0.5, p_telegraph_s)
	_active_duration = 0.42
	_shake_amount = p_shake
	_elapsed = 0.0
	_detonated = false
	_tick_timer = 0.0
	_active = true

	rotation = Vector3.ZERO
	scale = Vector3.ONE
	beam_mesh.visible = false
	outer_ring.visible = false
	inner_ring.visible = false
	orb_mesh.visible = false
	spike_ring_root.visible = false
	spike_ring_root.rotation = Vector3.ZERO

	_hazard_mat.set_shader_parameter("hazard_color", p_color)
	_hazard_mat.set_shader_parameter("border_danger_color", Color(1.0, 0.16, 0.26, 1.0))
	_hazard_mat.set_shader_parameter("inner_ratio", 0.0)
	_hazard_mat.set_shader_parameter("progress", 0.0)
	_hazard_mat.set_shader_parameter("hazard_stage", 3)
	_hazard_mat.set_shader_parameter("fade_out", 1.0)
	_hazard_mat.set_shader_parameter("safe_angle", _safe_angle)
	_hazard_mat.set_shader_parameter("safe_half_width", _safe_half_width)

	fill_disc.visible = true
	fill_disc.scale = Vector3(_radius, 1.0, _radius)
	_orb_mat.albedo_color = Color(1.0, 0.88, 0.42, 1.0)

	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if is_inside_tree():
		global_position = _target_pos
		reset_physics_interpolation()
	else:
		position = _target_pos

	visible = true
	set_physics_process(false)
	set_process(true)


func activate_clock_safe_circle(
	p_center: Vector3,
	p_radius: float,
	p_safe_pos: Vector3,
	p_safe_radius: float,
	p_damage: float,
	p_telegraph_s: float,
	p_color: Color,
	p_shake: float,
	p_players_root: Node3D
) -> void:
	_ensure_nodes()
	_mode = HazardMode.CLOCK_SAFE_CIRCLE
	_players_root = p_players_root
	_origin_pos = p_center
	_target_pos = Vector3(p_center.x, 0.045, p_center.z)
	_radius = maxf(6.0, p_radius)
	_inner_radius = 0.0
	_safe_world_pos = Vector3(p_safe_pos.x, 0.0, p_safe_pos.z)
	_safe_world_radius = clampf(p_safe_radius, 1.8, _radius * 0.45)
	_damage = p_damage
	_telegraph_time = maxf(0.5, p_telegraph_s)
	_active_duration = 0.42
	_shake_amount = p_shake
	_elapsed = 0.0
	_detonated = false
	_tick_timer = 0.0
	_active = true

	rotation = Vector3.ZERO
	scale = Vector3.ONE
	beam_mesh.visible = false
	outer_ring.visible = false
	inner_ring.visible = false
	orb_mesh.visible = false
	spike_ring_root.visible = false
	spike_ring_root.rotation = Vector3.ZERO

	var rel_uv := Vector2(
		(_safe_world_pos.x - p_center.x) / _radius,
		(_safe_world_pos.z - p_center.z) / _radius
	)
	_hazard_mat.set_shader_parameter("hazard_color", p_color)
	_hazard_mat.set_shader_parameter("border_danger_color", Color(1.0, 0.16, 0.28, 1.0))
	_hazard_mat.set_shader_parameter("inner_ratio", 0.0)
	_hazard_mat.set_shader_parameter("progress", 0.0)
	_hazard_mat.set_shader_parameter("hazard_stage", 5)
	_hazard_mat.set_shader_parameter("fade_out", 1.0)
	_hazard_mat.set_shader_parameter("safe_center_uv", rel_uv)
	_hazard_mat.set_shader_parameter("safe_radius_uv", clampf(_safe_world_radius / _radius, 0.05, 0.45))

	fill_disc.visible = true
	fill_disc.scale = Vector3(_radius, 1.0, _radius)
	_orb_mat.albedo_color = Color(1.0, 0.88, 0.42, 1.0)

	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if is_inside_tree():
		global_position = _target_pos
		reset_physics_interpolation()
	else:
		position = _target_pos

	visible = true
	set_physics_process(false)
	set_process(true)


func _layout_spike_ring() -> void:
	if _spike_meshes.is_empty():
		return
	var ring_r: float = _radius * 0.82
	if _mode == HazardMode.DONUT_AFTERSHOCK and _inner_radius > 0.2:
		ring_r = (_inner_radius + _radius) * 0.5
	for i in range(_spike_meshes.size()):
		var ang: float = (float(i) / float(_spike_meshes.size())) * TAU
		var sp: MeshInstance3D = _spike_meshes[i]
		sp.position = Vector3(cos(ang) * ring_r, 0.35, sin(ang) * ring_r)
		sp.rotation = Vector3(sin(ang) * 0.14, -ang, -cos(ang) * 0.14)
		sp.scale = Vector3.ONE


func _physics_process(delta: float) -> void:
	if not _active or _mode != HazardMode.ENEMY_ORB:
		return

	var step: float = _speed * delta
	var cur: Vector3 = global_position
	var nxt: Vector3 = cur + _dir * step

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space_state and _ray_query:
		_ray_query.from = cur
		_ray_query.to = nxt
		var hit: Dictionary = space_state.intersect_ray(_ray_query)
		if not hit.is_empty():
			var collider: Object = hit.get("collider", null)
			if _is_lance_orb and collider != null and collider.has_method("on_lance_hit"):
				collider.call("on_lance_hit", hit.get("position", nxt))
			deactivate()
			return

	global_position = nxt
	_traveled += step

	if _check_orb_player_hit():
		deactivate()
		return

	if _traveled >= _max_range:
		deactivate()


func _process(delta: float) -> void:
	if not _active:
		return

	_elapsed += delta

	match _mode:
		HazardMode.SNIPER_SIGHTLINE:
			var rem: float = _telegraph_time - _elapsed
			if rem <= 0.0:
				deactivate()
				return
			# Flash bright white-gold during final lock-on moment!
			var pulse: float = 0.5 + 0.5 * sin(_elapsed * 38.0)
			beam_mesh.scale.x = lerpf(0.75, 1.85, pulse)
			if rem < 0.32:
				_ring_mat.albedo_color = Color(1.0, 0.96, 0.58, 0.98)

		HazardMode.LOB_POOL:
			if not _detonated:
				var t: float = clampf(_elapsed / _telegraph_time, 0.0, 1.0)
				_hazard_mat.set_shader_parameter("progress", t)
				if orb_mesh:
					var world_lob: Vector3 = _origin_pos.lerp(_target_pos, t)
					world_lob.y += sin(t * PI) * 4.2 + 0.35
					orb_mesh.global_position = world_lob
				if _elapsed >= _telegraph_time:
					_detonated = true
					if orb_mesh:
						orb_mesh.visible = false
					_hazard_mat.set_shader_parameter("hazard_stage", 2)
					_hazard_mat.set_shader_parameter("progress", 1.0)
					_show_spore_globules()
					_damage_players_in_band(0.0, _radius, _damage)
					_tick_timer = 0.45
			else:
				var pool_age: float = _elapsed - _telegraph_time
				var fade_rem: float = clampf((_active_duration - pool_age) / 0.65, 0.0, 1.0)
				_hazard_mat.set_shader_parameter("fade_out", fade_rem)
				if spike_ring_root and spike_ring_root.visible:
					spike_ring_root.rotation.y += delta * 1.4
					for i in range(_spike_meshes.size()):
						var sp: MeshInstance3D = _spike_meshes[i]
						var bob: float = 0.20 + 0.09 * sin(_elapsed * 5.0 + float(i) * 1.3)
						sp.position.y = bob
						var s_val: float = 0.35 * fade_rem
						sp.scale = Vector3(s_val, s_val, s_val)
				_tick_timer -= delta
				if _tick_timer <= 0.0:
					_tick_timer = 0.48
					_damage_players_in_band(0.0, _radius, _damage * 0.55)
				if pool_age >= _active_duration:
					deactivate()

		HazardMode.GROUND_QUAKE:
			if not _detonated:
				var tq: float = clampf(_elapsed / _telegraph_time, 0.0, 1.0)
				_hazard_mat.set_shader_parameter("progress", tq)
				if _elapsed >= _telegraph_time:
					_detonated = true
					_hazard_mat.set_shader_parameter("hazard_stage", 1)
					_hazard_mat.set_shader_parameter("progress", 1.0)
					_show_eruption_spikes()
					_damage_players_in_band(0.0, _radius, _damage)
					if _shake_amount > 0.01 and is_inside_tree():
						get_tree().call_group("world_camera_shake", "add_camera_shake", _shake_amount)
			else:
				var fade_q: float = clampf((_elapsed - _telegraph_time) / _active_duration, 0.0, 1.0)
				_hazard_mat.set_shader_parameter("fade_out", 1.0 - fade_q)
				_animate_eruption_spikes(fade_q)
				if fade_q >= 1.0:
					deactivate()

		HazardMode.DONUT_AFTERSHOCK:
			if not _detonated:
				var td: float = clampf(_elapsed / _telegraph_time, 0.0, 1.0)
				_hazard_mat.set_shader_parameter("progress", td)
				if _elapsed >= _telegraph_time:
					_detonated = true
					_hazard_mat.set_shader_parameter("hazard_stage", 1)
					_hazard_mat.set_shader_parameter("progress", 1.0)
					_show_eruption_spikes()
					_damage_players_in_band(_inner_radius, _radius, _damage)
					if _shake_amount > 0.01 and is_inside_tree():
						get_tree().call_group("world_camera_shake", "add_camera_shake", _shake_amount)
			else:
				var fade_d: float = clampf((_elapsed - _telegraph_time) / _active_duration, 0.0, 1.0)
				_hazard_mat.set_shader_parameter("fade_out", 1.0 - fade_d)
				_animate_eruption_spikes(fade_d)
				if fade_d >= 1.0:
					deactivate()

		HazardMode.CLOCK_SECTOR, HazardMode.CLOCK_SAFE_CIRCLE:
			if not _detonated:
				var tc: float = clampf(_elapsed / _telegraph_time, 0.0, 1.0)
				_hazard_mat.set_shader_parameter("progress", tc)
				if _elapsed >= _telegraph_time:
					_detonated = true
					_hazard_mat.set_shader_parameter("progress", 1.0)
					_damage_players_outside_safe_zone(_mode == HazardMode.CLOCK_SAFE_CIRCLE)
					if _shake_amount > 0.01 and is_inside_tree():
						get_tree().call_group("world_camera_shake", "add_camera_shake", _shake_amount)
			else:
				var fade_c: float = clampf((_elapsed - _telegraph_time) / _active_duration, 0.0, 1.0)
				_hazard_mat.set_shader_parameter("fade_out", 1.0 - fade_c)
				if fade_c >= 1.0:
					deactivate()


func _show_eruption_spikes() -> void:
	if spike_ring_root == null:
		return
	spike_ring_root.visible = true
	for sp in _spike_meshes:
		sp.mesh = _shared_spike_mesh
		sp.scale = Vector3(1.15, 0.15, 1.15)


func _animate_eruption_spikes(fade_t: float) -> void:
	if spike_ring_root == null or not spike_ring_root.visible:
		return
	var s_y: float = sin(clampf(fade_t, 0.0, 1.0) * PI) * 1.15
	for i in range(_spike_meshes.size()):
		var sp: MeshInstance3D = _spike_meshes[i]
		sp.scale = Vector3(maxf(0.1, 1.15 * (1.0 - fade_t * 0.65)), maxf(0.05, s_y), maxf(0.1, 1.15 * (1.0 - fade_t * 0.65)))
		sp.position.y = 0.42 * s_y


func _show_spore_globules() -> void:
	if spike_ring_root == null:
		return
	spike_ring_root.visible = true
	var ring_r: float = _radius * 0.68
	for i in range(_spike_meshes.size()):
		var ang: float = (float(i) / float(_spike_meshes.size())) * TAU
		var sp: MeshInstance3D = _spike_meshes[i]
		sp.mesh = _shared_orb
		sp.rotation = Vector3.ZERO
		sp.position = Vector3(cos(ang) * ring_r, 0.22, sin(ang) * ring_r)
		sp.scale = Vector3.ONE * 0.35


func _check_orb_player_hit() -> bool:
	if _players_root == null or not is_instance_valid(_players_root):
		return false
	var hit_r2: float = (_radius + 0.36) * (_radius + 0.36)
	var count: int = _players_root.get_child_count()
	for i in range(count):
		var p3d: Node3D = _players_root.get_child(i) as Node3D
		if p3d == null or not p3d.visible:
			continue
		var dx: float = p3d.global_position.x - global_position.x
		var dz: float = p3d.global_position.z - global_position.z
		if (dx * dx + dz * dz) <= hit_r2:
			if p3d.has_method("try_apply_contact_damage"):
				p3d.call("try_apply_contact_damage", _damage, _dir)
			return true
	return false


func _damage_players_in_band(min_r: float, max_r: float, dmg: float) -> void:
	if dmg <= 0.0 or _players_root == null or not is_instance_valid(_players_root):
		return
	var min_r2: float = maxf(0.0, min_r - 0.25) * maxf(0.0, min_r - 0.25)
	var max_r2: float = (max_r + 0.32) * (max_r + 0.32)
	var count: int = _players_root.get_child_count()
	for i in range(count):
		var p3d: Node3D = _players_root.get_child(i) as Node3D
		if p3d == null or not p3d.visible:
			continue
		var dx: float = p3d.global_position.x - global_position.x
		var dz: float = p3d.global_position.z - global_position.z
		var d2: float = dx * dx + dz * dz
		if d2 >= min_r2 and d2 <= max_r2 and p3d.has_method("try_apply_contact_damage"):
			var k_dir: Vector3 = Vector3(dx, 0.0, dz).normalized() if d2 > 0.001 else Vector3.FORWARD
			p3d.call("try_apply_contact_damage", dmg, k_dir)


func _damage_players_outside_safe_zone(use_circle: bool) -> void:
	if _damage <= 0.0 or _players_root == null or not is_instance_valid(_players_root):
		return
	var outer_margin: float = 0.50 if use_circle else 0.35
	var max_r2: float = (_radius + outer_margin) * (_radius + outer_margin)
	var safe_r2: float = (_safe_world_radius + 0.28) * (_safe_world_radius + 0.28)
	var count: int = _players_root.get_child_count()
	for i in range(count):
		var p3d: Node3D = _players_root.get_child(i) as Node3D
		if p3d == null or not p3d.visible:
			continue
		var dx: float = p3d.global_position.x - global_position.x
		var dz: float = p3d.global_position.z - global_position.z
		var d2: float = dx * dx + dz * dz
		if d2 > max_r2:
			continue
		if use_circle:
			var s_dx: float = p3d.global_position.x - _safe_world_pos.x
			var s_dz: float = p3d.global_position.z - _safe_world_pos.z
			if (s_dx * s_dx + s_dz * s_dz) <= safe_r2:
				continue
		else:
			var p_ang: float = atan2(dz, dx)
			var ang_diff: float = absf(wrapf(p_ang - _safe_angle, -PI, PI))
			if ang_diff <= _safe_half_width:
				continue
		if p3d.has_method("try_apply_contact_damage"):
			var k_dir: Vector3 = Vector3(dx, 0.0, dz).normalized() if d2 > 0.001 else Vector3.FORWARD
			p3d.call("try_apply_contact_damage", _damage, k_dir)
