class_name VineBarrier
extends StaticBody3D

## Pooled animated Biome Gate Barrier that seals bridges across uncleared arenas
## and retracts underground once cleared:
## - Biome 0 (Verdant Meadow): Interwoven thorny briar vines, arches & blossoms
## - Biome 1 (Glacial Frostfield): Jagged crystalline glacier ice spires & ice wedges
## - Biome 2 (Astral Constellation): Celestial obelisks, spinning star-cores & light rails
## - Biome 3 (Volcanic Caldera): Stepped hexagonal basalt columns & magma cross-bars
## - Biome 4 (Arcane Anomaly): Hextech containment pylons, halo rings & plasma rails

var pool: Node = null
var bound_area_idx: int = -1

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var visuals_root: Node3D = $VisualsRoot

var _box_shape: BoxShape3D = null
var _pillars: Array[MeshInstance3D] = []
var _arches: Array[MeshInstance3D] = []
var _beam_rails: Array[MeshInstance3D] = []
var _spinners: Array[MeshInstance3D] = []
var _buds: Array[MeshInstance3D] = []

var _built_biome_id: int = -1
var _is_erupting: bool = false
var _is_retracting: bool = false
var _anim_t: float = 0.0
var _sway_time: float = 0.0

const ERUPT_DURATION: float = 0.28
const RETRACT_DURATION: float = 0.34

static var _active_biome_id: int = 0
static var _stalk_mesh: CylinderMesh = null
static var _arch_mesh: TorusMesh = null
static var _thorn_mesh: CylinderMesh = null
static var _bud_mesh: SphereMesh = null
static var _ice_crystal_mesh: CylinderMesh = null
static var _ice_wedge_mesh: CylinderMesh = null
static var _astral_pylon_mesh: CylinderMesh = null
static var _basalt_hex_mesh: CylinderMesh = null
static var _hex_monolith_mesh: BoxMesh = null
static var _beam_rail_mesh: BoxMesh = null
static var _octa_gem_mesh: SphereMesh = null
static var _halo_ring_mesh: TorusMesh = null

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

	_ice_crystal_mesh = CylinderMesh.new()
	_ice_crystal_mesh.top_radius = 0.03
	_ice_crystal_mesh.bottom_radius = 0.42
	_ice_crystal_mesh.height = 2.15
	_ice_crystal_mesh.radial_segments = 5

	_ice_wedge_mesh = CylinderMesh.new()
	_ice_wedge_mesh.top_radius = 0.16
	_ice_wedge_mesh.bottom_radius = 0.56
	_ice_wedge_mesh.height = 1.28
	_ice_wedge_mesh.radial_segments = 4

	_astral_pylon_mesh = CylinderMesh.new()
	_astral_pylon_mesh.top_radius = 0.12
	_astral_pylon_mesh.bottom_radius = 0.26
	_astral_pylon_mesh.height = 1.95
	_astral_pylon_mesh.radial_segments = 4

	_basalt_hex_mesh = CylinderMesh.new()
	_basalt_hex_mesh.top_radius = 0.30
	_basalt_hex_mesh.bottom_radius = 0.38
	_basalt_hex_mesh.height = 1.90
	_basalt_hex_mesh.radial_segments = 6

	_hex_monolith_mesh = BoxMesh.new()
	_hex_monolith_mesh.size = Vector3(0.32, 1.85, 0.36)

	_beam_rail_mesh = BoxMesh.new()
	_beam_rail_mesh.size = Vector3(1.0, 0.09, 0.09)

	_octa_gem_mesh = SphereMesh.new()
	_octa_gem_mesh.radius = 0.20
	_octa_gem_mesh.height = 0.44
	_octa_gem_mesh.radial_segments = 4
	_octa_gem_mesh.rings = 1

	_halo_ring_mesh = TorusMesh.new()
	_halo_ring_mesh.inner_radius = 0.34
	_halo_ring_mesh.outer_radius = 0.42
	_halo_ring_mesh.rings = 18
	_halo_ring_mesh.ring_segments = 6

	_vine_dark_mat = StandardMaterial3D.new()
	_vine_dark_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	_vine_dark_mat.albedo_color = Color(0.13, 0.33, 0.11)
	_vine_dark_mat.roughness = 0.72

	_vine_moss_mat = StandardMaterial3D.new()
	_vine_moss_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	_vine_moss_mat.albedo_color = Color(0.24, 0.53, 0.16)
	_vine_moss_mat.roughness = 0.58

	_bud_locked_mat = StandardMaterial3D.new()
	_bud_locked_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bud_locked_mat.albedo_color = Color(1.0, 0.34, 0.48)

	_bud_unlocked_mat = StandardMaterial3D.new()
	_bud_unlocked_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bud_unlocked_mat.albedo_color = Color(0.75, 1.0, 0.45)


static func apply_biome_palette(dark_col: Color, moss_col: Color, bud_col: Color, p_biome_id: int = 0) -> void:
	_ensure_static_assets()
	_active_biome_id = clampi(p_biome_id, 0, 4)
	if _vine_dark_mat:
		_vine_dark_mat.albedo_color = dark_col
	if _vine_moss_mat:
		_vine_moss_mat.albedo_color = moss_col
	if _bud_locked_mat:
		_bud_locked_mat.albedo_color = bud_col


func get_built_biome_id() -> int:
	return _built_biome_id


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_ensure_static_assets()
	collision_layer = 1
	collision_mask = 0

	_box_shape = BoxShape3D.new()
	_box_shape.size = Vector3(7.0, 2.6, 0.85)
	if collision_shape:
		collision_shape.shape = _box_shape
		collision_shape.position = Vector3(0.0, 1.1, 0.0)
		collision_shape.set_deferred("disabled", true)

	_ensure_biome_geometry()


func _clear_visual_children() -> void:
	if visuals_root == null:
		return
	for ch in visuals_root.get_children():
		visuals_root.remove_child(ch)
		ch.queue_free()
	_pillars.clear()
	_arches.clear()
	_beam_rails.clear()
	_spinners.clear()
	_buds.clear()


func _ensure_biome_geometry() -> void:
	if visuals_root == null or _built_biome_id == _active_biome_id:
		return
	_clear_visual_children()
	_built_biome_id = _active_biome_id

	match _built_biome_id:
		1:
			_build_glacier_wall()
		2:
			_build_astral_gate()
		3:
			_build_basalt_wall()
		4:
			_build_hextech_gate()
		_:
			_build_meadow_vines()


func _build_meadow_vines() -> void:
	for i in range(13):
		var z_off: float = (0.15 if (i % 2 == 0) else -0.15)
		var lean_z: float = (-0.19 if (i % 2 == 0) else 0.19)
		var lean_x: float = sin(float(i) * 1.7) * 0.15

		var stalk := MeshInstance3D.new()
		stalk.mesh = _stalk_mesh
		stalk.material_override = _vine_dark_mat if (i % 2 == 0) else _vine_moss_mat
		stalk.position = Vector3(0.0, 0.76, z_off)
		stalk.rotation = Vector3(lean_x, float(i) * 0.6, lean_z)
		visuals_root.add_child(stalk)
		_pillars.append(stalk)

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

	for a_idx in range(4):
		var arch := MeshInstance3D.new()
		arch.mesh = _arch_mesh
		arch.material_override = _vine_moss_mat if (a_idx % 2 == 1) else _vine_dark_mat
		arch.position = Vector3(0.0, 0.36, 0.0)
		arch.rotation = Vector3(PI * 0.5, 0.0, sin(float(a_idx) * 2.1) * 0.16)
		visuals_root.add_child(arch)
		_arches.append(arch)


func _build_glacier_wall() -> void:
	for i in range(11):
		var is_spire: bool = (i % 2 == 0)
		var shard := MeshInstance3D.new()
		shard.mesh = _ice_crystal_mesh if is_spire else _ice_wedge_mesh
		shard.material_override = _vine_moss_mat if is_spire else _vine_dark_mat
		var h_mult: float = 0.82 + 0.32 * absf(sin(float(i) * 1.4))
		shard.scale = Vector3(1.0, h_mult, 1.0)
		shard.position = Vector3(0.0, (0.95 if is_spire else 0.56) * h_mult, 0.14 if is_spire else -0.14)
		shard.rotation = Vector3(sin(float(i) * 1.9) * 0.18, float(i) * 0.72, (-0.16 if (i % 4 == 0) else 0.14))
		visuals_root.add_child(shard)
		_pillars.append(shard)

		if i % 2 == 0:
			var tip := MeshInstance3D.new()
			tip.mesh = _octa_gem_mesh
			tip.material_override = _bud_locked_mat
			tip.position = Vector3(0.0, 1.08, 0.0)
			tip.scale = Vector3(0.62, 0.78, 0.62)
			shard.add_child(tip)
			_buds.append(tip)


func _build_astral_gate() -> void:
	for i in range(5):
		var pylon := MeshInstance3D.new()
		pylon.mesh = _astral_pylon_mesh
		pylon.material_override = _vine_dark_mat if (i % 2 == 0) else _vine_moss_mat
		pylon.position = Vector3(0.0, 0.92, 0.0)
		pylon.rotation = Vector3(0.0, PI * 0.25, 0.0)
		visuals_root.add_child(pylon)
		_pillars.append(pylon)

		var star_core := MeshInstance3D.new()
		star_core.mesh = _octa_gem_mesh
		star_core.material_override = _bud_locked_mat
		star_core.position = Vector3(0.0, 1.24, 0.0)
		star_core.scale = Vector3(0.95, 1.15, 0.95)
		pylon.add_child(star_core)
		_buds.append(star_core)
		_spinners.append(star_core)

	for r_i in range(2):
		var rail := MeshInstance3D.new()
		rail.mesh = _beam_rail_mesh
		rail.material_override = _bud_locked_mat
		rail.position = Vector3(0.0, 0.68 + float(r_i) * 0.68, 0.0)
		rail.scale = Vector3(1.0, 0.75, 0.75)
		visuals_root.add_child(rail)
		_beam_rails.append(rail)
		_buds.append(rail)


func _build_basalt_wall() -> void:
	for i in range(9):
		var h_sc: float = 0.72 + 0.42 * absf(cos(float(i) * 1.15))
		var col := MeshInstance3D.new()
		col.mesh = _basalt_hex_mesh
		col.material_override = _vine_dark_mat if (i % 2 == 0) else _vine_moss_mat
		col.scale = Vector3(1.0, h_sc, 1.0)
		col.position = Vector3(0.0, 0.88 * h_sc, (0.12 if (i % 2 == 0) else -0.12))
		col.rotation = Vector3(0.0, float(i) * 0.52, 0.0)
		visuals_root.add_child(col)
		_pillars.append(col)

		if i % 2 == 1:
			var ember := MeshInstance3D.new()
			ember.mesh = _octa_gem_mesh
			ember.material_override = _bud_locked_mat
			ember.position = Vector3(0.0, 1.08, 0.0)
			ember.scale = Vector3(0.75, 0.95, 0.75)
			col.add_child(ember)
			_buds.append(ember)

	for r_i in range(2):
		var magma_bar := MeshInstance3D.new()
		magma_bar.mesh = _beam_rail_mesh
		magma_bar.material_override = _bud_locked_mat
		magma_bar.position = Vector3(0.0, 0.52 + float(r_i) * 0.62, 0.0)
		magma_bar.scale = Vector3(1.0, 0.95, 0.95)
		visuals_root.add_child(magma_bar)
		_beam_rails.append(magma_bar)
		_buds.append(magma_bar)


func _build_hextech_gate() -> void:
	for i in range(6):
		var mono := MeshInstance3D.new()
		mono.mesh = _hex_monolith_mesh
		mono.material_override = _vine_dark_mat if (i % 2 == 0) else _vine_moss_mat
		mono.position = Vector3(0.0, 0.88, 0.0)
		mono.rotation = Vector3(0.0, PI * 0.25 if (i % 2 == 1) else 0.0, 0.0)
		visuals_root.add_child(mono)
		_pillars.append(mono)

		var ring := MeshInstance3D.new()
		ring.mesh = _halo_ring_mesh
		ring.material_override = _bud_locked_mat
		ring.position = Vector3(0.0, 0.42, 0.0)
		ring.rotation = Vector3(0.45, float(i) * 0.8, -0.35)
		mono.add_child(ring)
		_buds.append(ring)
		_spinners.append(ring)

	for r_i in range(2):
		var plasma := MeshInstance3D.new()
		plasma.mesh = _beam_rail_mesh
		plasma.material_override = _bud_locked_mat
		plasma.position = Vector3(0.0, 0.62 + float(r_i) * 0.70, 0.0)
		plasma.scale = Vector3(1.0, 0.82, 0.82)
		visuals_root.add_child(plasma)
		_beam_rails.append(plasma)
		_buds.append(plasma)


func _layout_for_span(clean_span: float) -> void:
	var visual_span: float = maxf(4.2, clean_span - 0.5)
	for i in range(_pillars.size()):
		var frac: float = float(i) / float(maxi(1, _pillars.size() - 1)) - 0.5
		_pillars[i].position.x = frac * visual_span

	var arch_span: float = visual_span * 0.76
	var arch_scale_x: float = clampf(clean_span / 6.2, 0.95, 1.55)
	for a_i in range(_arches.size()):
		var a_frac: float = float(a_i) / float(maxi(1, _arches.size() - 1)) - 0.5
		_arches[a_i].position.x = a_frac * arch_span
		_arches[a_i].scale = Vector3(arch_scale_x, 1.0, 1.05)

	for rail in _beam_rails:
		rail.position.x = 0.0
		rail.scale.x = visual_span


## Raises the biome gate across a bridge edge from shoreline bank to shoreline bank
func activate_barrier(
	p_area_idx: int,
	world_pos: Vector3,
	bridge_dir_2d: Vector2,
	span_width: float
) -> void:
	_ensure_biome_geometry()
	bound_area_idx = p_area_idx
	var clean_span: float = maxf(4.8, span_width)
	if _box_shape:
		# Extend collision 1.0m beyond visual span into both shoreline walls so zero edge bypass is possible
		_box_shape.size = Vector3(clean_span + 1.0, 2.6, 0.85)

	_layout_for_span(clean_span)

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


## Immediately unlocks collision and retracts the barrier back underground
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
	for sp in _spinners:
		if sp != null and is_instance_valid(sp):
			sp.rotation.y += delta * 2.4

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
	elif _built_biome_id == 0:
		_sway_time += delta * 2.6
		if visuals_root:
			visuals_root.scale.y = 1.0 + sin(_sway_time) * 0.03
