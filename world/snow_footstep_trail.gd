class_name SnowFootstepTrail
extends Node3D

## Lightweight pooled snow glide trail for Glacial Frostfield.
## Stamped densely behind the sliding box player so overlapping feathered quads
## merge into one faint, continuous trough without individual footsteps.

const SNOW_SHADER: Shader = preload("res://shaders/SnowFootprint.gdshader")

const MAX_PRINTS: int = 96
const PRINT_LIFETIME: float = 9.5
const WALK_STEP_DIST: float = 0.14
const DASH_STEP_DIST: float = 0.14
const LATERAL_FOOT_OFFSET: float = 0.0
const PRINT_Y: float = 0.04

var _world: Node3D = null
var _players_root: Node = null
var _snow_enabled: bool = false
var _write_idx: int = 0
var _active_count: int = 0
var _ages: PackedFloat32Array = PackedFloat32Array()
var _active: PackedByteArray = PackedByteArray()
var _meshes: Array[MeshInstance3D] = []
var _mats: Array[ShaderMaterial] = []
var _player_state: Dictionary = {}

static var _shared_plane: PlaneMesh = null
static var _shared_mat: ShaderMaterial = null


static func _ensure_shared_resources() -> void:
	if _shared_plane != null:
		return
	_shared_plane = PlaneMesh.new()
	_shared_plane.size = Vector2(1.0, 1.0)

	_shared_mat = ShaderMaterial.new()
	_shared_mat.shader = SNOW_SHADER


func _ready() -> void:
	_ensure_shared_resources()
	_ages.resize(MAX_PRINTS)
	_active.resize(MAX_PRINTS)
	_meshes.resize(MAX_PRINTS)
	_mats.resize(MAX_PRINTS)
	for i in range(MAX_PRINTS):
		var mi := MeshInstance3D.new()
		var mat := _shared_mat.duplicate() as ShaderMaterial
		mi.mesh = _shared_plane
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_meshes[i] = mi
		_mats[i] = mat
		_ages[i] = 0.0
		_active[i] = 0
	visible = _snow_enabled
	set_process(_snow_enabled)


func setup(world_ref: Node3D) -> void:
	_world = world_ref


func set_snow_enabled(enabled: bool) -> void:
	_snow_enabled = enabled
	clear_prints()
	visible = enabled
	set_process(enabled)


func clear_prints() -> void:
	_write_idx = 0
	_active_count = 0
	_player_state.clear()
	for i in range(_meshes.size()):
		_ages[i] = 0.0
		_active[i] = 0
		var mi: MeshInstance3D = _meshes[i]
		if mi != null:
			mi.visible = false


func get_active_print_count() -> int:
	return _active_count


func _process(delta: float) -> void:
	if not _snow_enabled:
		return

	_sample_players()

	if _active_count <= 0:
		return

	var alive_now: int = 0
	for i in range(_meshes.size()):
		if _active[i] == 0:
			continue
		var mi: MeshInstance3D = _meshes[i]
		var next_age: float = _ages[i] + delta
		if next_age >= PRINT_LIFETIME:
			_active[i] = 0
			_ages[i] = 0.0
			if mi != null:
				mi.visible = false
		else:
			_ages[i] = next_age
			var ratio: float = next_age / PRINT_LIFETIME
			var fade: float = 1.0 - smoothstep(0.18, 1.0, ratio)
			var mat: ShaderMaterial = _mats[i] if i < _mats.size() else null
			if mat != null:
				mat.set_shader_parameter("fade_alpha", fade)
			alive_now += 1
	_active_count = alive_now


func _sample_players() -> void:
	if _players_root == null or not is_instance_valid(_players_root):
		if _world != null and _world.get_parent() != null:
			_players_root = _world.get_parent().get_node_or_null("Players")
	if _players_root == null:
		return

	for child in _players_root.get_children():
		var p3d := child as Node3D
		if p3d == null or not p3d.visible:
			continue
		var pid: int = p3d.get_instance_id()
		var pos3: Vector3 = p3d.global_position
		var pos2 := Vector2(pos3.x, pos3.z)

		if not _player_state.has(pid):
			_player_state[pid] = {
				"last_pos": pos2,
				"accum": 0.0
			}
			continue

		var st: Dictionary = _player_state[pid]
		var prev2: Vector2 = st["last_pos"] as Vector2
		var diff: Vector2 = pos2 - prev2
		var dist: float = diff.length()

		if dist > 3.5:
			st["last_pos"] = pos2
			st["accum"] = 0.0
			continue
		if dist < 0.005:
			continue

		st["last_pos"] = pos2
		var accum: float = float(st["accum"]) + dist
		var dashing: bool = bool(p3d.get("is_dashing")) if "is_dashing" in p3d else false
		var thresh: float = DASH_STEP_DIST if dashing else WALK_STEP_DIST
		var dir2: Vector2 = diff / dist
		var cur_step_pt: Vector2 = prev2

		while accum >= thresh:
			accum -= thresh
			cur_step_pt += dir2 * thresh
			var stamp2: Vector2 = cur_step_pt - dir2 * 0.08
			if _is_dry_snow(stamp2):
				var w: float = 0.58 if dashing else 0.52
				var l: float = 0.66 if dashing else 0.52
				_stamp_print(stamp2, dir2, w, l)

		st["accum"] = accum


func _is_dry_snow(pt: Vector2) -> bool:
	if _world == null:
		return true
	if _world.get("pond_instance") != null:
		var ang: float = atan2(pt.y, pt.x)
		var pond_r: float = 2.45 + sin(ang * 2.0) * 0.45 + cos(ang * 3.0 + 0.8) * 0.3 + sin(ang * 5.0) * 0.15
		if pt.length() <= pond_r:
			return false
	if _world.has_method("_is_point_on_filleted_land"):
		return bool(_world.call("_is_point_on_filleted_land", pt))
	return true


func _stamp_print(pos2: Vector2, dir2: Vector2, width: float, length: float) -> void:
	if _meshes.is_empty():
		return
	var idx: int = _write_idx
	_write_idx = (_write_idx + 1) % MAX_PRINTS

	var fwd3 := Vector3(dir2.x, 0.0, dir2.y)
	var right3 := Vector3(dir2.y, 0.0, -dir2.x)
	var step_basis := Basis(right3 * width, Vector3.UP, fwd3 * length)

	var mi: MeshInstance3D = _meshes[idx]
	if mi == null:
		return
	if _active[idx] == 0:
		_active_count += 1
	_active[idx] = 1
	_ages[idx] = 0.0
	mi.transform = Transform3D(step_basis, Vector3(pos2.x, PRINT_Y, pos2.y))
	var mat: ShaderMaterial = _mats[idx] if idx < _mats.size() else null
	if mat != null:
		mat.set_shader_parameter("fade_alpha", 1.0)
	mi.visible = true
