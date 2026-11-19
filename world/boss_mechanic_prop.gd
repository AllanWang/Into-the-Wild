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

# Vine / Spore gameplay timers
var spawn_interval: float = 2.8
var _ability_timer: float = 2.0
var _fuse_timer: float = 0.0
var _fuse_duration: float = 4.5
var _hit_flash_timer: float = 0.0
var _slam_state: int = 0
var _slam_timer: float = 0.0
var _slam_duration: float = 1.0
var _retracting: bool = false
var _retract_timer: float = 0.0

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
var _slam_pivot: Node3D = null
var _slam_stalk_mesh: MeshInstance3D = null
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
static var _mesh_vine_stalk: CylinderMesh = null
static var _mesh_vine_leaf: BoxMesh = null
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
static var _mat_vine_bud: StandardMaterial3D = null
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
	_mesh_vine_mound.top_radius = 0.54
	_mesh_vine_mound.bottom_radius = 1.18
	_mesh_vine_mound.height = 0.52
	_mesh_vine_mound.radial_segments = 8

	_mesh_vine_stalk = CylinderMesh.new()
	_mesh_vine_stalk.top_radius = 0.28
	_mesh_vine_stalk.bottom_radius = 0.54
	_mesh_vine_stalk.height = 2.75
	_mesh_vine_stalk.radial_segments = 7

	_mesh_vine_leaf = BoxMesh.new()
	_mesh_vine_leaf.size = Vector3(0.96, 0.08, 0.36)

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
	_mat_vine_bark = _make_toon_mat(Color(0.14, 0.44, 0.18), Color(0.05, 0.22, 0.08), 0.65)
	_mat_vine_leaf = _make_toon_mat(Color(0.28, 0.80, 0.32), Color(0.10, 0.38, 0.14), 0.85)
	_mat_vine_bud = _make_toon_mat(Color(0.84, 1.0, 0.30), Color(0.46, 0.72, 0.10), 1.15)
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
	mound.position = Vector3(0.0, 0.26, 0.0)
	mound.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vine_cluster_root.add_child(mound)

	var coil_heights: Array[float] = [0.80, 1.50, 2.20]
	var coil_scales: Array[float] = [0.58, 0.50, 0.42]
	var coil_rots: Array[Vector3] = [Vector3(28.0, 0.0, -24.0), Vector3(-26.0, 40.0, 22.0), Vector3(24.0, -35.0, -20.0)]
	for c_i in range(3):
		var coil := MeshInstance3D.new()
		coil.name = "VineCoil_%d" % c_i
		coil.mesh = _mesh_torus_band
		coil.material_override = _mat_vine_leaf
		coil.position = Vector3(0.0, coil_heights[c_i], 0.0)
		coil.scale = Vector3.ONE * coil_scales[c_i]
		coil.rotation_degrees = coil_rots[c_i]
		coil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_vine_cluster_root.add_child(coil)

	for l_i in range(4):
		var l_ang: float = float(l_i) * (TAU / 4.0) + 0.4
		var l_piv := Node3D.new()
		l_piv.name = "VineLeafPivot_%d" % l_i
		l_piv.position = Vector3(0.0, 1.10 if (l_i % 2 == 0) else 1.95, 0.0)
		l_piv.rotation = Vector3(0.0, l_ang, 0.0)
		_vine_cluster_root.add_child(l_piv)

		var leaf := MeshInstance3D.new()
		leaf.name = "VineLeaf_%d" % l_i
		leaf.mesh = _mesh_vine_leaf
		leaf.material_override = _mat_vine_leaf
		leaf.position = Vector3(0.0, 0.08, 0.62)
		leaf.rotation_degrees = Vector3(-26.0, 0.0, 0.0)
		leaf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		l_piv.add_child(leaf)

	_slam_pivot = Node3D.new()
	_slam_pivot.name = "SlamPivot"
	_slam_pivot.position = Vector3(0.0, 0.22, 0.0)
	_slam_pivot.visible = false
	_visual_root.add_child(_slam_pivot)

	_slam_stalk_mesh = MeshInstance3D.new()
	_slam_stalk_mesh.name = "SlamStalk"
	_slam_stalk_mesh.mesh = _mesh_vine_stalk
	_slam_stalk_mesh.material_override = _mat_vine_bark
	_slam_stalk_mesh.position = Vector3(0.0, 1.72, 0.0)
	_slam_stalk_mesh.scale = Vector3(0.95, 1.25, 0.95)
	_slam_stalk_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_slam_pivot.add_child(_slam_stalk_mesh)

	_slam_tip_mesh = MeshInstance3D.new()
	_slam_tip_mesh.name = "SlamTipBud"
	_slam_tip_mesh.mesh = _mesh_sac
	_slam_tip_mesh.material_override = _mat_slam_tip
	_slam_tip_mesh.position = Vector3(0.0, 3.45, 0.0)
	_slam_tip_mesh.scale = Vector3.ONE * 0.42
	_slam_tip_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_slam_pivot.add_child(_slam_tip_mesh)

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
	_retracting = false
	_retract_timer = 0.0

	global_position = Vector3(p_pos.x, 0.0, p_pos.z)
	if is_inside_tree():
		reset_physics_interpolation()

	_vine_cluster_root.visible = false
	_slam_pivot.visible = false
	_slam_pivot.rotation = Vector3.ZERO
	_slam_tip_mesh.scale = Vector3.ONE * 0.42
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
			body_cyl.radius = 0.86
			body_cyl.height = 2.8
			_body_col.position = Vector3(0.0, 1.4, 0.0)
			_body_col.set_deferred("disabled", false)
			hurt_cyl.radius = 1.05
			hurt_cyl.height = 2.9
			_hurt_col.position = Vector3(0.0, 1.45, 0.0)
			_main_mesh.visible = true
			_main_mesh.mesh = _mesh_vine_stalk
			_main_mesh.position = Vector3(0.0, 1.38, 0.0)
			_main_mesh.scale = Vector3.ONE
			_main_mat_normal = _mat_vine_bark
			_main_mesh.material_override = _mat_vine_bark
			_accent_mesh.mesh = _mesh_sac
			_accent_mesh.material_override = _mat_vine_bud
			_accent_mesh.position = Vector3(0.0, 2.78, 0.0)
			_accent_mesh.rotation_degrees = Vector3.ZERO
			_accent_mesh.scale = Vector3.ONE * 0.46
			_accent_mesh.visible = true
			_vine_cluster_root.visible = true
			_ring_mat.set_shader_parameter("hazard_color", Color(0.28, 0.94, 0.38, 1.0))
			_ring_mat.set_shader_parameter("border_danger_color", Color(0.86, 1.0, 0.34, 1.0))
			_ring_mat.set_shader_parameter("progress", 0.0)
			_ring_disc.scale = Vector3(2.8, 1.0, 2.8)
			_ring_disc.visible = true
			_hp_bar_root.position = Vector3(0.0, 3.45, 0.0)

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
			_slam_pivot.visible = true
			_visual_root.scale = Vector3(0.15, 0.06, 0.15)
			_ring_mat.set_shader_parameter("hazard_color", Color(0.32, 0.96, 0.42, 1.0))
			_ring_mat.set_shader_parameter("border_danger_color", Color(1.0, 0.22, 0.30, 1.0))
			_ring_mat.set_shader_parameter("progress", 0.15)
			_ring_disc.scale = Vector3(1.5, 1.0, 1.5)
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
	if _main_mesh:
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


func trigger_vine_slam(aim_dir: Vector3, telegraph_s: float) -> void:
	if _is_cleaned_up or prop_kind != PropKind.SLAM_VINE or _slam_pivot == null:
		return
	var flat_d := Vector3(aim_dir.x, 0.0, aim_dir.z)
	if flat_d.length_squared() < 0.0001:
		flat_d = Vector3.FORWARD
	else:
		flat_d = flat_d.normalized()
	_slam_pivot.rotation.y = atan2(flat_d.x, flat_d.z)
	_slam_state = 1
	_slam_timer = 0.0
	_slam_duration = maxf(0.35, telegraph_s)


func retract_and_free() -> void:
	if _is_cleaned_up:
		return
	_retracting = true
	_retract_timer = 0.0


func _process(delta: float) -> void:
	if _is_cleaned_up:
		return
	_elapsed += delta

	if _retracting:
		_retract_timer += delta
		if _visual_root:
			_visual_root.scale = _visual_root.scale.lerp(Vector3(0.10, 0.02, 0.10), clampf(14.0 * delta, 0.0, 1.0))
		if _retract_timer >= 0.26:
			_finish_destroy(false)
		return

	if _hit_flash_timer > 0.0:
		_hit_flash_timer -= delta
		if _hit_flash_timer <= 0.0 and _main_mesh and _main_mat_normal:
			_main_mesh.material_override = _main_mat_normal

	if _visual_root:
		_visual_root.scale = _visual_root.scale.lerp(Vector3.ONE, clampf(12.0 * delta, 0.0, 1.0))

	match prop_kind:
		PropKind.VINE_SPAWNER:
			if _visual_root:
				var phase_off: float = float(maxi(0, anchor_index)) * 1.1
				_visual_root.rotation.z = sin(_elapsed * 2.3 + phase_off) * 0.05
				_visual_root.rotation.x = cos(_elapsed * 1.9 + phase_off) * 0.04
			_ability_timer -= delta
			var denom: float = maxf(1.0, spawn_interval)
			var charge: float = clampf(1.0 - _ability_timer / denom, 0.0, 1.0)
			if _accent_mesh:
				_accent_mesh.scale = Vector3.ONE * lerpf(0.42, 0.68, charge)
			if _ring_mat:
				_ring_mat.set_shader_parameter("progress", charge)
			if _ability_timer <= 0.0:
				_ability_timer = denom
				if _visual_root:
					_visual_root.scale = Vector3(1.24, 0.82, 1.24)
				vine_spawn_requested.emit(self, global_position)

		PropKind.SLAM_VINE:
			if _slam_pivot:
				if _slam_state == 0:
					_slam_pivot.rotation.x = lerpf(_slam_pivot.rotation.x, sin(_elapsed * 2.6 + float(maxi(0, anchor_index))) * 0.06, clampf(10.0 * delta, 0.0, 1.0))
					if _slam_tip_mesh:
						_slam_tip_mesh.scale = Vector3.ONE * 0.42
					if _ring_mat:
						_ring_mat.set_shader_parameter("progress", 0.15)
				elif _slam_state == 1:
					_slam_timer += delta
					var t: float = clampf(_slam_timer / _slam_duration, 0.0, 1.0)
					_slam_pivot.rotation.x = lerpf(-0.12, -0.52, t) + sin(_elapsed * 34.0) * 0.04 * t
					if _slam_tip_mesh:
						_slam_tip_mesh.scale = Vector3.ONE * lerpf(0.38, 0.72, t)
					if _ring_mat:
						_ring_mat.set_shader_parameter("progress", t)
					if _slam_timer >= _slam_duration:
						_slam_state = 2
						_slam_timer = 0.0
				elif _slam_state == 2:
					_slam_timer += delta
					if _slam_timer < 0.10:
						var s_t: float = clampf(_slam_timer / 0.10, 0.0, 1.0)
						_slam_pivot.rotation.x = lerpf(-0.52, 1.45, s_t)
					elif _slam_timer < 0.36:
						_slam_pivot.rotation.x = 1.45
					elif _slam_timer < 0.52:
						var r_t: float = clampf((_slam_timer - 0.36) / 0.16, 0.0, 1.0)
						_slam_pivot.rotation.x = lerpf(1.45, 0.0, r_t)
					else:
						_slam_pivot.rotation.x = 0.0
						_slam_state = 0
					if _slam_tip_mesh:
						_slam_tip_mesh.scale = Vector3.ONE * 0.46
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
