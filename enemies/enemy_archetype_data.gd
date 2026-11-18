class_name EnemyArchetypeData
extends Resource

## Data Resource + shared static GPU/Physics resource cache for progressive Mini-Unit Spheres,
## Specialized Arena Elites, and Multi-Pattern Bosses.
## Shares meshes, materials, and SphereShape3Ds across all pooled enemies for zero per-spawn allocation.

enum ArchetypeId {
	CHASER = 0,          ## Agile crimson swarm sphere
	DASHER = 1,          ## Electric-cyan mini-sphere with swept wing-fins & spin wind-up juke-dash
	BURROWER = 2,        ## Subterranean amethyst-gold mini-sphere with nose drill-auger & invulnerable tunnel
	LUNGER = 3,          ## Fiery coral-orange striker sphere with twin tusks & crouched wind-up lunge
	BRUISER = 4,         ## Heavy armored amber sentinel with orbiting monolith shields & levitating quake slam
	MIRE_LOBBER = 5,     ## Standoff emerald castor with overhead swelling toxic mortar sac
	OCULAR_SNIPER = 6,   ## Long-range alabaster-gold marksman with spinning front scope monocle
	BOSS = 7,            ## Tectonic Sovereign — double-quake rings, bull-rush pillar/wall stun & seismic cross
	BOSS_BLIGHTWEAVER = 8, ## Blightweaver Core — acidic rain, warded conduit phase & plague spiral
	BOSS_CRYO_ARCHON = 9,  ## Cryo-Archon Valkyrie — glacial dash-slashes, rime lances & whiteout blizzard eye
	BOSS_CHRONOMANCER = 10 ## Astral Chronomancer — predictive starfall, temporal supernova & clockwork spiral
}

@export var archetype_id: ArchetypeId = ArchetypeId.CHASER
@export var display_name: String = "Crimson Wisp"
@export var radius: float = 0.38
@export var max_hp: float = 40.0
@export var contact_damage: float = 6.0
@export var move_speed: float = 3.8
@export var acceleration: float = 16.0
@export var can_lunge: bool = false
@export var accent_color: Color = Color(1.0, 0.4, 0.5, 1.0)

var body_material: StandardMaterial3D = null
var trim_material: StandardMaterial3D = null
var body_shape: SphereShape3D = null
var hurtbox_shape: SphereShape3D = null

const OVERHEAD_BAR_SHADER: Shader = preload("res://shaders/OverheadBar.gdshader")
const CONTACT_SHADOW_SHADER: Shader = preload("res://shaders/ContactShadow.gdshader")

static var _cache: Dictionary = {}
static var _unit_sphere_mesh: SphereMesh = null
static var _trim_ring_mesh: TorusMesh = null
static var _burrow_ring_mesh: TorusMesh = null
static var _fin_mesh: BoxMesh = null
static var _cone_spike_mesh: CylinderMesh = null
static var _plate_mesh: BoxMesh = null
static var _scope_ring_mesh: TorusMesh = null
static var _sac_orb_mesh: SphereMesh = null
static var _hit_flash_material: StandardMaterial3D = null
static var _armor_shell_mat: StandardMaterial3D = null
static var _impervious_shell_mat: StandardMaterial3D = null
static var _status_poison_mat: StandardMaterial3D = null
static var _status_burn_mat: StandardMaterial3D = null
static var _status_frost_mat: StandardMaterial3D = null
static var _hp_bar_material: ShaderMaterial = null
static var _hp_quad_mesh: QuadMesh = null
static var _contact_shadow_mesh: PlaneMesh = null
static var _contact_shadow_mat: ShaderMaterial = null


static func is_boss_archetype(id: int) -> bool:
	return (
		id == ArchetypeId.BOSS
		or id == ArchetypeId.BOSS_BLIGHTWEAVER
		or id == ArchetypeId.BOSS_CRYO_ARCHON
		or id == ArchetypeId.BOSS_CHRONOMANCER
	)


static func get_boss_epithet(id: int) -> String:
	match id:
		ArchetypeId.BOSS:
			return "Magma Earthshaker"
		ArchetypeId.BOSS_BLIGHTWEAVER:
			return "Verdant Broodmother"
		ArchetypeId.BOSS_CRYO_ARCHON:
			return "Rimeblade Sovereign"
		ArchetypeId.BOSS_CHRONOMANCER:
			return "Cosmic Timeweaver"
	return "Apex Warden"


static func _ensure_cache() -> void:
	if not _cache.is_empty():
		return

	_unit_sphere_mesh = SphereMesh.new()
	_unit_sphere_mesh.radius = 1.0
	_unit_sphere_mesh.height = 2.0
	_unit_sphere_mesh.radial_segments = 20
	_unit_sphere_mesh.rings = 12

	_trim_ring_mesh = TorusMesh.new()
	_trim_ring_mesh.inner_radius = 1.18
	_trim_ring_mesh.outer_radius = 1.32
	_trim_ring_mesh.rings = 24
	_trim_ring_mesh.ring_segments = 8

	_burrow_ring_mesh = TorusMesh.new()
	_burrow_ring_mesh.inner_radius = 0.72
	_burrow_ring_mesh.outer_radius = 1.05
	_burrow_ring_mesh.rings = 20
	_burrow_ring_mesh.ring_segments = 6

	_fin_mesh = BoxMesh.new()
	_fin_mesh.size = Vector3(0.12, 0.08, 0.65)

	_cone_spike_mesh = CylinderMesh.new()
	_cone_spike_mesh.top_radius = 0.03
	_cone_spike_mesh.bottom_radius = 0.28
	_cone_spike_mesh.height = 0.78
	_cone_spike_mesh.radial_segments = 6

	_plate_mesh = BoxMesh.new()
	_plate_mesh.size = Vector3(0.24, 0.62, 0.14)

	_scope_ring_mesh = TorusMesh.new()
	_scope_ring_mesh.inner_radius = 0.42
	_scope_ring_mesh.outer_radius = 0.54
	_scope_ring_mesh.rings = 18
	_scope_ring_mesh.ring_segments = 6

	_sac_orb_mesh = SphereMesh.new()
	_sac_orb_mesh.radius = 0.46
	_sac_orb_mesh.height = 0.92
	_sac_orb_mesh.radial_segments = 12
	_sac_orb_mesh.rings = 8

	_hit_flash_material = StandardMaterial3D.new()
	_hit_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hit_flash_material.albedo_color = Color(1.0, 0.98, 0.92, 1.0)

	_armor_shell_mat = StandardMaterial3D.new()
	_armor_shell_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_armor_shell_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_armor_shell_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_armor_shell_mat.albedo_color = Color(1.0, 0.80, 0.22, 0.28)

	_impervious_shell_mat = StandardMaterial3D.new()
	_impervious_shell_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_impervious_shell_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_impervious_shell_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_impervious_shell_mat.albedo_color = Color(1.0, 0.95, 0.68, 0.44)

	_status_poison_mat = _make_status_mat(Color(0.32, 0.90, 0.44), Color(0.10, 0.45, 0.16))
	_status_burn_mat = _make_status_mat(Color(1.0, 0.46, 0.14), Color(0.58, 0.16, 0.02))
	_status_frost_mat = _make_status_mat(Color(0.46, 0.88, 1.0), Color(0.12, 0.38, 0.54))

	_hp_bar_material = ShaderMaterial.new()
	_hp_bar_material.shader = OVERHEAD_BAR_SHADER
	_hp_bar_material.set_shader_parameter("fill_color", Color(0.96, 0.28, 0.34, 0.96))
	_hp_bar_material.set_shader_parameter("bg_color", Color(0.05, 0.07, 0.11, 0.86))
	_hp_bar_material.set_shader_parameter("border_color", Color(0.92, 0.89, 0.84, 0.38))

	_hp_quad_mesh = QuadMesh.new()
	_hp_quad_mesh.size = Vector2(1.0, 1.0)

	_contact_shadow_mesh = PlaneMesh.new()
	_contact_shadow_mesh.size = Vector2(1.0, 1.0)

	_contact_shadow_mat = ShaderMaterial.new()
	_contact_shadow_mat.render_priority = -1
	_contact_shadow_mat.shader = CONTACT_SHADOW_SHADER

	_cache[ArchetypeId.CHASER] = _build_entry(
		ArchetypeId.CHASER, "Crimson Wisp",
		0.38, 40.0, 5.0, 3.8, 18.0, false,
		Color(0.95, 0.24, 0.36), Color(0.45, 0.05, 0.14), Color(1.0, 0.52, 0.62)
	)
	_cache[ArchetypeId.DASHER] = _build_entry(
		ArchetypeId.DASHER, "Phase Skitterer",
		0.36, 44.0, 5.5, 4.0, 22.0, false,
		Color(0.18, 0.86, 0.98), Color(0.06, 0.42, 0.58), Color(0.72, 0.98, 1.0)
	)
	_cache[ArchetypeId.BURROWER] = _build_entry(
		ArchetypeId.BURROWER, "Subterranean Stalker",
		0.40, 52.0, 6.5, 3.7, 18.0, false,
		Color(0.72, 0.42, 0.96), Color(0.32, 0.12, 0.52), Color(1.0, 0.84, 0.36)
	)
	_cache[ArchetypeId.LUNGER] = _build_entry(
		ArchetypeId.LUNGER, "Feral Striker",
		0.42, 56.0, 7.0, 3.9, 20.0, true,
		Color(1.0, 0.38, 0.18), Color(0.54, 0.12, 0.04), Color(1.0, 0.86, 0.32)
	)
	_cache[ArchetypeId.BRUISER] = _build_entry(
		ArchetypeId.BRUISER, "Tremor Sentinel",
		0.62, 95.0, 9.0, 3.0, 14.0, false,
		Color(1.0, 0.58, 0.16), Color(0.48, 0.18, 0.02), Color(1.0, 0.84, 0.34)
	)
	_cache[ArchetypeId.MIRE_LOBBER] = _build_entry(
		ArchetypeId.MIRE_LOBBER, "Blight Lobber",
		0.48, 68.0, 6.0, 3.1, 15.0, false,
		Color(0.32, 0.92, 0.48), Color(0.08, 0.42, 0.16), Color(0.74, 1.0, 0.42)
	)
	_cache[ArchetypeId.OCULAR_SNIPER] = _build_entry(
		ArchetypeId.OCULAR_SNIPER, "Ocular Marksman",
		0.46, 62.0, 6.0, 2.9, 15.0, false,
		Color(0.96, 0.88, 0.46), Color(0.48, 0.36, 0.08), Color(1.0, 0.30, 0.42)
	)
	_cache[ArchetypeId.BOSS] = _build_entry(
		ArchetypeId.BOSS, "Tectonic Sovereign",
		1.04, 700.0, 14.0, 3.3, 15.0, true,
		Color(0.88, 0.24, 0.22), Color(0.48, 0.10, 0.06), Color(1.0, 0.72, 0.24)
	)
	_cache[ArchetypeId.BOSS_BLIGHTWEAVER] = _build_entry(
		ArchetypeId.BOSS_BLIGHTWEAVER, "Blightweaver Core",
		1.04, 720.0, 13.0, 3.2, 15.0, false,
		Color(0.24, 0.76, 0.44), Color(0.08, 0.36, 0.18), Color(0.78, 1.0, 0.44)
	)
	_cache[ArchetypeId.BOSS_CRYO_ARCHON] = _build_entry(
		ArchetypeId.BOSS_CRYO_ARCHON, "Cryo-Archon Valkyrie",
		1.02, 680.0, 14.0, 3.6, 16.0, true,
		Color(0.30, 0.78, 0.98), Color(0.08, 0.34, 0.58), Color(0.88, 0.98, 1.0)
	)
	_cache[ArchetypeId.BOSS_CHRONOMANCER] = _build_entry(
		ArchetypeId.BOSS_CHRONOMANCER, "Astral Chronomancer",
		1.04, 740.0, 13.0, 3.2, 15.0, false,
		Color(0.28, 0.22, 0.72), Color(0.14, 0.10, 0.46), Color(1.0, 0.86, 0.38)
	)


static func _make_status_mat(albedo: Color, emission: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.specular_mode = BaseMaterial3D.SPECULAR_TOON
	mat.albedo_color = albedo
	mat.roughness = 0.32
	mat.emission_enabled = true
	mat.emission = emission
	mat.emission_energy_multiplier = 0.95
	return mat


static func _build_entry(
	id: ArchetypeId,
	p_name: String,
	p_radius: float,
	p_hp: float,
	p_contact_dmg: float,
	p_speed: float,
	p_accel: float,
	p_lunge: bool,
	albedo: Color,
	emission: Color,
	trim_col: Color
) -> EnemyArchetypeData:
	var d := EnemyArchetypeData.new()
	d.archetype_id = id
	d.display_name = p_name
	d.radius = p_radius
	d.max_hp = p_hp
	d.contact_damage = p_contact_dmg
	d.move_speed = p_speed
	d.acceleration = p_accel
	d.can_lunge = p_lunge
	d.accent_color = trim_col

	var mat := StandardMaterial3D.new()
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.specular_mode = BaseMaterial3D.SPECULAR_TOON
	mat.albedo_color = albedo
	mat.roughness = 0.35
	mat.emission_enabled = true
	mat.emission = emission
	mat.emission_energy_multiplier = 0.75
	d.body_material = mat

	var t_mat := StandardMaterial3D.new()
	t_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	t_mat.albedo_color = trim_col
	d.trim_material = t_mat

	var b_shape := SphereShape3D.new()
	b_shape.radius = p_radius
	d.body_shape = b_shape

	var h_shape := SphereShape3D.new()
	h_shape.radius = p_radius * 1.15
	d.hurtbox_shape = h_shape
	return d


static func get_archetype(id: int) -> EnemyArchetypeData:
	_ensure_cache()
	if _cache.has(id):
		return _cache[id]
	return _cache[ArchetypeId.CHASER]


static func get_unit_sphere_mesh() -> SphereMesh:
	_ensure_cache()
	return _unit_sphere_mesh


static func get_trim_ring_mesh() -> TorusMesh:
	_ensure_cache()
	return _trim_ring_mesh


static func get_burrow_ring_mesh() -> TorusMesh:
	_ensure_cache()
	return _burrow_ring_mesh


static func get_fin_mesh() -> BoxMesh:
	_ensure_cache()
	return _fin_mesh


static func get_cone_spike_mesh() -> CylinderMesh:
	_ensure_cache()
	return _cone_spike_mesh


static func get_plate_mesh() -> BoxMesh:
	_ensure_cache()
	return _plate_mesh


static func get_scope_ring_mesh() -> TorusMesh:
	_ensure_cache()
	return _scope_ring_mesh


static func get_sac_orb_mesh() -> SphereMesh:
	_ensure_cache()
	return _sac_orb_mesh


static func get_hit_flash_material() -> StandardMaterial3D:
	_ensure_cache()
	return _hit_flash_material


static func get_armor_shell_material() -> StandardMaterial3D:
	_ensure_cache()
	return _armor_shell_mat


static func get_impervious_shell_material() -> StandardMaterial3D:
	_ensure_cache()
	return _impervious_shell_mat


static func get_hp_bar_material() -> ShaderMaterial:
	_ensure_cache()
	return _hp_bar_material


static func get_hp_quad_mesh() -> QuadMesh:
	_ensure_cache()
	return _hp_quad_mesh


static func get_status_poison_material() -> StandardMaterial3D:
	_ensure_cache()
	return _status_poison_mat


static func get_status_burn_material() -> StandardMaterial3D:
	_ensure_cache()
	return _status_burn_mat


static func get_status_frost_material() -> StandardMaterial3D:
	_ensure_cache()
	return _status_frost_mat


static func get_contact_shadow_mesh() -> PlaneMesh:
	_ensure_cache()
	return _contact_shadow_mesh


static func get_contact_shadow_material() -> ShaderMaterial:
	_ensure_cache()
	return _contact_shadow_mat
