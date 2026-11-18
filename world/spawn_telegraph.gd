class_name SpawnTelegraph
extends Node3D

## Pooled ground warning ring that telegraphs enemy spawn locations for 0.55s
## before spawning a pooled EnemySphere (uses shared static GPU meshes/materials).

signal telegraph_completed(enemy_id: int, area_idx: int, archetype_id: int, spawn_pos: Vector3)

var pool: Node = null

@onready var ring_mesh: MeshInstance3D = $RingMesh
@onready var inner_disc: MeshInstance3D = $InnerDisc

var _enemy_id: int = -1
var _area_idx: int = -1
var _archetype_id: int = 0
var _spawn_pos: Vector3 = Vector3.ZERO
var _duration: float = 0.55
var _elapsed: float = 0.0
var _target_radius: float = 0.65
var _active: bool = false

static var _shared_torus: TorusMesh = null
static var _shared_disc: CylinderMesh = null
static var _shared_ring_mat: StandardMaterial3D = null
static var _shared_disc_mat: StandardMaterial3D = null


static func _ensure_shared() -> void:
	if _shared_torus != null:
		return
	_shared_torus = TorusMesh.new()
	_shared_torus.inner_radius = 0.82
	_shared_torus.outer_radius = 1.0
	_shared_torus.rings = 24
	_shared_torus.ring_segments = 8

	_shared_disc = CylinderMesh.new()
	_shared_disc.top_radius = 0.82
	_shared_disc.bottom_radius = 0.82
	_shared_disc.height = 0.01
	_shared_disc.radial_segments = 20

	_shared_ring_mat = StandardMaterial3D.new()
	_shared_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shared_ring_mat.albedo_color = Color(1.0, 0.30, 0.42, 0.92)
	_shared_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_shared_disc_mat = StandardMaterial3D.new()
	_shared_disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shared_disc_mat.albedo_color = Color(1.0, 0.22, 0.35, 0.28)
	_shared_disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_ensure_shared()
	if ring_mesh:
		ring_mesh.mesh = _shared_torus
		ring_mesh.material_override = _shared_ring_mat
		ring_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if inner_disc:
		inner_disc.mesh = _shared_disc
		inner_disc.material_override = _shared_disc_mat
		inner_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func activate(
	p_enemy_id: int,
	p_area_idx: int,
	p_archetype_id: int,
	p_pos: Vector3,
	p_radius: float = 0.65,
	p_duration: float = 0.55
) -> void:
	_enemy_id = p_enemy_id
	_area_idx = p_area_idx
	_archetype_id = p_archetype_id
	_spawn_pos = p_pos
	_target_radius = maxf(0.55, p_radius * 1.45)
	_duration = maxf(0.15, p_duration)
	_elapsed = 0.0
	_active = true

	if is_inside_tree():
		global_position = Vector3(p_pos.x, 0.04, p_pos.z)
		reset_physics_interpolation()
	else:
		position = Vector3(p_pos.x, 0.04, p_pos.z)

	scale = Vector3.ONE * (_target_radius * 0.35)
	visible = true
	set_process(true)


func deactivate() -> void:
	_active = false
	set_process(false)
	visible = false


func on_pool_release() -> void:
	deactivate()


func _process(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta
	var t: float = clampf(_elapsed / _duration, 0.0, 1.0)
	var eased: float = 1.0 - pow(1.0 - t, 3.0)
	var s: float = lerpf(_target_radius * 0.35, _target_radius, eased)
	scale = Vector3(s, 1.0, s)
	if inner_disc:
		var fill_s: float = clampf(t, 0.05, 1.0)
		inner_disc.scale = Vector3(fill_s, 1.0, fill_s)

	if _elapsed >= _duration:
		_active = false
		telegraph_completed.emit(_enemy_id, _area_idx, _archetype_id, _spawn_pos)
		if pool and pool.has_method("release"):
			pool.release(self)
		else:
			queue_free()
