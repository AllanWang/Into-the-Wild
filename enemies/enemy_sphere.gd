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
## - BOSS_BLIGHTWEAVER (8): Blightweaver Core -> 0.75s acidic rain, 0.70s salvo spin, 1.30s levitating safe-eye cataclysm

const ArchetypeScript = preload("res://enemies/enemy_archetype_data.gd")
const HazardScript = preload("res://world/enemy_hazard_effect.gd")

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
var _burrow_ring_inst: MeshInstance3D = null

var _archetype: EnemyArchetypeData = null
var _players_root: Node3D = null
var _is_active_unit: bool = false
var _is_dying: bool = false
var _death_timer: float = 0.0
var _hit_flash_timer: float = 0.0
var _suppress_hit_flash: bool = false
var _bob_phase: float = 0.0
var _base_radius: float = 0.38

# Ability / AI state machine timers (zero allocation)
var _ability_cd: float = 2.0
var _action_timer: float = 0.0
var _windup_timer: float = 0.0
var _windup_duration_ref: float = 1.0
var _pending_action_kind: int = 0 # 0=none, 1=dash/lunge/lob, 2=boss_charge, 3=boss_acid, 4=boss_salvo
var _pending_target_pos: Vector3 = Vector3.ZERO
var _action_dir: Vector3 = Vector3.FORWARD
var _burrow_state: int = 0 # 0=Surface, 1=Burrowed (Invulnerable!), 2=Emerging warning, 3=Diving windup
var _boss_pattern_idx: int = 0
var _sub_step_timer: float = 0.0
var _sub_steps_left: int = 0

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
	wall_min_slide_angle = 0.0
	collision_layer = 4
	collision_mask = 5 # Collide with Layer 1 (World & VineBarriers) + Layer 3 (Other Enemies)

	if sphere_mesh_inst:
		sphere_mesh_inst.mesh = ArchetypeScript.get_unit_sphere_mesh()
	if hp_bg_mesh:
		hp_bg_mesh.visible = false
	if hp_fill_mesh:
		hp_fill_mesh.mesh = ArchetypeScript.get_hp_quad_mesh()
		hp_fill_mesh.material_override = ArchetypeScript.get_hp_bar_material()

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

	if _burrow_ring_inst == null:
		_burrow_ring_inst = MeshInstance3D.new()
		_burrow_ring_inst.name = "BurrowFloorRing"
		_burrow_ring_inst.mesh = ArchetypeScript.get_burrow_ring_mesh()
		_burrow_ring_inst.position = Vector3(0.0, 0.05, 0.0)
		_burrow_ring_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_burrow_ring_inst.visible = false
		add_child(_burrow_ring_inst)

	if hurtbox_comp and health_comp:
		hurtbox_comp.health_component = health_comp
	if health_comp:
		if not health_comp.damaged.is_connected(_on_damaged):
			health_comp.damaged.connect(_on_damaged)
		if not health_comp.health_changed.is_connected(_on_health_changed):
			health_comp.health_changed.connect(_on_health_changed)
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
	if _burrow_ring_inst:
		_burrow_ring_inst.visible = false
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

	var is_boss: bool = ArchetypeScript.is_boss_archetype(_archetype.archetype_id)
	if hp_bar_root:
		hp_bar_root.position = Vector3(0.0, _base_radius * 2.0 + 0.45, 0.0)
		var bar_w: float = clampf(_base_radius * 2.3, 0.75, 2.1)
		if hp_fill_mesh:
			hp_fill_mesh.scale = Vector3(bar_w, 0.12 if is_boss else 0.10, 1.0)
			hp_fill_mesh.set_instance_shader_parameter("fill_ratio", 1.0)
		hp_bar_root.visible = is_boss

	if health_comp:
		health_comp.setup_max_health(_archetype.max_hp)

	_is_active_unit = true
	_is_dying = false
	_death_timer = 0.0
	_hit_flash_timer = 0.0
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
	set_process(true)
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
			if _role_prop_a and _role_prop_b:
				_role_prop_a.mesh = ArchetypeScript.get_sac_orb_mesh()
				_role_prop_a.position = Vector3(0.0, 1.12, 0.0)
				_role_prop_a.scale = Vector3(0.76, 0.76, 0.76)
				_role_prop_a.visible = true
				_role_prop_b.mesh = ArchetypeScript.get_scope_ring_mesh()
				_role_prop_b.position = Vector3(0.0, 0.08, 1.18)
				_role_prop_b.rotation_degrees = Vector3(90.0, 0.0, 0.0)
				_role_prop_b.visible = true


func deactivate() -> void:
	_is_active_unit = false
	_is_dying = false
	_reset_statuses()
	if is_in_group("characters"):
		remove_from_group("characters")
	if is_in_group("active_enemies"):
		remove_from_group("active_enemies")

	set_process(false)
	set_physics_process(false)
	visible = false
	velocity = Vector3.ZERO

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


## Resolves direct weapon/ability damage plus elemental on-hit traits (ignored while burrowed underground!).
func apply_combat_hit(raw_damage: float, hit_dir: Vector3, proc_coeff: float, shooter_stats: Object) -> void:
	if _is_dying or not _is_active_unit or _burrow_state == 1:
		return

	var hit_center: Vector3 = global_position + Vector3(0.0, _base_radius, 0.0)
	if hurtbox_comp:
		hurtbox_comp.apply_hit(raw_damage, hit_dir)
	elif health_comp:
		health_comp.take_damage(raw_damage, hit_dir)

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
	if health_comp and hp_bar_root and health_comp.current_health < health_comp.max_health:
		hp_bar_root.visible = true


func _process(delta: float) -> void:
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
				if _pending_action_kind == 3 and _role_prop_a:
					_role_prop_a.scale = Vector3.ONE * lerpf(0.76, 1.55, windup_prog)
					target_rot_x = -0.25 * windup_prog
				elif _pending_action_kind == 4:
					visual_root.rotation.y += delta * 10.0
					target_pos.y = _base_radius + 0.30
				else:
					var bw_lev: float = 1.25 * sin(windup_prog * PI * 0.85)
					target_pos.y = _base_radius + 0.08 + maxf(0.0, bw_lev)
			_:
				target_scale = Vector3(_base_radius * 1.24, _base_radius * 0.74, _base_radius * 1.24)
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
				if _role_prop_a:
					_role_prop_a.scale = Vector3.ONE * 0.76

	visual_root.scale = visual_root.scale.lerp(target_scale, clampf(14.0 * delta, 0.0, 1.0))
	visual_root.position = visual_root.position.lerp(target_pos, clampf(16.0 * delta, 0.0, 1.0))
	visual_root.rotation.x = lerpf(visual_root.rotation.x, target_rot_x, clampf(14.0 * delta, 0.0, 1.0))
	visual_root.rotation.z = lerpf(visual_root.rotation.z, target_rot_z, clampf(14.0 * delta, 0.0, 1.0))


func _physics_process(delta: float) -> void:
	if not _is_active_unit or _is_dying or _archetype == null:
		return

	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	if _burrow_state != 1:
		_tick_statuses(delta)
		if _is_dying or not _is_active_unit:
			return

	var combined_slow: float = clampf(maxf(_frost_slow, _external_slow), 0.0, 0.85)
	var speed_mult: float = 1.0 - combined_slow

	var target_player: Node3D = _find_nearest_player()
	var desired_vel := Vector3.ZERO
	var aid: int = _archetype.archetype_id

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
						_action_timer = 0.22
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
						_rpc_enemy_sightline(global_position, _action_dir, 3.2, 0.58, Color(0.25, 0.92, 1.0))
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
						_action_timer = 0.32
				elif _action_timer > 0.0:
					_action_timer -= delta
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
						_rpc_enemy_ground_hazard(
							HazardScript.HazardMode.LOB_POOL,
							global_position + Vector3(0.0, 0.9, 0.0),
							_pending_target_pos,
							2.5,
							0.0,
							9.0,
							1.10,
							4.8,
							Color(0.36, 0.98, 0.48),
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
						_rpc_enemy_orb(
							global_position + Vector3(0.0, 0.42, 0.0) + _action_dir * 0.5,
							_action_dir,
							29.0,
							24.0,
							13.0,
							Color(1.0, 0.92, 0.42),
							true
						)
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

			ArchetypeScript.ArchetypeId.BOSS, ArchetypeScript.ArchetypeId.BOSS_BLIGHTWEAVER:
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
		move_and_slide()
		_check_player_contact_damage()


func _tick_boss_ai(delta: float, target_player: Node3D, dir: Vector3, dist: float, speed_mult: float) -> Vector3:
	var is_enraged: bool = (health_comp != null and health_comp.current_health <= health_comp.max_health * 0.5)
	var rate_mult: float = 1.22 if is_enraged else 1.0

	if _windup_timer > 0.0:
		_windup_timer -= delta
		if _windup_timer <= 0.0:
			var kind: int = _pending_action_kind
			_pending_action_kind = 0
			if kind == 2:
				_action_timer = 0.48
			elif kind == 3:
				_launch_boss_acidic_rain(target_player, is_enraged)
			elif kind == 4:
				_fire_boss_orb_fan(_action_dir, 7, 108.0, Color(0.84, 0.36, 1.0))
				_sub_steps_left = 1
				_sub_step_timer = 0.55
		return Vector3.ZERO

	if _action_timer > 0.0:
		_action_timer -= delta
		if _action_timer <= 0.0 and _archetype.archetype_id == ArchetypeScript.ArchetypeId.BOSS:
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
		return _action_dir * (14.2 * speed_mult)

	_ability_cd -= delta * speed_mult * rate_mult
	if _ability_cd <= 0.0:
		var pat: int = _boss_pattern_idx % 3
		_boss_pattern_idx += 1
		if _archetype.archetype_id == ArchetypeScript.ArchetypeId.BOSS:
			# TECTONIC SOVEREIGN
			match pat:
				0:
					# Pattern 1: Seismic Double-Quake (1.15s inner crater -> 1.05s outer donut ring!)
					_ability_cd = 4.0
					_windup_timer = 1.15
					_windup_duration_ref = 1.15
					_pending_action_kind = 1
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
					# Pattern 2: Faultline Spikes (3 -> 5 fanning crimson ground-eruption craters!)
					_ability_cd = 3.8
					_windup_timer = 0.95
					_windup_duration_ref = 0.95
					_pending_action_kind = 5
					var lanes: int = 5 if is_enraged else 3
					var half_ang: float = deg_to_rad(32.0 if is_enraged else 22.0)
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
					# Pattern 3: Telegraphed Juggernaut Charge (0.85s windup + sightline before moving!)
					_ability_cd = 3.8
					_action_dir = dir
					_windup_timer = 0.85
					_windup_duration_ref = 0.85
					_pending_action_kind = 2
					if visual_root:
						visual_root.rotation.y = atan2(_action_dir.x, _action_dir.z)
					_rpc_enemy_sightline(global_position, _action_dir, 9.8, 0.85, Color(1.0, 0.22, 0.30))
		else:
			# BLIGHTWEAVER CORE
			match pat:
				0:
					# Pattern 1: Acidic Rain (0.75s wind-up -> 1.15s LOB_POOL flight!)
					_ability_cd = 4.2
					_windup_timer = 0.75
					_windup_duration_ref = 0.75
					_pending_action_kind = 3
					_pending_target_pos = target_player.global_position
				1:
					# Pattern 2: Horizon Salvo (0.70s spin wind-up -> staggered 7-orb + 6-orb fans!)
					_ability_cd = 3.8
					_action_dir = dir
					_windup_timer = 0.70
					_windup_duration_ref = 0.70
					_pending_action_kind = 4
				_:
					# Pattern 3: Safe-Eye Cataclysm (1.30s levitating telegraph -> 4.3m..11.8m outer blast!)
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
						Color(0.92, 0.24, 0.92),
						0.68
					)

	if dist > (_base_radius + 0.35):
		return dir * (_archetype.move_speed * speed_mult)
	return Vector3.ZERO


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


func _execute_boss_sub_step(_target_player: Node3D) -> void:
	_sub_steps_left = maxi(0, _sub_steps_left - 1)
	if _archetype == null:
		return
	if _archetype.archetype_id == ArchetypeScript.ArchetypeId.BOSS:
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
	elif _archetype.archetype_id == ArchetypeScript.ArchetypeId.BOSS_BLIGHTWEAVER:
		_fire_boss_orb_fan(_action_dir.rotated(Vector3.UP, deg_to_rad(9.0)), 6, 94.0, Color(0.42, 0.96, 0.68))


func _fire_boss_orb_fan(center_dir: Vector3, count: int, total_deg: float, col: Color) -> void:
	var half_r: float = deg_to_rad(total_deg * 0.5)
	var origin: Vector3 = global_position + Vector3(0.0, 0.55, 0.0)
	for i in range(count):
		var frac: float = (float(i) / float(maxi(1, count - 1))) * 2.0 - 1.0 if count > 1 else 0.0
		var o_dir: Vector3 = center_dir.rotated(Vector3.UP, frac * half_r)
		_rpc_enemy_orb(origin + o_dir * 0.6, o_dir, 11.5, 19.0, 11.0, col, false)


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
	if hp_fill_mesh:
		hp_fill_mesh.set_instance_shader_parameter("fill_ratio", ratio)
	if current_hp < max_hp and current_hp > 0.0 and _burrow_state != 1:
		hp_bar_root.visible = true


func _on_died() -> void:
	if _is_dying:
		return
	_is_dying = true
	_is_active_unit = false
	_death_timer = 0.16

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
	if sphere_mesh_inst:
		sphere_mesh_inst.material_override = ArchetypeScript.get_hit_flash_material()
	if visual_root:
		visual_root.visible = true
		visual_root.scale = Vector3.ONE * (_base_radius * 1.38)

	defeated.emit(enemy_id, area_idx)
