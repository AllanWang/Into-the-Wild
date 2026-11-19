class_name BossMechanicProp
extends StaticBody3D

## Interactive 3D Boss Arena Prop supporting:
## - BASALT_PILLAR: Solid destructible lava pillar (shatters boss Monolith Armor on Bull-Rush impact)
## - VINE_SPAWNER: Coiled briar vine pillar spawning verdant swarmers while Briarbloom Matriarch stays impervious
## - SPORE_SAC: Swelling toxic pod that pops harmlessly if focused or erupts room-wide at 4.5s
## - ICE_OBELISK: Solid crystalline pillar casting a safe Whiteout shelter shadow & shattering on Lance/Dash
## - SLAM_VINE: Temporary Illaoi-style briar lash stalk that erupts near a player, winds up, and slams forward

enum PropKind {
	BASALT_PILLAR = 0,
	VINE_SPAWNER = 1,
	SPORE_SAC = 2,
	ICE_OBELISK = 3,
	SLAM_VINE = 4
}

const HazardScript = preload("res://world/enemy_hazard_effect.gd")
const OVERHEAD_BAR_SHADER: Shader = preload("res://shaders/OverheadBar.gdshader")
const HAZARD_SHADER: Shader = preload("res://shaders/EnemyHazard.gdshader")

signal prop_destroyed(prop: BossMechanicProp, was_player_cleared: bool)
signal pillar_impacted(prop: BossMechanicProp, shattered: bool)
signal obelisk_shattered(prop: BossMechanicProp, world_pos: Vector3)
signal spore_detonated(prop: BossMechanicProp, world_pos: Vector3)
signal vine_spawn_requested(prop: BossMechanicProp, world_pos: Vector3)

var prop_kind: int = PropKind.BASALT_PILLAR
var anchor_index: int = -1
var _boss_node: Node3D = null
var _players_root: Node3D = null
var _is_cleaned_up: bool = false
var _elapsed: float = 0.0

# Pillar durability
var _durability: int = 2
var _max_durability: int = 2

const SLAM_SEG_COUNT: int = 12
const SPAWNER_SEG_COUNT: int = 8

# Vine / Spore gameplay timers
var spawn_interval: float = 2.8
var _ability_timer: float = 2.0
var _fuse_timer: float = 0.0
var _fuse_duration: float = 4.5
var _hit_flash_timer: float = 0.0
var _slam_state: int = 0
var _slam_timer: float = 0.0
var _slam_duration: float = 1.0
var _slam_target_reach: float = 20.6
var _slam_target_width: float = 2.6
var _target_slam_yaw: float = 0.0
var _slam_yaw_initialized: bool = false
var _emerge_t: float = 1.0
var _spawner_pulse_t: float = 0.0
var _retracting: bool = false
var _retract_timer: float = 0.0
var _inst_slam_bark_mat: StandardMaterial3D = null
var _inst_slam_leaf_mat: StandardMaterial3D = null
var _inst_slam_thorn_mat: StandardMaterial3D = null
var _inst_slam_tip_mat: StandardMaterial3D = null

# Components
var health_comp: HealthComponent = null
var hurtbox_comp: HurtboxComponent = null
var _body_col: CollisionShape3D = null
var _hurt_col: CollisionShape3D = null

# Visuals
var _visual_root: Node3D = null
var _main_mesh: MeshInstance3D = null
var _accent_mesh: MeshInstance3D = null
var _vine_cluster_root: Node3D = null
var _spawner_vine_root: Node3D = null
var _spawner_joints: Array[Node3D] = []
var _spawner_flank_joints: Array = []
var _spawner_blossom_root: Node3D = null
var _spawner_heart_mesh: MeshInstance3D = null
var _spawner_petal_pivots: Array[Node3D] = []
var _spawner_flash_meshes: Array[MeshInstance3D] = []
var _slam_pivot: Node3D = null
var _slam_joints: Array[Node3D] = []
var _slam_seg_holders: Array[Node3D] = []
var _slam_base_lens: Array[float] = []
var _slam_base_rads: Array[float] = []
var _slam_thorn_meshes: Array[MeshInstance3D] = []
var _slam_tip_mesh: MeshInstance3D = null
var _ring_disc: MeshInstance3D = null
var _shelter_pivot: Node3D = null
var _shelter_mesh: MeshInstance3D = null
var _hp_bar_root: Node3D = null
var _hp_fill_mesh: MeshInstance3D = null
var _hp_bar_mat: ShaderMaterial = null
var _ring_mat: ShaderMaterial = null
var _main_mat_normal: StandardMaterial3D = null

static var _mesh_hex_pillar: CylinderMesh = null
static var _mesh_ice_spire: CylinderMesh = null
static var _mesh_vine_mound: CylinderMesh = null
static var _mesh_vine_seg: ArrayMesh = null
static var _mesh_lance_leaf: ArrayMesh = null
static var _mesh_briar_thorn: ArrayMesh = null
static var _mesh_root_claw: ArrayMesh = null
static var _mesh_sac: SphereMesh = null
static var _mesh_torus_band: TorusMesh = null
static var _mesh_floor_plane: PlaneMesh = null
static var _mesh_shelter_plane: PlaneMesh = null
static var _mesh_hp_quad: QuadMesh = null

static var _mat_basalt: StandardMaterial3D = null
static var _mat_basalt_cracked: StandardMaterial3D = null
static var _mat_magma_glow: StandardMaterial3D = null
static var _mat_vine_bark: StandardMaterial3D = null
static var _mat_vine_leaf: StandardMaterial3D = null
static var _mat_vine_thorn: StandardMaterial3D = null
static var _mat_vine_blossom: StandardMaterial3D = null
static var _mat_vine_bud: StandardMaterial3D = null
static var _mat_slam_thorn_hot: StandardMaterial3D = null
static var _mat_slam_tip: StandardMaterial3D = null
static var _mat_spore: StandardMaterial3D = null
static var _mat_ice: StandardMaterial3D = null
static var _mat_ice_core: StandardMaterial3D = null
static var _mat_shelter: StandardMaterial3D = null
static var _mat_hit_flash: StandardMaterial3D = null
static var _base_hp_bar_mat: ShaderMaterial = null


static func _ensure_shared() -> void:
	if _mesh_hex_pillar != null:
		return

	_mesh_hex_pillar = CylinderMesh.new()
	_mesh_hex_pillar.top_radius = 1.02
	_mesh_hex_pillar.bottom_radius = 1.18
	_mesh_hex_pillar.height = 3.5
	_mesh_hex_pillar.radial_segments = 6

	_mesh_ice_spire = CylinderMesh.new()
	_mesh_ice_spire.top_radius = 0.08
	_mesh_ice_spire.bottom_radius = 0.96
	_mesh_ice_spire.height = 3.3
	_mesh_ice_spire.radial_segments = 5

	_mesh_vine_mound = CylinderMesh.new()
	_mesh_vine_mound.top_radius = 0.68
	_mesh_vine_mound.bottom_radius = 1.24
	_mesh_vine_mound.height = 0.28
	_mesh_vine_mound.radial_segments = 10

	_mesh_vine_seg = _build_fluted_vine_segment_mesh()
	_mesh_lance_leaf = _build_lance_leaf_mesh()
	_mesh_briar_thorn = _build_curved_thorn_mesh()
	_mesh_root_claw = _build_root_claw_mesh()

	_mesh_sac = SphereMesh.new()
	_mesh_sac.radius = 0.65
	_mesh_sac.height = 1.3
	_mesh_sac.radial_segments = 14
	_mesh_sac.rings = 10

	_mesh_torus_band = TorusMesh.new()
	_mesh_torus_band.inner_radius = 1.02
	_mesh_torus_band.outer_radius = 1.24
	_mesh_torus_band.rings = 18
	_mesh_torus_band.ring_segments = 6

	_mesh_floor_plane = PlaneMesh.new()
	_mesh_floor_plane.size = Vector2(2.0, 2.0)

	_mesh_shelter_plane = PlaneMesh.new()
	_mesh_shelter_plane.size = Vector2(2.8, 9.5)

	_mesh_hp_quad = QuadMesh.new()
	_mesh_hp_quad.size = Vector2(1.0, 1.0)

	_mat_basalt = _make_toon_mat(Color(0.20, 0.17, 0.21), Color(0.28, 0.10, 0.04), 0.55)
	_mat_basalt_cracked = _make_toon_mat(Color(0.32, 0.18, 0.16), Color(0.95, 0.36, 0.08), 1.35)
	_mat_magma_glow = _make_unshaded_mat(Color(1.0, 0.56, 0.16, 0.95), false)
	_mat_vine_bark = _make_toon_mat(Color(0.09, 0.34, 0.14), Color(0.03, 0.14, 0.05), 0.45)
	_mat_vine_leaf = _make_toon_mat(Color(0.22, 0.72, 0.28), Color(0.08, 0.32, 0.11), 0.75)
	_mat_vine_leaf.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_vine_thorn = _make_toon_mat(Color(0.78, 0.98, 0.34), Color(0.36, 0.56, 0.10), 0.85)
	_mat_vine_blossom = _make_toon_mat(Color(0.76, 0.98, 0.32), Color(0.38, 0.62, 0.12), 1.05)
	_mat_vine_blossom.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_vine_bud = _make_toon_mat(Color(0.86, 1.0, 0.36), Color(0.52, 0.82, 0.14), 1.35)
	_mat_slam_thorn_hot = _make_toon_mat(Color(1.0, 0.34, 0.30), Color(0.95, 0.22, 0.22), 1.25)
	_mat_slam_tip = _make_toon_mat(Color(0.96, 0.38, 0.32), Color(0.82, 0.96, 0.26), 1.25)
	_mat_spore = _make_toon_mat(Color(0.48, 0.94, 0.34), Color(0.26, 0.55, 0.12), 1.15)
	_mat_ice = _make_toon_mat(Color(0.68, 0.94, 1.0), Color(0.18, 0.54, 0.78), 0.90)
	_mat_ice_core = _make_unshaded_mat(Color(0.56, 0.94, 1.0, 0.92), false)
	_mat_shelter = _make_unshaded_mat(Color(0.14, 0.82, 0.98, 0.34), true)
	_mat_hit_flash = _make_unshaded_mat(Color(1.0, 0.98, 0.92, 1.0), false)

	_base_hp_bar_mat = ShaderMaterial.new()
	_base_hp_bar_mat.shader = OVERHEAD_BAR_SHADER
	_base_hp_bar_mat.set_shader_parameter("fill_color", Color(0.96, 0.32, 0.38, 0.96))
	_base_hp_bar_mat.set_shader_parameter("bg_color", Color(0.05, 0.07, 0.11, 0.86))
	_base_hp_bar_mat.set_shader_parameter("border_color", Color(0.92, 0.89, 0.84, 0.38))


static func _make_toon_mat(albedo: Color, emission: Color, emit_energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.specular_mode = BaseMaterial3D.SPECULAR_TOON
	mat.albedo_color = albedo
	mat.roughness = 0.35
	mat.emission_enabled = true
	mat.emission = emission
	mat.emission_energy_multiplier = emit_energy
	return mat


static func _make_unshaded_mat(col: Color, alpha_blend: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	if alpha_blend:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


static func _add_outward_tri(
	st: SurfaceTool,
	v0: Vector3,
	v1: Vector3,
	v2: Vector3,
	n0: Vector3,
	n1: Vector3,
	n2: Vector3,
	outward_hint: Vector3
) -> void:
	# Godot 4 uses CW front-face winding: (v1 - v0).cross(v2 - v0) points opposite to outward front normal
	if (v1 - v0).cross(v2 - v0).dot(outward_hint) > 0.0:
		st.set_normal(n0)
		st.add_vertex(v0)
		st.set_normal(n2)
		st.add_vertex(v2)
		st.set_normal(n1)
		st.add_vertex(v1)
	else:
		st.set_normal(n0)
		st.add_vertex(v0)
		st.set_normal(n1)
		st.add_vertex(v1)
		st.set_normal(n2)
		st.add_vertex(v2)


static func _build_fluted_vine_segment_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides: int = 12
	var ys: Array[float] = [-0.04, 0.02, 0.28, 0.58, 0.90, 1.02]
	var r_mults: Array[float] = [0.34, 0.50, 0.47, 0.44, 0.42, 0.28]
	var rings: Array = []
	var norms: Array = []

	for ri in range(ys.size()):
		var y: float = ys[ri]
		var r_ring: float = r_mults[ri]
		var r_verts: Array[Vector3] = []
		var r_norms: Array[Vector3] = []
		for si in range(sides + 1):
			var ang: float = (float(si % sides) / float(sides)) * TAU
			var flute: float = 1.0 + 0.13 * sin(ang * 3.0 + y * 2.5)
			var r: float = r_ring * flute
			var nx: float = cos(ang)
			var nz: float = -sin(ang)
			var ny: float = -0.35 if ri == 0 else (0.35 if ri == ys.size() - 1 else 0.0)
			var nrm := Vector3(nx, ny, nz).normalized()
			r_verts.append(Vector3(nx * r, y, nz * r))
			r_norms.append(nrm)
		rings.append(r_verts)
		norms.append(r_norms)

	for ri in range(ys.size() - 1):
		var y_mid: float = 0.5 * (ys[ri] + ys[ri + 1])
		for si in range(sides):
			var v00: Vector3 = rings[ri][si]
			var v10: Vector3 = rings[ri][si + 1]
			var v01: Vector3 = rings[ri + 1][si]
			var v11: Vector3 = rings[ri + 1][si + 1]
			var n00: Vector3 = norms[ri][si]
			var n10: Vector3 = norms[ri][si + 1]
			var n01: Vector3 = norms[ri + 1][si]
			var n11: Vector3 = norms[ri + 1][si + 1]
			var mid: Vector3 = 0.25 * (v00 + v10 + v01 + v11)
			var out_h: Vector3 = (mid - Vector3(0.0, y_mid, 0.0)).normalized()
			_add_outward_tri(st, v00, v01, v11, n00, n01, n11, out_h)
			_add_outward_tri(st, v00, v11, v10, n00, n11, n10, out_h)

	return st.commit()


static func _build_lance_leaf_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var zs: Array[float] = [0.0, 0.20, 0.45, 0.68, 0.86, 0.98]
	var hs: Array[float] = [0.02, 0.12, 0.15, 0.11, 0.03, -0.05]
	var ws: Array[float] = [0.04, 0.21, 0.23, 0.17, 0.09, 0.0]

	for i in range(zs.size() - 1):
		var c0 := Vector3(0.0, hs[i] + (0.03 if (i >= 1 and i <= 3) else 0.01), zs[i])
		var l0 := Vector3(-ws[i], hs[i], zs[i])
		var r0 := Vector3(ws[i], hs[i], zs[i])
		var c1 := Vector3(0.0, hs[i + 1] + (0.03 if (i + 1 >= 1 and i + 1 <= 3) else 0.01), zs[i + 1])
		var l1 := Vector3(-ws[i + 1], hs[i + 1], zs[i + 1])
		var r1 := Vector3(ws[i + 1], hs[i + 1], zs[i + 1])
		var nl := Vector3(-0.18, 0.98, 0.0).normalized()
		var nr := Vector3(0.18, 0.98, 0.0).normalized()
		if i + 1 == zs.size() - 1:
			_add_outward_tri(st, l0, c1, c0, nl, Vector3.UP, Vector3.UP, Vector3.UP)
			_add_outward_tri(st, c0, c1, r0, Vector3.UP, Vector3.UP, nr, Vector3.UP)
		else:
			_add_outward_tri(st, l0, l1, c1, nl, nl, Vector3.UP, Vector3.UP)
			_add_outward_tri(st, l0, c1, c0, nl, Vector3.UP, Vector3.UP, Vector3.UP)
			_add_outward_tri(st, c0, c1, r1, Vector3.UP, Vector3.UP, nr, Vector3.UP)
			_add_outward_tri(st, c0, r1, r0, Vector3.UP, nr, nr, Vector3.UP)

	return st.commit()


static func _build_curved_thorn_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centers: Array[Vector3] = [
		Vector3(0.0, 0.0, 0.0),
		Vector3(0.0, 0.13, -0.02),
		Vector3(0.0, 0.25, -0.06),
		Vector3(0.0, 0.35, -0.12)
	]
	var rxs: Array[float] = [0.10, 0.072, 0.036, 0.004]
	var rzs: Array[float] = [0.13, 0.095, 0.048, 0.004]
	var sides: int = 6
	var rings: Array = []

	for ri in range(centers.size()):
		var ring_v: Array[Vector3] = []
		for si in range(sides + 1):
			var a: float = (float(si % sides) / float(sides)) * TAU
			ring_v.append(centers[ri] + Vector3(cos(a) * rxs[ri], 0.0, -sin(a) * rzs[ri]))
		rings.append(ring_v)

	for ri in range(centers.size() - 1):
		var c_mid: Vector3 = 0.5 * (centers[ri] + centers[ri + 1])
		for si in range(sides):
			var v00: Vector3 = rings[ri][si]
			var v10: Vector3 = rings[ri][si + 1]
			var v01: Vector3 = rings[ri + 1][si]
			var v11: Vector3 = rings[ri + 1][si + 1]
			var mid: Vector3 = 0.25 * (v00 + v10 + v01 + v11)
			var out_h: Vector3 = (mid - c_mid).normalized()
			var n00: Vector3 = (v00 - centers[ri]).normalized()
			var n10: Vector3 = (v10 - centers[ri]).normalized()
			var n01: Vector3 = (v01 - centers[ri + 1]).normalized()
			var n11: Vector3 = (v11 - centers[ri + 1]).normalized()
			_add_outward_tri(st, v00, v01, v11, n00, n01, n11, out_h)
			_add_outward_tri(st, v00, v11, v10, n00, n11, n10, out_h)

	return st.commit()


static func _build_root_claw_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3] = [
		Vector3(0.0, 0.34, 0.16),
		Vector3(0.0, 0.42, 0.52),
		Vector3(0.0, 0.24, 0.90),
		Vector3(0.0, -0.05, 1.32)
	]
	var rxs: Array[float] = [0.22, 0.16, 0.10, 0.03]
	var rys: Array[float] = [0.20, 0.14, 0.09, 0.03]
	var sides: int = 6
	var rings: Array = []

	for ri in range(pts.size()):
		var ring_v: Array[Vector3] = []
		for si in range(sides + 1):
			var a: float = (float(si % sides) / float(sides)) * TAU
			ring_v.append(pts[ri] + Vector3(cos(a) * rxs[ri], sin(a) * rys[ri], 0.0))
		rings.append(ring_v)

	for ri in range(pts.size() - 1):
		var c_mid: Vector3 = 0.5 * (pts[ri] + pts[ri + 1])
		for si in range(sides):
			var v00: Vector3 = rings[ri][si]
			var v10: Vector3 = rings[ri][si + 1]
			var v01: Vector3 = rings[ri + 1][si]
			var v11: Vector3 = rings[ri + 1][si + 1]
			var mid: Vector3 = 0.25 * (v00 + v10 + v01 + v11)
			var out_h: Vector3 = (mid - c_mid).normalized()
			var n00: Vector3 = (v00 - pts[ri]).normalized()
			var n10: Vector3 = (v10 - pts[ri]).normalized()
			var n01: Vector3 = (v01 - pts[ri + 1]).normalized()
			var n11: Vector3 = (v11 - pts[ri + 1]).normalized()
			_add_outward_tri(st, v00, v01, v11, n00, n01, n11, out_h)
			_add_outward_tri(st, v00, v11, v10, n00, n11, n10, out_h)

	return st.commit()


func _init() -> void:
	_ensure_shared()
	collision_layer = 1
	collision_mask = 0


func _ensure_nodes() -> void:
	if _visual_root != null:
		return

	_body_col = CollisionShape3D.new()
	_body_col.name = "CollisionShape3D"
	var body_cyl := CylinderShape3D.new()
	body_cyl.radius = 1.0
	body_cyl.height = 3.2
	_body_col.shape = body_cyl
	_body_col.position = Vector3(0.0, 1.6, 0.0)
	add_child(_body_col)

	health_comp = HealthComponent.new()
	health_comp.name = "HealthComponent"
	add_child(health_comp)
	health_comp.health_changed.connect(_on_health_changed)
	health_comp.died.connect(_on_died)

	hurtbox_comp = HurtboxComponent.new()
	hurtbox_comp.name = "HurtboxComponent"
	hurtbox_comp.health_component = health_comp
	_hurt_col = CollisionShape3D.new()
	_hurt_col.name = "CollisionShape3D"
	var hurt_cyl := CylinderShape3D.new()
	hurt_cyl.radius = 0.9
	hurt_cyl.height = 2.6
	_hurt_col.shape = hurt_cyl
	_hurt_col.position = Vector3(0.0, 1.3, 0.0)
	hurtbox_comp.add_child(_hurt_col)
	add_child(hurtbox_comp)

	_visual_root = Node3D.new()
	_visual_root.name = "VisualRoot"
	add_child(_visual_root)

	_main_mesh = MeshInstance3D.new()
	_main_mesh.name = "MainMesh"
	_main_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual_root.add_child(_main_mesh)

	_accent_mesh = MeshInstance3D.new()
	_accent_mesh.name = "AccentMesh"
	_accent_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual_root.add_child(_accent_mesh)

	_vine_cluster_root = Node3D.new()
	_vine_cluster_root.name = "VineClusterRoot"
	_vine_cluster_root.visible = false
	_visual_root.add_child(_vine_cluster_root)

	var mound := MeshInstance3D.new()
	mound.name = "VineMound"
	mound.mesh = _mesh_vine_mound
	mound.material_override = _mat_vine_bark
	mound.position = Vector3(0.0, 0.14, 0.0)
	mound.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vine_cluster_root.add_child(mound)

	for r_i in range(5):
		var r_ang: float = float(r_i) * (TAU / 5.0) + 0.18
		var claw := MeshInstance3D.new()
		claw.name = "VineRootClaw_%d" % r_i
		claw.mesh = _mesh_root_claw
		claw.material_override = _mat_vine_bark
		claw.rotation = Vector3(0.0, r_ang, 0.0)
		claw.scale = Vector3.ONE * 1.08
		claw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_vine_cluster_root.add_child(claw)

	for l_i in range(5):
		var l_ang: float = float(l_i) * (TAU / 5.0) + 0.78
		var l_piv := Node3D.new()
		l_piv.name = "CollarLeafPivot_%d" % l_i
		l_piv.position = Vector3(0.0, 0.22, 0.0)
		l_piv.rotation = Vector3(0.0, l_ang, 0.0)
		_vine_cluster_root.add_child(l_piv)

		var leaf := MeshInstance3D.new()
		leaf.name = "CollarLeaf_%d" % l_i
		leaf.mesh = _mesh_lance_leaf
		leaf.material_override = _mat_vine_leaf
		leaf.position = Vector3(0.0, 0.0, 0.42)
		leaf.rotation_degrees = Vector3(14.0, 0.0, 0.0)
		leaf.scale = Vector3(1.18, 1.0, 1.15)
		leaf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		l_piv.add_child(leaf)

	_spawner_flash_meshes.clear()
	_spawner_joints.clear()
	_spawner_petal_pivots.clear()
	_spawner_flank_joints.clear()

	_spawner_vine_root = Node3D.new()
	_spawner_vine_root.name = "SpawnerVineRoot"
	_spawner_vine_root.position = Vector3(0.0, 0.18, 0.0)
	_spawner_vine_root.visible = false
	_visual_root.add_child(_spawner_vine_root)

	var sp_parent: Node3D = _spawner_vine_root
	for k in range(SPAWNER_SEG_COUNT):
		var u: float = float(k) / float(SPAWNER_SEG_COUNT - 1)
		var seg_len: float = lerpf(0.62, 0.44, u)
		var seg_rad: float = lerpf(0.95, 0.36, pow(u, 0.85))
		var joint := Node3D.new()
		joint.name = "SpawnerJoint_%d" % k
		if k > 0:
			var prev_u: float = float(k - 1) / float(SPAWNER_SEG_COUNT - 1)
			joint.position = Vector3(0.0, lerpf(0.62, 0.44, prev_u), 0.0)
		sp_parent.add_child(joint)
		_spawner_joints.append(joint)

		var holder := Node3D.new()
		holder.name = "SpawnerHolder_%d" % k
		holder.scale = Vector3(seg_rad, seg_len, seg_rad)
		joint.add_child(holder)

		var seg_m := MeshInstance3D.new()
		seg_m.name = "SpawnerSeg_%d" % k
		seg_m.mesh = _mesh_vine_seg
		seg_m.material_override = _mat_vine_bark
		seg_m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(seg_m)
		_spawner_flash_meshes.append(seg_m)

		if k >= 1 and k <= SPAWNER_SEG_COUNT - 2:
			for t_side in [-1.0, 1.0]:
				var th := MeshInstance3D.new()
				th.name = "SpawnerThorn_%d_%d" % [k, int(t_side)]
				th.mesh = _mesh_briar_thorn
				th.material_override = _mat_vine_thorn
				th.position = Vector3(0.42 * t_side, 0.46 if t_side > 0.0 else 0.78, 0.0)
				th.rotation_degrees = Vector3(0.0, 0.0, -56.0 * t_side)
				th.scale = Vector3.ONE * 0.85
				th.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				holder.add_child(th)

		if k == 1 or k == 3 or k == 5:
			var lf := MeshInstance3D.new()
			lf.name = "SpawnerLeaf_%d" % k
			lf.mesh = _mesh_lance_leaf
			lf.material_override = _mat_vine_leaf
			lf.position = Vector3(0.0, 0.55, 0.25)
			lf.rotation_degrees = Vector3(18.0, 90.0 if (k == 3) else -50.0, 0.0)
			lf.scale = Vector3(0.85, 0.85, 0.95)
			lf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			joint.add_child(lf)

		sp_parent = joint

	_spawner_blossom_root = Node3D.new()
	_spawner_blossom_root.name = "SpawnerBlossom"
	_spawner_blossom_root.position = Vector3(0.0, 0.45, 0.0)
	sp_parent.add_child(_spawner_blossom_root)

	_spawner_heart_mesh = MeshInstance3D.new()
	_spawner_heart_mesh.name = "SpawnerSporeHeart"
	_spawner_heart_mesh.mesh = _mesh_sac
	_spawner_heart_mesh.material_override = _mat_vine_bud
	_spawner_heart_mesh.position = Vector3(0.0, 0.12, 0.0)
	_spawner_heart_mesh.scale = Vector3.ONE * 0.44
	_spawner_heart_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spawner_blossom_root.add_child(_spawner_heart_mesh)

	for p_i in range(5):
		var p_ang: float = float(p_i) * (TAU / 5.0)
		var p_piv := Node3D.new()
		p_piv.name = "BlossomPetalPivot_%d" % p_i
		p_piv.rotation = Vector3(0.0, p_ang, 0.0)
		_spawner_blossom_root.add_child(p_piv)
		_spawner_petal_pivots.append(p_piv)

		var petal := MeshInstance3D.new()
		petal.name = "BlossomPetal_%d" % p_i
		petal.mesh = _mesh_lance_leaf
		petal.material_override = _mat_vine_blossom
		petal.position = Vector3(0.0, 0.0, 0.08)
		petal.scale = Vector3(1.15, 1.0, 0.88)
		petal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p_piv.add_child(petal)

	for fl_i in range(2):
		var fl_base := Node3D.new()
		fl_base.name = "FlankTendril_%d" % fl_i
		var yaw_fl: float = 2.05 if fl_i == 0 else -2.05
		fl_base.position = Vector3(sin(yaw_fl) * 0.52, 0.14, cos(yaw_fl) * 0.52)
		fl_base.rotation = Vector3(0.0, yaw_fl, 0.0)
		_spawner_vine_root.add_child(fl_base)
		var fl_chain: Array[Node3D] = []
		var fl_parent: Node3D = fl_base
		for fk in range(4):
			var fu: float = float(fk) / 3.0
			var f_len: float = lerpf(0.48, 0.34, fu)
			var f_rad: float = lerpf(0.45, 0.18, fu)
			var fj := Node3D.new()
			fj.name = "FlankJoint_%d_%d" % [fl_i, fk]
			if fk > 0:
				fj.position = Vector3(0.0, lerpf(0.48, 0.34, float(fk - 1) / 3.0), 0.0)
			fl_parent.add_child(fj)
			fl_chain.append(fj)

			var fh := Node3D.new()
			fh.name = "FlankHolder_%d_%d" % [fl_i, fk]
			fh.scale = Vector3(f_rad, f_len, f_rad)
			fj.add_child(fh)

			var fm := MeshInstance3D.new()
			fm.name = "FlankSeg_%d_%d" % [fl_i, fk]
			fm.mesh = _mesh_vine_seg
			fm.material_override = _mat_vine_bark
			fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			fh.add_child(fm)
			_spawner_flash_meshes.append(fm)
			fl_parent = fj
		_spawner_flank_joints.append(fl_chain)

	_inst_slam_bark_mat = _make_slam_inst_mat(_mat_vine_bark, 2)
	_inst_slam_leaf_mat = _make_slam_inst_mat(_mat_vine_leaf, 3)
	_inst_slam_thorn_mat = _make_slam_inst_mat(_mat_vine_thorn, 3)
	_inst_slam_tip_mat = _make_slam_inst_mat(_mat_slam_tip, 3)

	_slam_joints.clear()
	_slam_seg_holders.clear()
	_slam_base_lens.clear()
	_slam_base_rads.clear()
	_slam_thorn_meshes.clear()

	_slam_pivot = Node3D.new()
	_slam_pivot.name = "SlamPivot"
	_slam_pivot.position = Vector3(0.0, 0.14, 0.0)
	_slam_pivot.visible = false
	_visual_root.add_child(_slam_pivot)

	var slam_parent: Node3D = _slam_pivot
	for k in range(SLAM_SEG_COUNT):
		var u: float = float(k) / float(SLAM_SEG_COUNT - 1)
		var base_len: float = lerpf(0.94, 0.76, u)
		var base_rad: float = lerpf(1.70, 0.65, pow(u, 0.78))
		_slam_base_lens.append(base_len)
		_slam_base_rads.append(base_rad)

		var joint := Node3D.new()
		joint.name = "SlamJoint_%d" % k
		joint.position = Vector3(0.0, 0.12 if k == 0 else _slam_base_lens[k - 1], 0.0)
		slam_parent.add_child(joint)
		_slam_joints.append(joint)

		var holder := Node3D.new()
		holder.name = "SlamHolder_%d" % k
		holder.scale = Vector3(base_rad, base_len, base_rad)
		joint.add_child(holder)
		_slam_seg_holders.append(holder)

		var seg_mesh := MeshInstance3D.new()
		seg_mesh.name = "SlamSegMesh_%d" % k
		seg_mesh.mesh = _mesh_vine_seg
		seg_mesh.material_override = _inst_slam_bark_mat
		seg_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(seg_mesh)

		if k >= 1 and k < SLAM_SEG_COUNT - 1:
			for s_sign in [-1.0, 1.0]:
				var th := MeshInstance3D.new()
				th.name = "SlamThorn_%d_%d" % [k, int(s_sign)]
				th.mesh = _mesh_briar_thorn
				th.material_override = _inst_slam_thorn_mat
				th.position = Vector3(0.35 * s_sign, 0.44 if s_sign > 0.0 else 0.76, 0.0)
				th.rotation_degrees = Vector3(0.0, 0.0, -68.0 * s_sign)
				th.scale = Vector3(0.44, 0.62, 0.44)
				th.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				holder.add_child(th)
				_slam_thorn_meshes.append(th)

		if k == 1 or k == 3 or k == 5 or k == 7:
			for s_sign in [-1.0, 1.0]:
				var lf := MeshInstance3D.new()
				lf.name = "SlamLeaf_%d_%d" % [k, int(s_sign)]
				lf.mesh = _mesh_lance_leaf
				lf.material_override = _inst_slam_leaf_mat
				lf.position = Vector3(0.28 * s_sign, 0.50, 0.0)
				lf.rotation_degrees = Vector3(12.0, 82.0 * s_sign, -18.0 * s_sign)
				lf.scale = Vector3(0.62, 0.72, 0.68)
				lf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				holder.add_child(lf)

		if k == SLAM_SEG_COUNT - 1:
			var spear := MeshInstance3D.new()
			spear.name = "SlamTipSpear"
			spear.mesh = _mesh_briar_thorn
			spear.material_override = _inst_slam_thorn_mat
			spear.position = Vector3(0.0, 0.88, 0.0)
			spear.rotation_degrees = Vector3(10.0, 0.0, 0.0)
			spear.scale = Vector3(1.45, 2.35, 1.45)
			spear.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			holder.add_child(spear)
			_slam_thorn_meshes.append(spear)

			_slam_tip_mesh = MeshInstance3D.new()
			_slam_tip_mesh.name = "SlamTipEmber"
			_slam_tip_mesh.mesh = _mesh_sac
			_slam_tip_mesh.material_override = _inst_slam_tip_mat
			_slam_tip_mesh.position = Vector3(0.0, 0.96, 0.0)
			_slam_tip_mesh.scale = Vector3.ONE * 0.24
			_slam_tip_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			holder.add_child(_slam_tip_mesh)

		slam_parent = joint

	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = HAZARD_SHADER
	_ring_mat.set_shader_parameter("inner_ratio", 0.0)
	_ring_mat.set_shader_parameter("hazard_stage", 0)
	_ring_mat.set_shader_parameter("fade_out", 1.0)

	_ring_disc = MeshInstance3D.new()
	_ring_disc.name = "FloorRingDisc"
	_ring_disc.mesh = _mesh_floor_plane
	_ring_disc.material_override = _ring_mat
	_ring_disc.position = Vector3(0.0, 0.04, 0.0)
	_ring_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring_disc.visible = false
	add_child(_ring_disc)

	_shelter_pivot = Node3D.new()
	_shelter_pivot.name = "ShelterPivot"
	_shelter_pivot.visible = false
	add_child(_shelter_pivot)

	_shelter_mesh = MeshInstance3D.new()
	_shelter_mesh.name = "ShelterShadowMesh"
	_shelter_mesh.mesh = _mesh_shelter_plane
	_shelter_mesh.material_override = _mat_shelter
	_shelter_mesh.position = Vector3(0.0, 0.042, 4.9)
	_shelter_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shelter_pivot.add_child(_shelter_mesh)

	_hp_bar_root = Node3D.new()
	_hp_bar_root.name = "HPBarRoot"
	_hp_bar_root.position = Vector3(0.0, 2.9, 0.0)
	_hp_bar_root.visible = false
	add_child(_hp_bar_root)

	_hp_bar_mat = _base_hp_bar_mat.duplicate() as ShaderMaterial
	_hp_fill_mesh = MeshInstance3D.new()
	_hp_fill_mesh.name = "HPFill"
	_hp_fill_mesh.mesh = _mesh_hp_quad
	_hp_fill_mesh.material_override = _hp_bar_mat
	_hp_fill_mesh.scale = Vector3(1.25, 0.11, 1.0)
	_hp_fill_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hp_bar_root.add_child(_hp_fill_mesh)


func configure(
	p_kind: int,
	p_pos: Vector3,
	p_boss: Node3D,
	p_players_root: Node3D,
	p_hp: float = 100.0,
	p_anchor_idx: int = -1
) -> void:
	_ensure_shared()
	_ensure_nodes()
	prop_kind = p_kind
	anchor_index = p_anchor_idx
	_boss_node = p_boss
	_players_root = p_players_root
	_is_cleaned_up = false
	_elapsed = 0.0
	_hit_flash_timer = 0.0
	_fuse_timer = 0.0
	spawn_interval = 2.8
	_ability_timer = 1.4 + float(maxi(0, p_anchor_idx) % 5) * 0.45
	_slam_state = 0
	_slam_timer = 0.0
	_slam_duration = 1.0
	_slam_target_reach = 20.6
	_slam_target_width = 2.6
	_slam_yaw_initialized = false
	_emerge_t = 1.0
	_spawner_pulse_t = 0.0
	_retracting = false
	_retract_timer = 0.0

	global_position = Vector3(p_pos.x, 0.0, p_pos.z)
	if is_inside_tree():
		reset_physics_interpolation()

	_vine_cluster_root.visible = false
	_vine_cluster_root.scale = Vector3.ONE
	_spawner_vine_root.visible = false
	_slam_pivot.visible = false
	_slam_pivot.position = Vector3(0.0, 0.14, 0.0)
	_slam_pivot.rotation = Vector3.ZERO
	if _slam_tip_mesh:
		_slam_tip_mesh.scale = Vector3.ONE * 0.24
	_ring_disc.visible = false
	_shelter_pivot.visible = false
	_hp_bar_root.visible = false
	_visual_root.scale = Vector3.ONE
	_visual_root.position = Vector3.ZERO
	_visual_root.rotation = Vector3.ZERO

	var is_targetable: bool = false
	var body_cyl: CylinderShape3D = _body_col.shape as CylinderShape3D
	var hurt_cyl: CylinderShape3D = _hurt_col.shape as CylinderShape3D

	match prop_kind:
		PropKind.BASALT_PILLAR:
			_durability = 2
			_max_durability = 2
			collision_layer = 1
			body_cyl.radius = 1.15
			body_cyl.height = 3.5
			_body_col.position = Vector3(0.0, 1.75, 0.0)
			_body_col.set_deferred("disabled", false)
			_main_mesh.visible = true
			_main_mesh.mesh = _mesh_hex_pillar
			_main_mesh.position = Vector3(0.0, 1.75, 0.0)
			_main_mesh.scale = Vector3.ONE
			_main_mat_normal = _mat_basalt
			_main_mesh.material_override = _mat_basalt
			_accent_mesh.mesh = _mesh_torus_band
			_accent_mesh.material_override = _mat_magma_glow
			_accent_mesh.position = Vector3(0.0, 1.85, 0.0)
			_accent_mesh.rotation_degrees = Vector3.ZERO
			_accent_mesh.scale = Vector3(1.06, 1.0, 1.06)
			_accent_mesh.visible = true

		PropKind.VINE_SPAWNER:
			is_targetable = true
			collision_layer = 4
			body_cyl.radius = 0.92
			body_cyl.height = 3.8
			_body_col.position = Vector3(0.0, 1.9, 0.0)
			_body_col.set_deferred("disabled", false)
			hurt_cyl.radius = 1.15
			hurt_cyl.height = 4.0
			_hurt_col.position = Vector3(0.0, 2.0, 0.0)
			_main_mesh.visible = false
			_accent_mesh.visible = false
			_vine_cluster_root.visible = true
			_spawner_vine_root.visible = true
			for m in _spawner_flash_meshes:
				if m:
					m.material_override = _mat_vine_bark
			_ring_mat.set_shader_parameter("hazard_color", Color(0.28, 0.94, 0.38, 1.0))
			_ring_mat.set_shader_parameter("border_danger_color", Color(0.86, 1.0, 0.34, 1.0))
			_ring_mat.set_shader_parameter("progress", 0.0)
			_ring_disc.scale = Vector3(3.0, 1.0, 3.0)
			_ring_disc.visible = true
			_hp_bar_root.position = Vector3(0.0, 4.65, 0.0)

		PropKind.SPORE_SAC:
			is_targetable = true
			_fuse_duration = 4.5
			collision_layer = 4
			body_cyl.radius = 0.68
			body_cyl.height = 1.6
			_body_col.position = Vector3(0.0, 0.8, 0.0)
			_body_col.set_deferred("disabled", false)
			hurt_cyl.radius = 0.85
			hurt_cyl.height = 1.8
			_hurt_col.position = Vector3(0.0, 0.9, 0.0)
			_main_mesh.visible = true
			_main_mesh.mesh = _mesh_sac
			_main_mesh.position = Vector3(0.0, 0.85, 0.0)
			_main_mesh.scale = Vector3.ONE * 0.65
			_main_mat_normal = _mat_spore
			_main_mesh.material_override = _mat_spore
			_accent_mesh.visible = false
			_ring_mat.set_shader_parameter("hazard_color", Color(0.42, 0.98, 0.44, 1.0))
			_ring_mat.set_shader_parameter("border_danger_color", Color(1.0, 0.22, 0.34, 1.0))
			_ring_mat.set_shader_parameter("progress", 0.0)
			_ring_disc.scale = Vector3(7.2, 1.0, 7.2)
			_ring_disc.visible = true
			_hp_bar_root.position = Vector3(0.0, 2.25, 0.0)

		PropKind.ICE_OBELISK:
			collision_layer = 1
			body_cyl.radius = 0.95
			body_cyl.height = 3.3
			_body_col.position = Vector3(0.0, 1.65, 0.0)
			_body_col.set_deferred("disabled", false)
			_main_mesh.visible = true
			_main_mesh.mesh = _mesh_ice_spire
			_main_mesh.position = Vector3(0.0, 1.65, 0.0)
			_main_mesh.scale = Vector3.ONE
			_main_mat_normal = _mat_ice
			_main_mesh.material_override = _mat_ice
			_accent_mesh.mesh = _mesh_torus_band
			_accent_mesh.material_override = _mat_ice_core
			_accent_mesh.position = Vector3(0.0, 1.25, 0.0)
			_accent_mesh.rotation_degrees = Vector3.ZERO
			_accent_mesh.scale = Vector3(0.76, 1.0, 0.76)
			_accent_mesh.visible = true

		PropKind.SLAM_VINE:
			is_targetable = false
			collision_layer = 0
			_body_col.set_deferred("disabled", true)
			_main_mesh.visible = false
			_accent_mesh.visible = false
			_vine_cluster_root.visible = true
			_vine_cluster_root.scale = Vector3.ONE * 0.30
			_slam_pivot.visible = true
			_slam_pivot.position = Vector3(0.0, -1.6, 0.0)
			_emerge_t = 0.0
			_set_slam_translucency(0.96, 0.0)
			_update_slam_vine_pose(0.0, 0.35, 1.0, false)
			_ring_mat.set_shader_parameter("hazard_color", Color(0.32, 0.96, 0.42, 1.0))
			_ring_mat.set_shader_parameter("border_danger_color", Color(1.0, 0.22, 0.30, 1.0))
			_ring_mat.set_shader_parameter("progress", 0.15)
			_ring_disc.scale = Vector3(1.65, 1.0, 1.65)
			_ring_disc.visible = true

	if is_targetable:
		if not is_in_group("active_enemies"):
			add_to_group("active_enemies")
		hurtbox_comp.set_active_deferred(true)
		health_comp.setup_max_health(maxf(10.0, p_hp))
		if _hp_bar_mat:
			_hp_bar_mat.set_shader_parameter("fill_ratio", 1.0)
		_hp_bar_root.visible = true
	else:
		if is_in_group("active_enemies"):
			remove_from_group("active_enemies")
		hurtbox_comp.set_active_deferred(false)
		_hp_bar_root.visible = false

	set_process(true)


func is_targetable_prop() -> bool:
	return (
		prop_kind == PropKind.VINE_SPAWNER
		or prop_kind == PropKind.SPORE_SAC
	)


static func _make_slam_inst_mat(base_mat: StandardMaterial3D, prio: int = 2) -> StandardMaterial3D:
	var mat: StandardMaterial3D = base_mat.duplicate() as StandardMaterial3D
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.render_priority = prio
	return mat


func _set_slam_translucency(alpha_val: float, hot_blend: float) -> void:
	var a: float = clampf(alpha_val, 0.0, 1.0)
	var h: float = clampf(hot_blend, 0.0, 1.0)
	if _inst_slam_bark_mat:
		_inst_slam_bark_mat.albedo_color = Color(0.06, 0.36, 0.22).lerp(Color(0.04, 0.30, 0.20), h)
		_inst_slam_bark_mat.albedo_color.a = a
		_inst_slam_bark_mat.emission = Color(0.03, 0.14, 0.06).lerp(Color(0.16, 0.42, 0.22), h)
		_inst_slam_bark_mat.emission_energy_multiplier = lerpf(0.45, 0.92, h)
	if _inst_slam_leaf_mat:
		_inst_slam_leaf_mat.albedo_color = Color(0.16, 0.66, 0.26, clampf(a + 0.06, 0.0, 1.0))
		_inst_slam_leaf_mat.emission = Color(0.06, 0.28, 0.10).lerp(Color(0.22, 0.56, 0.18), h)
		_inst_slam_leaf_mat.emission_energy_multiplier = lerpf(0.70, 1.00, h)
	if _inst_slam_thorn_mat:
		var a_th: float = clampf(a + 0.16, 0.0, 1.0)
		var base_c := Color(0.78, 0.98, 0.34, a_th)
		var hot_c := Color(1.0, 0.32, 0.28, a_th)
		_inst_slam_thorn_mat.albedo_color = base_c.lerp(hot_c, h)
		_inst_slam_thorn_mat.emission = Color(0.36, 0.56, 0.10).lerp(Color(0.95, 0.22, 0.22), h)
		_inst_slam_thorn_mat.emission_energy_multiplier = lerpf(0.85, 1.35, h)
	if _inst_slam_tip_mat:
		_inst_slam_tip_mat.albedo_color = Color(0.96, 0.38, 0.32, clampf(a + 0.18, 0.0, 1.0))
		_inst_slam_tip_mat.emission_energy_multiplier = lerpf(1.25, 1.65, h)


static func _pose_coiled_pitch(u: float) -> float:
	return lerpf(-0.22, 1.68, pow(clampf(u, 0.0, 1.0), 1.35))


static func _pose_windup_pitch(u: float) -> float:
	return lerpf(-0.62, 1.32, pow(clampf(u, 0.0, 1.0), 1.48))


func apply_combat_hit(
	raw_damage: float,
	hit_dir: Vector3,
	_proc_coeff: float,
	_shooter_stats: Object,
	_attacker_pos: Vector3 = Vector3.INF
) -> void:
	if _is_cleaned_up or not is_targetable_prop():
		return
	if health_comp == null or health_comp.is_dead:
		return
	_hit_flash_timer = 0.08
	if prop_kind == PropKind.VINE_SPAWNER:
		for m in _spawner_flash_meshes:
			if m:
				m.material_override = _mat_hit_flash
	elif _main_mesh:
		_main_mesh.material_override = _mat_hit_flash
	if _visual_root:
		_visual_root.scale = Vector3(1.12, 0.90, 1.12)
	health_comp.take_damage(raw_damage, hit_dir)


func take_boss_charge_impact() -> bool:
	if _is_cleaned_up or prop_kind != PropKind.BASALT_PILLAR:
		return false
	_durability -= 1
	var shattered: bool = _durability <= 0
	if not shattered:
		_main_mat_normal = _mat_basalt_cracked
		if _main_mesh:
			_main_mesh.material_override = _mat_basalt_cracked
		_visual_root.scale = Vector3(1.15, 0.88, 1.15)
		pillar_impacted.emit(self, false)
	else:
		pillar_impacted.emit(self, true)
		_finish_destroy(true)
	return shattered


func on_lance_hit(_hit_pos: Vector3) -> void:
	if _is_cleaned_up or prop_kind != PropKind.ICE_OBELISK:
		return
	var pos: Vector3 = global_position
	obelisk_shattered.emit(self, pos)
	_finish_destroy(true)


func set_whiteout_shadow(active: bool, boss_pos: Vector3) -> void:
	if _shelter_pivot == null or prop_kind != PropKind.ICE_OBELISK:
		return
	if not active:
		_shelter_pivot.visible = false
		return
	var away: Vector3 = global_position - boss_pos
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3.FORWARD
	else:
		away = away.normalized()
	_shelter_pivot.rotation.y = atan2(away.x, away.z)
	_shelter_pivot.visible = true


func set_vine_spawn_interval(interval_s: float) -> void:
	spawn_interval = maxf(1.2, interval_s)
	_ability_timer = minf(_ability_timer, spawn_interval * (0.45 + 0.10 * float(maxi(0, anchor_index) % 5)))


func trigger_vine_slam(
	aim_dir: Vector3,
	telegraph_s: float,
	ribbon_length: float = 22.0,
	ribbon_width: float = 2.6
) -> void:
	if _is_cleaned_up or prop_kind != PropKind.SLAM_VINE or _slam_pivot == null:
		return
	var flat_d := Vector3(aim_dir.x, 0.0, aim_dir.z)
	if flat_d.length_squared() < 0.0001:
		flat_d = Vector3.FORWARD
	else:
		flat_d = flat_d.normalized()
	_target_slam_yaw = atan2(flat_d.x, flat_d.z)
	if not _slam_yaw_initialized:
		_slam_pivot.rotation.y = _target_slam_yaw
		_slam_yaw_initialized = true
	_slam_target_reach = clampf(ribbon_length * 0.95, 12.0, 22.5)
	_slam_target_width = clampf(ribbon_width, 1.8, 3.6)
	_slam_state = 1
	_slam_timer = 0.0
	_slam_duration = maxf(0.40, telegraph_s)


func retract_and_free() -> void:
	if _is_cleaned_up:
		return
	_retracting = true
	_retract_timer = 0.0


func _update_spawner_vine_pose(delta: float, charge: float) -> void:
	if _spawner_joints.is_empty():
		return
	var phase_off: float = float(maxi(0, anchor_index)) * 1.15
	_spawner_pulse_t = maxf(0.0, _spawner_pulse_t - delta * 1.8)
	var prev_x: float = 0.0
	var prev_z: float = 0.0
	for k in range(_spawner_joints.size()):
		var u: float = float(k) / float(maxi(1, _spawner_joints.size() - 1))
		var pulse_wave: float = _spawner_pulse_t * sin(clampf(1.0 - u, 0.0, 1.0) * PI) * 0.14
		var cum_x: float = 0.24 * sin(u * PI * 1.6 + phase_off * 0.35) + sin(_elapsed * 2.2 - u * 3.1 + phase_off) * (0.06 + 0.10 * u) - pulse_wave
		var cum_z: float = 0.18 * cos(u * PI * 1.4 - phase_off * 0.25) + cos(_elapsed * 1.85 - u * 2.7 + phase_off) * (0.05 + 0.09 * u)
		_spawner_joints[k].rotation.x = cum_x - prev_x
		_spawner_joints[k].rotation.z = cum_z - prev_z
		prev_x = cum_x
		prev_z = cum_z

	for fl_i in range(_spawner_flank_joints.size()):
		var fl_chain: Array = _spawner_flank_joints[fl_i]
		var px: float = 0.0
		var pz: float = 0.0
		for fk in range(fl_chain.size()):
			var fu: float = float(fk) / float(maxi(1, fl_chain.size() - 1))
			var cx: float = lerpf(0.32, 0.98, fu) + sin(_elapsed * 2.5 + float(fl_i) * 2.1 - fu * 2.0) * 0.08
			var cz: float = sin(_elapsed * 2.1 + float(fl_i) * 1.4 - fu * 2.2) * 0.10
			var jn: Node3D = fl_chain[fk] as Node3D
			jn.rotation.x = cx - px
			jn.rotation.z = cz - pz
			px = cx
			pz = cz

	if _spawner_heart_mesh:
		var hs: float = lerpf(0.42, 0.68, charge) + _spawner_pulse_t * 0.16
		_spawner_heart_mesh.scale = Vector3.ONE * hs
	for p_i in range(_spawner_petal_pivots.size()):
		var p_piv: Node3D = _spawner_petal_pivots[p_i]
		if p_piv:
			var p_open: float = lerpf(-0.55, 0.32, charge) + sin(_elapsed * 3.2 + float(p_i) * 1.2) * 0.06
			p_piv.rotation.x = p_open


func _update_slam_vine_pose(
	strike_blend: float,
	emerge_scale: float,
	len_mult: float,
	use_windup_base: bool,
	windup_blend: float = 0.0,
	bounce_offset: float = 0.0
) -> void:
	if _slam_joints.is_empty():
		return
	var prev_pitch: float = 0.0
	var prev_sway: float = 0.0
	var prev_seg_len: float = 0.12
	var flat_pitch: float = PI * 0.50
	var phase_s: float = float(maxi(0, anchor_index)) * 1.37
	var total_base: float = 10.20
	var target_len_mult: float = clampf(_slam_target_reach / total_base, 1.15, 2.25)

	for k in range(_slam_joints.size()):
		var u: float = float(k) / float(maxi(1, _slam_joints.size() - 1))
		var coiled_p: float = _pose_coiled_pitch(u)
		var windup_p: float = _pose_windup_pitch(u)
		var rest_p: float = lerpf(coiled_p, windup_p, windup_blend) if use_windup_base else coiled_p
		if emerge_scale < 0.999:
			rest_p = lerpf(lerpf(0.10, 1.35, u), rest_p, emerge_scale)

		var seg_strike: float = clampf(strike_blend, 0.0, 1.0)
		var cum_pitch: float = lerpf(rest_p, flat_pitch, seg_strike) + bounce_offset * sin(u * PI) * (1.0 - u * 0.25)
		var sway_amt: float = lerpf(0.06, 0.025, seg_strike)
		var cum_sway: float = sin(_elapsed * 2.8 - u * 3.6 + phase_s) * sway_amt * u

		var base_len: float = _slam_base_lens[k]
		var base_rad: float = _slam_base_rads[k]
		var slammed_w: float = ((_slam_target_width * 0.96) / 0.96) * (lerpf(1.04, 0.92, u / 0.78) if u <= 0.78 else lerpf(0.92, 0.42, (u - 0.78) / 0.22))
		var slammed_thick: float = lerpf(0.30, 0.16, u)

		var k_len_mult: float = lerpf(len_mult, target_len_mult, seg_strike) if seg_strike > 0.001 else len_mult
		var cur_seg_len: float = base_len * k_len_mult * emerge_scale
		var cur_w: float = lerpf(base_rad, slammed_w, seg_strike)
		var cur_thick: float = lerpf(base_rad, slammed_thick, seg_strike)

		var j_node: Node3D = _slam_joints[k]
		if k == 0:
			j_node.position = Vector3(0.0, lerpf(0.12, 0.01, seg_strike), 0.0)
		else:
			j_node.position = Vector3(0.0, prev_seg_len, 0.0)
		j_node.rotation.x = cum_pitch - prev_pitch
		j_node.rotation.z = cum_sway - prev_sway

		var h_node: Node3D = _slam_seg_holders[k]
		h_node.scale = Vector3(cur_w, cur_seg_len, cur_thick)

		prev_pitch = cum_pitch
		prev_sway = cum_sway
		prev_seg_len = cur_seg_len


func _update_slam_vine_chain_stepped(
	mode: int,
	t_val: float,
	emerge_ease: float
) -> void:
	if _slam_joints.is_empty():
		return
	var prev_pitch: float = 0.0
	var prev_sway: float = 0.0
	var prev_seg_len: float = 0.12
	var flat_pitch: float = PI * 0.50
	var phase_s: float = float(maxi(0, anchor_index)) * 1.37
	var total_base: float = 10.20
	var target_len_mult: float = clampf(_slam_target_reach / total_base, 1.15, 2.25)

	for k in range(_slam_joints.size()):
		var u: float = float(k) / float(maxi(1, _slam_joints.size() - 1))
		var coiled_p: float = _pose_coiled_pitch(u)
		var windup_p: float = _pose_windup_pitch(u)

		var seg_strike: float = 0.0
		var k_len_mult: float = 1.0
		var rest_p: float = coiled_p

		if mode == 1:
			# Strike cascade (t_val in [0, 1]): trunk drives first, tip cracks last
			var u_delay: float = u * 0.28
			var jt: float = clampf((t_val - u_delay) / (1.0 - u_delay), 0.0, 1.0)
			var whip_jt: float = lerpf(jt * jt, jt * jt * (3.0 - 2.0 * jt), 0.35)
			rest_p = windup_p
			seg_strike = whip_jt
			k_len_mult = lerpf(1.15, target_len_mult, whip_jt)
		else:
			# Smooth base-to-tip peel-back recoil (t_val in [0, 1])
			var u_delay_r: float = u * 0.26
			var jr: float = clampf((t_val - u_delay_r) / (1.0 - u_delay_r), 0.0, 1.0)
			var peel_r: float = jr * jr * (3.0 - 2.0 * jr)
			rest_p = coiled_p
			seg_strike = 1.0 - peel_r
			k_len_mult = lerpf(target_len_mult, 1.0, peel_r)

		if emerge_ease < 0.999:
			rest_p = lerpf(lerpf(0.10, 1.35, u), rest_p, emerge_ease)

		var cum_pitch: float = lerpf(rest_p, flat_pitch, seg_strike)
		var sway_amt: float = lerpf(0.06, 0.025, seg_strike)
		var cum_sway: float = sin(_elapsed * 2.8 - u * 3.6 + phase_s) * sway_amt * u

		var base_len: float = _slam_base_lens[k]
		var base_rad: float = _slam_base_rads[k]
		var slammed_w: float = ((_slam_target_width * 0.96) / 0.96) * (lerpf(1.04, 0.92, u / 0.78) if u <= 0.78 else lerpf(0.92, 0.42, (u - 0.78) / 0.22))
		var slammed_thick: float = lerpf(0.30, 0.16, u)

		var cur_seg_len: float = base_len * k_len_mult * emerge_ease
		var cur_w: float = lerpf(base_rad, slammed_w, seg_strike)
		var cur_thick: float = lerpf(base_rad, slammed_thick, seg_strike)

		var j_node: Node3D = _slam_joints[k]
		if k == 0:
			j_node.position = Vector3(0.0, lerpf(0.12, 0.01, seg_strike), 0.0)
		else:
			j_node.position = Vector3(0.0, prev_seg_len, 0.0)
		j_node.rotation.x = cum_pitch - prev_pitch
		j_node.rotation.z = cum_sway - prev_sway

		var h_node: Node3D = _slam_seg_holders[k]
		h_node.scale = Vector3(cur_w, cur_seg_len, cur_thick)

		prev_pitch = cum_pitch
		prev_sway = cum_sway
		prev_seg_len = cur_seg_len


func _process(delta: float) -> void:
	if _is_cleaned_up:
		return
	_elapsed += delta

	if _retracting:
		_retract_timer += delta
		if prop_kind == PropKind.SLAM_VINE and _slam_pivot:
			var rt: float = clampf(_retract_timer / 0.38, 0.0, 1.0)
			var ease_rt: float = rt * rt * (3.0 - 2.0 * rt)
			_slam_pivot.position.y = lerpf(0.14, -2.8, ease_rt)
			if _vine_cluster_root:
				var c_fade: float = clampf(1.0 - maxf(0.0, (rt - 0.35) / 0.65), 0.05, 1.0)
				_vine_cluster_root.scale = Vector3.ONE * c_fade
			_set_slam_translucency(lerpf(0.88, 0.0, ease_rt), 0.0)
			_update_slam_vine_pose(0.0, clampf(1.0 - rt * 0.65, 0.25, 1.0), lerpf(1.0, 0.38, ease_rt), false)
			if _ring_mat:
				_ring_mat.set_shader_parameter("fade_out", clampf(1.0 - rt, 0.0, 1.0))
			if _retract_timer >= 0.38:
				_finish_destroy(false)
			return
		if _visual_root:
			_visual_root.scale = _visual_root.scale.lerp(Vector3(0.10, 0.02, 0.10), clampf(14.0 * delta, 0.0, 1.0))
		if _retract_timer >= 0.26:
			_finish_destroy(false)
		return

	if _hit_flash_timer > 0.0:
		_hit_flash_timer -= delta
		if _hit_flash_timer <= 0.0:
			if prop_kind == PropKind.VINE_SPAWNER:
				for m in _spawner_flash_meshes:
					if m:
						m.material_override = _mat_vine_bark
			elif _main_mesh and _main_mat_normal:
				_main_mesh.material_override = _main_mat_normal

	if _visual_root and prop_kind != PropKind.SLAM_VINE:
		_visual_root.scale = _visual_root.scale.lerp(Vector3.ONE, clampf(12.0 * delta, 0.0, 1.0))

	match prop_kind:
		PropKind.VINE_SPAWNER:
			_ability_timer -= delta
			var denom: float = maxf(1.0, spawn_interval)
			var charge: float = clampf(1.0 - _ability_timer / denom, 0.0, 1.0)
			if _ring_mat:
				_ring_mat.set_shader_parameter("progress", charge)
			if _ability_timer <= 0.0:
				_ability_timer = denom
				_spawner_pulse_t = 1.0
				if _visual_root:
					_visual_root.scale = Vector3(1.16, 0.88, 1.16)
				vine_spawn_requested.emit(self, global_position)
			_update_spawner_vine_pose(delta, charge)

		PropKind.SLAM_VINE:
			if _slam_pivot:
				if _emerge_t < 1.0:
					_emerge_t = minf(1.0, _emerge_t + delta / 0.28)
				var e_inv: float = 1.0 - _emerge_t
				var e_ease: float = 1.0 - (e_inv * e_inv * e_inv)
				_slam_pivot.position.y = lerpf(-1.6, 0.14, e_ease)
				if _vine_cluster_root:
					_vine_cluster_root.scale = Vector3.ONE * lerpf(0.30, 1.0, e_ease)
				var emp_s: float = lerpf(0.38, 1.0, e_ease)
				_slam_pivot.rotation.y = lerp_angle(_slam_pivot.rotation.y, _target_slam_yaw, clampf(10.0 * delta, 0.0, 1.0))

				if _slam_state == 0:
					_slam_pivot.position.y = lerpf(-1.6, 0.14, e_ease)
					_set_slam_translucency(0.94, 0.0)
					_update_slam_vine_pose(0.0, emp_s, 1.0, false)
					if _slam_tip_mesh:
						_slam_tip_mesh.scale = Vector3.ONE * 0.24
					if _ring_mat:
						_ring_mat.set_shader_parameter("progress", 0.15)
				elif _slam_state == 1:
					_slam_timer += delta
					var t: float = clampf(_slam_timer / _slam_duration, 0.0, 1.0)
					if t < 0.64:
						_slam_pivot.position.y = lerpf(-1.6, 0.14, e_ease)
						var w_t: float = clampf(t / 0.64, 0.0, 1.0)
						var w_ease: float = w_t * w_t * (3.0 - 2.0 * w_t)
						_set_slam_translucency(0.96, lerpf(0.0, 0.65, w_ease))
						_update_slam_vine_pose(0.0, emp_s, lerpf(1.0, 1.15, w_ease), true, w_ease)
					else:
						var s_t: float = clampf((t - 0.64) / 0.36, 0.0, 1.0)
						var s_ease: float = s_t * s_t * (3.0 - 2.0 * s_t)
						_slam_pivot.position.y = lerpf(0.14, 0.05, s_ease)
						var a_ease: float = clampf((s_t - 0.12) / 0.88, 0.0, 1.0)
						a_ease = a_ease * a_ease * (3.0 - 2.0 * a_ease)
						_set_slam_translucency(lerpf(0.96, 0.46, a_ease), lerpf(0.65, 1.0, s_t))
						_update_slam_vine_chain_stepped(1, s_t, emp_s)
					if _slam_tip_mesh:
						_slam_tip_mesh.scale = Vector3.ONE * lerpf(0.24, 0.42, t)
					if _ring_mat:
						_ring_mat.set_shader_parameter("progress", t)
					if _slam_timer >= _slam_duration:
						_slam_state = 2
						_slam_timer = 0.0
				elif _slam_state == 2:
					_slam_timer += delta
					var target_len_mult: float = clampf(_slam_target_reach / 10.20, 1.15, 2.25)
					if _slam_timer < 0.22:
						_slam_pivot.position.y = 0.05
						var bounce: float = -exp(-_slam_timer * 14.0) * absf(sin(_slam_timer * 34.0)) * 0.06
						_set_slam_translucency(0.46, 1.0)
						_update_slam_vine_pose(1.0, 1.0, target_len_mult, false, 0.0, bounce)
					elif _slam_timer < 0.62:
						var rec_t: float = clampf((_slam_timer - 0.22) / 0.40, 0.0, 1.0)
						var r_ease: float = rec_t * rec_t * (3.0 - 2.0 * rec_t)
						_slam_pivot.position.y = lerpf(0.05, 0.14, r_ease)
						_set_slam_translucency(lerpf(0.46, 0.94, r_ease), lerpf(1.0, 0.0, r_ease))
						_update_slam_vine_chain_stepped(2, rec_t, 1.0)
					else:
						_slam_pivot.position.y = 0.14
						_set_slam_translucency(0.94, 0.0)
						_update_slam_vine_pose(0.0, 1.0, 1.0, false)
						_slam_state = 0
					if _slam_tip_mesh:
						_slam_tip_mesh.scale = Vector3.ONE * 0.28
					if _ring_mat:
						_ring_mat.set_shader_parameter("progress", 1.0 if _slam_timer < 0.28 else 0.15)

		PropKind.SPORE_SAC:
			_fuse_timer += delta
			var prog: float = clampf(_fuse_timer / maxf(0.5, _fuse_duration), 0.0, 1.0)
			if _main_mesh:
				var s_val: float = lerpf(0.65, 1.45, prog)
				_main_mesh.scale = Vector3.ONE * s_val
				_main_mesh.position.y = 0.85 * s_val
			if _ring_mat:
				_ring_mat.set_shader_parameter("progress", prog)
			if _fuse_timer >= _fuse_duration:
				var pos: Vector3 = global_position
				if ProjectilePool and ProjectilePool.has_method("spawn_enemy_ground_hazard") and _players_root != null:
					ProjectilePool.call(
						"spawn_enemy_ground_hazard",
						HazardScript.HazardMode.GROUND_QUAKE,
						pos,
						pos,
						7.2,
						0.0,
						16.0,
						0.22,
						0.45,
						Color(0.45, 0.98, 0.42),
						0.42,
						_players_root
					)
				spore_detonated.emit(self, pos)
				_finish_destroy(false)


func _find_nearest_player() -> Node3D:
	if _players_root == null or not is_instance_valid(_players_root):
		return null
	var best: Node3D = null
	var best_d2: float = INF
	for i in range(_players_root.get_child_count()):
		var p3d: Node3D = _players_root.get_child(i) as Node3D
		if p3d == null or not p3d.visible:
			continue
		var d2: float = global_position.distance_squared_to(p3d.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = p3d
	return best


func _on_health_changed(cur_hp: float, max_hp: float) -> void:
	if _hp_bar_mat:
		_hp_bar_mat.set_shader_parameter("fill_ratio", clampf(cur_hp / maxf(1.0, max_hp), 0.0, 1.0))


func _on_died() -> void:
	_finish_destroy(true)


func _finish_destroy(was_player_cleared: bool) -> void:
	if _is_cleaned_up:
		return
	_is_cleaned_up = true
	if is_in_group("active_enemies"):
		remove_from_group("active_enemies")
	set_process(false)
	visible = false
	if _body_col:
		_body_col.set_deferred("disabled", true)
	if hurtbox_comp:
		hurtbox_comp.set_active_deferred(false)
	prop_destroyed.emit(self, was_player_cleared)
	queue_free()


func cleanup_and_free() -> void:
	if _is_cleaned_up:
		return
	_is_cleaned_up = true
	if is_in_group("active_enemies"):
		remove_from_group("active_enemies")
	set_process(false)
	visible = false
	if _body_col:
		_body_col.set_deferred("disabled", true)
	if hurtbox_comp:
		hurtbox_comp.set_active_deferred(false)
	queue_free()
