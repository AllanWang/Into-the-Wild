class_name VineBarrier
extends StaticBody3D

## Pooled animated 3D thorny vine barrier that erupts across bridge edges
## when entering an uncleared arena and retracts underground when cleared.
## Repopulates stalk X-positions cleanly for any shoreline-to-shoreline bridge span
## without stretching cylinder cross-sections.

var pool: Node = null
var bound_area_idx: int = -1

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var visuals_root: Node3D = $VisualsRoot

var _box_shape: BoxShape3D = null
var _stalks: Array[MeshInstance3D] = []
var _arches: Array[MeshInstance3D] = []
var _buds: Array[MeshInstance3D] = []
var _is_erupting: bool = false
var _is_retracting: bool = false
var _anim_t: float = 0.0
var _sway_time: float = 0.0

const STALK_COUNT: int = 13
const ARCH_COUNT: int = 4
const ERUPT_DURATION: float = 0.28
const RETRACT_DURATION: float = 0.34

static var _stalk_mesh: CylinderMesh = null
static var _arch_mesh: TorusMesh = null
static var _thorn_mesh: CylinderMesh = null
static var _bud_mesh: SphereMesh = null
static var _vine_dark_mat: StandardMaterial3D = null
static var _vine_moss_mat: StandardMaterial3D = null
static var _bud_locked_mat: StandardMaterial3D = null
static var _bud_unlocked_mat: StandardMaterial3D = null


static func _ensure_static_assets() -> void:
	if _stalk_mesh != null:
		return

	_stalk_mesh = CylinderMesh.new()
	_stalk_mesh.top_radius = 0.10
	_stalk_mesh.bottom_radius = 0.22
	_stalk_mesh.height = 1.75
	_stalk_mesh.radial_segments = 8

	_arch_mesh = TorusMesh.new()
	_arch_mesh.inner_radius = 0.72
	_arch_mesh.outer_radius = 0.92
	_arch_mesh.rings = 14
	_arch_mesh.ring_segments = 6

	_thorn_mesh = CylinderMesh.new()
	_thorn_mesh.top_radius = 0.01
	_thorn_mesh.bottom_radius = 0.08
	_thorn_mesh.height = 0.38
	_thorn_mesh.radial_segments = 6

	_bud_mesh = SphereMesh.new()
	_bud_mesh.radius = 0.15
	_bud_mesh.height = 0.30
	_bud_mesh.radial_segments = 10
	_bud_mesh.rings = 6

	_vine_dark_mat = StandardMaterial3D.new()
	_vine_dark_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	_vine_dark_mat.albedo_color = Color(0.13, 0.33, 0.11)
	_vine_dark_mat.roughness = 0.8

	_vine_moss_mat = StandardMaterial3D.new()
	_vine_moss_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	_vine_moss_mat.albedo_color = Color(0.24, 0.53, 0.16)
	_vine_moss_mat.roughness = 0.75

	_bud_locked_mat = StandardMaterial3D.new()
	_bud_locked_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bud_locked_mat.albedo_color = Color(1.0, 0.34, 0.48)

	_bud_unlocked_mat = StandardMaterial3D.new()
	_bud_unlocked_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bud_unlocked_mat.albedo_color = Color(0.75, 1.0, 0.45)


func _ready() -> void:
	_ensure_static_assets()
	collision_layer = 1
	collision_mask = 0

	_box_shape = BoxShape3D.new()
	_box_shape.size = Vector3(7.0, 2.6, 0.85)
	if collision_shape:
		collision_shape.shape = _box_shape
		collision_shape.position = Vector3(0.0, 1.1, 0.0)
		collision_shape.set_deferred("disabled", true)

	_populate_vine_geometry_once()


func _populate_vine_geometry_once() -> void:
	if visuals_root == null or visuals_root.get_child_count() > 0:
		return

	_stalks.clear()
	_arches.clear()
	_buds.clear()

	for i in range(STALK_COUNT):
		var z_off: float = (0.15 if (i % 2 == 0) else -0.15)
		var lean_z: float = (-0.19 if (i % 2 == 0) else 0.19)
		var lean_x: float = sin(float(i) * 1.7) * 0.15

		var stalk := MeshInstance3D.new()
		stalk.mesh = _stalk_mesh
		stalk.material_override = _vine_dark_mat if (i % 2 == 0) else _vine_moss_mat
		stalk.position = Vector3(0.0, 0.76, z_off)
		stalk.rotation = Vector3(lean_x, float(i) * 0.6, lean_z)
		visuals_root.add_child(stalk)
		_stalks.append(stalk)

		for t_idx in range(2):
			var thorn := MeshInstance3D.new()
			thorn.mesh = _thorn_mesh
			thorn.material_override = _vine_dark_mat
			var ty: float = -0.15 + float(t_idx) * 0.48
			var side: float = 1.0 if (t_idx == 0) else -1.0
			thorn.position = Vector3(side * 0.14, ty, 0.08 * side)
			thorn.rotation = Vector3(0.35 * side, 0.0, -0.85 * side)
			stalk.add_child(thorn)

		if i % 2 == 1:
			var bud := MeshInstance3D.new()
			bud.mesh = _bud_mesh
			bud.material_override = _bud_locked_mat
			bud.position = Vector3(0.0, 0.82, 0.0)
			stalk.add_child(bud)
			_buds.append(bud)

	for a_idx in range(ARCH_COUNT):
		var arch := MeshInstance3D.new()
		arch.mesh = _arch_mesh
		arch.material_override = _vine_moss_mat if (a_idx % 2 == 1) else _vine_dark_mat
		arch.position = Vector3(0.0, 0.36, 0.0)
		arch.rotation = Vector3(PI * 0.5, 0.0, sin(float(a_idx) * 2.1) * 0.16)
		visuals_root.add_child(arch)
		_arches.append(arch)


func _layout_for_span(clean_span: float) -> void:
	var visual_span: float = maxf(4.2, clean_span - 0.5)
	for i in range(_stalks.size()):
		var frac: float = float(i) / float(maxi(1, _stalks.size() - 1)) - 0.5
		_stalks[i].position.x = frac * visual_span

	var arch_span: float = visual_span * 0.76
	var arch_scale_x: float = clampf(clean_span / 6.2, 0.95, 1.55)
	for a_i in range(_arches.size()):
		var a_frac: float = float(a_i) / float(maxi(1, _arches.size() - 1)) - 0.5
		_arches[a_i].position.x = a_frac * arch_span
		_arches[a_i].scale = Vector3(arch_scale_x, 1.0, 1.05)


## Raises the vine wall across a bridge edge from shoreline bank to shoreline bank
func activate_barrier(
	p_area_idx: int,
	world_pos: Vector3,
	bridge_dir_2d: Vector2,
	span_width: float
) -> void:
	bound_area_idx = p_area_idx
	var clean_span: float = maxf(4.8, span_width)
	if _box_shape:
		# Extend collision 1.0m beyond visual span into both water walls so zero edge bypass is possible
		_box_shape.size = Vector3(clean_span + 1.0, 2.6, 0.85)

	_layout_for_span(clean_span)

	# Local X spans across the bridge width (perpendicular to bridge_dir_2d)
	var perp_2d: Vector2 = Vector2(-bridge_dir_2d.y, bridge_dir_2d.x).normalized()
	var yaw: float = -atan2(perp_2d.y, perp_2d.x)

	if is_inside_tree():
		global_position = Vector3(world_pos.x, 0.0, world_pos.z)
		global_rotation = Vector3(0.0, yaw, 0.0)
		reset_physics_interpolation()
	else:
		position = Vector3(world_pos.x, 0.0, world_pos.z)
		rotation = Vector3(0.0, yaw, 0.0)

	for bud in _buds:
		bud.material_override = _bud_locked_mat

	if visuals_root:
		visuals_root.scale = Vector3(1.0, 0.1, 1.0)
		visuals_root.position = Vector3(0.0, -1.55, 0.0)

	if collision_shape:
		collision_shape.set_deferred("disabled", false)

	_is_erupting = true
	_is_retracting = false
	_anim_t = 0.0
	_sway_time = 0.0
	visible = true
	set_process(true)


## Immediately unlocks collision and retracts the vines back into the meadow
func retract_barrier() -> void:
	if not visible or _is_retracting:
		return
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	for bud in _buds:
		bud.material_override = _bud_unlocked_mat
	_is_erupting = false
	_is_retracting = true
	_anim_t = 0.0


func deactivate() -> void:
	_is_erupting = false
	_is_retracting = false
	bound_area_idx = -1
	set_process(false)
	visible = false
	if collision_shape:
		collision_shape.set_deferred("disabled", true)


func on_pool_release() -> void:
	deactivate()


func _process(delta: float) -> void:
	if _is_erupting:
		_anim_t = minf(1.0, _anim_t + delta / ERUPT_DURATION)
		var inv: float = 1.0 - _anim_t
		var ease_val: float = 1.0 - inv * inv * inv
		if visuals_root:
			visuals_root.position.y = lerpf(-1.55, 0.0, ease_val)
			visuals_root.scale.y = lerpf(0.2, 1.05, ease_val)
		if _anim_t >= 1.0:
			_is_erupting = false
			if visuals_root:
				visuals_root.position.y = 0.0
				visuals_root.scale.y = 1.0
	elif _is_retracting:
		_anim_t = minf(1.0, _anim_t + delta / RETRACT_DURATION)
		var ease_in: float = _anim_t * _anim_t
		if visuals_root:
			visuals_root.position.y = lerpf(0.0, -1.75, ease_in)
			visuals_root.scale.y = lerpf(1.0, 0.15, ease_in)
		if _anim_t >= 1.0:
			_is_retracting = false
			if pool and pool.has_method("release"):
				pool.release(self)
			else:
				deactivate()
	else:
		_sway_time += delta * 2.6
		if visuals_root:
			visuals_root.scale.y = 1.0 + sin(_sway_time) * 0.03
