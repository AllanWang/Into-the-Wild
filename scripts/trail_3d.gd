@tool
class_name Trail3D
extends MeshInstance3D

@export var trail_width: float = 0.08
@export var max_points: int = 10
@export var trail_color: Color = Color(1.0, 1.0, 1.0, 0.2)
## Offset along travel direction. Negative value offsets it behind the center so it starts cleanly from the back of the sphere.
@export var offset_along_direction: float = -0.05

var _points: Array[Vector3] = []
var _imm_mesh: ImmediateMesh
var _parent_3d: Node3D = null
var _travel_dir: Vector3 = Vector3.FORWARD
static var _shared_trail_mat: StandardMaterial3D = null

func _get_configuration_warnings() -> PackedStringArray:
	# ImmediateMesh is handled dynamically at runtime, so suppress the static MeshInstance3D warning
	return PackedStringArray()

func _init() -> void:
	if Engine.is_editor_hint():
		return
	_imm_mesh = ImmediateMesh.new()
	mesh = _imm_mesh

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	
	top_level = true
	global_transform = Transform3D.IDENTITY
	_parent_3d = get_parent() as Node3D
	
	if not _imm_mesh:
		_imm_mesh = ImmediateMesh.new()
		mesh = _imm_mesh
	
	if _shared_trail_mat == null:
		_shared_trail_mat = StandardMaterial3D.new()
		_shared_trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shared_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shared_trail_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_shared_trail_mat.vertex_color_use_as_albedo = true
		_shared_trail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = _shared_trail_mat

func _exit_tree() -> void:
	reset()

## Clears all recorded points and dynamic mesh surfaces.
func reset() -> void:
	_points.clear()
	if _imm_mesh:
		_imm_mesh.clear_surfaces()

## Activates the trail when acquired from a pool.
func activate(initial_pos: Vector3 = Vector3.INF, initial_dir: Vector3 = Vector3.FORWARD) -> void:
	reset()
	if _parent_3d == null:
		_parent_3d = get_parent() as Node3D
	_travel_dir = initial_dir.normalized() if initial_dir.length_squared() > 0.0001 else Vector3.FORWARD
	global_transform = Transform3D.IDENTITY
	reset_physics_interpolation()
	if initial_pos.is_finite():
		_points.push_front(initial_pos + _travel_dir * offset_along_direction)
	visible = true
	set_physics_process(true)

## Deactivates the trail when released back into a pool.
func deactivate() -> void:
	reset()
	set_physics_process(false)
	visible = false

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	
	if _parent_3d == null or not is_instance_valid(_parent_3d):
		queue_free()
		return
	
	# Start inside the bullet sphere, offset backward along cached travel direction
	var start_pos: Vector3 = _parent_3d.global_position + _travel_dir * offset_along_direction
	
	_points.push_front(start_pos)
	if _points.size() > max_points:
		_points.pop_back()
	
	if _points.size() < 2 or not _imm_mesh:
		return
	
	_imm_mesh.clear_surfaces()
	_imm_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	
	var pt_count := _points.size()
	for i in range(pt_count):
		var t := float(i) / float(pt_count - 1)
		var w := trail_width * (1.0 - t)
		var c := trail_color
		c.a *= (1.0 - t)
		
		_imm_mesh.surface_set_color(c)
		_imm_mesh.surface_add_vertex(_points[i] + Vector3(0.0, w * 0.5, 0.0))
		_imm_mesh.surface_add_vertex(_points[i] - Vector3(0.0, w * 0.5, 0.0))
	
	_imm_mesh.surface_end()
