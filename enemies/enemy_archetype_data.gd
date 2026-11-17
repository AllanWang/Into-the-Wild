class_name EnemyArchetypeData
extends Resource

## Data Resource + shared static GPU/Physics resource cache for progressive Mini-Unit Spheres,
## Specialized Arena Elites, and Multi-Pattern Bosses.
## Shares meshes, materials, and SphereShape3Ds across all pooled enemies for zero per-spawn allocation.

enum ArchetypeId {
	CHASER = 0,          ## Agile crimson swarm sphere
	DASHER = 1,          ## Electric-cyan mini-sphere with periodic lateral/diagonal juke-dash
	BURROWER = 2,        ## Subterranean amethyst-gold mini-sphere that burrows underground (invulnerable!)
	LUNGER = 3,          ## Fiery coral-orange striker sphere with crouched wind-up lunge
	BRUISER = 4,         ## Heavy armored amber sentinel that slams radial ground quakes
	MIRE_LOBBER = 5,     ## Standoff emerald-violet caster lobbing persistent damaging corrosive pools
	OCULAR_SNIPER = 6,   ## Long-range alabaster-gold marksman with lock-on sightline & lance
	BOSS = 7,            ## Tectonic Sovereign — double-quake rings, faultline spikes & juggernaut charge
	BOSS_BLIGHTWEAVER = 8 ## Blightweaver Core — acidic rain pools, horizon fans & safe-eye cataclysm
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

static var _cache: Dictionary = {}
static var _unit_sphere_mesh: SphereMesh = null
static var _trim_ring_mesh: TorusMesh = null
static var _burrow_ring_mesh: TorusMesh = null
static var _hit_flash_material: StandardMaterial3D = null
static var _status_poison_mat: StandardMaterial3D = null
static var _status_burn_mat: StandardMaterial3D = null
static var _status_frost_mat: StandardMaterial3D = null
static var _hp_bar_material: ShaderMaterial = null
static var _hp_quad_mesh: QuadMesh = null


static func is_boss_archetype(id: int) -> bool:
	return id == ArchetypeId.BOSS or id == ArchetypeId.BOSS_BLIGHTWEAVER


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

	_hit_flash_material = StandardMaterial3D.new()
	_hit_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hit_flash_material.albedo_color = Color(1.0, 0.98, 0.92, 1.0)

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
		1.02, 280.0, 14.0, 3.3, 15.0, true,
		Color(0.88, 0.24, 0.32), Color(0.46, 0.08, 0.12), Color(1.0, 0.80, 0.28)
	)
	_cache[ArchetypeId.BOSS_BLIGHTWEAVER] = _build_entry(
		ArchetypeId.BOSS_BLIGHTWEAVER, "Blightweaver Core",
		1.02, 270.0, 13.0, 3.2, 15.0, false,
		Color(0.68, 0.20, 0.92), Color(0.34, 0.06, 0.48), Color(0.36, 0.98, 0.58)
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


static func get_hit_flash_material() -> StandardMaterial3D:
	_ensure_cache()
	return _hit_flash_material


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
