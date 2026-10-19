@tool
class_name Trail3D
extends MeshInstance3D

@export var trail_width: float = 0.08
@export var max_points: int = 24
@export var trail_color: Color = Color(1.0, 1.0, 1.0, 0.2)
## Offset along travel direction. Negative value offsets it behind the center so it starts cleanly from the back of the sphere.
@export var offset_along_direction: float = -0.05

var _points: Array[Vector3] = []
var _imm_mesh: ImmediateMesh

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
	
	if not _imm_mesh:
		_imm_mesh = ImmediateMesh.new()
		mesh = _imm_mesh
	
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = mat

func _exit_tree() -> void:
	if _imm_mesh:
		_imm_mesh.clear_surfaces()
	_points.clear()

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	
	var parent := get_parent()
	if not parent or not is_instance_valid(parent):
		queue_free()
		return
	
	var dir := Vector3.FORWARD
	if "direction" in parent:
		dir = (parent.direction as Vector3).normalized()
	
	# Start inside the bullet sphere, offset backward along travel direction
	var start_pos: Vector3 = (parent as Node3D).global_position + dir * offset_along_direction
	
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
