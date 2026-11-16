class_name HealingWell
extends Node3D

## Pooled persistent Healing Well placed infrequently across stages (1 every ~4 arenas).
## Remains permanently in its room for the duration of the run so players can pass by
## at full health and backtrack across cleared bridges later to restore +45% Max HP per charge.

const ZoneScript = preload("res://world/combat_zone_effect.gd")

var pool: Node = null
var area_idx: int = -1

@onready var basin_mesh: MeshInstance3D = $BasinMesh
@onready var rim_mesh: MeshInstance3D = $RimMesh
@onready var water_mesh: MeshInstance3D = $WaterMesh
@onready var orb_a: MeshInstance3D = $OrbA
@onready var orb_b: MeshInstance3D = $OrbB
@onready var prompt_label: Label3D = $PromptLabel

var _players_root: Node3D = null
var _encounter_mgr: Node = null
var _active: bool = false
var _charges_left: int = 2
var _max_charges: int = 2
var _phase: float = 0.0

const INTERACT_RADIUS: float = 3.1
const HEAL_PCT: float = 0.45

static var _shared_basin: CylinderMesh = null
static var _shared_rim: TorusMesh = null
static var _shared_water: CylinderMesh = null
static var _shared_orb: SphereMesh = null
static var _stone_mat: StandardMaterial3D = null
static var _water_full_mat: StandardMaterial3D = null
static var _water_empty_mat: StandardMaterial3D = null
static var _orb_mat: StandardMaterial3D = null


static func _ensure_shared() -> void:
	if _shared_basin != null:
		return

	_shared_basin = CylinderMesh.new()
	_shared_basin.top_radius = 1.02
	_shared_basin.bottom_radius = 1.14
	_shared_basin.height = 0.28
	_shared_basin.radial_segments = 12

	_shared_rim = TorusMesh.new()
	_shared_rim.inner_radius = 0.84
	_shared_rim.outer_radius = 1.12
	_shared_rim.rings = 20
	_shared_rim.ring_segments = 8

	_shared_water = CylinderMesh.new()
	_shared_water.top_radius = 0.88
	_shared_water.bottom_radius = 0.88
	_shared_water.height = 0.04
	_shared_water.radial_segments = 16

	_shared_orb = SphereMesh.new()
	_shared_orb.radius = 0.16
	_shared_orb.height = 0.38
	_shared_orb.radial_segments = 4
	_shared_orb.rings = 1

	_stone_mat = StandardMaterial3D.new()
	_stone_mat.albedo_color = Color(0.26, 0.30, 0.35, 1.0)
	_stone_mat.roughness = 0.72

	_water_full_mat = StandardMaterial3D.new()
	_water_full_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_water_full_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_water_full_mat.albedo_color = Color(0.22, 0.96, 0.66, 0.86)

	_water_empty_mat = StandardMaterial3D.new()
	_water_empty_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_water_empty_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_water_empty_mat.albedo_color = Color(0.12, 0.20, 0.24, 0.58)

	_orb_mat = StandardMaterial3D.new()
	_orb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_orb_mat.albedo_color = Color(0.45, 1.0, 0.74, 1.0)


func _ready() -> void:
	_ensure_shared()
	if basin_mesh:
		basin_mesh.mesh = _shared_basin
		basin_mesh.position = Vector3(0.0, 0.14, 0.0)
		basin_mesh.material_override = _stone_mat
	if rim_mesh:
		rim_mesh.mesh = _shared_rim
		rim_mesh.position = Vector3(0.0, 0.28, 0.0)
		rim_mesh.material_override = _stone_mat
	if water_mesh:
		water_mesh.mesh = _shared_water
		water_mesh.position = Vector3(0.0, 0.27, 0.0)
		water_mesh.material_override = _water_full_mat
		water_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if orb_a:
		orb_a.mesh = _shared_orb
		orb_a.material_override = _orb_mat
	if orb_b:
		orb_b.mesh = _shared_orb
		orb_b.material_override = _orb_mat


func activate_well(
	p_area_idx: int,
	p_pos: Vector3,
	p_players_root: Node3D,
	p_encounter_mgr: Node,
	p_charges: int = 2
) -> void:
	_ensure_shared()
	area_idx = p_area_idx
	_players_root = p_players_root
	_encounter_mgr = p_encounter_mgr
	_max_charges = maxi(1, p_charges)
	_charges_left = _max_charges
	_phase = 0.0
	_active = true

	_refresh_visuals()

	if is_inside_tree():
		global_position = Vector3(p_pos.x, 0.0, p_pos.z)
		reset_physics_interpolation()
	else:
		position = Vector3(p_pos.x, 0.0, p_pos.z)

	visible = true
	set_process(true)


func _refresh_visuals() -> void:
	if water_mesh:
		water_mesh.material_override = _water_full_mat if _charges_left > 0 else _water_empty_mat
	if orb_a:
		orb_a.visible = (_charges_left >= 1)
	if orb_b:
		orb_b.visible = (_charges_left >= 2)


func deactivate() -> void:
	_active = false
	_players_root = null
	_encounter_mgr = null
	set_process(false)
	visible = false


func on_pool_release() -> void:
	deactivate()


func _process(delta: float) -> void:
	if not _active:
		return

	_phase += delta * 2.1
	if _charges_left > 0:
		if orb_a and orb_a.visible:
			orb_a.position = Vector3(cos(_phase) * 0.46, 0.86 + sin(_phase * 1.6) * 0.08, sin(_phase) * 0.46)
			orb_a.rotation.y += delta * 1.6
		if orb_b and orb_b.visible:
			orb_b.position = Vector3(cos(_phase + PI) * 0.46, 0.86 + sin(_phase * 1.6 + PI) * 0.08, sin(_phase + PI) * 0.46)
			orb_b.rotation.y += delta * 1.6

	if _charges_left <= 0:
		if prompt_label:
			prompt_label.text = "◆ Healing Well (Depleted)"
			prompt_label.modulate = Color(0.65, 0.72, 0.74, 0.58)
		return

	var combat_locked: bool = false
	if _encounter_mgr != null and is_instance_valid(_encounter_mgr) and _encounter_mgr.has_method("is_encounter_active"):
		combat_locked = bool(_encounter_mgr.call("is_encounter_active"))

	if combat_locked:
		if prompt_label:
			prompt_label.text = "◆ Healing Well (Clear Arena First)"
			prompt_label.modulate = Color(0.95, 0.78, 0.48, 0.72)
		return

	var near_player: Node3D = _find_local_player_in_range()
	if near_player == null:
		if prompt_label:
			prompt_label.text = "◆ Healing Well [%d/%d]" % [_charges_left, _max_charges]
			prompt_label.modulate = Color(0.48, 0.98, 0.74, 0.82)
		return

	var hc: HealthComponent = near_player.call("get_health_component") as HealthComponent if near_player.has_method("get_health_component") else null
	var is_full_hp: bool = (hc == null) or (hc.current_health >= hc.max_health - 0.25)

	if prompt_label:
		if is_full_hp:
			prompt_label.text = "◆ Healing Well — Full HP [%d/%d]" % [_charges_left, _max_charges]
			prompt_label.modulate = Color(0.68, 0.94, 0.82, 0.82)
		else:
			prompt_label.text = "[F] Drink Healing Well (+45%% HP) [%d/%d]" % [_charges_left, _max_charges]
			prompt_label.modulate = Color(0.42, 1.0, 0.72, 1.0)

	if not is_full_hp and hc != null:
		var blocked: bool = bool(near_player.get("ui_input_blocked")) if ("ui_input_blocked" in near_player) else false
		if not blocked and Input.is_action_just_pressed("interact"):
			var heal_amt: float = hc.max_health * HEAL_PCT
			var gained: float = hc.heal(heal_amt)
			if gained > 0.01:
				_charges_left = maxi(0, _charges_left - 1)
				_refresh_visuals()
				if ProjectilePool and ProjectilePool.has_method("spawn_zone_effect"):
					ProjectilePool.call(
						"spawn_zone_effect",
						ZoneScript.ZoneMode.SELF_WARD,
						near_player.global_position,
						2.3,
						0.0,
						0.50,
						"heal_well",
						Color(0.32, 1.0, 0.68, 1.0),
						null,
						0.0,
						near_player
					)


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
