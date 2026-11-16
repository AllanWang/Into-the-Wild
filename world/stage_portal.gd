class_name StagePortal
extends Node3D

## Procedural 3D Rift Portal spawned upon clearing the Final Stage (Boss Citadel).
## Invites the player to press [F] to step into the next map (new seed + starting point)
## while preserving their full equipped loadout, shards, abilities, artifact, and stats.

signal portal_activated(player_node: Node)

const INTERACT_RADIUS: float = 3.1

var base_mesh: MeshInstance3D = null
var floor_ring_mesh: MeshInstance3D = null
var arch_mesh: MeshInstance3D = null
var vortex_mesh: MeshInstance3D = null
var mote_a: MeshInstance3D = null
var mote_b: MeshInstance3D = null
var prompt_label: Label3D = null

var _players_root: Node3D = null
var _active: bool = false
var _phase: float = 0.0
var _player_in_range: bool = false

static var _shared_base: CylinderMesh = null
static var _shared_floor_ring: TorusMesh = null
static var _shared_arch: TorusMesh = null
static var _shared_vortex: CylinderMesh = null
static var _shared_mote: SphereMesh = null

static var _base_mat: StandardMaterial3D = null
static var _floor_ring_mat: StandardMaterial3D = null
static var _arch_mat: StandardMaterial3D = null
static var _vortex_mat: StandardMaterial3D = null
static var _mote_mat: StandardMaterial3D = null


static func _ensure_shared() -> void:
	if _shared_base != null:
		return

	_shared_base = CylinderMesh.new()
	_shared_base.top_radius = 1.32
	_shared_base.bottom_radius = 1.54
	_shared_base.height = 0.22
	_shared_base.radial_segments = 12

	_shared_floor_ring = TorusMesh.new()
	_shared_floor_ring.inner_radius = 1.62
	_shared_floor_ring.outer_radius = 1.78
	_shared_floor_ring.rings = 28
	_shared_floor_ring.ring_segments = 8

	_shared_arch = TorusMesh.new()
	_shared_arch.inner_radius = 1.04
	_shared_arch.outer_radius = 1.24
	_shared_arch.rings = 28
	_shared_arch.ring_segments = 10

	_shared_vortex = CylinderMesh.new()
	_shared_vortex.top_radius = 1.04
	_shared_vortex.bottom_radius = 1.04
	_shared_vortex.height = 0.06
	_shared_vortex.radial_segments = 24

	_shared_mote = SphereMesh.new()
	_shared_mote.radius = 0.16
	_shared_mote.height = 0.36
	_shared_mote.radial_segments = 4
	_shared_mote.rings = 1

	_base_mat = StandardMaterial3D.new()
	_base_mat.albedo_color = Color(0.16, 0.18, 0.26, 1.0)
	_base_mat.roughness = 0.62

	_floor_ring_mat = StandardMaterial3D.new()
	_floor_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_floor_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_floor_ring_mat.albedo_color = Color(0.68, 0.56, 1.0, 0.62)

	_arch_mat = StandardMaterial3D.new()
	_arch_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	_arch_mat.albedo_color = Color(0.32, 0.26, 0.48, 1.0)
	_arch_mat.emission_enabled = true
	_arch_mat.emission = Color(0.46, 0.34, 0.92, 1.0)
	_arch_mat.emission_energy_multiplier = 1.15

	_vortex_mat = StandardMaterial3D.new()
	_vortex_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_vortex_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_vortex_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_vortex_mat.albedo_color = Color(0.48, 0.78, 1.0, 0.72)

	_mote_mat = StandardMaterial3D.new()
	_mote_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mote_mat.albedo_color = Color(0.74, 0.96, 1.0, 1.0)


func _ready() -> void:
	_ensure_nodes()
	if not _active:
		visible = false
		set_process(false)


func _ensure_nodes() -> void:
	_ensure_shared()
	if base_mesh != null:
		return

	base_mesh = MeshInstance3D.new()
	base_mesh.name = "BaseMesh"
	base_mesh.mesh = _shared_base
	base_mesh.position = Vector3(0.0, 0.11, 0.0)
	base_mesh.material_override = _base_mat
	add_child(base_mesh)

	floor_ring_mesh = MeshInstance3D.new()
	floor_ring_mesh.name = "FloorRingMesh"
	floor_ring_mesh.mesh = _shared_floor_ring
	floor_ring_mesh.position = Vector3(0.0, 0.04, 0.0)
	floor_ring_mesh.material_override = _floor_ring_mat
	floor_ring_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(floor_ring_mesh)

	arch_mesh = MeshInstance3D.new()
	arch_mesh.name = "ArchMesh"
	arch_mesh.mesh = _shared_arch
	arch_mesh.position = Vector3(0.0, 1.48, 0.0)
	arch_mesh.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	arch_mesh.material_override = _arch_mat
	add_child(arch_mesh)

	vortex_mesh = MeshInstance3D.new()
	vortex_mesh.name = "VortexMesh"
	vortex_mesh.mesh = _shared_vortex
	vortex_mesh.position = Vector3(0.0, 1.48, 0.0)
	vortex_mesh.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	vortex_mesh.material_override = _vortex_mat
	vortex_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(vortex_mesh)

	mote_a = MeshInstance3D.new()
	mote_a.name = "MoteA"
	mote_a.mesh = _shared_mote
	mote_a.material_override = _mote_mat
	mote_a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mote_a)

	mote_b = MeshInstance3D.new()
	mote_b.name = "MoteB"
	mote_b.mesh = _shared_mote
	mote_b.material_override = _mote_mat
	mote_b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mote_b)

	prompt_label = Label3D.new()
	prompt_label.name = "PromptLabel"
	prompt_label.position = Vector3(0.0, 3.05, 0.0)
	prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	prompt_label.no_depth_test = true
	prompt_label.font_size = 28
	prompt_label.outline_size = 5
	prompt_label.pixel_size = 0.005
	prompt_label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	prompt_label.text = "◆ Rift Portal"
	prompt_label.modulate = Color(0.86, 0.78, 1.0, 0.86)
	add_child(prompt_label)


func activate_portal(p_pos: Vector3, p_players_root: Node3D) -> void:
	_ensure_nodes()
	_players_root = p_players_root
	_active = true
	_phase = 0.0
	_player_in_range = false

	if prompt_label:
		prompt_label.visible = true
		prompt_label.text = "◆ Rift Portal"
		prompt_label.modulate = Color(0.86, 0.78, 1.0, 0.86)

	if is_inside_tree():
		global_position = Vector3(p_pos.x, 0.0, p_pos.z)
		reset_physics_interpolation()
	else:
		position = Vector3(p_pos.x, 0.0, p_pos.z)

	visible = true
	set_process(true)


func deactivate() -> void:
	_active = false
	_players_root = null
	_player_in_range = false
	set_process(false)
	visible = false


func _process(delta: float) -> void:
	if not _active:
		return

	_phase += delta * 2.2
	if vortex_mesh:
		var pulse: float = 0.94 + sin(_phase * 1.8) * 0.06
		vortex_mesh.scale = Vector3(pulse, 1.0, pulse)
		vortex_mesh.rotation.y += delta * 1.4
	if floor_ring_mesh:
		floor_ring_mesh.rotation.y -= delta * 0.65
	if mote_a:
		mote_a.position = Vector3(cos(_phase) * 1.38, 1.48 + sin(_phase) * 1.38, sin(_phase * 2.0) * 0.18)
		mote_a.rotation.y += delta * 2.4
	if mote_b:
		mote_b.position = Vector3(cos(_phase + PI) * 1.38, 1.48 + sin(_phase + PI) * 1.38, sin(_phase * 2.0 + PI) * 0.18)
		mote_b.rotation.y += delta * 2.4

	var near_player: Node3D = _find_local_player_in_range()
	var now_in_range: bool = (near_player != null)
	if now_in_range != _player_in_range:
		_player_in_range = now_in_range
		if prompt_label:
			prompt_label.visible = true
			if _player_in_range:
				prompt_label.text = "[F] Enter Rift Portal — Next Map"
				prompt_label.modulate = Color(0.66, 0.94, 1.0, 1.0)
			else:
				prompt_label.text = "◆ Rift Portal"
				prompt_label.modulate = Color(0.86, 0.78, 1.0, 0.86)

	if _player_in_range and near_player != null:
		var blocked: bool = bool(near_player.get("ui_input_blocked")) if ("ui_input_blocked" in near_player) else false
		if not blocked and Input.is_action_just_pressed("interact"):
			var p_ref: Node = near_player
			deactivate()
			portal_activated.emit(p_ref)


func _find_local_player_in_range() -> Node3D:
	if _players_root == null or not is_instance_valid(_players_root):
		return null
	var r2: float = INTERACT_RADIUS * INTERACT_RADIUS
	var count: int = _players_root.get_child_count()
	for i in range(count):
		var p3d: Node3D = _players_root.get_child(i) as Node3D
		if p3d == null or not p3d.visible:
			continue
		if not p3d.is_multiplayer_authority():
			continue
		var dx: float = p3d.global_position.x - global_position.x
		var dz: float = p3d.global_position.z - global_position.z
		if dx * dx + dz * dz <= r2:
			return p3d
	return null
