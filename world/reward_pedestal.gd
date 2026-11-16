class_name RewardPedestal
extends Node3D

## Pooled 3D Upgrade Shrine / Reward Pedestal spawned in Spawn Sanctuary and upon Arena clear.
## Displays a floating octahedron crystal and invites the player to press [F] to draft 1 of 3 upgrades.

const CatalogScript = preload("res://scripts/data/combat_catalog.gd")

signal pedestal_interacted(pedestal: Node3D, player_node: Node)

var pool: Node = null

@onready var plinth_mesh: MeshInstance3D = $PlinthMesh
@onready var ring_mesh: MeshInstance3D = $RingMesh
@onready var crystal_mesh: MeshInstance3D = $CrystalMesh
@onready var prompt_label: Label3D = $PromptLabel

var _players_root: Node3D = null
var _active: bool = false
var _consuming: bool = false
var _consume_timer: float = 0.0
var _phase: float = 0.0
var _player_in_range: bool = false
var _rolled_cards: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()

const INTERACT_RADIUS: float = 3.1

static var _shared_plinth: CylinderMesh = null
static var _shared_ring: TorusMesh = null
static var _shared_octahedron: SphereMesh = null
static var _plinth_mat: StandardMaterial3D = null
static var _ring_mat: StandardMaterial3D = null
static var _crystal_mat: StandardMaterial3D = null


static func _ensure_shared() -> void:
	if _shared_plinth != null:
		return

	_shared_plinth = CylinderMesh.new()
	_shared_plinth.top_radius = 0.44
	_shared_plinth.bottom_radius = 0.58
	_shared_plinth.height = 0.40
	_shared_plinth.radial_segments = 8

	_shared_ring = TorusMesh.new()
	_shared_ring.inner_radius = 1.18
	_shared_ring.outer_radius = 1.32
	_shared_ring.rings = 24
	_shared_ring.ring_segments = 8

	# radial_segments=4, rings=1 produces a crisp 8-face octahedron diamond
	_shared_octahedron = SphereMesh.new()
	_shared_octahedron.radius = 0.34
	_shared_octahedron.height = 0.78
	_shared_octahedron.radial_segments = 4
	_shared_octahedron.rings = 1

	_plinth_mat = StandardMaterial3D.new()
	_plinth_mat.albedo_color = Color(0.18, 0.21, 0.27, 1.0)
	_plinth_mat.roughness = 0.65

	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.albedo_color = Color(0.95, 0.88, 0.62, 0.58)

	_crystal_mat = StandardMaterial3D.new()
	_crystal_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	_crystal_mat.albedo_color = Color(0.56, 0.94, 1.0, 1.0)
	_crystal_mat.emission_enabled = true
	_crystal_mat.emission = Color(0.32, 0.82, 0.96, 1.0)
	_crystal_mat.emission_energy_multiplier = 1.35


func _ready() -> void:
	_rng.randomize()
	_ensure_shared()
	if plinth_mesh:
		plinth_mesh.mesh = _shared_plinth
		plinth_mesh.position = Vector3(0.0, 0.20, 0.0)
		plinth_mesh.material_override = _plinth_mat
	if ring_mesh:
		ring_mesh.mesh = _shared_ring
		ring_mesh.position = Vector3(0.0, 0.04, 0.0)
		ring_mesh.material_override = _ring_mat
		ring_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if crystal_mesh:
		crystal_mesh.mesh = _shared_octahedron
		crystal_mesh.position = Vector3(0.0, 1.08, 0.0)
		crystal_mesh.material_override = _crystal_mat


func activate_pedestal(p_pos: Vector3, p_players_root: Node3D, p_seed_hint: int = 0) -> void:
	_ensure_shared()
	_players_root = p_players_root
	_active = true
	_consuming = false
	_consume_timer = 0.0
	_phase = 0.0
	_player_in_range = false
	_rolled_cards.clear()

	if p_seed_hint != 0:
		_rng.seed = int(p_seed_hint) ^ int(Time.get_ticks_usec() & 0xFFFF)
	else:
		_rng.randomize()

	scale = Vector3.ONE
	if crystal_mesh:
		crystal_mesh.scale = Vector3.ONE
	if prompt_label:
		prompt_label.text = "[F]"
		prompt_label.modulate = Color(0.56, 0.96, 1.0, 1.0)
		prompt_label.visible = false

	if is_inside_tree():
		global_position = Vector3(p_pos.x, 0.0, p_pos.z)
		reset_physics_interpolation()
	else:
		position = Vector3(p_pos.x, 0.0, p_pos.z)

	visible = true
	set_process(true)


func get_or_roll_cards(player_node: Node) -> Array[Dictionary]:
	if not _rolled_cards.is_empty():
		return _rolled_cards

	var eq_weapons: Array = player_node.get("weapon_slots") if (player_node and "weapon_slots" in player_node) else []
	var eq_abilities: Array = player_node.get("ability_slots") if (player_node and "ability_slots" in player_node) else []
	var eq_artifact: int = int(player_node.get("artifact_id")) if (player_node and "artifact_id" in player_node) else 0

	var ability_pool: Array[Dictionary] = []
	for abid in CatalogScript.get_all_ability_ids():
		if not eq_abilities.has(abid):
			ability_pool.append({"category": "ability", "id": abid})
	for artid in CatalogScript.get_all_artifact_ids():
		if eq_artifact != artid:
			ability_pool.append({"category": "artifact", "id": artid})

	var weapon_or_shard_pool: Array[Dictionary] = []
	for sh_id in CatalogScript.get_all_shard_ids():
		weapon_or_shard_pool.append({"category": "shard", "id": sh_id})
	if _rng.randf() < 0.40:
		var unowned_weps: Array[Dictionary] = []
		for wid in CatalogScript.get_all_weapon_ids():
			if not eq_weapons.has(wid):
				unowned_weps.append({"category": "weapon", "id": wid})
		if not unowned_weps.is_empty():
			weapon_or_shard_pool = unowned_weps

	var stat_pool: Array[Dictionary] = [
		{"category": "trait", "id": CatalogScript.TraitId.STAT_AD},
		{"category": "trait", "id": CatalogScript.TraitId.STAT_AP},
		{"category": "trait", "id": CatalogScript.TraitId.STAT_HP},
		{"category": "trait", "id": CatalogScript.TraitId.STAT_ATK_SPD},
		{"category": "trait", "id": CatalogScript.TraitId.STAT_HASTE},
		{"category": "trait", "id": CatalogScript.TraitId.STAT_MOVE_SPD}
	]

	# Card 1: Ability or Artifact
	if not ability_pool.is_empty():
		_rolled_cards.append(ability_pool[_rng.randi_range(0, ability_pool.size() - 1)])
	else:
		_rolled_cards.append({"category": "shard", "id": CatalogScript.ShardId.SHARD_STORM})

	# Card 2: Weapon Shard (or new Weapon)
	_rolled_cards.append(weapon_or_shard_pool[_rng.randi_range(0, weapon_or_shard_pool.size() - 1)])

	# Card 3: Stat Buff
	_rolled_cards.append(stat_pool[_rng.randi_range(0, stat_pool.size() - 1)])

	return _rolled_cards


func _has_card(arr: Array[Dictionary], cand: Dictionary) -> bool:
	for c in arr:
		if c.get("category") == cand.get("category") and int(c.get("id", -1)) == int(cand.get("id", -2)):
			return true
	return false


func consume_pedestal() -> void:
	if not _active or _consuming:
		return
	_consuming = true
	_consume_timer = 0.24
	if prompt_label:
		prompt_label.visible = false


func deactivate() -> void:
	_active = false
	_consuming = false
	_players_root = null
	_rolled_cards.clear()
	set_process(false)
	visible = false


func on_pool_release() -> void:
	deactivate()


func _release_self() -> void:
	_active = false
	if pool and pool.has_method("release"):
		pool.release(self)
	else:
		deactivate()


func _process(delta: float) -> void:
	if not _active:
		return

	if _consuming:
		_consume_timer -= delta
		scale = scale.lerp(Vector3.ZERO, clampf(16.0 * delta, 0.0, 1.0))
		if _consume_timer <= 0.0:
			_release_self()
		return

	_phase += delta * 2.4
	if crystal_mesh:
		crystal_mesh.position.y = 1.08 + sin(_phase) * 0.10
		crystal_mesh.rotation.y += delta * 1.35

	var near_player: Node3D = _find_local_player_in_range()
	var now_in_range: bool = (near_player != null)
	if now_in_range != _player_in_range:
		_player_in_range = now_in_range
		if prompt_label:
			prompt_label.visible = _player_in_range
			if _player_in_range:
				prompt_label.text = "[F]"
				prompt_label.modulate = Color(0.56, 0.96, 1.0, 1.0)

	if _player_in_range and near_player != null:
		var blocked: bool = bool(near_player.get("ui_input_blocked")) if ("ui_input_blocked" in near_player) else false
		if not blocked and Input.is_action_just_pressed("interact"):
			pedestal_interacted.emit(self, near_player)


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
		if (dx * dx + dz * dz) <= r2:
			return p3d
	return null
