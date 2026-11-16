class_name EnemyArchetypeData
extends Resource

## Data Resource + shared static GPU/Physics resource cache for placeholder Sphere Enemies.
## Shares meshes, materials, and SphereShape3Ds across all pooled enemies for zero per-spawn allocation.

enum ArchetypeId {
	CHASER,  ## Agile crimson sphere
	BRUISER, ## Larger amber elite sphere
	BOSS     ## Colossal violet-crimson apex boss sphere with periodic lunge
}

@export var archetype_id: ArchetypeId = ArchetypeId.CHASER
@export var display_name: String = "Crimson Wisp"
@export var radius: float = 0.38
@export var max_hp: float = 40.0
@export var contact_damage: float = 6.0
@export var move_speed: float = 3.8
@export var acceleration: float = 16.0
@export var can_lunge: bool = false

var body_material: StandardMaterial3D = null
var body_shape: SphereShape3D = null
var hurtbox_shape: SphereShape3D = null

const OVERHEAD_BAR_SHADER: Shader = preload("res://shaders/OverheadBar.gdshader")

static var _cache: Dictionary = {}
static var _unit_sphere_mesh: SphereMesh = null
static var _hit_flash_material: StandardMaterial3D = null
static var _status_poison_mat: StandardMaterial3D = null
static var _status_burn_mat: StandardMaterial3D = null
static var _status_frost_mat: StandardMaterial3D = null
static var _hp_bar_material: ShaderMaterial = null
static var _hp_quad_mesh: QuadMesh = null


static func _ensure_cache() -> void:
	if not _cache.is_empty():
		return

	_unit_sphere_mesh = SphereMesh.new()
	_unit_sphere_mesh.radius = 1.0
	_unit_sphere_mesh.height = 2.0
	_unit_sphere_mesh.radial_segments = 20
	_unit_sphere_mesh.rings = 12

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
		Color(0.95, 0.24, 0.36), Color(0.45, 0.05, 0.14)
	)
	_cache[ArchetypeId.BRUISER] = _build_entry(
		ArchetypeId.BRUISER, "Amber Sentinel",
		0.58, 80.0, 8.0, 3.0, 14.0, false,
		Color(1.0, 0.56, 0.16), Color(0.48, 0.18, 0.02)
	)
	_cache[ArchetypeId.BOSS] = _build_entry(
		ArchetypeId.BOSS, "Apex Core",
		0.98, 220.0, 14.0, 3.3, 15.0, true,
		Color(0.76, 0.18, 0.88), Color(0.38, 0.05, 0.48)
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
	emission: Color
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

	var mat := StandardMaterial3D.new()
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.specular_mode = BaseMaterial3D.SPECULAR_TOON
	mat.albedo_color = albedo
	mat.roughness = 0.35
	mat.emission_enabled = true
	mat.emission = emission
	mat.emission_energy_multiplier = 0.75
	d.body_material = mat

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
