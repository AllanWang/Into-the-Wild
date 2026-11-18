class_name CombatZoneEffect
extends Node3D

## Pooled multi-mode 3D combat zone effect for AoE weapons, Abilities (Q/E), and Artifacts (R).
## Distinct Celestial Player Signatures: spinning 4-point inner diamond rune, inward-converging
## focus ring on casts, airy additive aura, and sky-beam flash on detonation!

enum ZoneMode {
	DELAYED_BLAST = 0,  ## Nova Mortar & Starfall Strike (inward focus convergence -> sky-beam blast)
	SOLAR_PILLAR = 1,   ## Solar Convergence [R] (3 orbital beam pulses over 1.35s)
	STASIS_FIELD = 2,   ## Frost Nova [Q/E] & Chronosphere [R] (spinning rune + persistent slow aura)
	SELF_WARD = 3,      ## Aegis Barrier & Tempo Surge (quick expanding aura ring around caster)
	WHIP_ARC = 4,       ## Chain Lash sweeping 116-deg ribbon cleave (+45% outer tip sweetspot!)
	INSTANT_BLAST = 5   ## Siege Cannon concussive detonation shockwave
}

var pool: Node = null

@onready var ring_mesh: MeshInstance3D = $RingMesh
@onready var disc_mesh: MeshInstance3D = $DiscMesh
@onready var pillar_mesh: MeshInstance3D = $PillarMesh

var inner_rune_mesh: MeshInstance3D = null
var focus_ring_mesh: MeshInstance3D = null
var outer_frame_mesh: MeshInstance3D = null
var whip_pivot: Node3D = null
var whip_cord_mesh: MeshInstance3D = null
var whip_wake_mesh: MeshInstance3D = null

var _mode: int = ZoneMode.DELAYED_BLAST
var _radius: float = 2.8
var _damage: float = 0.0
var _proc_coeff: float = 1.0
var _slow_ratio: float = 0.0
var _leech_ratio: float = 0.0
var _shooter_stats: Object = null
var _follow_target: Node3D = null
var _caster_node: Node3D = null
var _aim_dir: Vector3 = Vector3.FORWARD

var _elapsed: float = 0.0
var _duration: float = 0.5
var _detonated: bool = false
var _pulses_left: int = 0
var _pulse_timer: float = 0.0
var _slow_tick_timer: float = 0.0
var _active: bool = false

static var _shared_torus: TorusMesh = null
static var _shared_outer_frame: TorusMesh = null
static var _shared_diamond_rune: TorusMesh = null
static var _shared_disc: CylinderMesh = null
static var _shared_pillar: CylinderMesh = null
static var _shared_whip_fill: ArrayMesh = null
static var _shared_whip_rim: ArrayMesh = null
static var _shared_whip_cord: ArrayMesh = null
static var _shared_whip_wake: ArrayMesh = null
static var _ring_mats: Dictionary = {}
static var _fill_mats: Dictionary = {}
static var _frame_mats: Dictionary = {}
static var _whip_mats: Dictionary = {}


static func _build_sector_range_mesh(
	inner_r: float,
	outer_r: float,
	start_angle_deg: float,
	end_angle_deg: float,
	segs: int
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var start_rad: float = deg_to_rad(start_angle_deg)
	var end_rad: float = deg_to_rad(end_angle_deg)
	for i in range(segs):
		var a0: float = lerpf(start_rad, end_rad, float(i) / float(segs))
		var a1: float = lerpf(start_rad, end_rad, float(i + 1) / float(segs))
		var d0 := Vector3(sin(a0), 0.0, -cos(a0))
		var d1 := Vector3(sin(a1), 0.0, -cos(a1))
		var p00: Vector3 = d0 * inner_r
		var p01: Vector3 = d0 * outer_r
		var p10: Vector3 = d1 * inner_r
		var p11: Vector3 = d1 * outer_r
		st.set_normal(Vector3.UP)
		st.add_vertex(p00)
		st.add_vertex(p01)
		st.add_vertex(p11)
		st.set_normal(Vector3.UP)
		st.add_vertex(p00)
		st.add_vertex(p11)
		st.add_vertex(p10)
	return st.commit()


static func _build_sector_mesh(inner_r: float, outer_r: float, half_angle_deg: float, segs: int) -> ArrayMesh:
	return _build_sector_range_mesh(inner_r, outer_r, -half_angle_deg, half_angle_deg, segs)


## Builds an articulated curved whip ribbon extending continuously from near the caster's
## center (r = 0.02, y = 0.30) to the outer tip (r = 1.0, y = 0.03) with a slight trailing S-lag.
static func _build_whip_cord_mesh(segs: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3] = []
	var half_ws: Array[float] = []
	for i in range(segs + 1):
		var frac: float = float(i) / float(segs)
		var r: float = lerpf(0.02, 1.0, frac)
		var lag_rad: float = -0.18 * sin(frac * PI)
		var y_h: float = lerpf(0.30, 0.03, pow(frac, 0.72))
		pts.append(Vector3(sin(lag_rad) * r, y_h, -cos(lag_rad) * r))
		var hw: float = 0.012 + 0.004 * frac
		if frac >= 0.68 and frac <= 0.94:
			var tip_t: float = sin(((frac - 0.68) / 0.26) * PI)
			hw += 0.013 * tip_t
		elif frac > 0.94:
			hw = lerpf(0.016, 0.003, (frac - 0.94) / 0.06)
		half_ws.append(hw)

	for i in range(segs):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var fwd: Vector3 = b - a
		fwd.y = 0.0
		var side := Vector3.RIGHT
		if fwd.length_squared() > 0.00001:
			fwd = fwd.normalized()
			side = Vector3(-fwd.z, 0.0, fwd.x)
		var a0: Vector3 = a - side * half_ws[i]
		var a1: Vector3 = a + side * half_ws[i]
		var b0: Vector3 = b - side * half_ws[i + 1]
		var b1: Vector3 = b + side * half_ws[i + 1]
		st.set_normal(Vector3.UP)
		st.add_vertex(a0)
		st.add_vertex(b0)
		st.add_vertex(b1)
		st.set_normal(Vector3.UP)
		st.add_vertex(a0)
		st.add_vertex(b1)
		st.add_vertex(a1)
	return st.commit()


static func _ensure_shared() -> void:
	if _shared_torus != null:
		return

	_shared_torus = TorusMesh.new()
	_shared_torus.inner_radius = 0.88
	_shared_torus.outer_radius = 1.0
	_shared_torus.rings = 28
	_shared_torus.ring_segments = 8

	_shared_outer_frame = TorusMesh.new()
	_shared_outer_frame.inner_radius = 0.995
	_shared_outer_frame.outer_radius = 1.045
	_shared_outer_frame.rings = 28
	_shared_outer_frame.ring_segments = 8

	# Crisp 4-point celestial diamond rune for Friendly / Player AoEs!
	_shared_diamond_rune = TorusMesh.new()
	_shared_diamond_rune.inner_radius = 0.86
	_shared_diamond_rune.outer_radius = 0.96
	_shared_diamond_rune.rings = 4
	_shared_diamond_rune.ring_segments = 6

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

	_shared_whip_fill = _build_sector_mesh(0.03, 1.0, 58.0, 20)
	_shared_whip_rim = _build_sector_mesh(0.70, 1.0, 58.0, 20)
	_shared_whip_cord = _build_whip_cord_mesh(18)
	_shared_whip_wake = _build_sector_range_mesh(0.03, 1.0, -42.0, 0.0, 14)


static func _get_palette_mats(key: String, col: Color) -> Array[StandardMaterial3D]:
	_ensure_shared()
	if _ring_mats.has(key):
		return [_ring_mats[key] as StandardMaterial3D, _fill_mats[key] as StandardMaterial3D, _frame_mats[key] as StandardMaterial3D]

	var r_mat := StandardMaterial3D.new()
	r_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	r_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	r_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	r_mat.albedo_color = Color(col.r, col.g, col.b, 0.95)

	var f_mat := StandardMaterial3D.new()
	f_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	f_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	f_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	f_mat.albedo_color = Color(col.r * 0.48, col.g * 0.72, col.b * 0.96, 0.24)

	var frame_mat := StandardMaterial3D.new()
	frame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	frame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	frame_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	frame_mat.albedo_color = Color(col.r * 0.14, col.g * 0.26, col.b * 0.48, 0.82)

	_ring_mats[key] = r_mat
	_fill_mats[key] = f_mat
	_frame_mats[key] = frame_mat
	return [r_mat, f_mat, frame_mat]


static func _get_whip_mats(key: String, col: Color) -> Array[StandardMaterial3D]:
	_ensure_shared()
	if _whip_mats.has(key):
		return _whip_mats[key] as Array[StandardMaterial3D]

	var cord_mat := StandardMaterial3D.new()
	cord_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cord_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cord_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cord_mat.albedo_color = col.lightened(0.28)

	var wake_mat := StandardMaterial3D.new()
	wake_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wake_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wake_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	wake_mat.albedo_color = Color(col.r, col.g, col.b, 0.42)

	var rim_mat := StandardMaterial3D.new()
	rim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rim_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rim_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	rim_mat.albedo_color = Color(col.r, col.g, col.b, 0.34)

	var arr: Array[StandardMaterial3D] = [cord_mat, wake_mat, rim_mat]
	_whip_mats[key] = arr
	return arr


func _ensure_player_fx_nodes() -> void:
	_ensure_shared()
	if inner_rune_mesh == null:
		inner_rune_mesh = MeshInstance3D.new()
		inner_rune_mesh.name = "InnerRuneMesh"
		inner_rune_mesh.mesh = _shared_diamond_rune
		inner_rune_mesh.position = Vector3(0.0, 0.02, 0.0)
		inner_rune_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(inner_rune_mesh)
	if focus_ring_mesh == null:
		focus_ring_mesh = MeshInstance3D.new()
		focus_ring_mesh.name = "FocusRingMesh"
		focus_ring_mesh.mesh = _shared_torus
		focus_ring_mesh.position = Vector3(0.0, 0.025, 0.0)
		focus_ring_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(focus_ring_mesh)
	if outer_frame_mesh == null:
		outer_frame_mesh = MeshInstance3D.new()
		outer_frame_mesh.name = "OuterFrameMesh"
		outer_frame_mesh.mesh = _shared_outer_frame
		outer_frame_mesh.position = Vector3(0.0, 0.018, 0.0)
		outer_frame_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(outer_frame_mesh)
	if whip_pivot == null:
		whip_pivot = Node3D.new()
		whip_pivot.name = "WhipPivot"
		whip_pivot.visible = false
		add_child(whip_pivot)

		whip_cord_mesh = MeshInstance3D.new()
		whip_cord_mesh.name = "WhipCordMesh"
		whip_cord_mesh.mesh = _shared_whip_cord
		whip_cord_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		whip_pivot.add_child(whip_cord_mesh)

		whip_wake_mesh = MeshInstance3D.new()
		whip_wake_mesh.name = "WhipWakeMesh"
		whip_wake_mesh.mesh = _shared_whip_wake
		whip_wake_mesh.position = Vector3(0.0, 0.012, 0.0)
		whip_wake_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		whip_pivot.add_child(whip_wake_mesh)


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_ensure_player_fx_nodes()
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
	p_caster_node: Node3D = null,
	p_aim_dir: Vector3 = Vector3.FORWARD
) -> void:
	_ensure_player_fx_nodes()
	_mode = p_mode
	_radius = maxf(0.8, p_radius)
	_damage = maxf(0.0, p_damage)
	_proc_coeff = 1.0
	_slow_ratio = clampf(p_slow_ratio, 0.0, 0.90)
	_leech_ratio = clampf(p_leech_ratio, 0.0, 2.0)
	_shooter_stats = p_shooter_stats
	_follow_target = p_follow_target
	_caster_node = p_caster_node
	_aim_dir = Vector3(p_aim_dir.x, 0.0, p_aim_dir.z).normalized() if Vector2(p_aim_dir.x, p_aim_dir.z).length_squared() > 0.001 else Vector3.FORWARD
	_elapsed = 0.0
	_duration = maxf(0.16, p_duration)
	_detonated = false
	_slow_tick_timer = 0.0
	_active = true
	rotation = Vector3.ZERO

	var is_whip: bool = (_mode == ZoneMode.WHIP_ARC)
	var mats: Array[StandardMaterial3D] = _get_palette_mats(p_color_key, p_color)
	var w_mats: Array[StandardMaterial3D] = _get_whip_mats(p_color_key, p_color) if is_whip else ([] as Array[StandardMaterial3D])
	if ring_mesh:
		ring_mesh.mesh = (_shared_whip_rim as Mesh) if is_whip else (_shared_torus as Mesh)
		ring_mesh.material_override = w_mats[2] if is_whip else mats[0]
		ring_mesh.visible = true
	if disc_mesh:
		disc_mesh.mesh = (_shared_whip_fill as Mesh) if is_whip else (_shared_disc as Mesh)
		disc_mesh.material_override = mats[1]
		disc_mesh.visible = true
		disc_mesh.scale = Vector3.ONE if (is_whip or _mode == ZoneMode.DELAYED_BLAST) else Vector3.ONE * 0.25
	if pillar_mesh:
		pillar_mesh.material_override = mats[1]
		pillar_mesh.visible = (_mode == ZoneMode.SOLAR_PILLAR)
		pillar_mesh.scale = Vector3(1.0, 1.0, 1.0)
	if inner_rune_mesh:
		inner_rune_mesh.material_override = mats[0]
		inner_rune_mesh.visible = not is_whip
		inner_rune_mesh.scale = Vector3(0.68, 1.0, 0.68)
		inner_rune_mesh.rotation = Vector3.ZERO
	if focus_ring_mesh:
		focus_ring_mesh.material_override = mats[0]
		focus_ring_mesh.visible = (not is_whip) and (_mode != ZoneMode.INSTANT_BLAST)
		focus_ring_mesh.scale = Vector3.ONE if _mode == ZoneMode.DELAYED_BLAST else Vector3(0.42, 1.0, 0.42)
	if outer_frame_mesh:
		outer_frame_mesh.material_override = mats[2]
		outer_frame_mesh.visible = not is_whip
	if whip_pivot:
		whip_pivot.visible = is_whip
		if is_whip:
			whip_pivot.rotation = Vector3(0.0, deg_to_rad(58.0), 0.0)
			if whip_cord_mesh:
				whip_cord_mesh.material_override = w_mats[0]
			if whip_wake_mesh:
				whip_wake_mesh.material_override = w_mats[1]
				whip_wake_mesh.visible = false
				whip_wake_mesh.scale = Vector3(0.02, 1.0, 1.0)

	if is_inside_tree():
		global_position = Vector3(p_pos.x, 0.06, p_pos.z)
		if is_whip:
			look_at(global_position + _aim_dir, Vector3.UP)
		reset_physics_interpolation()
	else:
		position = Vector3(p_pos.x, 0.06, p_pos.z)
		if is_whip:
			rotation.y = atan2(-_aim_dir.x, -_aim_dir.z)

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
	elif _mode == ZoneMode.WHIP_ARC:
		_proc_coeff = 0.85
		scale = Vector3(_radius * 0.82, 1.0, _radius * 0.82)
		_apply_whip_cleave(_damage)
	elif _mode == ZoneMode.INSTANT_BLAST:
		scale = Vector3(_radius * 0.38, 1.0, _radius * 0.38)
		if disc_mesh:
			disc_mesh.scale = Vector3.ONE
		if _damage > 0.0:
			_apply_aoe_damage(_damage, true)
	else:
		# DELAYED_BLAST: inward-converging focus ring + airy glow (opposite of enemy outward fill!)
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
	if inner_rune_mesh:
		inner_rune_mesh.visible = false
	if focus_ring_mesh:
		focus_ring_mesh.visible = false
	if outer_frame_mesh:
		outer_frame_mesh.visible = false
	if whip_pivot:
		whip_pivot.visible = false
		whip_pivot.rotation = Vector3.ZERO


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
		var follow_pos: Vector3 = _follow_target.get_global_transform_interpolated().origin
		global_position = Vector3(follow_pos.x, 0.05, follow_pos.z)

	if inner_rune_mesh and inner_rune_mesh.visible:
		inner_rune_mesh.rotation.y += delta * 2.8

	match _mode:
		ZoneMode.DELAYED_BLAST:
			var telegraph_time: float = _duration - 0.16
			if not _detonated:
				var t: float = clampf(_elapsed / maxf(0.1, telegraph_time), 0.0, 1.0)
				if focus_ring_mesh:
					var s_f: float = lerpf(1.0, 0.12, t)
					focus_ring_mesh.scale = Vector3(s_f, 1.0, s_f)
				if disc_mesh:
					var breathe: float = 0.88 + 0.08 * sin(_elapsed * 10.0)
					disc_mesh.scale = Vector3(breathe, 1.0, breathe)
				if _elapsed >= telegraph_time:
					_detonated = true
					_apply_aoe_damage(_damage, true)
					if focus_ring_mesh:
						focus_ring_mesh.visible = false
					if disc_mesh:
						disc_mesh.scale = Vector3(1.12, 1.0, 1.12)
					if pillar_mesh:
						pillar_mesh.visible = true
						pillar_mesh.scale = Vector3(0.45, 1.0, 0.45)
					scale = Vector3(_radius * 1.12, 1.0, _radius * 1.12)
			else:
				var fade_t: float = clampf((_elapsed - telegraph_time) / 0.16, 0.0, 1.0)
				var s: float = lerpf(_radius * 1.12, _radius * 0.4, fade_t)
				scale = Vector3(s, 1.0, s)
				if pillar_mesh:
					var bw: float = lerpf(0.45, 0.05, fade_t)
					pillar_mesh.scale = Vector3(bw, 1.0, bw)
				if _elapsed >= _duration:
					_release_self()

		ZoneMode.SOLAR_PILLAR:
			if disc_mesh:
				var pulse_s: float = 0.85 + 0.15 * sin(_elapsed * 14.0)
				disc_mesh.scale = Vector3(pulse_s, 1.0, pulse_s)
			if focus_ring_mesh:
				var fp: float = 0.40 + 0.08 * cos(_elapsed * 12.0)
				focus_ring_mesh.scale = Vector3(fp, 1.0, fp)
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
			if focus_ring_mesh:
				var fs: float = 0.42 + 0.06 * sin(_elapsed * 6.0)
				focus_ring_mesh.scale = Vector3(fs, 1.0, fs)
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

		ZoneMode.WHIP_ARC:
			var tw: float = clampf(_elapsed / _duration, 0.0, 1.0)
			var r_t: float = clampf(tw / 0.22, 0.0, 1.0)
			var cur_s: float = lerpf(_radius * 0.82, _radius, r_t)
			scale = Vector3(cur_s, 1.0, cur_s)
			var sweep_t: float = 1.0 - pow(1.0 - tw, 2.35)
			if whip_pivot:
				# Decreasing Y rotation sweeps -Z clockwise from left (-58 deg) to right (+58 deg)
				whip_pivot.rotation.y = deg_to_rad(lerpf(58.0, -58.0, sweep_t))
			if whip_wake_mesh:
				var wake_span: float = (116.0 * sweep_t) / 42.0
				whip_wake_mesh.visible = sweep_t >= 0.02
				whip_wake_mesh.scale = Vector3(clampf(wake_span, 0.02, 1.0), 1.0, 1.0)
			if _elapsed >= _duration:
				_release_self()

		ZoneMode.INSTANT_BLAST:
			var tb: float = clampf(_elapsed / _duration, 0.0, 1.0)
			var eased_b: float = 1.0 - (1.0 - tb) * (1.0 - tb)
			var sb: float = lerpf(_radius * 0.38, _radius * 1.10, eased_b)
			scale = Vector3(sb, 1.0, sb)
			if disc_mesh:
				disc_mesh.scale = Vector3(1.0 - tb * 0.65, 1.0, 1.0 - tb * 0.65)
			if _elapsed >= _duration:
				_release_self()


func _apply_whip_cleave(base_dmg: float) -> void:
	if base_dmg <= 0.0 or not is_inside_tree():
		return
	var max_r: float = _radius + 0.45
	var max_r2: float = max_r * max_r
	var sweet_min_r: float = _radius * 0.70
	var cos_half: float = cos(deg_to_rad(60.0))
	var enemies: Array[Node] = get_tree().get_nodes_in_group("active_enemies")
	for e_node in enemies:
		var e3d: Node3D = e_node as Node3D
		if e3d == null or not e3d.visible:
			continue
		var dx: float = e3d.global_position.x - global_position.x
		var dz: float = e3d.global_position.z - global_position.z
		var d2: float = dx * dx + dz * dz
		if d2 > max_r2:
			continue
		var dist: float = sqrt(d2)
		var to_e: Vector3 = Vector3(dx, 0.0, dz) / maxf(0.001, dist)
		if dist > 1.0 and _aim_dir.dot(to_e) < cos_half:
			continue
		if e3d.has_method("apply_combat_hit"):
			var is_sweetspot: bool = (dist >= sweet_min_r)
			var final_dmg: float = base_dmg * (1.45 if is_sweetspot else 1.0)
			e3d.call("apply_combat_hit", final_dmg, to_e, _proc_coeff, _shooter_stats)


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
