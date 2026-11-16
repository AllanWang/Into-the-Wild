class_name CombatZoneEffect
extends Node3D

## Pooled multi-mode 3D combat zone effect for AoE weapons, Abilities (Q/E), and Artifacts (R).
## Shares static TorusMesh, CylinderMesh, and cached palette materials for zero runtime allocations.

enum ZoneMode {
	DELAYED_BLAST = 0,  ## Nova Mortar & Starfall Strike (0.35s telegraph -> AoE hit + flash)
	SOLAR_PILLAR = 1,   ## Solar Convergence [R] (3 orbital beam pulses over 1.35s)
	STASIS_FIELD = 2,   ## Frost Nova [Q/E] & Chronosphere [R] (initial hit + persistent slow aura)
	SELF_WARD = 3       ## Aegis Barrier & Tempo Surge (quick expanding aura ring around caster)
}

var pool: Node = null

@onready var ring_mesh: MeshInstance3D = $RingMesh
@onready var disc_mesh: MeshInstance3D = $DiscMesh
@onready var pillar_mesh: MeshInstance3D = $PillarMesh

var _mode: int = ZoneMode.DELAYED_BLAST
var _radius: float = 2.8
var _damage: float = 0.0
var _proc_coeff: float = 1.0
var _slow_ratio: float = 0.0
var _leech_ratio: float = 0.0
var _shooter_stats: Object = null
var _follow_target: Node3D = null
var _caster_node: Node3D = null

var _elapsed: float = 0.0
var _duration: float = 0.5
var _detonated: bool = false
var _pulses_left: int = 0
var _pulse_timer: float = 0.0
var _slow_tick_timer: float = 0.0
var _active: bool = false

static var _shared_torus: TorusMesh = null
static var _shared_disc: CylinderMesh = null
static var _shared_pillar: CylinderMesh = null
static var _ring_mats: Dictionary = {}
static var _fill_mats: Dictionary = {}


static func _ensure_shared() -> void:
	if _shared_torus != null:
		return

	_shared_torus = TorusMesh.new()
	_shared_torus.inner_radius = 0.88
	_shared_torus.outer_radius = 1.0
	_shared_torus.rings = 28
	_shared_torus.ring_segments = 8

	_shared_disc = CylinderMesh.new()
	_shared_disc.top_radius = 0.90
	_shared_disc.bottom_radius = 0.90
	_shared_disc.height = 0.015
	_shared_disc.radial_segments = 24

	_shared_pillar = CylinderMesh.new()
	_shared_pillar.top_radius = 0.42
	_shared_pillar.bottom_radius = 0.65
	_shared_pillar.height = 9.0
	_shared_pillar.radial_segments = 16


static func _get_palette_mats(key: String, col: Color) -> Array[StandardMaterial3D]:
	_ensure_shared()
	if _ring_mats.has(key):
		return [_ring_mats[key] as StandardMaterial3D, _fill_mats[key] as StandardMaterial3D]

	var r_mat := StandardMaterial3D.new()
	r_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	r_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	r_mat.albedo_color = Color(col.r, col.g, col.b, 0.90)

	var f_mat := StandardMaterial3D.new()
	f_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	f_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	f_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	f_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	f_mat.albedo_color = Color(col.r, col.g, col.b, 0.26)

	_ring_mats[key] = r_mat
	_fill_mats[key] = f_mat
	return [r_mat, f_mat]


func _ready() -> void:
	_ensure_shared()
	if ring_mesh:
		ring_mesh.mesh = _shared_torus
		ring_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if disc_mesh:
		disc_mesh.mesh = _shared_disc
		disc_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if pillar_mesh:
		pillar_mesh.mesh = _shared_pillar
		pillar_mesh.position = Vector3(0.0, 4.5, 0.0)
		pillar_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func activate_zone(
	p_mode: int,
	p_pos: Vector3,
	p_radius: float,
	p_damage: float,
	p_duration: float,
	p_color_key: String,
	p_color: Color,
	p_shooter_stats: Object = null,
	p_slow_ratio: float = 0.0,
	p_follow_target: Node3D = null,
	p_leech_ratio: float = 0.0,
	p_caster_node: Node3D = null
) -> void:
	_mode = p_mode
	_radius = maxf(0.8, p_radius)
	_damage = maxf(0.0, p_damage)
	_proc_coeff = 1.0
	_slow_ratio = clampf(p_slow_ratio, 0.0, 0.90)
	_leech_ratio = clampf(p_leech_ratio, 0.0, 2.0)
	_shooter_stats = p_shooter_stats
	_follow_target = p_follow_target
	_caster_node = p_caster_node
	_elapsed = 0.0
	_duration = maxf(0.2, p_duration)
	_detonated = false
	_slow_tick_timer = 0.0
	_active = true

	var mats: Array[StandardMaterial3D] = _get_palette_mats(p_color_key, p_color)
	if ring_mesh:
		ring_mesh.material_override = mats[0]
		ring_mesh.visible = true
	if disc_mesh:
		disc_mesh.material_override = mats[1]
		disc_mesh.visible = true
		disc_mesh.scale = Vector3.ONE * 0.2
	if pillar_mesh:
		pillar_mesh.material_override = mats[1]
		pillar_mesh.visible = (_mode == ZoneMode.SOLAR_PILLAR)
		pillar_mesh.scale = Vector3(1.0, 1.0, 1.0)

	if is_inside_tree():
		global_position = Vector3(p_pos.x, 0.05, p_pos.z)
		reset_physics_interpolation()
	else:
		position = Vector3(p_pos.x, 0.05, p_pos.z)

	if _mode == ZoneMode.SOLAR_PILLAR:
		_pulses_left = 3
		_pulse_timer = 0.08
		scale = Vector3(_radius, 1.0, _radius)
	elif _mode == ZoneMode.STASIS_FIELD:
		scale = Vector3(_radius * 0.35, 1.0, _radius * 0.35)
		if _damage > 0.0:
			_apply_aoe_damage(_damage, true)
		_apply_aoe_slow()
	elif _mode == ZoneMode.SELF_WARD:
		scale = Vector3(_radius * 0.25, 1.0, _radius * 0.25)
	else:
		# DELAYED_BLAST
		scale = Vector3(_radius, 1.0, _radius)

	visible = true
	set_process(true)


func deactivate() -> void:
	_active = false
	_shooter_stats = null
	_follow_target = null
	_caster_node = null
	_leech_ratio = 0.0
	set_process(false)
	visible = false
	if pillar_mesh:
		pillar_mesh.visible = false


func on_pool_release() -> void:
	deactivate()


func _release_self() -> void:
	_active = false
	if pool and pool.has_method("release"):
		pool.release(self)
	else:
		deactivate()


func _process(delta: float) -> void:
	if not _active:
		return

	_elapsed += delta

	if _follow_target != null and is_instance_valid(_follow_target):
		global_position = Vector3(_follow_target.global_position.x, 0.05, _follow_target.global_position.z)

	match _mode:
		ZoneMode.DELAYED_BLAST:
			var telegraph_time: float = _duration - 0.16
			if not _detonated:
				var t: float = clampf(_elapsed / maxf(0.1, telegraph_time), 0.0, 1.0)
				if disc_mesh:
					disc_mesh.scale = Vector3(t, 1.0, t)
				if _elapsed >= telegraph_time:
					_detonated = true
					_apply_aoe_damage(_damage, true)
					if disc_mesh:
						disc_mesh.scale = Vector3(1.12, 1.0, 1.12)
					scale = Vector3(_radius * 1.12, 1.0, _radius * 1.12)
			else:
				var fade_t: float = clampf((_elapsed - telegraph_time) / 0.16, 0.0, 1.0)
				var s: float = lerpf(_radius * 1.12, _radius * 0.4, fade_t)
				scale = Vector3(s, 1.0, s)
				if _elapsed >= _duration:
					_release_self()

		ZoneMode.SOLAR_PILLAR:
			if disc_mesh:
				var pulse_s: float = 0.85 + 0.15 * sin(_elapsed * 14.0)
				disc_mesh.scale = Vector3(pulse_s, 1.0, pulse_s)
			if pillar_mesh:
				var beam_w: float = 0.75 + 0.25 * sin(_elapsed * 18.0)
				pillar_mesh.scale = Vector3(beam_w, 1.0, beam_w)
			if _pulses_left > 0:
				_pulse_timer -= delta
				if _pulse_timer <= 0.0:
					_pulses_left -= 1
					_pulse_timer = 0.45
					_apply_aoe_damage(_damage, true)
			if _elapsed >= _duration:
				_release_self()

		ZoneMode.STASIS_FIELD:
			var grow_t: float = clampf(_elapsed / 0.22, 0.0, 1.0)
			var cur_r: float = lerpf(_radius * 0.35, _radius, grow_t)
			scale = Vector3(cur_r, 1.0, cur_r)
			if disc_mesh:
				disc_mesh.scale = Vector3(0.96, 1.0, 0.96)
			_slow_tick_timer -= delta
			if _slow_tick_timer <= 0.0:
				_slow_tick_timer = 0.18
				_apply_aoe_slow()
			if _elapsed >= _duration:
				_release_self()

		ZoneMode.SELF_WARD:
			var t: float = clampf(_elapsed / _duration, 0.0, 1.0)
			var eased: float = 1.0 - (1.0 - t) * (1.0 - t)
			var s: float = lerpf(_radius * 0.25, _radius, eased)
			scale = Vector3(s, 1.0, s)
			if disc_mesh:
				disc_mesh.scale = Vector3(1.0 - t * 0.5, 1.0, 1.0 - t * 0.5)
			if _elapsed >= _duration:
				_release_self()


func _apply_aoe_damage(dmg: float, apply_traits: bool) -> void:
	if dmg <= 0.0 or not is_inside_tree():
		return
	var r2: float = (_radius + 0.45) * (_radius + 0.45)
	var total_dealt: float = 0.0
	var enemies: Array[Node] = get_tree().get_nodes_in_group("active_enemies")
	for e_node in enemies:
		var e3d: Node3D = e_node as Node3D
		if e3d == null or not e3d.visible:
			continue
		var dx: float = e3d.global_position.x - global_position.x
		var dz: float = e3d.global_position.z - global_position.z
		if (dx * dx + dz * dz) <= r2 and e3d.has_method("apply_combat_hit"):
			var hp_before: float = dmg
			if e3d is EnemySphere and (e3d as EnemySphere).health_comp != null:
				hp_before = (e3d as EnemySphere).health_comp.current_health
			var hit_dir: Vector3 = Vector3(dx, 0.0, dz).normalized() if (dx * dx + dz * dz) > 0.001 else Vector3.FORWARD
			e3d.call("apply_combat_hit", dmg, hit_dir, _proc_coeff if apply_traits else 0.0, _shooter_stats if apply_traits else null)
			var hp_after: float = 0.0
			if e3d is EnemySphere and (e3d as EnemySphere).health_comp != null:
				hp_after = (e3d as EnemySphere).health_comp.current_health
			total_dealt += maxf(0.0, hp_before - hp_after)

	if _leech_ratio > 0.001 and total_dealt > 0.01 and _caster_node != null and is_instance_valid(_caster_node):
		if _caster_node.has_method("heal_from_leech"):
			_caster_node.call("heal_from_leech", total_dealt * _leech_ratio)


func _apply_aoe_slow() -> void:
	if _slow_ratio <= 0.01 or not is_inside_tree():
		return
	var r2: float = (_radius + 0.45) * (_radius + 0.45)
	var enemies: Array[Node] = get_tree().get_nodes_in_group("active_enemies")
	for e_node in enemies:
		var e3d: Node3D = e_node as Node3D
		if e3d == null or not e3d.visible:
			continue
		var dx: float = e3d.global_position.x - global_position.x
		var dz: float = e3d.global_position.z - global_position.z
		if (dx * dx + dz * dz) <= r2 and e3d.has_method("apply_external_slow"):
			e3d.call("apply_external_slow", _slow_ratio, 0.35)
