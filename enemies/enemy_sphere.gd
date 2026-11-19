class_name EnemySphere
extends CharacterBody3D

## Pooled Enemy unit supporting Distinct 3D Role Silhouettes, Wind-Up Tells & Telegraph Timings:
## - CHASER (0): Crimson melee swarm sphere with eager forward-rolling bounce
## - DASHER (1): Twin wing-fins, nervous hover weave -> 0.58s rapid spin + cyan sightline -> juke-dash
## - BURROWER (2): Nose drill-auger -> 0.55s nose-down drill hop -> invulnerable tunnel -> 0.78s strobe emerge ring
## - LUNGER (3): Twin forward tusks -> 0.78s pull-back shudder + crimson sightline -> lunge
## - BRUISER (4): Orbiting monolith armor plates -> 1.15s high levitation spin -> radial Ground Quake + camera shake
## - MIRE_LOBBER (5): Overhead swelling toxic mortar sac -> 0.65s swell lean-back -> 1.10s arcing Blight Pool
## - OCULAR_SNIPER (6): Floating front aiming scope ring -> 1.25s spinning lock-on sightline -> Sniper Lance
## - BOSS (7): Tectonic Sovereign -> 1.15s levitating double-quake, 0.95s faultline cascade, 0.85s shudder charge
## - BOSS_BLIGHTWEAVER (8): Briarbloom Matriarch -> vine-spawner pillars, swarmer hordes, petal-curl thorn shell & spore blooms

const ArchetypeScript = preload("res://enemies/enemy_archetype_data.gd")
const HazardScript = preload("res://world/enemy_hazard_effect.gd")
const BossPropScript = preload("res://world/boss_mechanic_prop.gd")

signal defeated(enemy_id: int, area_idx: int)

var pool: Node = null
var enemy_id: int = -1
var area_idx: int = -1
var grass_displacement_size: float = 0.65

@onready var visual_root: Node3D = $VisualRoot
@onready var sphere_mesh_inst: MeshInstance3D = $VisualRoot/SphereMesh
@onready var body_col_shape: CollisionShape3D = $CollisionShape3D
@onready var health_comp: HealthComponent = $HealthComponent
@onready var hurtbox_comp: HurtboxComponent = $HurtboxComponent
@onready var hurtbox_col_shape: CollisionShape3D = $HurtboxComponent/CollisionShape3D
@onready var hp_bar_root: Node3D = $HPBarRoot
@onready var hp_bg_mesh: MeshInstance3D = $HPBarRoot/HPBg
@onready var hp_fill_mesh: MeshInstance3D = $HPBarRoot/HPFill

var _trim_ring_a: MeshInstance3D = null
var _trim_ring_b: MeshInstance3D = null
var _role_prop_a: MeshInstance3D = null
var _role_prop_b: MeshInstance3D = null
var _plant_crown_root: Node3D = null
var _plant_petal_pivots: Array[Node3D] = []
var _ward_shell_mesh: MeshInstance3D = null
var _aegis_dome_mesh: MeshInstance3D = null
var _aegis_dome_ring: MeshInstance3D = null
var _aegis_dome_mat: StandardMaterial3D = null
var _aegis_ring_mat: StandardMaterial3D = null
var _burrow_ring_inst: MeshInstance3D = null
var _contact_shadow_inst: MeshInstance3D = null

var _archetype: EnemyArchetypeData = null
var _players_root: Node3D = null
var boss_director: Node = null
var _is_active_unit: bool = false
var _is_dying: bool = false
var _death_timer: float = 0.0
var _hit_flash_timer: float = 0.0
var _suppress_hit_flash: bool = false
var _bob_phase: float = 0.0
var _base_radius: float = 0.38

# Hades-style multi-bar, armor, phase-shift & biome minion state
var _is_elite_unit: bool = false
var is_boss_reinforcement: bool = false
var is_astral_clone: bool = false
var is_vine_swarmer: bool = false
var _boss_phase: int = 1
var _frenzy_mult: float = 1.0
var _stagger_timer: float = 0.0
var _exposed_mult: float = 1.0
var _burst_window_dmg: float = 0.0
var _biome_trait_id: int = 0
var _biome_special_used: bool = false
var _hp_bar_mat: ShaderMaterial = null

# Signature boss mechanics state
var _return_to_center_active: bool = false
var _return_target_pos: Vector3 = Vector3.ZERO
var _clock_sector_queued: bool = false
var _aegis_dome_timer: float = 0.0
var _aegis_dome_radius: float = 8.2
var _aegis_dome_hp: float = 0.0
var _aegis_flash_timer: float = 0.0

# Ability / AI state machine timers (zero allocation)
var _ability_cd: float = 2.0
var _action_timer: float = 0.0
var _windup_timer: float = 0.0
var _windup_duration_ref: float = 1.0
var _pending_action_kind: int = 0 # 0=none, 1=dash/lunge/lob, 2=boss_charge, 3=boss_acid, 4=boss_salvo, 5=boss_spikes
var _pending_target_pos: Vector3 = Vector3.ZERO
var _action_dir: Vector3 = Vector3.FORWARD
var _burrow_state: int = 0 # 0=Surface, 1=Burrowed (Invulnerable!), 2=Emerging warning, 3=Diving windup
var _boss_pattern_idx: int = 0
var _sub_step_timer: float = 0.0
var _sub_steps_left: int = 0
var _sub_step_kind: int = 0

# Primitive zero-allocation elemental status state
var _poison_stacks: int = 0
var _poison_dps: float = 0.0
var _poison_timer: float = 0.0
var _burn_dps: float = 0.0
var _burn_timer: float = 0.0
var _frost_slow: float = 0.0
var _frost_timer: float = 0.0
var _external_slow: float = 0.0
var _external_slow_timer: float = 0.0
var _dot_accum: float = 0.0


func _ready() -> void:
	set_process(false)
	wall_min_slide_angle = 0.0
	collision_layer = 4
	collision_mask = 5 # Collide with Layer 1 (World & VineBarriers) + Layer 3 (Other Enemies)

	if sphere_mesh_inst:
		sphere_mesh_inst.mesh = ArchetypeScript.get_unit_sphere_mesh()
	if hp_bg_mesh:
		hp_bg_mesh.visible = false
	if hp_fill_mesh:
		hp_fill_mesh.mesh = ArchetypeScript.get_hp_quad_mesh()
		_hp_bar_mat = ArchetypeScript.get_hp_bar_material().duplicate() as ShaderMaterial
		hp_fill_mesh.material_override = _hp_bar_mat

	if visual_root and _trim_ring_a == null:
		_trim_ring_a = MeshInstance3D.new()
		_trim_ring_a.name = "TrimRingA"
		_trim_ring_a.mesh = ArchetypeScript.get_trim_ring_mesh()
		_trim_ring_a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual_root.add_child(_trim_ring_a)

		_trim_ring_b = MeshInstance3D.new()
		_trim_ring_b.name = "TrimRingB"
		_trim_ring_b.mesh = ArchetypeScript.get_trim_ring_mesh()
		_trim_ring_b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual_root.add_child(_trim_ring_b)

		_role_prop_a = MeshInstance3D.new()
		_role_prop_a.name = "RolePropA"
		_role_prop_a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_role_prop_a.visible = false
		visual_root.add_child(_role_prop_a)

		_role_prop_b = MeshInstance3D.new()
		_role_prop_b.name = "RolePropB"
		_role_prop_b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_role_prop_b.visible = false
		visual_root.add_child(_role_prop_b)

		_ward_shell_mesh = MeshInstance3D.new()
		_ward_shell_mesh.name = "WardShellMesh"
		_ward_shell_mesh.mesh = ArchetypeScript.get_unit_sphere_mesh()
		_ward_shell_mesh.scale = Vector3.ONE * 1.36
		_ward_shell_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ward_shell_mesh.visible = false
		visual_root.add_child(_ward_shell_mesh)

		_plant_crown_root = Node3D.new()
		_plant_crown_root.name = "PlantCrownRoot"
		_plant_crown_root.visible = false
		visual_root.add_child(_plant_crown_root)

		var bud_mesh := MeshInstance3D.new()
		bud_mesh.name = "FloralBud"
		bud_mesh.mesh = ArchetypeScript.get_sac_orb_mesh()
		bud_mesh.material_override = ArchetypeScript.get_bloom_core_material()
		bud_mesh.position = Vector3(0.0, 0.98, 0.0)
		bud_mesh.scale = Vector3.ONE * 0.74
		bud_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_plant_crown_root.add_child(bud_mesh)

		_plant_petal_pivots.clear()
		for p_i in range(5):
			var p_ang: float = float(p_i) * (TAU / 5.0)
			var pivot := Node3D.new()
			pivot.name = "PetalPivot_%d" % p_i
			pivot.position = Vector3(sin(p_ang) * 0.62, 0.42, cos(p_ang) * 0.62)
			pivot.rotation = Vector3(0.0, p_ang, 0.0)
			_plant_crown_root.add_child(pivot)

			var leaf := MeshInstance3D.new()
			leaf.name = "PetalBlade_%d" % p_i
			leaf.mesh = ArchetypeScript.get_petal_mesh()
			leaf.material_override = ArchetypeScript.get_petal_material()
			leaf.position = Vector3(0.0, 0.0, 0.42)
			leaf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			pivot.add_child(leaf)
			_plant_petal_pivots.append(pivot)

	if _burrow_ring_inst == null:
		_burrow_ring_inst = MeshInstance3D.new()
		_burrow_ring_inst.name = "BurrowFloorRing"
		_burrow_ring_inst.mesh = ArchetypeScript.get_burrow_ring_mesh()
		_burrow_ring_inst.position = Vector3(0.0, 0.05, 0.0)
		_burrow_ring_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_burrow_ring_inst.visible = false
		add_child(_burrow_ring_inst)

	if _aegis_dome_mesh == null:
		_aegis_dome_mat = StandardMaterial3D.new()
		_aegis_dome_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_aegis_dome_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_aegis_dome_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_aegis_dome_mat.albedo_color = Color(0.24, 0.82, 1.0, 0.22)

		_aegis_ring_mat = StandardMaterial3D.new()
		_aegis_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_aegis_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_aegis_ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_aegis_ring_mat.albedo_color = Color(0.56, 0.96, 1.0, 0.88)

		_aegis_dome_mesh = MeshInstance3D.new()
		_aegis_dome_mesh.name = "AegisDomeMesh"
		_aegis_dome_mesh.mesh = ArchetypeScript.get_unit_sphere_mesh()
		_aegis_dome_mesh.material_override = _aegis_dome_mat
		_aegis_dome_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_aegis_dome_mesh.visible = false
		add_child(_aegis_dome_mesh)

		_aegis_dome_ring = MeshInstance3D.new()
		_aegis_dome_ring.name = "AegisDomeRing"
		_aegis_dome_ring.mesh = ArchetypeScript.get_trim_ring_mesh()
		_aegis_dome_ring.material_override = _aegis_ring_mat
		_aegis_dome_ring.position = Vector3(0.0, 0.06, 0.0)
		_aegis_dome_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_aegis_dome_ring.visible = false
		add_child(_aegis_dome_ring)

	if OS.has_feature("web") and _contact_shadow_inst == null:
		_contact_shadow_inst = MeshInstance3D.new()
		_contact_shadow_inst.name = "ContactShadow"
		_contact_shadow_inst.mesh = ArchetypeScript.get_contact_shadow_mesh()
		_contact_shadow_inst.material_override = ArchetypeScript.get_contact_shadow_material()
		_contact_shadow_inst.position = Vector3(0.0, 0.024, 0.0)
		_contact_shadow_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_contact_shadow_inst.visible = false
		add_child(_contact_shadow_inst)

	if hurtbox_comp and health_comp:
		hurtbox_comp.health_component = health_comp
	if health_comp:
		if not health_comp.damaged.is_connected(_on_damaged):
			health_comp.damaged.connect(_on_damaged)
		if not health_comp.health_changed.is_connected(_on_health_changed):
			health_comp.health_changed.connect(_on_health_changed)
		if not health_comp.armor_changed.is_connected(_on_armor_changed):
			health_comp.armor_changed.connect(_on_armor_changed)
		if not health_comp.armor_broken.is_connected(_on_armor_broken):
			health_comp.armor_broken.connect(_on_armor_broken)
		if not health_comp.bar_broken.is_connected(_on_bar_broken):
			health_comp.bar_broken.connect(_on_bar_broken)
		if not health_comp.phase_gate_changed.is_connected(_on_phase_gate_changed):
			health_comp.phase_gate_changed.connect(_on_phase_gate_changed)
		if not health_comp.died.is_connected(_on_died):
			health_comp.died.connect(_on_died)


func is_burrowed_invulnerable() -> bool:
	return _burrow_state == 1


func _reset_statuses() -> void:
	_poison_stacks = 0
	_poison_dps = 0.0
	_poison_timer = 0.0
	_burn_dps = 0.0
	_burn_timer = 0.0
	_frost_slow = 0.0
	_frost_timer = 0.0
	_external_slow = 0.0
	_external_slow_timer = 0.0
	_dot_accum = 0.0
	_suppress_hit_flash = false
	_burrow_state = 0
	_windup_timer = 0.0
	_windup_duration_ref = 1.0
	_pending_action_kind = 0
	_action_timer = 0.0
	_sub_steps_left = 0
	_sub_step_kind = 0
	_is_elite_unit = false
	is_boss_reinforcement = false
	is_astral_clone = false
	is_vine_swarmer = false
	_boss_phase = 1
	_frenzy_mult = 1.0
	_stagger_timer = 0.0
	_exposed_mult = 1.0
	_burst_window_dmg = 0.0
	_biome_trait_id = 0
	_biome_special_used = false
	_return_to_center_active = false
	_return_target_pos = Vector3.ZERO
	_clock_sector_queued = false
	_aegis_flash_timer = 0.0
	_deactivate_aegis_dome()
	if _ward_shell_mesh:
		_ward_shell_mesh.visible = false
	if _plant_crown_root:
		_plant_crown_root.visible = false
	if _burrow_ring_inst:
		_burrow_ring_inst.visible = false
	if _contact_shadow_inst:
		_contact_shadow_inst.visible = false
	if visual_root:
		visual_root.visible = true
		visual_root.rotation = Vector3.ZERO


func activate(
	p_enemy_id: int,
	p_area_idx: int,
	p_archetype_id: int,
	p_spawn_pos: Vector3,
	p_players_root: Node3D
) -> void:
	enemy_id = p_enemy_id
	area_idx = p_area_idx
	_players_root = p_players_root
	_archetype = ArchetypeScript.get_archetype(p_archetype_id)
	_base_radius = _archetype.radius
	grass_displacement_size = clampf(_base_radius * 1.55, 0.55, 1.45)
	_reset_statuses()

	if not is_in_group("characters"):
		add_to_group("characters")
	if not is_in_group("active_enemies"):
		add_to_group("active_enemies")

	if body_col_shape:
		body_col_shape.shape = _archetype.body_shape
		body_col_shape.position = Vector3(0.0, _base_radius, 0.0)
		body_col_shape.set_deferred("disabled", false)

	if hurtbox_col_shape:
		hurtbox_col_shape.shape = _archetype.hurtbox_shape
		hurtbox_col_shape.position = Vector3(0.0, _base_radius, 0.0)
	if hurtbox_comp:
		hurtbox_comp.set_active_deferred(true)

	if sphere_mesh_inst:
		sphere_mesh_inst.material_override = _archetype.body_material

	_configure_trim_visuals()

	if visual_root:
		visual_root.visible = true
		visual_root.position = Vector3(0.0, _base_radius + 0.06, 0.0)
		visual_root.scale = Vector3.ONE * (_base_radius * 0.2)
		visual_root.rotation = Vector3.ZERO

	if _contact_shadow_inst:
		_contact_shadow_inst.scale = Vector3(_base_radius * 2.45, 1.0, _base_radius * 2.45)
		_contact_shadow_inst.visible = true

	var is_boss: bool = ArchetypeScript.is_boss_archetype(_archetype.archetype_id)
	if hp_bar_root:
		hp_bar_root.position = Vector3(0.0, _base_radius * 2.0 + 0.45, 0.0)
		var bar_w: float = clampf(_base_radius * 2.3, 0.75, 2.1)
		if hp_fill_mesh:
			hp_fill_mesh.scale = Vector3(bar_w, 0.13 if is_boss else 0.10, 1.0)
		if _hp_bar_mat:
			_hp_bar_mat.set_shader_parameter("fill_ratio", 1.0)
			_hp_bar_mat.set_shader_parameter("armor_ratio", 0.0)
			_hp_bar_mat.set_shader_parameter("stock_pips", 1.0)
			_hp_bar_mat.set_shader_parameter("impervious_ratio", 0.0)
		hp_bar_root.visible = false

	if health_comp:
		health_comp.setup_max_health(_archetype.max_hp)
	_refresh_ward_shell()
	boss_director = null

	_is_active_unit = true
	_is_dying = false
	_death_timer = 0.0
	_hit_flash_timer = 0.0
	if _archetype != null and _archetype.archetype_id == ArchetypeScript.ArchetypeId.BOSS_CHRONOMANCER:
		_ability_cd = 1.0
		_boss_pattern_idx = 0
	else:
		_ability_cd = 1.45 + float(p_enemy_id % 5) * 0.32
		_boss_pattern_idx = p_enemy_id % 3
	_bob_phase = float(p_enemy_id) * 1.37
	velocity = Vector3.ZERO

	if is_inside_tree():
		global_position = p_spawn_pos
		reset_physics_interpolation()
	else:
		position = p_spawn_pos

	visible = true
	set_physics_process(true)


func _configure_trim_visuals() -> void:
	if _trim_ring_a == null or _archetype == null:
		return
	var aid: int = _archetype.archetype_id
	var is_boss: bool = ArchetypeScript.is_boss_archetype(aid)
	_trim_ring_a.material_override = _archetype.trim_material
	_trim_ring_b.material_override = _archetype.trim_material
	if _burrow_ring_inst:
		_burrow_ring_inst.material_override = _archetype.trim_material
		_burrow_ring_inst.scale = Vector3.ONE * (_base_radius * 1.6)
		_burrow_ring_inst.visible = false

	_trim_ring_a.visible = (aid != ArchetypeScript.ArchetypeId.CHASER)
	_trim_ring_b.visible = is_boss
	_trim_ring_a.scale = Vector3.ONE
	_trim_ring_b.scale = Vector3.ONE * 1.22

	if _role_prop_a:
		_role_prop_a.visible = false
		_role_prop_a.scale = Vector3.ONE
		_role_prop_a.rotation = Vector3.ZERO
		_role_prop_a.material_override = _archetype.trim_material
	if _role_prop_b:
		_role_prop_b.visible = false
		_role_prop_b.scale = Vector3.ONE
		_role_prop_b.rotation = Vector3.ZERO
		_role_prop_b.material_override = _archetype.trim_material
	if _plant_crown_root:
		_plant_crown_root.visible = (aid == ArchetypeScript.ArchetypeId.BOSS_BLIGHTWEAVER)
		_plant_crown_root.rotation = Vector3.ZERO
		for piv in _plant_petal_pivots:
			if piv:
				piv.rotation_degrees.x = 8.0

	match aid:
		ArchetypeScript.ArchetypeId.DASHER:
			_trim_ring_a.rotation_degrees = Vector3(18.0, 0.0, -18.0)
			if _role_prop_a and _role_prop_b:
				_role_prop_a.mesh = ArchetypeScript.get_fin_mesh()
				_role_prop_a.position = Vector3(-0.95, 0.0, 0.25)
				_role_prop_a.rotation_degrees = Vector3(0.0, 28.0, 0.0)
				_role_prop_a.visible = true
				_role_prop_b.mesh = ArchetypeScript.get_fin_mesh()
				_role_prop_b.position = Vector3(0.95, 0.0, 0.25)
				_role_prop_b.rotation_degrees = Vector3(0.0, -28.0, 0.0)
				_role_prop_b.visible = true
		ArchetypeScript.ArchetypeId.BURROWER:
			_trim_ring_a.rotation_degrees = Vector3(0.0, 0.0, 0.0)
			if _role_prop_a:
				_role_prop_a.mesh = ArchetypeScript.get_cone_spike_mesh()
				_role_prop_a.position = Vector3(0.0, -0.35, 0.85)
				_role_prop_a.rotation_degrees = Vector3(-125.0, 0.0, 0.0)
				_role_prop_a.visible = true
		ArchetypeScript.ArchetypeId.LUNGER:
			_trim_ring_a.rotation_degrees = Vector3(68.0, 0.0, 0.0)
			if _role_prop_a and _role_prop_b:
				_role_prop_a.mesh = ArchetypeScript.get_cone_spike_mesh()
				_role_prop_a.position = Vector3(-0.55, -0.10, 0.92)
				_role_prop_a.rotation_degrees = Vector3(85.0, 0.0, 0.0)
				_role_prop_a.scale = Vector3(0.85, 0.85, 0.85)
				_role_prop_a.visible = true
				_role_prop_b.mesh = ArchetypeScript.get_cone_spike_mesh()
				_role_prop_b.position = Vector3(0.55, -0.10, 0.92)
				_role_prop_b.rotation_degrees = Vector3(85.0, 0.0, 0.0)
				_role_prop_b.scale = Vector3(0.85, 0.85, 0.85)
				_role_prop_b.visible = true
		ArchetypeScript.ArchetypeId.BRUISER:
			_trim_ring_a.rotation_degrees = Vector3(24.0, 0.0, -24.0)
			if _role_prop_a and _role_prop_b:
				_role_prop_a.mesh = ArchetypeScript.get_plate_mesh()
				_role_prop_a.position = Vector3(-1.15, 0.0, 0.0)
				_role_prop_a.visible = true
				_role_prop_b.mesh = ArchetypeScript.get_plate_mesh()
				_role_prop_b.position = Vector3(1.15, 0.0, 0.0)
				_role_prop_b.visible = true
		ArchetypeScript.ArchetypeId.MIRE_LOBBER:
			_trim_ring_a.rotation_degrees = Vector3(36.0, 0.0, 28.0)
			if _role_prop_a:
				_role_prop_a.mesh = ArchetypeScript.get_sac_orb_mesh()
				_role_prop_a.position = Vector3(0.0, 1.05, 0.0)
				_role_prop_a.visible = true
		ArchetypeScript.ArchetypeId.OCULAR_SNIPER:
			_trim_ring_a.rotation_degrees = Vector3(88.0, 0.0, 0.0)
			if _role_prop_a:
				_role_prop_a.mesh = ArchetypeScript.get_scope_ring_mesh()
				_role_prop_a.position = Vector3(0.0, 0.05, 1.08)
				_role_prop_a.rotation_degrees = Vector3(90.0, 0.0, 0.0)
				_role_prop_a.visible = true
		ArchetypeScript.ArchetypeId.BOSS:
			_trim_ring_a.rotation_degrees = Vector3(24.0, 0.0, -24.0)
			_trim_ring_b.rotation_degrees = Vector3(-42.0, 30.0, 32.0)
			if _role_prop_a and _role_prop_b:
				_role_prop_a.mesh = ArchetypeScript.get_plate_mesh()
				_role_prop_a.position = Vector3(-1.18, 0.22, 0.0)
				_role_prop_a.scale = Vector3(1.12, 1.12, 1.12)
				_role_prop_a.visible = true
				_role_prop_b.mesh = ArchetypeScript.get_plate_mesh()
				_role_prop_b.position = Vector3(1.18, 0.22, 0.0)
				_role_prop_b.scale = Vector3(1.12, 1.12, 1.12)
				_role_prop_b.visible = true
		ArchetypeScript.ArchetypeId.BOSS_BLIGHTWEAVER:
			_trim_ring_a.rotation_degrees = Vector3(24.0, 0.0, -24.0)
			_trim_ring_b.rotation_degrees = Vector3(-42.0, 30.0, 32.0)
		ArchetypeScript.ArchetypeId.BOSS_CRYO_ARCHON:
			_trim_ring_a.rotation_degrees = Vector3(16.0, 0.0, -28.0)
			_trim_ring_b.rotation_degrees = Vector3(-18.0, 36.0, 28.0)
			if _role_prop_a and _role_prop_b:
				_role_prop_a.mesh = ArchetypeScript.get_fin_mesh()
				_role_prop_a.position = Vector3(-1.24, 0.25, -0.15)
				_role_prop_a.rotation_degrees = Vector3(0.0, 24.0, 18.0)
				_role_prop_a.scale = Vector3(2.0, 1.35, 2.3)
				_role_prop_a.visible = true
				_role_prop_b.mesh = ArchetypeScript.get_fin_mesh()
				_role_prop_b.position = Vector3(1.24, 0.25, -0.15)
				_role_prop_b.rotation_degrees = Vector3(0.0, -24.0, -18.0)
				_role_prop_b.scale = Vector3(2.0, 1.35, 2.3)
				_role_prop_b.visible = true
		ArchetypeScript.ArchetypeId.BOSS_CHRONOMANCER:
			_trim_ring_a.rotation_degrees = Vector3(52.0, 0.0, -34.0)
			_trim_ring_b.rotation_degrees = Vector3(-52.0, 45.0, 34.0)
			if _role_prop_a and _role_prop_b:
				_role_prop_a.mesh = ArchetypeScript.get_sac_orb_mesh()
				_role_prop_a.position = Vector3(0.0, 1.24, 0.0)
				_role_prop_a.scale = Vector3(0.68, 0.68, 0.68)
				_role_prop_a.visible = true
				_role_prop_b.mesh = ArchetypeScript.get_scope_ring_mesh()
				_role_prop_b.position = Vector3(0.0, 0.14, 1.12)
				_role_prop_b.rotation_degrees = Vector3(90.0, 0.0, 0.0)
				_role_prop_b.scale = Vector3(1.45, 1.45, 1.45)
				_role_prop_b.visible = true


## Configures Hades-style multi-bar life stocks, yellow armor buffer, and phase-gate imperviousness.
func configure_elite_or_boss(
	p_bar_hp: float,
	p_bars: int,
	p_armor: float,
	p_phase_gate_s: float,
	p_is_elite: bool
) -> void:
	_is_elite_unit = p_is_elite
	_boss_phase = 1
	_frenzy_mult = 1.0
	_stagger_timer = 0.0
	_exposed_mult = 1.0
	_burst_window_dmg = 0.0
	if health_comp:
		health_comp.setup_combat_bars(p_bar_hp, p_bars, p_armor, p_phase_gate_s)
	var is_boss: bool = (_archetype != null and ArchetypeScript.is_boss_archetype(_archetype.archetype_id))
	if hp_bar_root:
		var bar_w: float = clampf(_base_radius * (2.5 if (p_is_elite and p_bars > 1) else 2.3), 0.78, 2.3)
		if hp_fill_mesh:
			hp_fill_mesh.scale = Vector3(bar_w, 0.13 if (is_boss or p_is_elite) else 0.10, 1.0)
		if _hp_bar_mat:
			_hp_bar_mat.set_shader_parameter("fill_ratio", 1.0)
			_hp_bar_mat.set_shader_parameter("armor_ratio", 1.0 if p_armor > 0.01 else 0.0)
			_hp_bar_mat.set_shader_parameter("stock_pips", float(maxi(1, p_bars)))
			_hp_bar_mat.set_shader_parameter("impervious_ratio", 0.0)
		hp_bar_root.visible = (not is_boss) and (p_is_elite or p_armor > 0.01)
	_refresh_ward_shell()


func _should_hide_overhead_hp() -> bool:
	return _archetype != null and ArchetypeScript.is_boss_archetype(_archetype.archetype_id)


func configure_astral_clone(bar_hp: float) -> void:
	is_astral_clone = true
	is_boss_reinforcement = true
	if _role_prop_a:
		_role_prop_a.visible = false
	if visual_root:
		visual_root.scale = Vector3.ONE * (_base_radius * 0.88)
	if health_comp:
		health_comp.setup_max_health(bar_hp)
	if hp_bar_root:
		hp_bar_root.visible = false
	_refresh_ward_shell()


func configure_vine_swarmer(bar_hp: float) -> void:
	is_vine_swarmer = true
	is_boss_reinforcement = true
	if visual_root:
		visual_root.scale = Vector3.ONE * (_base_radius * 0.88)
	if health_comp:
		health_comp.setup_max_health(maxf(8.0, bar_hp))
	_refresh_body_material()


func force_despawn_clone() -> void:
	if not _is_dying:
		_on_died()


func cancel_active_pattern() -> void:
	_windup_timer = 0.0
	_action_timer = 0.0
	_pending_action_kind = 0
	_sub_steps_left = 0
	_sub_step_kind = 0


func force_return_to_point(pt: Vector3) -> void:
	cancel_active_pattern()
	_return_target_pos = Vector3(pt.x, 0.0, pt.z)
	_return_to_center_active = true


func queue_clock_sector_soon() -> void:
	_clock_sector_queued = true
	_ability_cd = minf(_ability_cd, 0.65)


func trigger_boss_stagger(duration: float, exposed_bonus: float, shatter_arm: bool) -> void:
	if _is_dying or not _is_active_unit:
		return
	if shatter_arm and health_comp != null:
		health_comp.shatter_armor()
	_deactivate_aegis_dome()
	_windup_timer = 0.0
	_action_timer = 0.0
	_pending_action_kind = 0
	_sub_steps_left = 0
	_sub_step_kind = 0
	_stagger_timer = maxf(_stagger_timer, duration)
	_exposed_mult = maxf(_exposed_mult, exposed_bonus)
	_burst_window_dmg = 0.0


func activate_aegis_dome(radius: float, duration: float) -> void:
	if _is_dying or not _is_active_unit:
		return
	_aegis_dome_radius = maxf(4.0, radius)
	_aegis_dome_timer = maxf(1.0, duration)
	_aegis_dome_hp = 180.0
	_aegis_flash_timer = 0.0
	if not is_in_group("aegis_dome_bosses"):
		add_to_group("aegis_dome_bosses")
	if _aegis_dome_mesh:
		_aegis_dome_mesh.scale = Vector3(_aegis_dome_radius, _aegis_dome_radius * 0.42, _aegis_dome_radius)
		_aegis_dome_mesh.visible = true
	if _aegis_dome_ring:
		var ring_s: float = _aegis_dome_radius / 1.25
		_aegis_dome_ring.scale = Vector3(ring_s, 1.0, ring_s)
		_aegis_dome_ring.visible = true


func is_aegis_dome_active() -> bool:
	return _aegis_dome_timer > 0.0 and _is_active_unit and not _is_dying


func get_aegis_dome_radius() -> float:
	return _aegis_dome_radius


func notify_dome_deflect(_hit_pos: Vector3) -> void:
	_aegis_flash_timer = 0.14
	if _aegis_ring_mat:
		_aegis_ring_mat.albedo_color = Color(1.0, 0.98, 0.88, 0.98)


func _deactivate_aegis_dome() -> void:
	_aegis_dome_timer = 0.0
	_aegis_dome_hp = 0.0
	_aegis_flash_timer = 0.0
	if is_in_group("aegis_dome_bosses"):
		remove_from_group("aegis_dome_bosses")
	if _aegis_dome_mesh:
		_aegis_dome_mesh.visible = false
	if _aegis_dome_ring:
		_aegis_dome_ring.visible = false


func _refresh_ward_shell() -> void:
	if _ward_shell_mesh == null or health_comp == null:
		return
	if health_comp.is_impervious():
		_ward_shell_mesh.visible = true
		_ward_shell_mesh.material_override = ArchetypeScript.get_impervious_shell_material()
	elif health_comp.has_armor():
		_ward_shell_mesh.visible = true
		_ward_shell_mesh.material_override = ArchetypeScript.get_armor_shell_material()
	else:
		_ward_shell_mesh.visible = false


## Attaches biome-specific minion modifiers for non-boss enemies across the 5 biomes.
func set_biome_trait(p_biome_id: int) -> void:
	_biome_trait_id = p_biome_id
	_biome_special_used = false
	if _archetype == null or ArchetypeScript.is_boss_archetype(_archetype.archetype_id):
		return
	var aid: int = _archetype.archetype_id
	if _biome_trait_id == 4 and health_comp != null:
		# Arcane Anomaly specialists spawn with an 18% Arcane Ward Shield.
		if (
			aid == ArchetypeScript.ArchetypeId.DASHER
			or aid == ArchetypeScript.ArchetypeId.BURROWER
			or aid == ArchetypeScript.ArchetypeId.MIRE_LOBBER
			or aid == ArchetypeScript.ArchetypeId.OCULAR_SNIPER
		):
			health_comp.set_shield(health_comp.max_health * 0.18)


func deactivate() -> void:
	_is_active_unit = false
	_is_dying = false
	boss_director = null
	_reset_statuses()
	if is_in_group("characters"):
		remove_from_group("characters")
	if is_in_group("active_enemies"):
		remove_from_group("active_enemies")

	set_process(false)
	set_physics_process(false)
	visible = false
	velocity = Vector3.ZERO
	if _contact_shadow_inst:
		_contact_shadow_inst.visible = false

	if body_col_shape:
		body_col_shape.set_deferred("disabled", true)
	if hurtbox_comp:
		hurtbox_comp.set_active_deferred(false)


func on_pool_release() -> void:
	deactivate()


func _release_to_pool() -> void:
	if pool and pool.has_method("release"):
		pool.release(self)
	else:
		queue_free()


## Resolves direct weapon/ability damage plus elemental on-hit traits (ignored while burrowed or Impervious!).
func apply_combat_hit(
	raw_damage: float,
	hit_dir: Vector3,
	proc_coeff: float,
	shooter_stats: Object,
	attacker_pos: Vector3 = Vector3.INF
) -> void:
	if _is_dying or not _is_active_unit or _burrow_state == 1:
		return
	if is_aegis_dome_active():
		if attacker_pos != Vector3.INF:
			var dx_a: float = attacker_pos.x - global_position.x
			var dz_a: float = attacker_pos.z - global_position.z
			if (dx_a * dx_a + dz_a * dz_a) > (_aegis_dome_radius + 0.35) * (_aegis_dome_radius + 0.35):
				notify_dome_deflect(attacker_pos)
				return
		_aegis_dome_hp -= raw_damage
		if _aegis_dome_hp <= 0.0:
			_deactivate_aegis_dome()
			trigger_boss_stagger(1.5, 1.35, false)

	if health_comp != null and health_comp.is_impervious():
		return

	if (
		not is_astral_clone
		and _archetype != null
		and _archetype.archetype_id == ArchetypeScript.ArchetypeId.BOSS_CHRONOMANCER
		and boss_director != null
		and boss_director.has_method("notify_true_chronomancer_hit")
	):
		boss_director.call("notify_true_chronomancer_hit")

	var effective_raw: float = raw_damage
	if _stagger_timer > 0.0 and _exposed_mult > 1.01:
		effective_raw *= _exposed_mult
	elif _archetype != null and ArchetypeScript.is_boss_archetype(_archetype.archetype_id) and not is_astral_clone and health_comp != null:
		if _burst_window_dmg > health_comp.max_health * 0.52:
			effective_raw *= 0.50
		_burst_window_dmg += effective_raw

	var hit_center: Vector3 = global_position + Vector3(0.0, _base_radius, 0.0)
	if hurtbox_comp:
		hurtbox_comp.apply_hit(effective_raw, hit_dir)
	elif health_comp:
		health_comp.take_damage(effective_raw, hit_dir)

	if shooter_stats == null or proc_coeff <= 0.01:
		return

	var p_rank: int = int(shooter_stats.get("poison_rank"))
	var s_rank: int = int(shooter_stats.get("shock_rank"))
	var b_rank: int = int(shooter_stats.get("burn_rank"))
	var f_rank: int = int(shooter_stats.get("frost_rank"))
	var ad_val: float = float(shooter_stats.get("attack_damage"))
	var ap_val: float = float(shooter_stats.get("ability_power"))

	if s_rank > 0:
		var shock_chance: float = clampf((0.30 + 0.10 * float(s_rank)) * proc_coeff, 0.06, 0.95)
		if randf() <= shock_chance:
			var arc_dmg: float = (5.0 + 3.5 * float(s_rank)) + ap_val * (0.55 + 0.20 * float(s_rank))
			_trigger_shock_chain(hit_center, arc_dmg, 3)

	if _is_dying or not _is_active_unit:
		return

	if p_rank > 0:
		if randf() <= clampf(proc_coeff * 1.15, 0.25, 1.0):
			var max_stacks: int = 6 + p_rank * 4
			_poison_stacks = mini(max_stacks, _poison_stacks + 1)
			_poison_dps = (0.75 + 0.35 * float(p_rank)) + (ad_val * 0.06 + ap_val * 0.08)
			_poison_timer = 3.6

	if b_rank > 0:
		var total_ignite: float = raw_damage * (0.38 + 0.24 * float(b_rank)) * clampf(proc_coeff, 0.35, 1.2) + ap_val * (0.30 * float(b_rank))
		var cand_dps: float = total_ignite / 3.0
		_burn_dps = maxf(_burn_dps, cand_dps)
		_burn_timer = 3.0

	if f_rank > 0:
		var slow_amt: float = clampf(0.28 + 0.11 * float(f_rank), 0.0, 0.72)
		_frost_slow = maxf(_frost_slow, slow_amt)
		_frost_timer = maxf(_frost_timer, 2.5)

	if _hit_flash_timer <= 0.0:
		_refresh_body_material()


func receive_arc_damage(amount: float) -> void:
	if _is_dying or not _is_active_unit or _burrow_state == 1 or amount <= 0.0:
		return
	if health_comp:
		health_comp.take_damage(amount, Vector3.ZERO)


func apply_external_slow(ratio: float, duration: float) -> void:
	if _is_dying or not _is_active_unit or _burrow_state == 1:
		return
	_external_slow = maxf(_external_slow, clampf(ratio, 0.0, 0.90))
	_external_slow_timer = maxf(_external_slow_timer, duration)
	if _hit_flash_timer <= 0.0:
		_refresh_body_material()


func _trigger_shock_chain(origin: Vector3, arc_dmg: float, max_targets: int) -> void:
	if not is_inside_tree():
		return
	var candidates: Array[EnemySphere] = []
	var max_r2: float = 6.2 * 6.2
	var enemies: Array[Node] = get_tree().get_nodes_in_group("active_enemies")
	for n in enemies:
		if n == self:
			continue
		var es: EnemySphere = n as EnemySphere
		if es == null or not es._is_active_unit or es._is_dying or es._burrow_state == 1 or not es.visible:
			continue
		var dx: float = es.global_position.x - origin.x
		var dz: float = es.global_position.z - origin.z
		if (dx * dx + dz * dz) <= max_r2:
			candidates.append(es)
			if candidates.size() >= max_targets:
				break

	var prev_pt: Vector3 = origin
	for target_es in candidates:
		var next_pt: Vector3 = target_es.global_position + Vector3(0.0, target_es._base_radius, 0.0)
		if ProjectilePool and ProjectilePool.has_method("spawn_lightning_arc"):
			ProjectilePool.call("spawn_lightning_arc", prev_pt, next_pt)
		target_es.receive_arc_damage(arc_dmg)
		prev_pt = next_pt


func _refresh_body_material() -> void:
	if sphere_mesh_inst == null or _archetype == null:
		return
	if _burn_timer > 0.0:
		sphere_mesh_inst.material_override = ArchetypeScript.get_status_burn_material()
	elif _poison_timer > 0.0 and _poison_stacks > 0:
		sphere_mesh_inst.material_override = ArchetypeScript.get_status_poison_material()
	elif _frost_timer > 0.0 or _external_slow_timer > 0.0:
		sphere_mesh_inst.material_override = ArchetypeScript.get_status_frost_material()
	elif is_vine_swarmer:
		sphere_mesh_inst.material_override = ArchetypeScript.get_vine_swarmer_material()
	else:
		sphere_mesh_inst.material_override = _archetype.body_material


func _enter_burrow_dive_windup(tunnel_dir: Vector3) -> void:
	_burrow_state = 3
	_windup_timer = 0.55
	_windup_duration_ref = 0.55
	_action_dir = tunnel_dir
	velocity = Vector3.ZERO


func _enter_burrow(tunnel_dir: Vector3) -> void:
	_burrow_state = 1
	_action_timer = 0.95
	_windup_timer = 0.0
	_action_dir = tunnel_dir
	if visual_root:
		visual_root.visible = false
		visual_root.rotation.x = 0.0
	if hp_bar_root:
		hp_bar_root.visible = false
	if hurtbox_comp:
		hurtbox_comp.set_active_deferred(false)
	if body_col_shape:
		body_col_shape.set_deferred("disabled", true)
	if _burrow_ring_inst:
		_burrow_ring_inst.visible = true
	if _contact_shadow_inst:
		_contact_shadow_inst.visible = false


func _enter_burrow_emerge_warning() -> void:
	_burrow_state = 2
	_windup_timer = 0.78
	_windup_duration_ref = 0.78
	velocity = Vector3.ZERO
	if _burrow_ring_inst:
		_burrow_ring_inst.scale = Vector3.ONE * (_base_radius * 2.35)


func _complete_burrow_emerge() -> void:
	_burrow_state = 0
	_ability_cd = 4.4
	if _burrow_ring_inst:
		_burrow_ring_inst.visible = false
		_burrow_ring_inst.scale = Vector3.ONE * (_base_radius * 1.6)
	if body_col_shape:
		body_col_shape.set_deferred("disabled", false)
	if hurtbox_comp:
		hurtbox_comp.set_active_deferred(true)
	if visual_root:
		visual_root.visible = true
		visual_root.rotation.x = 0.0
		visual_root.position = Vector3(0.0, _base_radius + 0.06, 0.0)
		visual_root.scale = Vector3(_base_radius * 0.75, _base_radius * 1.45, _base_radius * 0.75)
	if _contact_shadow_inst:
		_contact_shadow_inst.visible = true
	if health_comp and hp_bar_root and not _should_hide_overhead_hp() and health_comp.current_health < health_comp.max_health:
		hp_bar_root.visible = true
	if _biome_trait_id == 1 and (not multiplayer.has_multiplayer_peer() or multiplayer.is_server()):
		_rpc_enemy_ground_hazard(
			HazardScript.HazardMode.GROUND_QUAKE,
			global_position,
			global_position,
			2.1,
			0.0,
			7.0,
			0.45,
			0.24,
			Color(0.42, 0.90, 1.0),
			0.12
		)


func _step_visual_pose(delta: float) -> void:
	if _is_dying:
		_death_timer -= delta
		if visual_root:
			visual_root.scale = visual_root.scale.lerp(Vector3.ZERO, clampf(18.0 * delta, 0.0, 1.0))
		if _death_timer <= 0.0:
			_release_to_pool()
		return

	if not _is_active_unit or _archetype == null:
		return

	if _hit_flash_timer > 0.0:
		_hit_flash_timer -= delta
		if _hit_flash_timer <= 0.0:
			_refresh_body_material()

	_bob_phase += delta * 5.2

	if (_burrow_state == 1 or _burrow_state == 2) and _burrow_ring_inst:
		var pulse_b: float = (2.35 if _burrow_state == 2 else 1.55) + 0.25 * sin(_bob_phase * (3.8 if _burrow_state == 2 else 2.6))
		_burrow_ring_inst.scale = Vector3.ONE * (_base_radius * pulse_b)
		_burrow_ring_inst.rotation.y += delta * (7.5 if _burrow_state == 2 else 4.5)
		return

	var aid: int = _archetype.archetype_id
	var windup_prog: float = clampf(1.0 - (_windup_timer / maxf(0.05, _windup_duration_ref)), 0.0, 1.0) if _windup_timer > 0.0 else 0.0

	if _trim_ring_a and _trim_ring_a.visible:
		var spin_a: float = 7.5 if _windup_timer > 0.0 else 1.9
		_trim_ring_a.rotation.y += delta * spin_a
	if _trim_ring_b and _trim_ring_b.visible:
		var spin_b: float = -6.0 if _windup_timer > 0.0 else -1.4
		_trim_ring_b.rotation.y += delta * spin_b
		_trim_ring_b.rotation.x += delta * 0.7

	if visual_root == null:
		return

	var target_scale := Vector3.ONE * _base_radius
	var target_pos := Vector3(0.0, _base_radius + 0.06 + sin(_bob_phase) * 0.05, 0.0)
	var target_rot_x: float = 0.0
	var target_rot_z: float = 0.0

	if _windup_timer > 0.0:
		match aid:
			ArchetypeScript.ArchetypeId.DASHER:
				visual_root.rotation.y += delta * 18.0
				target_scale = Vector3(_base_radius * 0.88, _base_radius * 1.15, _base_radius * 0.88)
			ArchetypeScript.ArchetypeId.BURROWER:
				target_pos.y = _base_radius + 0.35 * sin(windup_prog * PI)
				target_rot_x = deg_to_rad(75.0)
				visual_root.rotation.y += delta * 14.0
			ArchetypeScript.ArchetypeId.LUNGER:
				var pull_back: Vector3 = -_action_dir * (0.28 * windup_prog)
				var shudder: Vector3 = Vector3(-_action_dir.z, 0.0, _action_dir.x) * (sin(_bob_phase * 11.0) * 0.09)
				target_pos = Vector3(pull_back.x + shudder.x, _base_radius * 0.72, pull_back.z + shudder.z)
				target_scale = Vector3(_base_radius * 1.36, _base_radius * 0.58, _base_radius * 1.36)
			ArchetypeScript.ArchetypeId.BRUISER:
				var lev_h: float = 0.95 * windup_prog if windup_prog < 0.85 else 0.95 * (1.0 - (windup_prog - 0.85) / 0.15)
				target_pos.y = _base_radius + 0.08 + maxf(0.0, lev_h)
				visual_root.rotation.y += delta * 7.5
				target_scale = Vector3(_base_radius * 1.14, _base_radius * 0.92, _base_radius * 1.14)
			ArchetypeScript.ArchetypeId.MIRE_LOBBER:
				target_rot_x = -0.35 * windup_prog
				if _role_prop_a:
					var sac_s: float = lerpf(1.0, 1.85, windup_prog)
					_role_prop_a.scale = Vector3.ONE * sac_s
			ArchetypeScript.ArchetypeId.OCULAR_SNIPER:
				target_pos.y = _base_radius + 0.28
				if _role_prop_a:
					_role_prop_a.rotation.y += delta * 12.0
					var sc_ring: float = lerpf(1.0, 0.58, windup_prog)
					_role_prop_a.scale = Vector3.ONE * sc_ring
			ArchetypeScript.ArchetypeId.BOSS:
				if _pending_action_kind == 2:
					var c_back: Vector3 = -_action_dir * (0.36 * windup_prog)
					var c_shud: Vector3 = Vector3(-_action_dir.z, 0.0, _action_dir.x) * (sin(_bob_phase * 12.0) * 0.11)
					target_pos = Vector3(c_back.x + c_shud.x, _base_radius * 0.82, c_back.z + c_shud.z)
					target_scale = Vector3(_base_radius * 1.24, _base_radius * 0.72, _base_radius * 1.24)
				elif _pending_action_kind == 5:
					target_rot_x = 0.28 * windup_prog
				else:
					var b_lev: float = 1.25 * sin(windup_prog * PI * 0.85)
					target_pos.y = _base_radius + 0.08 + maxf(0.0, b_lev)
					visual_root.rotation.y += delta * 5.0
			ArchetypeScript.ArchetypeId.BOSS_BLIGHTWEAVER:
				if _pending_action_kind == 3:
					target_rot_x = -0.25 * windup_prog
				elif _pending_action_kind == 4:
					visual_root.rotation.y += delta * 10.0
					target_pos.y = _base_radius + 0.30
				else:
					var bw_lev: float = 1.25 * sin(windup_prog * PI * 0.85)
					target_pos.y = _base_radius + 0.08 + maxf(0.0, bw_lev)
			ArchetypeScript.ArchetypeId.BOSS_CRYO_ARCHON:
				if _pending_action_kind == 2:
					var cr_back: Vector3 = -_action_dir * (0.40 * windup_prog)
					target_pos = Vector3(cr_back.x, _base_radius + 0.16, cr_back.z)
					target_rot_x = 0.32 * windup_prog
					target_scale = Vector3(_base_radius * 0.92, _base_radius * 1.10, _base_radius * 1.18)
				elif _pending_action_kind == 4:
					visual_root.rotation.y += delta * 14.0
					target_pos.y = _base_radius + 0.32
				else:
					var cr_lev: float = 1.25 * sin(windup_prog * PI * 0.85)
					target_pos.y = _base_radius + 0.10 + maxf(0.0, cr_lev)
			ArchetypeScript.ArchetypeId.BOSS_CHRONOMANCER:
				visual_root.rotation.y += delta * (8.5 if _pending_action_kind == 4 else 4.2)
				target_pos.y = _base_radius + 0.25 + 0.75 * sin(windup_prog * PI * 0.85)
				if _role_prop_a:
					_role_prop_a.scale = Vector3.ONE * lerpf(0.68, 1.42, windup_prog)
			_:
				target_scale = Vector3(_base_radius * 1.24, _base_radius * 0.74, _base_radius * 1.24)
	elif _stagger_timer > 0.0:
		target_rot_z = sin(_bob_phase * 14.0) * 0.24
		target_scale = Vector3(_base_radius * 1.14, _base_radius * 0.82, _base_radius * 1.14)
	elif _action_timer > 0.0:
		target_scale = Vector3(_base_radius * 0.84, _base_radius * 0.86, _base_radius * 1.32)
	else:
		# Distinct per-role idle/movement animations!
		match aid:
			ArchetypeScript.ArchetypeId.CHASER:
				target_rot_x = sin(_bob_phase * 1.4) * 0.18
			ArchetypeScript.ArchetypeId.DASHER:
				target_pos.x = sin(_bob_phase * 2.2) * 0.10
				target_rot_z = -sin(_bob_phase * 2.2) * 0.18
			ArchetypeScript.ArchetypeId.BURROWER:
				target_pos.y = _base_radius + 0.02 + absf(sin(_bob_phase * 1.6)) * 0.03
			ArchetypeScript.ArchetypeId.BRUISER:
				target_pos.y = _base_radius + 0.04 + absf(sin(_bob_phase * 0.85)) * 0.08
			ArchetypeScript.ArchetypeId.MIRE_LOBBER:
				var sq: float = 0.07 * sin(_bob_phase)
				target_scale = Vector3(_base_radius * (1.0 + sq), _base_radius * (1.0 - sq), _base_radius * (1.0 + sq))
				if _role_prop_a:
					_role_prop_a.scale = Vector3.ONE
			ArchetypeScript.ArchetypeId.OCULAR_SNIPER:
				target_pos.y = _base_radius + 0.28
				if _role_prop_a:
					_role_prop_a.scale = Vector3.ONE
			ArchetypeScript.ArchetypeId.BOSS_BLIGHTWEAVER:
				target_pos.y = _base_radius + 0.08 + sin(_bob_phase * 1.1) * 0.06
			ArchetypeScript.ArchetypeId.BOSS_CRYO_ARCHON:
				target_pos.y = _base_radius + 0.14 + sin(_bob_phase * 1.4) * 0.08
			ArchetypeScript.ArchetypeId.BOSS_CHRONOMANCER:
				target_pos.y = _base_radius + 0.24 + sin(_bob_phase) * 0.09
				if _role_prop_a:
					_role_prop_a.scale = Vector3.ONE * 0.68

	if _plant_crown_root and _plant_crown_root.visible:
		var is_imp: bool = (health_comp != null and health_comp.is_impervious())
		_plant_crown_root.rotation.y += delta * (1.8 if is_imp else 0.7)
		var petal_pitch: float = -58.0 if is_imp else (26.0 if _stagger_timer > 0.0 else (8.0 + sin(_bob_phase * 1.6) * 6.0))
		var p_t: float = clampf(10.0 * delta, 0.0, 1.0)
		for piv in _plant_petal_pivots:
			if piv:
				piv.rotation_degrees.x = lerpf(piv.rotation_degrees.x, petal_pitch, p_t)

	if _ward_shell_mesh and _ward_shell_mesh.visible:
		var pulse_w: float = 1.35 + 0.06 * sin(_bob_phase * 2.4)
		_ward_shell_mesh.scale = Vector3.ONE * pulse_w

	visual_root.scale = visual_root.scale.lerp(target_scale, clampf(14.0 * delta, 0.0, 1.0))
	visual_root.position = visual_root.position.lerp(target_pos, clampf(16.0 * delta, 0.0, 1.0))
	visual_root.rotation.x = lerpf(visual_root.rotation.x, target_rot_x, clampf(14.0 * delta, 0.0, 1.0))
	visual_root.rotation.z = lerpf(visual_root.rotation.z, target_rot_z, clampf(14.0 * delta, 0.0, 1.0))


func _physics_process(delta: float) -> void:
	_step_visual_pose(delta)

	if not _is_active_unit or _is_dying or _archetype == null:
		return

	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	if _burst_window_dmg > 0.0:
		var decay_rate: float = health_comp.max_health * 0.42 if health_comp != null else 100.0
		_burst_window_dmg = maxf(0.0, _burst_window_dmg - decay_rate * delta)

	if _burrow_state != 1:
		_tick_statuses(delta)
		if _is_dying or not _is_active_unit:
			return

	var aid: int = _archetype.archetype_id
	var is_boss_u: bool = ArchetypeScript.is_boss_archetype(aid)

	if _aegis_dome_timer > 0.0:
		_aegis_dome_timer -= delta
		if _aegis_flash_timer > 0.0:
			_aegis_flash_timer -= delta
			if _aegis_flash_timer <= 0.0 and _aegis_ring_mat:
				_aegis_ring_mat.albedo_color = Color(0.56, 0.96, 1.0, 0.88)
		if _aegis_dome_timer <= 0.0:
			_deactivate_aegis_dome()

	if health_comp != null and health_comp.is_impervious():
		if _return_to_center_active:
			var to_c: Vector3 = _return_target_pos - global_position
			to_c.y = 0.0
			if to_c.length_squared() <= 0.25:
				_return_to_center_active = false
				velocity = Vector3.ZERO
			else:
				var c_dir: Vector3 = to_c.normalized()
				velocity = c_dir * 12.0
		else:
			velocity.x = move_toward(velocity.x, 0.0, 35.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 35.0 * delta)
			velocity.y = 0.0
		move_and_slide()
		return
	_return_to_center_active = false

	if _stagger_timer > 0.0:
		_stagger_timer -= delta
		if _stagger_timer <= 0.0:
			_stagger_timer = 0.0
			_exposed_mult = 1.0
		velocity.x = move_toward(velocity.x, 0.0, 28.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 28.0 * delta)
		velocity.y = 0.0
		move_and_slide()
		return

	var slow_cap: float = 0.42 if is_boss_u else (0.55 if (health_comp != null and health_comp.has_armor()) else 0.85)
	var combined_slow: float = clampf(maxf(_frost_slow, _external_slow), 0.0, slow_cap)
	var speed_mult: float = (1.0 - combined_slow) * _frenzy_mult

	var target_player: Node3D = _find_nearest_player()
	var desired_vel := Vector3.ZERO

	if _sub_steps_left > 0:
		_sub_step_timer -= delta
		if _sub_step_timer <= 0.0:
			_execute_boss_sub_step(target_player)

	if target_player:
		var to_target: Vector3 = target_player.global_position - global_position
		to_target.y = 0.0
		var dist: float = to_target.length()
		var dir: Vector3 = to_target / dist if dist > 0.05 else Vector3.FORWARD

		match aid:
			ArchetypeScript.ArchetypeId.DASHER:
				if _windup_timer > 0.0:
					_windup_timer -= delta
					desired_vel = Vector3.ZERO
					if _windup_timer <= 0.0:
						_pending_action_kind = 0
						_action_timer = 0.28 if _biome_trait_id == 1 else 0.22
						if _biome_trait_id == 4:
							_rpc_enemy_orb(
								global_position + Vector3(0.0, 0.40, 0.0) + _action_dir * 0.4,
								_action_dir,
								13.5,
								9.0,
								7.0,
								Color(0.88, 0.32, 1.0),
								false
							)
				elif _action_timer > 0.0:
					_action_timer -= delta
					desired_vel = _action_dir * (14.5 * speed_mult)
				else:
					_ability_cd -= delta * speed_mult
					if _ability_cd <= 0.0 and dist < 11.5 and dist > 1.8:
						_ability_cd = 2.6
						_windup_timer = 0.58
						_windup_duration_ref = 0.58
						_pending_action_kind = 1
						var side_sign: float = 1.0 if (enemy_id % 2 == 0) else -1.0
						if sin(_bob_phase) < 0.0:
							side_sign = -side_sign
						_action_dir = dir.rotated(Vector3.UP, side_sign * 0.58).normalized()
						var d_sight_col: Color = Color(0.65, 0.96, 1.0) if _biome_trait_id == 1 else Color(0.25, 0.92, 1.0)
						_rpc_enemy_sightline(global_position, _action_dir, 3.2, 0.58, d_sight_col)
					elif dist > (_base_radius + 0.18):
						desired_vel = dir * (_archetype.move_speed * speed_mult)

			ArchetypeScript.ArchetypeId.BURROWER:
				if _burrow_state == 3:
					_windup_timer -= delta
					desired_vel = Vector3.ZERO
					if _windup_timer <= 0.0:
						_enter_burrow(_action_dir)
				elif _burrow_state == 1:
					_action_timer -= delta
					desired_vel = dir * (_archetype.move_speed * 1.72)
					if _action_timer <= 0.0 or dist <= 1.35:
						_enter_burrow_emerge_warning()
				elif _burrow_state == 2:
					_windup_timer -= delta
					desired_vel = Vector3.ZERO
					if _windup_timer <= 0.0:
						_complete_burrow_emerge()
				else:
					_ability_cd -= delta * speed_mult
					if _ability_cd <= 0.0 and dist > 2.6 and dist < 10.5:
						_enter_burrow_dive_windup(dir)
					elif dist > (_base_radius + 0.18):
						desired_vel = dir * (_archetype.move_speed * speed_mult)

			ArchetypeScript.ArchetypeId.LUNGER:
				if _windup_timer > 0.0:
					_windup_timer -= delta
					desired_vel = Vector3.ZERO
					if _windup_timer <= 0.0:
						_action_timer = 0.40 if _biome_trait_id == 1 else 0.32
				elif _action_timer > 0.0:
					_action_timer -= delta
					if _action_timer <= 0.0 and _biome_trait_id == 3:
						_rpc_enemy_ground_hazard(
							HazardScript.HazardMode.LOB_POOL,
							global_position + Vector3(0.0, 0.30, 0.0),
							global_position,
							1.8,
							0.0,
							6.5,
							0.25,
							2.4,
							Color(1.0, 0.42, 0.14),
							0.08
						)
					desired_vel = _action_dir * (16.2 * speed_mult)
				else:
					_ability_cd -= delta * speed_mult
					if _ability_cd <= 0.0 and dist < 6.8 and dist > 1.6:
						_ability_cd = 3.1
						_windup_timer = 0.78
						_windup_duration_ref = 0.78
						_action_dir = dir
						if visual_root:
							visual_root.rotation.y = atan2(_action_dir.x, _action_dir.z)
						_rpc_enemy_sightline(global_position, _action_dir, 4.8, 0.78, Color(1.0, 0.22, 0.28))
						if sphere_mesh_inst:
							sphere_mesh_inst.material_override = ArchetypeScript.get_hit_flash_material()
						_hit_flash_timer = 0.20
					elif dist > (_base_radius + 0.18):
						desired_vel = dir * (_archetype.move_speed * speed_mult)

			ArchetypeScript.ArchetypeId.BRUISER:
				if _windup_timer > 0.0:
					_windup_timer -= delta
					desired_vel = Vector3.ZERO
				else:
					_ability_cd -= delta * speed_mult
					if _ability_cd <= 0.0 and dist <= 4.1:
						_ability_cd = 4.2
						_windup_timer = 1.15
						_windup_duration_ref = 1.15
						_rpc_enemy_ground_hazard(
							HazardScript.HazardMode.GROUND_QUAKE,
							global_position,
							global_position,
							4.2,
							0.0,
							12.0,
							1.15,
							0.30,
							Color(1.0, 0.18, 0.26),
							0.36
						)
					elif dist > (_base_radius + 0.18):
						desired_vel = dir * (_archetype.move_speed * speed_mult)

			ArchetypeScript.ArchetypeId.MIRE_LOBBER:
				if _windup_timer > 0.0:
					_windup_timer -= delta
					desired_vel = Vector3.ZERO
					if _windup_timer <= 0.0:
						_pending_action_kind = 0
						var pool_col: Color = Color(0.38, 0.88, 1.0) if _biome_trait_id == 1 else Color(0.36, 0.98, 0.48)
						_rpc_enemy_ground_hazard(
							HazardScript.HazardMode.LOB_POOL,
							global_position + Vector3(0.0, 0.9, 0.0),
							_pending_target_pos,
							2.5,
							0.0,
							9.0,
							1.10,
							4.8,
							pool_col,
							0.0
						)
				else:
					if dist < 6.8:
						desired_vel = -dir * (_archetype.move_speed * 0.82 * speed_mult)
					elif dist > 11.2:
						desired_vel = dir * (_archetype.move_speed * speed_mult)
					else:
						var strafe := Vector3(-dir.z, 0.0, dir.x) * (1.0 if (enemy_id % 2 == 0) else -1.0)
						desired_vel = strafe * (_archetype.move_speed * 0.55 * speed_mult)

					_ability_cd -= delta * speed_mult
					if _ability_cd <= 0.0 and dist < 16.5:
						_ability_cd = 4.0
						_windup_timer = 0.65
						_windup_duration_ref = 0.65
						_pending_action_kind = 1
						_pending_target_pos = target_player.global_position
						if target_player is CharacterBody3D:
							var pv: Vector3 = (target_player as CharacterBody3D).velocity
							_pending_target_pos += Vector3(pv.x, 0.0, pv.z) * 0.35

			ArchetypeScript.ArchetypeId.OCULAR_SNIPER:
				if _windup_timer > 0.0:
					_windup_timer -= delta
					desired_vel = Vector3.ZERO
					if _windup_timer <= 0.0:
						var orb_origin: Vector3 = global_position + Vector3(0.0, 0.42, 0.0) + _action_dir * 0.5
						_rpc_enemy_orb(
							orb_origin,
							_action_dir,
							29.0,
							24.0,
							13.0,
							Color(1.0, 0.92, 0.42),
							true
						)
						if _biome_trait_id == 2:
							for side_deg in [-13.0, 13.0]:
								var s_dir: Vector3 = _action_dir.rotated(Vector3.UP, deg_to_rad(side_deg))
								_rpc_enemy_orb(orb_origin, s_dir, 21.0, 20.0, 8.0, Color(1.0, 0.86, 0.36), false)
				else:
					if dist < 9.5:
						desired_vel = -dir * (_archetype.move_speed * 0.85 * speed_mult)
					elif dist > 15.0:
						desired_vel = dir * (_archetype.move_speed * speed_mult)
					_ability_cd -= delta * speed_mult
					if _ability_cd <= 0.0 and dist < 21.0:
						_ability_cd = 4.2
						_windup_timer = 1.25
						_windup_duration_ref = 1.25
						_action_dir = dir
						if visual_root:
							visual_root.rotation.y = atan2(_action_dir.x, _action_dir.z)
						_rpc_enemy_sightline(global_position, _action_dir, 23.0, 1.25, Color(1.0, 0.24, 0.34))

			ArchetypeScript.ArchetypeId.BOSS, ArchetypeScript.ArchetypeId.BOSS_BLIGHTWEAVER, ArchetypeScript.ArchetypeId.BOSS_CRYO_ARCHON, ArchetypeScript.ArchetypeId.BOSS_CHRONOMANCER:
				desired_vel = _tick_boss_ai(delta, target_player, dir, dist, speed_mult)

			_:
				if dist > (_base_radius + 0.18):
					desired_vel = dir * (_archetype.move_speed * speed_mult)

		if dir.length_squared() > 0.01 and visual_root and _windup_timer <= 0.0:
			visual_root.rotation.y = lerp_angle(visual_root.rotation.y, atan2(dir.x, dir.z), 12.0 * delta)

	var use_accel: float = _archetype.acceleration * (2.5 if _action_timer > 0.0 else 1.0)
	velocity.x = move_toward(velocity.x, desired_vel.x, use_accel * delta)
	velocity.z = move_toward(velocity.z, desired_vel.z, use_accel * delta)
	velocity.y = 0.0

	if _burrow_state == 1:
		global_position += velocity * delta
	else:
		var was_boss_charging: bool = (_action_timer > 0.0 and aid == ArchetypeScript.ArchetypeId.BOSS)
		var was_cryo_dashing: bool = (_action_timer > 0.0 and aid == ArchetypeScript.ArchetypeId.BOSS_CRYO_ARCHON)
		move_and_slide()
		if was_cryo_dashing and boss_director != null and boss_director.has_method("on_boss_dash_pos"):
			boss_director.call("on_boss_dash_pos", self, global_position)
		if was_boss_charging and is_on_wall():
			var hit_pillar: Object = _find_colliding_pillar_prop()
			if hit_pillar != null and boss_director != null and boss_director.has_method("on_boss_pillar_collision"):
				_action_timer = 0.0
				_sub_steps_left = 0
				boss_director.call("on_boss_pillar_collision", self, hit_pillar)
			elif _hit_static_wall():
				_action_timer = 0.0
				_sub_steps_left = 0
				_stagger_timer = 0.85
				_rpc_enemy_ground_hazard(
					HazardScript.HazardMode.GROUND_QUAKE,
					global_position,
					global_position,
					3.0,
					0.0,
					10.0,
					0.55,
					0.26,
					Color(1.0, 0.72, 0.24),
					0.42
				)
		_check_player_contact_damage()


func _find_colliding_pillar_prop() -> Object:
	for s_i in range(get_slide_collision_count()):
		var col_obj: Object = get_slide_collision(s_i).get_collider()
		if col_obj is BossPropScript and (col_obj as BossPropScript).prop_kind == BossPropScript.PropKind.BASALT_PILLAR:
			return col_obj
	return null


func _hit_static_wall() -> bool:
	for s_i in range(get_slide_collision_count()):
		var col_obj: Object = get_slide_collision(s_i).get_collider()
		if col_obj is StaticBody3D:
			return true
	return false


func _tick_boss_ai(delta: float, target_player: Node3D, dir: Vector3, dist: float, speed_mult: float) -> Vector3:
	var aid: int = _archetype.archetype_id
	var is_p2: bool = (_boss_phase >= 2) or (health_comp != null and health_comp.current_health <= health_comp.max_health * 0.5)
	var is_p3: bool = (_boss_phase >= 3)
	var rate_mult: float = 1.24 if is_p3 else (1.12 if is_p2 else 1.0)

	if _windup_timer > 0.0:
		_windup_timer -= delta
		if _windup_timer <= 0.0:
			var kind: int = _pending_action_kind
			_pending_action_kind = 0
			if kind == 2:
				_action_timer = 0.36 if aid == ArchetypeScript.ArchetypeId.BOSS_CRYO_ARCHON else 0.48
				if aid == ArchetypeScript.ArchetypeId.BOSS and is_p2 and _sub_step_kind != 6:
					_sub_step_kind = 6
					_sub_steps_left = 1
					_sub_step_timer = 0.62
			elif kind == 3:
				if aid == ArchetypeScript.ArchetypeId.BOSS_CHRONOMANCER:
					_launch_chronomancer_starfall(target_player, is_p2)
				else:
					_launch_boss_acidic_rain(target_player, is_p2)
			elif kind == 4:
				if aid == ArchetypeScript.ArchetypeId.BOSS_CRYO_ARCHON:
					_fire_boss_orb_fan(_action_dir, 7 if is_p2 else 5, 112.0 if is_p2 else 88.0, Color(0.54, 0.94, 1.0), true, 24.5)
					if is_p3:
						_sub_step_kind = 1
						_sub_steps_left = 1
						_sub_step_timer = 0.48
				elif aid == ArchetypeScript.ArchetypeId.BOSS_CHRONOMANCER:
					_fire_boss_radial_ring(10 if is_p2 else 8, _bob_phase, Color(1.0, 0.84, 0.34), false, 10.8)
					if is_p3:
						_sub_step_kind = 4
						_sub_steps_left = 3
						_sub_step_timer = 0.36
				else:
					_fire_boss_orb_fan(_action_dir, 7, 108.0, Color(0.56, 0.98, 0.34), false, 11.5)
					_sub_step_kind = 3
					_sub_steps_left = 2 if is_p3 else 1
					_sub_step_timer = 0.48
		return Vector3.ZERO

	if _action_timer > 0.0:
		_action_timer -= delta
		if _action_timer <= 0.0:
			if aid == ArchetypeScript.ArchetypeId.BOSS:
				_rpc_enemy_ground_hazard(
					HazardScript.HazardMode.GROUND_QUAKE,
					global_position,
					global_position,
					3.8,
					0.0,
					14.0,
					0.65,
					0.28,
					Color(1.0, 0.22, 0.28),
					0.48
				)
			elif aid == ArchetypeScript.ArchetypeId.BOSS_CRYO_ARCHON:
				_rpc_enemy_ground_hazard(
					HazardScript.HazardMode.GROUND_QUAKE,
					global_position,
					global_position,
					2.6,
					0.0,
					12.0,
					0.85,
					0.28,
					Color(0.44, 0.90, 1.0),
					0.34
				)
		var charge_spd: float = 16.8 if aid == ArchetypeScript.ArchetypeId.BOSS_CRYO_ARCHON else 14.2
		return _action_dir * (charge_spd * speed_mult)

	_ability_cd -= delta * speed_mult * rate_mult
	if _ability_cd <= 0.0:
		var pat: int = _boss_pattern_idx % 3
		_boss_pattern_idx += 1
		match aid:
			ArchetypeScript.ArchetypeId.BOSS:
				# TECTONIC SOVEREIGN
				match pat:
					0:
						_ability_cd = 4.0
						_windup_timer = 1.15
						_windup_duration_ref = 1.15
						_pending_action_kind = 1
						_sub_step_kind = 0
						_rpc_enemy_ground_hazard(
							HazardScript.HazardMode.GROUND_QUAKE,
							global_position,
							global_position,
							4.4,
							0.0,
							16.0,
							1.15,
							0.30,
							Color(1.0, 0.16, 0.24),
							0.62
						)
						_sub_steps_left = 1
						_sub_step_timer = 0.85
					1:
						# Faultline Spikes (or 4-Way Seismic Cross in Phase 3!)
						_ability_cd = 3.8
						_windup_timer = 0.95
						_windup_duration_ref = 0.95
						_pending_action_kind = 5
						if is_p3:
							_launch_tectonic_cross(0.0)
							_sub_step_kind = 5
							_sub_steps_left = 1
							_sub_step_timer = 0.85
						else:
							var lanes: int = 5 if is_p2 else 3
							var half_ang: float = deg_to_rad(32.0 if is_p2 else 22.0)
							for l_i in range(lanes):
								var frac: float = (float(l_i) / float(maxi(1, lanes - 1))) * 2.0 - 1.0
								var l_dir: Vector3 = dir.rotated(Vector3.UP, frac * half_ang)
								for step_d in [3.6, 6.8, 10.0]:
									var p_spot: Vector3 = global_position + l_dir * float(step_d)
									_rpc_enemy_ground_hazard(
										HazardScript.HazardMode.GROUND_QUAKE,
										global_position,
										p_spot,
										1.85,
										0.0,
										13.0,
										0.95 + float(step_d) * 0.06,
										0.26,
										Color(1.0, 0.24, 0.30),
										0.20 if step_d < 4.0 else 0.0
									)
					_:
						# Telegraphed Bull-Rush Charge (2-hit chain in Phase 2+!)
						_ability_cd = 3.8
						_action_dir = dir
						_windup_timer = 0.85
						_windup_duration_ref = 0.85
						_pending_action_kind = 2
						_sub_step_kind = 0
						if visual_root:
							visual_root.rotation.y = atan2(_action_dir.x, _action_dir.z)
						_rpc_enemy_sightline(global_position, _action_dir, 9.8, 0.85, Color(1.0, 0.22, 0.30))

			ArchetypeScript.ArchetypeId.BOSS_BLIGHTWEAVER:
				# BLIGHTWEAVER CORE
				match pat:
					0:
						_ability_cd = 4.2
						_windup_timer = 0.75
						_windup_duration_ref = 0.75
						_pending_action_kind = 3
						_pending_target_pos = target_player.global_position
					1:
						_ability_cd = 3.8
						_action_dir = dir
						_windup_timer = 0.70
						_windup_duration_ref = 0.70
						_pending_action_kind = 4
					_:
						_ability_cd = 4.5
						_windup_timer = 1.30
						_windup_duration_ref = 1.30
						_pending_action_kind = 1
						_rpc_enemy_ground_hazard(
							HazardScript.HazardMode.DONUT_AFTERSHOCK,
							global_position,
							global_position,
							11.8,
							4.3,
							18.0,
							1.30,
							0.36,
							Color(0.32, 0.94, 0.42),
							0.68
						)
						if is_p2:
							for off_deg in [-18.0, 18.0]:
								var l_d: Vector3 = dir.rotated(Vector3.UP, deg_to_rad(off_deg))
								_rpc_enemy_sightline(global_position, l_d, 20.0, 1.15, Color(0.42, 0.98, 0.64))

			ArchetypeScript.ArchetypeId.BOSS_CRYO_ARCHON:
				# CRYO-ARCHON VALKYRIE
				match pat:
					0:
						# Glacial Dash-Slash (0.72s sightline -> dash leaving rime shatter)
						_ability_cd = 3.2
						_action_dir = dir
						_windup_timer = 0.72
						_windup_duration_ref = 0.72
						_pending_action_kind = 2
						_sub_step_kind = 0
						if visual_root:
							visual_root.rotation.y = atan2(_action_dir.x, _action_dir.z)
						_rpc_enemy_sightline(global_position, _action_dir, 11.0, 0.72, Color(0.36, 0.92, 1.0))
					1:
						# Rime Lance Fan (5 -> 7 lances, plus delayed Frost Shatter in Phase 3)
						_ability_cd = 3.6
						_action_dir = dir
						_windup_timer = 0.78
						_windup_duration_ref = 0.78
						_pending_action_kind = 4
						_rpc_enemy_sightline(global_position, _action_dir, 18.0, 0.78, Color(0.45, 0.94, 1.0))
					_:
						# Whiteout Blizzard Eye (safe inner eye -> delayed inner frost shatter in P2+)
						_ability_cd = 4.4
						_windup_timer = 1.25
						_windup_duration_ref = 1.25
						_pending_action_kind = 1
						_rpc_enemy_ground_hazard(
							HazardScript.HazardMode.DONUT_AFTERSHOCK,
							global_position,
							global_position,
							11.4,
							3.8,
							17.0,
							1.25,
							0.32,
							Color(0.38, 0.88, 1.0),
							0.58
						)
						if is_p2:
							_sub_step_kind = 1
							_sub_steps_left = 1
							_sub_step_timer = 0.90

			ArchetypeScript.ArchetypeId.BOSS_CHRONOMANCER:
				if is_astral_clone:
					match pat % 2:
						0:
							_ability_cd = 3.2
							_action_dir = dir
							_windup_timer = 0.65
							_windup_duration_ref = 0.65
							_pending_action_kind = 4
						_:
							_ability_cd = 3.6
							_windup_timer = 0.75
							_windup_duration_ref = 0.75
							_pending_action_kind = 3
							_pending_target_pos = target_player.global_position
				else:
					# ASTRAL CHRONOMANCER — Multi-area ticking clocks, astrolabe volleys & large Clock-Dial Judgment
					if _clock_sector_queued:
						pat = 2
						_clock_sector_queued = false
					match pat:
						0:
							# Multi-Area Time-Ticking Clocks (2 -> 3 simultaneous localized zones)
							_ability_cd = 4.4
							_windup_timer = 1.25
							_windup_duration_ref = 1.25
							_pending_action_kind = 1
							_launch_chronomancer_multi_clocks(target_player, is_p2)
						1:
							# Astrolabe Clockwork Ring (clockwise spiral in Phase 3)
							_ability_cd = 3.6
							_action_dir = dir
							_windup_timer = 0.75
							_windup_duration_ref = 0.75
							_pending_action_kind = 4
						_:
							if is_p2 and boss_director != null and boss_director.has_method("try_trigger_mid_combat_horology"):
								if bool(boss_director.call("try_trigger_mid_combat_horology")):
									_ability_cd = 1.2
									return Vector3.ZERO
							# Large Localized Clock-Dial Judgment
							_ability_cd = 4.6
							_windup_timer = 2.45
							_windup_duration_ref = 2.45
							_pending_action_kind = 1
							var side_ang: float = 1.35 if (_boss_pattern_idx % 2 == 0) else -1.35
							var safe_ang: float = atan2(dir.z, dir.x) + side_ang
							_rpc_enemy_clock_sector(global_position, 15.5, safe_ang, deg_to_rad(32.0), 22.0, 2.45, Color(0.56, 0.28, 0.96), 0.55)
							if boss_director != null and boss_director.has_method("notify_clock_sector_cast"):
								boss_director.call("notify_clock_sector_cast", 2.45)

	if dist > (_base_radius + 0.35):
		return dir * (_archetype.move_speed * speed_mult)
	return Vector3.ZERO


func _launch_tectonic_cross(base_angle_deg: float) -> void:
	var base_rad: float = deg_to_rad(base_angle_deg)
	for arm_i in range(4):
		var arm_dir: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, base_rad + float(arm_i) * (PI * 0.5))
		for step_d in [3.4, 6.8, 10.2]:
			var spot: Vector3 = global_position + arm_dir * float(step_d)
			_rpc_enemy_ground_hazard(
				HazardScript.HazardMode.GROUND_QUAKE,
				global_position,
				spot,
				1.9,
				0.0,
				13.0,
				0.95 + float(step_d) * 0.05,
				0.26,
				Color(1.0, 0.24, 0.30),
				0.18 if step_d < 4.0 else 0.0
			)


func _launch_chronomancer_multi_clocks(target_player: Node3D, is_p2: bool) -> void:
	var count_z: int = 3 if is_p2 else 2
	var radius_z: float = 6.5 if is_p2 else 6.2
	var tel_s: float = 2.2 if is_p2 else 2.4
	var safe_half_w: float = deg_to_rad(30.0 if is_p2 else 34.0)
	var dmg: float = 20.0 if is_p2 else 18.0
	var p_pos: Vector3 = target_player.global_position if (target_player != null and is_instance_valid(target_player)) else global_position
	var arena_c: Vector3 = global_position
	if boss_director != null and boss_director.has_method("get_arena_center"):
		arena_c = boss_director.call("get_arena_center")
	var base_a: float = _bob_phase
	var z0_pos := Vector3(p_pos.x + cos(base_a) * 1.8, 0.0, p_pos.z + sin(base_a) * 1.8)
	_rpc_enemy_clock_sector(z0_pos, radius_z, base_a + 0.85, safe_half_w, dmg, tel_s, Color(0.56, 0.28, 0.96), 0.35)
	var away_dir := Vector3(arena_c.x - z0_pos.x, 0.0, arena_c.z - z0_pos.z)
	var away_ang: float = atan2(away_dir.z, away_dir.x) if away_dir.length_squared() > 0.25 else (base_a + PI)
	for z_i in range(1, count_z):
		var spread_a: float = away_ang + (0.0 if count_z == 2 else (-0.72 if z_i == 1 else 0.72))
		var z_pos := Vector3(arena_c.x + cos(spread_a) * 9.2, 0.0, arena_c.z + sin(spread_a) * 9.2)
		_rpc_enemy_clock_sector(z_pos, radius_z, spread_a + float(z_i) * 1.1, safe_half_w, dmg, tel_s, Color(0.56, 0.28, 0.96), 0.25)
	if boss_director != null and boss_director.has_method("notify_multi_clock_cast"):
		boss_director.call("notify_multi_clock_cast", tel_s)


func _launch_chronomancer_starfall(target_player: Node3D, is_p2: bool) -> void:
	var anchor: Vector3 = target_player.global_position if (target_player != null and is_instance_valid(target_player)) else _pending_target_pos
	if target_player is CharacterBody3D:
		var pv: Vector3 = (target_player as CharacterBody3D).velocity
		anchor += Vector3(pv.x, 0.0, pv.z) * 0.45
	var count_s: int = 5 if is_p2 else 3
	for i in range(count_s):
		var ang: float = float(i) * (TAU / float(count_s)) + _bob_phase
		var off_r: float = 0.4 if i == 0 else 3.6
		var land_pt: Vector3 = anchor + Vector3(cos(ang) * off_r, 0.0, sin(ang) * off_r)
		_rpc_enemy_ground_hazard(
			HazardScript.HazardMode.GROUND_QUAKE,
			global_position,
			land_pt,
			2.35,
			0.0,
			13.0,
			1.00 + float(i) * 0.14,
			0.30,
			Color(1.0, 0.80, 0.30),
			0.25 if i == 0 else 0.0
		)


func _launch_boss_acidic_rain(target_player: Node3D, is_enraged: bool) -> void:
	var anchor: Vector3 = target_player.global_position if (target_player != null and is_instance_valid(target_player)) else _pending_target_pos
	var count_p: int = 5 if is_enraged else 3
	for m_i in range(count_p):
		var ang_m: float = float(m_i) * (TAU / float(count_p)) + _bob_phase
		var off_r: float = 0.8 if m_i == 0 else 3.8
		var land_pt: Vector3 = anchor + Vector3(cos(ang_m) * off_r, 0.0, sin(ang_m) * off_r)
		_rpc_enemy_ground_hazard(
			HazardScript.HazardMode.LOB_POOL,
			global_position + Vector3(0.0, 1.25, 0.0),
			land_pt,
			3.0,
			0.0,
			11.0,
			1.15,
			6.2,
			Color(0.42, 1.0, 0.56),
			0.18 if m_i == 0 else 0.0
		)


func _execute_boss_sub_step(target_player: Node3D) -> void:
	_sub_steps_left = maxi(0, _sub_steps_left - 1)
	if _archetype == null:
		return
	var aid: int = _archetype.archetype_id
	if _sub_step_kind == 6 and aid == ArchetypeScript.ArchetypeId.BOSS:
		_sub_step_kind = 0
		if target_player != null and is_instance_valid(target_player):
			var d_v: Vector3 = target_player.global_position - global_position
			d_v.y = 0.0
			_action_dir = d_v.normalized() if d_v.length_squared() > 0.01 else _action_dir
		_windup_timer = 0.52
		_windup_duration_ref = 0.52
		_pending_action_kind = 2
		_rpc_enemy_sightline(global_position, _action_dir, 9.8, 0.52, Color(1.0, 0.28, 0.34))
		return

	if _sub_step_kind == 5 and aid == ArchetypeScript.ArchetypeId.BOSS:
		_sub_step_kind = 0
		_launch_tectonic_cross(45.0)
		return

	if aid == ArchetypeScript.ArchetypeId.BOSS:
		_rpc_enemy_ground_hazard(
			HazardScript.HazardMode.DONUT_AFTERSHOCK,
			global_position,
			global_position,
			9.2,
			4.4,
			16.0,
			1.05,
			0.32,
			Color(1.0, 0.18, 0.28),
			0.55
		)
	elif aid == ArchetypeScript.ArchetypeId.BOSS_BLIGHTWEAVER:
		var ang_off: float = 9.0 + float(2 - _sub_steps_left) * 14.0
		_fire_boss_orb_fan(_action_dir.rotated(Vector3.UP, deg_to_rad(ang_off)), 6, 94.0, Color(0.42, 0.96, 0.68), false, 11.5)
	elif aid == ArchetypeScript.ArchetypeId.BOSS_CRYO_ARCHON:
		if _sub_step_kind == 1:
			_sub_step_kind = 0
			_rpc_enemy_ground_hazard(
				HazardScript.HazardMode.GROUND_QUAKE,
				global_position,
				global_position,
				4.0,
				0.0,
				14.0,
				0.90,
				0.28,
				Color(0.48, 0.94, 1.0),
				0.42
			)
	elif aid == ArchetypeScript.ArchetypeId.BOSS_CHRONOMANCER:
		if _sub_step_kind == 2:
			_sub_step_kind = 0
			var origin: Vector3 = global_position + Vector3(0.0, 0.55, 0.0)
			for q_i in range(4):
				var l_d: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, float(q_i) * (PI * 0.5) + 0.35)
				_rpc_enemy_orb(origin + l_d * 0.6, l_d, 26.0, 22.0, 12.0, Color(1.0, 0.88, 0.42), true)
		elif _sub_step_kind == 4:
			var step_ang: float = _bob_phase - float(3 - _sub_steps_left) * 0.34
			_fire_boss_radial_ring(6, step_ang, Color(0.76, 0.52, 1.0), false, 10.6)
			if _sub_steps_left > 0:
				_sub_step_timer = 0.36


func _fire_boss_radial_ring(count: int, angle_offset_rad: float, col: Color, is_lance: bool, spd: float) -> void:
	var origin: Vector3 = global_position + Vector3(0.0, 0.55, 0.0)
	for i in range(count):
		var ang: float = angle_offset_rad + float(i) * (TAU / float(maxi(1, count)))
		var o_dir := Vector3(sin(ang), 0.0, -cos(ang))
		_rpc_enemy_orb(origin + o_dir * 0.6, o_dir, spd, 20.0, 11.0, col, is_lance)


func _fire_boss_orb_fan(
	center_dir: Vector3,
	count: int,
	total_deg: float,
	col: Color,
	is_lance: bool = false,
	spd: float = 11.5
) -> void:
	var half_r: float = deg_to_rad(total_deg * 0.5)
	var origin: Vector3 = global_position + Vector3(0.0, 0.55, 0.0)
	for i in range(count):
		var frac: float = (float(i) / float(maxi(1, count - 1))) * 2.0 - 1.0 if count > 1 else 0.0
		var o_dir: Vector3 = center_dir.rotated(Vector3.UP, frac * half_r)
		_rpc_enemy_orb(origin + o_dir * 0.6, o_dir, spd, 20.0, 11.0, col, is_lance)


@rpc("authority", "call_local", "reliable")
func _rpc_enemy_orb(p_start: Vector3, p_dir: Vector3, p_spd: float, p_rng: float, p_dmg: float, p_col: Color, p_is_lance: bool) -> void:
	if ProjectilePool and ProjectilePool.has_method("spawn_enemy_orb"):
		ProjectilePool.call("spawn_enemy_orb", p_start, p_dir, p_spd, p_rng, p_dmg, p_col, p_is_lance, _players_root)


@rpc("authority", "call_local", "reliable")
func _rpc_enemy_sightline(p_origin: Vector3, p_dir: Vector3, p_len: float, p_dur: float, p_col: Color) -> void:
	if ProjectilePool and ProjectilePool.has_method("spawn_enemy_sightline"):
		ProjectilePool.call("spawn_enemy_sightline", p_origin, p_dir, p_len, p_dur, p_col)


@rpc("authority", "call_local", "reliable")
func _rpc_enemy_ground_hazard(
	p_mode: int,
	p_origin: Vector3,
	p_target: Vector3,
	p_rad: float,
	p_inner_rad: float,
	p_dmg: float,
	p_tel_s: float,
	p_pool_s: float,
	p_col: Color,
	p_shake: float
) -> void:
	if ProjectilePool and ProjectilePool.has_method("spawn_enemy_ground_hazard"):
		ProjectilePool.call(
			"spawn_enemy_ground_hazard",
			p_mode,
			p_origin,
			p_target,
			p_rad,
			p_inner_rad,
			p_dmg,
			p_tel_s,
			p_pool_s,
			p_col,
			p_shake,
			_players_root
		)


@rpc("authority", "call_local", "reliable")
func _rpc_enemy_clock_sector(
	p_center: Vector3,
	p_rad: float,
	p_safe_ang: float,
	p_safe_half_w: float,
	p_dmg: float,
	p_tel_s: float,
	p_col: Color,
	p_shake: float
) -> void:
	if ProjectilePool and ProjectilePool.has_method("spawn_enemy_clock_sector"):
		ProjectilePool.call(
			"spawn_enemy_clock_sector",
			p_center,
			p_rad,
			p_safe_ang,
			p_safe_half_w,
			p_dmg,
			p_tel_s,
			p_col,
			p_shake,
			_players_root
		)


func _tick_statuses(delta: float) -> void:
	var status_expired: bool = false

	if _poison_timer > 0.0:
		_poison_timer -= delta
		if _poison_timer <= 0.0:
			_poison_timer = 0.0
			_poison_stacks = 0
			_poison_dps = 0.0
			status_expired = true

	if _burn_timer > 0.0:
		_burn_timer -= delta
		if _burn_timer <= 0.0:
			_burn_timer = 0.0
			_burn_dps = 0.0
			status_expired = true

	if _frost_timer > 0.0:
		_frost_timer -= delta
		if _frost_timer <= 0.0:
			_frost_timer = 0.0
			_frost_slow = 0.0
			status_expired = true

	if _external_slow_timer > 0.0:
		_external_slow_timer -= delta
		if _external_slow_timer <= 0.0:
			_external_slow_timer = 0.0
			_external_slow = 0.0
			status_expired = true

	if status_expired and _hit_flash_timer <= 0.0:
		_refresh_body_material()

	var total_dps: float = float(_poison_stacks) * _poison_dps + _burn_dps
	if _archetype != null and ArchetypeScript.is_boss_archetype(_archetype.archetype_id) and health_comp != null:
		total_dps = minf(total_dps, health_comp.max_health * 0.14)
	if total_dps > 0.01 and health_comp != null:
		_dot_accum += delta
		if _dot_accum >= 0.40:
			var tick_dmg: float = total_dps * _dot_accum
			_dot_accum = 0.0
			_suppress_hit_flash = true
			health_comp.take_damage(tick_dmg, Vector3.ZERO)
			_suppress_hit_flash = false
	else:
		_dot_accum = 0.0


func _check_player_contact_damage() -> void:
	if _burrow_state == 1 or _players_root == null or not is_instance_valid(_players_root) or _archetype == null:
		return
	var contact_range: float = _base_radius + 0.36
	var contact_range_sq: float = contact_range * contact_range
	var child_count: int = _players_root.get_child_count()
	for i in range(child_count):
		var p3d: Node3D = _players_root.get_child(i) as Node3D
		if p3d == null or not p3d.visible:
			continue
		var dx: float = p3d.global_position.x - global_position.x
		var dz: float = p3d.global_position.z - global_position.z
		var d2: float = dx * dx + dz * dz
		if d2 <= contact_range_sq and p3d.has_method("try_apply_contact_damage"):
			var hit_dir: Vector3 = Vector3(dx, 0.0, dz).normalized() if d2 > 0.0001 else Vector3.FORWARD
			p3d.call("try_apply_contact_damage", _archetype.contact_damage, hit_dir)


func _find_nearest_player() -> Node3D:
	if _players_root == null or not is_instance_valid(_players_root):
		return null
	var best: Node3D = null
	var best_d2: float = INF
	var child_count: int = _players_root.get_child_count()
	for i in range(child_count):
		var p3d: Node3D = _players_root.get_child(i) as Node3D
		if p3d == null or not p3d.visible:
			continue
		var d2: float = global_position.distance_squared_to(p3d.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = p3d
	return best


func _on_damaged(_amount: float, _hit_dir: Vector3) -> void:
	if not _is_active_unit or _is_dying or _suppress_hit_flash:
		return
	_hit_flash_timer = 0.08
	if sphere_mesh_inst:
		sphere_mesh_inst.material_override = ArchetypeScript.get_hit_flash_material()
	if visual_root:
		visual_root.scale = Vector3(_base_radius * 1.12, _base_radius * 0.90, _base_radius * 1.12)


func _on_health_changed(current_hp: float, max_hp: float) -> void:
	if hp_bar_root == null or _archetype == null:
		return
	var ratio: float = clampf(current_hp / maxf(1.0, max_hp), 0.0, 1.0)
	if _hp_bar_mat:
		_hp_bar_mat.set_shader_parameter("fill_ratio", ratio)
	if not _should_hide_overhead_hp() and current_hp < max_hp and current_hp > 0.0 and _burrow_state != 1:
		hp_bar_root.visible = true

	if _biome_trait_id == 2 and not _biome_special_used and not _is_dying and _is_active_unit and current_hp > 0.0 and current_hp <= max_hp * 0.50:
		var aid: int = _archetype.archetype_id
		if (
			aid == ArchetypeScript.ArchetypeId.DASHER
			or aid == ArchetypeScript.ArchetypeId.LUNGER
			or aid == ArchetypeScript.ArchetypeId.OCULAR_SNIPER
		):
			_biome_special_used = true
			if is_inside_tree() and (not multiplayer.has_multiplayer_peer() or multiplayer.is_server()):
				var side := Vector3(cos(_bob_phase), 0.0, sin(_bob_phase)).normalized() * 1.85
				if not test_move(global_transform, side):
					global_position += side
					reset_physics_interpolation()
				_hit_flash_timer = 0.14
				if sphere_mesh_inst:
					sphere_mesh_inst.material_override = ArchetypeScript.get_hit_flash_material()


func _on_armor_changed(cur_arm: float, max_arm: float) -> void:
	if _hp_bar_mat:
		var a_ratio: float = clampf(cur_arm / maxf(1.0, max_arm), 0.0, 1.0) if cur_arm > 0.01 else 0.0
		_hp_bar_mat.set_shader_parameter("armor_ratio", a_ratio)
	if hp_bar_root and not _should_hide_overhead_hp() and _burrow_state != 1 and cur_arm > 0.01:
		hp_bar_root.visible = true
	_refresh_ward_shell()


func _on_armor_broken() -> void:
	_refresh_ward_shell()
	if _archetype == null:
		return
	var aid: int = _archetype.archetype_id
	if ArchetypeScript.is_boss_archetype(aid) and not is_astral_clone:
		if _stagger_timer <= 0.0:
			trigger_boss_stagger(1.8, 1.40, false)
			if is_inside_tree():
				get_tree().call_group("world_camera_shake", "add_camera_shake", 0.36)
			if boss_director != null and boss_director.has_method("on_boss_armor_broken"):
				boss_director.call("on_boss_armor_broken", self)
	elif not ArchetypeScript.is_boss_archetype(aid):
		# Hades-style Armor Break interrupt & stun on Elites!
		_windup_timer = 0.0
		_action_timer = 0.0
		_pending_action_kind = 0
		_stagger_timer = 0.55
		_frenzy_mult = maxf(_frenzy_mult, 1.15)
		if is_inside_tree():
			get_tree().call_group("world_camera_shake", "add_camera_shake", 0.22)


func _on_bar_broken(remaining_bars: int, total_bars: int, _bar_max_hp: float) -> void:
	_boss_phase = clampi((total_bars - remaining_bars) + 1, 1, total_bars)
	_burst_window_dmg = 0.0
	_windup_timer = 0.0
	_action_timer = 0.0
	_pending_action_kind = 0
	_sub_steps_left = 0
	_sub_step_kind = 0
	_frost_slow = 0.0
	_frost_timer = 0.0
	_external_slow = 0.0
	_external_slow_timer = 0.0
	_refresh_body_material()

	if _hp_bar_mat:
		_hp_bar_mat.set_shader_parameter("stock_pips", float(maxi(1, remaining_bars)))
		_hp_bar_mat.set_shader_parameter("fill_ratio", 1.0)

	if _archetype == null:
		return
	if ArchetypeScript.is_boss_archetype(_archetype.archetype_id) and not is_astral_clone:
		if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
			_rpc_enemy_ground_hazard(
				HazardScript.HazardMode.GROUND_QUAKE,
				global_position,
				global_position,
				4.6,
				0.0,
				12.0,
				0.95,
				0.28,
				Color(1.0, 0.78, 0.26),
				0.45
			)
			if boss_director != null and boss_director.has_method("on_boss_phase_changed"):
				boss_director.call("on_boss_phase_changed", self, _boss_phase)
		if remaining_bars == 1:
			_frenzy_mult = 1.18
	elif _is_elite_unit:
		_stagger_timer = 0.45
		_frenzy_mult = 1.18
		if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
			_rpc_enemy_ground_hazard(
				HazardScript.HazardMode.GROUND_QUAKE,
				global_position,
				global_position,
				3.2,
				0.0,
				8.0,
				0.55,
				0.24,
				Color(1.0, 0.72, 0.24),
				0.26
			)


func _on_phase_gate_changed(is_imp: bool, _remaining_bars: int) -> void:
	if _hp_bar_mat:
		_hp_bar_mat.set_shader_parameter("impervious_ratio", 1.0 if is_imp else 0.0)
	_refresh_ward_shell()


func _on_died() -> void:
	if _is_dying:
		return
	_is_dying = true
	_is_active_unit = false
	_death_timer = 0.16
	_deactivate_aegis_dome()

	if is_in_group("characters"):
		remove_from_group("characters")
	if is_in_group("active_enemies"):
		remove_from_group("active_enemies")
	if body_col_shape:
		body_col_shape.set_deferred("disabled", true)
	if hurtbox_comp:
		hurtbox_comp.set_active_deferred(false)
	if hp_bar_root:
		hp_bar_root.visible = false
	if _burrow_ring_inst:
		_burrow_ring_inst.visible = false
	if _contact_shadow_inst:
		_contact_shadow_inst.visible = false
	if sphere_mesh_inst:
		sphere_mesh_inst.material_override = ArchetypeScript.get_hit_flash_material()
	if visual_root:
		visual_root.visible = true
		visual_root.scale = Vector3.ONE * (_base_radius * 1.38)

	if _biome_trait_id == 3 and _archetype != null and (not multiplayer.has_multiplayer_peer() or multiplayer.is_server()):
		var aid: int = _archetype.archetype_id
		if aid == ArchetypeScript.ArchetypeId.CHASER or aid == ArchetypeScript.ArchetypeId.LUNGER:
			_rpc_enemy_ground_hazard(
				HazardScript.HazardMode.GROUND_QUAKE,
				global_position,
				global_position,
				2.1,
				0.0,
				9.0,
				0.85,
				0.24,
				Color(1.0, 0.34, 0.12),
				0.14
			)

	defeated.emit(enemy_id, area_idx)
