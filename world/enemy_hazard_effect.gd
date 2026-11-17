class_name EnemyHazardEffect
extends Node3D

## Pooled multi-mode Enemy Projectile & Ground Hazard node:
## - ENEMY_ORB (0): Enemy ranged bolt / sniper lance / boss volley orb
## - LOB_POOL (1): Arcing mortar globule (0.85s telegraph) -> persistent damaging ground pool
## - GROUND_QUAKE (2): Telegraphed radial ground slam + camera shake
## - DONUT_AFTERSHOCK (3): Telegraphed outer-ring eruption with a safe inner eye!
## - SNIPER_SIGHTLINE (4): Tracking/locked laser line warning before sniper lance fires

enum HazardMode {
	ENEMY_ORB = 0,
	LOB_POOL = 1,
	GROUND_QUAKE = 2,
	DONUT_AFTERSHOCK = 3,
	SNIPER_SIGHTLINE = 4
}

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

var outer_ring: MeshInstance3D = null
var inner_ring: MeshInstance3D = null
var fill_disc: MeshInstance3D = null
var orb_mesh: MeshInstance3D = null
var beam_mesh: MeshInstance3D = null

var _ring_mat: StandardMaterial3D = null
var _fill_mat: StandardMaterial3D = null
var _orb_mat: StandardMaterial3D = null

var _ray_query: PhysicsRayQueryParameters3D = null

static var _shared_torus: TorusMesh = null
static var _shared_disc: CylinderMesh = null
static var _shared_donut_disc: TorusMesh = null
static var _shared_orb: SphereMesh = null
static var _shared_lance: BoxMesh = null
static var _shared_beam: BoxMesh = null


static func _ensure_shared() -> void:
	if _shared_torus != null:
		return

	_shared_torus = TorusMesh.new()
	_shared_torus.inner_radius = 0.90
	_shared_torus.outer_radius = 1.0
	_shared_torus.rings = 28
	_shared_torus.ring_segments = 8

	_shared_disc = CylinderMesh.new()
	_shared_disc.top_radius = 0.94
	_shared_disc.bottom_radius = 0.94
	_shared_disc.height = 0.02
	_shared_disc.radial_segments = 24

	_shared_donut_disc = TorusMesh.new()
	_shared_donut_disc.inner_radius = 0.48
	_shared_donut_disc.outer_radius = 0.98
	_shared_donut_disc.rings = 32
	_shared_donut_disc.ring_segments = 8

	_shared_orb = SphereMesh.new()
	_shared_orb.radius = 0.24
	_shared_orb.height = 0.48
	_shared_orb.radial_segments = 14
	_shared_orb.rings = 8

	_shared_lance = BoxMesh.new()
	_shared_lance.size = Vector3(0.18, 0.18, 1.35)

	_shared_beam = BoxMesh.new()
	_shared_beam.size = Vector3(0.07, 0.04, 1.0)


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

	_fill_mat = StandardMaterial3D.new()
	_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

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
	fill_disc.mesh = _shared_disc
	fill_disc.material_override = _fill_mat
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
	_radius = 0.34 if p_is_lance else 0.30
	_elapsed = 0.0
	_active = true

	outer_ring.visible = false
	inner_ring.visible = false
	fill_disc.visible = false
	beam_mesh.visible = false
	orb_mesh.visible = true
	orb_mesh.mesh = (_shared_lance as Mesh) if p_is_lance else (_shared_orb as Mesh)
	orb_mesh.position = Vector3.ZERO
	orb_mesh.scale = Vector3.ONE * (1.0 if p_is_lance else 1.18)
	_orb_mat.albedo_color = p_color

	scale = Vector3.ONE
	rotation = Vector3.ZERO
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
	beam_mesh.visible = true
	beam_mesh.scale = Vector3(1.0, 1.0, _max_range)
	beam_mesh.position = Vector3(0.0, 0.32, -_max_range * 0.5)
	_ring_mat.albedo_color = Color(p_color.r, p_color.g, p_color.b, 0.88)

	scale = Vector3.ONE
	rotation = Vector3.ZERO
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
	_target_pos = Vector3(p_target.x, 0.04, p_target.z)
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

	_ring_mat.albedo_color = Color(p_color.r, p_color.g, p_color.b, 0.92)
	_fill_mat.albedo_color = Color(p_color.r, p_color.g, p_color.b, 0.30)
	_orb_mat.albedo_color = p_color.lightened(0.20)

	outer_ring.visible = true
	outer_ring.scale = Vector3(_radius, 1.0, _radius)

	if _mode == HazardMode.DONUT_AFTERSHOCK and _inner_radius > 0.2:
		inner_ring.visible = true
		inner_ring.scale = Vector3(_inner_radius, 1.0, _inner_radius)
		fill_disc.mesh = _shared_donut_disc as Mesh
		fill_disc.visible = true
		fill_disc.scale = Vector3(_radius, 0.15, _radius)
	else:
		inner_ring.visible = false
		fill_disc.mesh = _shared_disc as Mesh
		fill_disc.visible = true
		fill_disc.scale = Vector3(0.15, 1.0, 0.15)

	orb_mesh.visible = (_mode == HazardMode.LOB_POOL)
	if orb_mesh.visible:
		orb_mesh.mesh = _shared_orb as Mesh
		orb_mesh.scale = Vector3.ONE * 1.15

	if is_inside_tree():
		global_position = _target_pos
		reset_physics_interpolation()
	else:
		position = _target_pos

	visible = true
	set_physics_process(false)
	set_process(true)


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
			beam_mesh.scale.x = lerpf(0.7, 1.7, pulse)
			if rem < 0.26:
				_ring_mat.albedo_color = Color(1.0, 0.96, 0.58, 0.98)

		HazardMode.LOB_POOL:
			if not _detonated:
				var t: float = clampf(_elapsed / _telegraph_time, 0.0, 1.0)
				fill_disc.scale = Vector3(_radius * t, 1.0, _radius * t)
				if orb_mesh:
					var world_lob: Vector3 = _origin_pos.lerp(_target_pos, t)
					world_lob.y += sin(t * PI) * 3.8 + 0.35
					orb_mesh.global_position = world_lob
				if _elapsed >= _telegraph_time:
					_detonated = true
					if orb_mesh:
						orb_mesh.visible = false
					fill_disc.scale = Vector3(_radius, 1.0, _radius)
					_fill_mat.albedo_color.a = 0.46
					_damage_players_in_band(0.0, _radius, _damage)
					_tick_timer = 0.45
			else:
				var pool_age: float = _elapsed - _telegraph_time
				var pulse_r: float = _radius * (0.96 + 0.04 * sin(pool_age * 7.0))
				fill_disc.scale = Vector3(pulse_r, 1.0, pulse_r)
				_tick_timer -= delta
				if _tick_timer <= 0.0:
					_tick_timer = 0.48
					_damage_players_in_band(0.0, _radius, _damage * 0.55)
				if pool_age >= _active_duration:
					deactivate()

		HazardMode.GROUND_QUAKE:
			if not _detonated:
				var tq: float = clampf(_elapsed / _telegraph_time, 0.0, 1.0)
				fill_disc.scale = Vector3(_radius * tq, 1.0, _radius * tq)
				if _elapsed >= _telegraph_time:
					_detonated = true
					fill_disc.scale = Vector3(_radius * 1.08, 1.0, _radius * 1.08)
					_fill_mat.albedo_color.a = 0.65
					_damage_players_in_band(0.0, _radius, _damage)
					if _shake_amount > 0.01 and is_inside_tree():
						get_tree().call_group("world_camera_shake", "add_camera_shake", _shake_amount)
			else:
				var fade_q: float = clampf((_elapsed - _telegraph_time) / _active_duration, 0.0, 1.0)
				_fill_mat.albedo_color.a = lerpf(0.65, 0.0, fade_q)
				_ring_mat.albedo_color.a = lerpf(0.95, 0.0, fade_q)
				if fade_q >= 1.0:
					deactivate()

		HazardMode.DONUT_AFTERSHOCK:
			if not _detonated:
				var td: float = clampf(_elapsed / _telegraph_time, 0.0, 1.0)
				_fill_mat.albedo_color.a = lerpf(0.14, 0.44, td)
				if _elapsed >= _telegraph_time:
					_detonated = true
					_fill_mat.albedo_color.a = 0.72
					_damage_players_in_band(_inner_radius, _radius, _damage)
					if _shake_amount > 0.01 and is_inside_tree():
						get_tree().call_group("world_camera_shake", "add_camera_shake", _shake_amount)
			else:
				var fade_d: float = clampf((_elapsed - _telegraph_time) / _active_duration, 0.0, 1.0)
				_fill_mat.albedo_color.a = lerpf(0.72, 0.0, fade_d)
				_ring_mat.albedo_color.a = lerpf(0.95, 0.0, fade_d)
				if fade_d >= 1.0:
					deactivate()


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
