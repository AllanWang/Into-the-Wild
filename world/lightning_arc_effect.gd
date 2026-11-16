class_name LightningArcEffect
extends MeshInstance3D

## Pooled 3D jagged lightning bolt visual for Shock chain-lightning procs.
## Uses ImmediateMesh + single static StandardMaterial3D; returns to pool after 0.14s.

var pool: Node = null

var _imm: ImmediateMesh = null
var _timer: float = 0.0
var _active: bool = false

const DURATION: float = 0.14

static var _shared_arc_mat: StandardMaterial3D = null


static func _ensure_mat() -> void:
	if _shared_arc_mat != null:
		return
	_shared_arc_mat = StandardMaterial3D.new()
	_shared_arc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shared_arc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shared_arc_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_shared_arc_mat.vertex_color_use_as_albedo = true
	_shared_arc_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


func _ready() -> void:
	_ensure_mat()
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_imm = ImmediateMesh.new()
	mesh = _imm
	material_override = _shared_arc_mat


func activate_arc(from_pos: Vector3, to_pos: Vector3) -> void:
	if _imm == null:
		_imm = ImmediateMesh.new()
		mesh = _imm
	_ensure_mat()
	material_override = _shared_arc_mat

	global_transform = Transform3D.IDENTITY
	reset_physics_interpolation()

	_build_bolt_ribbon(from_pos, to_pos)
	_timer = DURATION
	_active = true
	visible = true
	set_process(true)


func _build_bolt_ribbon(a: Vector3, b: Vector3) -> void:
	_imm.clear_surfaces()
	var delta_v: Vector3 = b - a
	var dist: float = delta_v.length()
	if dist < 0.05:
		return

	var dir: Vector3 = delta_v / dist
	var side: Vector3 = dir.cross(Vector3.UP).normalized()
	if side.length_squared() < 0.01:
		side = Vector3.RIGHT

	var segs: int = 5
	var half_w: float = 0.075
	var col_core := Color(0.62, 0.95, 1.0, 0.95)

	_imm.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in range(segs + 1):
		var t: float = float(i) / float(segs)
		var pt: Vector3 = a.lerp(b, t)
		if i > 0 and i < segs:
			var jag: float = (0.28 if (i % 2 == 1) else -0.24)
			pt += side * jag + Vector3(0.0, 0.08 * jag, 0.0)
		_imm.surface_set_color(col_core)
		_imm.surface_add_vertex(pt + side * half_w + Vector3(0.0, 0.04, 0.0))
		_imm.surface_add_vertex(pt - side * half_w - Vector3(0.0, 0.04, 0.0))
	_imm.surface_end()


func deactivate() -> void:
	_active = false
	set_process(false)
	visible = false
	if _imm:
		_imm.clear_surfaces()


func on_pool_release() -> void:
	deactivate()


func _process(delta: float) -> void:
	if not _active:
		return
	_timer -= delta
	if _timer <= 0.0:
		_active = false
		if pool and pool.has_method("release"):
			pool.release(self)
		else:
			deactivate()
