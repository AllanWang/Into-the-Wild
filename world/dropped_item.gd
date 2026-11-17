class_name DroppedItem
extends Node3D

## Pooled 3D Ground Loot Drop spawned whenever a player replaces an equipped Weapon,
## Artifact, Ability, or Weapon Shard so zero items are ever discarded.
## Players can press [F] to pick up or swap any dropped item back into their build.

const CatalogScript = preload("res://scripts/data/combat_catalog.gd")

signal dropped_item_interacted(drop_node: Node3D, player_node: Node)

const INTERACT_RADIUS: float = 2.45
const POP_DURATION: float = 0.22

var item_category: String = ""
var item_id: int = 0
var item_name: String = "Relic"

var base_mesh: MeshInstance3D = null
var halo_mesh: MeshInstance3D = null
var core_mesh: MeshInstance3D = null
var prompt_label: Label3D = null

var _accent_mat: StandardMaterial3D = null
var _halo_mat: StandardMaterial3D = null

var _players_root: Node3D = null
var _active: bool = false
var _consuming: bool = false
var _consume_timer: float = 0.0
var _pop_timer: float = 0.0
var _pickup_grace: float = 0.0
var _pop_origin: Vector3 = Vector3.ZERO
var _target_pos: Vector3 = Vector3.ZERO
var _phase: float = 0.0
var _player_in_range: bool = false

static var _shared_base: CylinderMesh = null
static var _shared_halo: TorusMesh = null
static var _shared_weapon_mesh: BoxMesh = null
static var _shared_artifact_mesh: TorusMesh = null
static var _shared_gem_mesh: SphereMesh = null
static var _shared_base_mat: StandardMaterial3D = null


static func _ensure_shared() -> void:
	if _shared_base != null:
		return

	_shared_base = CylinderMesh.new()
	_shared_base.top_radius = 0.28
	_shared_base.bottom_radius = 0.36
	_shared_base.height = 0.09
	_shared_base.radial_segments = 10

	_shared_halo = TorusMesh.new()
	_shared_halo.inner_radius = 0.56
	_shared_halo.outer_radius = 0.66
	_shared_halo.rings = 20
	_shared_halo.ring_segments = 8

	_shared_weapon_mesh = BoxMesh.new()
	_shared_weapon_mesh.size = Vector3(0.24, 0.24, 0.58)

	_shared_artifact_mesh = TorusMesh.new()
	_shared_artifact_mesh.inner_radius = 0.19
	_shared_artifact_mesh.outer_radius = 0.31
	_shared_artifact_mesh.rings = 20
	_shared_artifact_mesh.ring_segments = 8

	_shared_gem_mesh = SphereMesh.new()
	_shared_gem_mesh.radius = 0.24
	_shared_gem_mesh.height = 0.54
	_shared_gem_mesh.radial_segments = 4
	_shared_gem_mesh.rings = 1

	_shared_base_mat = StandardMaterial3D.new()
	_shared_base_mat.albedo_color = Color(0.16, 0.19, 0.25, 1.0)
	_shared_base_mat.roughness = 0.65


func _ready() -> void:
	_ensure_nodes()
	if not _active:
		visible = false
		set_process(false)


func _ensure_nodes() -> void:
	_ensure_shared()
	if base_mesh != null:
		return

	_accent_mat = StandardMaterial3D.new()
	_accent_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	_accent_mat.albedo_color = Color(1.0, 0.86, 0.42, 1.0)
	_accent_mat.emission_enabled = true
	_accent_mat.emission = Color(0.85, 0.68, 0.24, 1.0)
	_accent_mat.emission_energy_multiplier = 1.25

	_halo_mat = StandardMaterial3D.new()
	_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_halo_mat.albedo_color = Color(1.0, 0.86, 0.42, 0.58)

	base_mesh = MeshInstance3D.new()
	base_mesh.name = "BaseMesh"
	base_mesh.mesh = _shared_base
	base_mesh.position = Vector3(0.0, 0.045, 0.0)
	base_mesh.material_override = _shared_base_mat
	add_child(base_mesh)

	halo_mesh = MeshInstance3D.new()
	halo_mesh.name = "HaloMesh"
	halo_mesh.mesh = _shared_halo
	halo_mesh.position = Vector3(0.0, 0.03, 0.0)
	halo_mesh.material_override = _halo_mat
	halo_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo_mesh)

	core_mesh = MeshInstance3D.new()
	core_mesh.name = "CoreMesh"
	core_mesh.mesh = _shared_gem_mesh
	core_mesh.position = Vector3(0.0, 0.68, 0.0)
	core_mesh.material_override = _accent_mat
	add_child(core_mesh)

	prompt_label = Label3D.new()
	prompt_label.name = "PromptLabel"
	prompt_label.position = Vector3(0.0, 1.30, 0.0)
	prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	prompt_label.no_depth_test = true
	prompt_label.font_size = 24
	prompt_label.outline_size = 5
	prompt_label.pixel_size = 0.005
	prompt_label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	prompt_label.text = "◆ Dropped Item"
	add_child(prompt_label)


func is_available() -> bool:
	return not _active


func get_spec() -> Dictionary:
	return {
		"category": item_category,
		"id": item_id
	}


func activate_drop(
	p_category: String,
	p_id: int,
	p_origin_pos: Vector3,
	p_target_pos: Vector3,
	p_players_root: Node3D
) -> void:
	_ensure_nodes()
	item_category = p_category
	item_id = p_id
	_players_root = p_players_root
	_active = true
	_consuming = false
	_consume_timer = 0.0
	_pop_timer = POP_DURATION
	_pickup_grace = 0.28
	_pop_origin = Vector3(p_origin_pos.x, 0.0, p_origin_pos.z)
	_target_pos = Vector3(p_target_pos.x, 0.0, p_target_pos.z)
	_phase = 0.0
	_player_in_range = false
	scale = Vector3.ONE

	var info: Dictionary = _lookup_catalog_entry(item_category, item_id)
	item_name = str(info.get("name", "Relic"))
	var col: Color = info.get("color", Color(0.86, 0.88, 0.96, 1.0)) as Color

	if _accent_mat:
		_accent_mat.albedo_color = col
		_accent_mat.emission = col.darkened(0.18)
	if _halo_mat:
		_halo_mat.albedo_color = Color(col.r, col.g, col.b, 0.62)

	if core_mesh:
		core_mesh.scale = Vector3.ONE
		match item_category:
			"weapon":
				core_mesh.mesh = _shared_weapon_mesh
				core_mesh.rotation_degrees = Vector3(26.0, 0.0, 45.0)
			"artifact":
				core_mesh.mesh = _shared_artifact_mesh
				core_mesh.rotation_degrees = Vector3(68.0, 0.0, 0.0)
			_:
				core_mesh.mesh = _shared_gem_mesh
				core_mesh.rotation_degrees = Vector3.ZERO

	_refresh_prompt_text(false)

	if is_inside_tree():
		global_position = _pop_origin
		reset_physics_interpolation()
	else:
		position = _pop_origin

	visible = true
	set_process(true)


func consume_drop() -> void:
	if not _active or _consuming:
		return
	_consuming = true
	_consume_timer = 0.16
	if prompt_label:
		prompt_label.visible = false


func deactivate() -> void:
	_active = false
	_consuming = false
	_players_root = null
	_player_in_range = false
	set_process(false)
	visible = false


func _process(delta: float) -> void:
	if not _active:
		return

	if _consuming:
		_consume_timer -= delta
		scale = scale.lerp(Vector3.ZERO, clampf(18.0 * delta, 0.0, 1.0))
		if _consume_timer <= 0.0:
			deactivate()
		return

	if _pickup_grace > 0.0:
		_pickup_grace = maxf(0.0, _pickup_grace - delta)

	if _pop_timer > 0.0:
		_pop_timer = maxf(0.0, _pop_timer - delta)
		var progress: float = 1.0 - (_pop_timer / POP_DURATION)
		var eased: float = 1.0 - (1.0 - progress) * (1.0 - progress)
		global_position = _pop_origin.lerp(_target_pos, eased)
		if core_mesh:
			core_mesh.position.y = 0.68 + sin(progress * PI) * 0.56
			core_mesh.rotation.y += delta * 6.5
	else:
		global_position = _target_pos
		_phase += delta * 2.6
		if core_mesh:
			core_mesh.position.y = 0.68 + sin(_phase) * 0.08
			core_mesh.rotation.y += delta * 1.65

	if _pickup_grace > 0.0:
		return

	var near_player: Node3D = _find_local_player_in_range()
	var now_in_range: bool = (near_player != null)
	if now_in_range != _player_in_range:
		_player_in_range = now_in_range
		_refresh_prompt_text(_player_in_range)

	if _player_in_range and near_player != null:
		var can_act: bool = true
		if near_player.has_method("can_world_interact"):
			can_act = bool(near_player.call("can_world_interact"))
		elif "ui_input_blocked" in near_player:
			can_act = not bool(near_player.get("ui_input_blocked"))
		if can_act and Input.is_action_just_pressed("interact"):
			if near_player.has_method("consume_world_interact"):
				near_player.call("consume_world_interact")
			dropped_item_interacted.emit(self, near_player)


func _refresh_prompt_text(in_range: bool) -> void:
	if prompt_label == null:
		return
	prompt_label.visible = true
	var kind_label: String = _category_title(item_category)
	if in_range:
		if item_category == "artifact":
			prompt_label.text = "[F] Equip %s (%s)" % [item_name, kind_label]
		else:
			prompt_label.text = "[F] Pick Up %s (%s)" % [item_name, kind_label]
		prompt_label.modulate = Color(0.56, 0.96, 1.0, 1.0)
	else:
		prompt_label.text = "◆ %s (%s)" % [item_name, kind_label]
		prompt_label.modulate = Color(0.94, 0.91, 0.85, 0.82)


static func _category_title(cat: String) -> String:
	match cat:
		"weapon":
			return "Weapon"
		"artifact":
			return "Artifact"
		"ability":
			return "Ability"
		"shard":
			return "Shard"
	return "Item"


static func _lookup_catalog_entry(cat: String, id: int) -> Dictionary:
	match cat:
		"weapon":
			return CatalogScript.get_weapon(id)
		"artifact":
			return CatalogScript.get_artifact(id)
		"ability":
			return CatalogScript.get_ability(id)
		"shard":
			return CatalogScript.get_shard(id)
	return {}


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
			var mgr: Node = get_parent()
			if mgr != null and mgr.has_method("is_nearest_interactable") and not bool(mgr.call("is_nearest_interactable", self, p3d, INTERACT_RADIUS)):
				return null
			return p3d
	return null
