class_name EnemySphere
extends CharacterBody3D

## Pooled Sphere Enemy with HealthComponent + HurtboxComponent composition,
## shared static GPU/Physics resources, real-time 3D grass displacement,
## and zero-allocation elemental status processing (Poison, Burn, Frost, Shock).

const ArchetypeScript = preload("res://enemies/enemy_archetype_data.gd")

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

var _archetype: EnemyArchetypeData = null
var _players_root: Node3D = null
var _is_active_unit: bool = false
var _is_dying: bool = false
var _death_timer: float = 0.0
var _hit_flash_timer: float = 0.0
var _suppress_hit_flash: bool = false
var _bob_phase: float = 0.0
var _lunge_cooldown: float = 2.4
var _lunge_timer: float = 0.0
var _lunge_dir: Vector3 = Vector3.ZERO
var _base_radius: float = 0.38

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

	if hurtbox_comp and health_comp:
		hurtbox_comp.health_component = health_comp
	if health_comp:
		if not health_comp.damaged.is_connected(_on_damaged):
			health_comp.damaged.connect(_on_damaged)
		if not health_comp.health_changed.is_connected(_on_health_changed):
			health_comp.health_changed.connect(_on_health_changed)
		if not health_comp.died.is_connected(_on_died):
			health_comp.died.connect(_on_died)


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

	if visual_root:
		visual_root.position = Vector3(0.0, _base_radius + 0.06, 0.0)
		visual_root.scale = Vector3.ONE * (_base_radius * 0.2)

	if hp_bar_root:
		hp_bar_root.position = Vector3(0.0, _base_radius * 2.0 + 0.42, 0.0)
		var bar_w: float = clampf(_base_radius * 2.2, 0.75, 1.8)
		if hp_fill_mesh:
			hp_fill_mesh.scale = Vector3(bar_w, 0.11, 1.0)
			hp_fill_mesh.set_instance_shader_parameter("fill_ratio", 1.0)
		hp_bar_root.visible = (_archetype.archetype_id == ArchetypeScript.ArchetypeId.BOSS)

	if health_comp:
		health_comp.setup_max_health(_archetype.max_hp)

	_is_active_unit = true
	_is_dying = false
	_death_timer = 0.0
	_hit_flash_timer = 0.0
	_lunge_cooldown = 2.0 + float(p_enemy_id % 5) * 0.35
	_lunge_timer = 0.0
	_lunge_dir = Vector3.ZERO
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


## Resolves direct weapon/ability damage plus elemental on-hit traits (Poison, Burn, Frost, Shock).
func apply_combat_hit(raw_damage: float, hit_dir: Vector3, proc_coeff: float, shooter_stats: Object) -> void:
	if _is_dying or not _is_active_unit:
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

	# Shock chain lightning can arc to nearby foes even off a killing blow
	if s_rank > 0:
		var shock_chance: float = clampf((0.30 + 0.10 * float(s_rank)) * proc_coeff, 0.06, 0.95)
		if randf() <= shock_chance:
			var arc_dmg: float = (5.0 + 3.5 * float(s_rank)) + ap_val * (0.55 + 0.20 * float(s_rank))
			_trigger_shock_chain(hit_center, arc_dmg, 3)

	if _is_dying or not _is_active_unit:
		return

	# Poison: stacking DoT (rewards fast / multi-pellet weapons)
	if p_rank > 0:
		if randf() <= clampf(proc_coeff * 1.15, 0.25, 1.0):
			var max_stacks: int = 6 + p_rank * 4
			_poison_stacks = mini(max_stacks, _poison_stacks + 1)
			_poison_dps = (0.75 + 0.35 * float(p_rank)) + (ad_val * 0.06 + ap_val * 0.08)
			_poison_timer = 3.6

	# Burn: proportional % of triggering hit over 3.0s (rewards heavy single-hit weapons)
	if b_rank > 0:
		var total_ignite: float = raw_damage * (0.38 + 0.24 * float(b_rank)) * clampf(proc_coeff, 0.35, 1.2) + ap_val * (0.30 * float(b_rank))
		var cand_dps: float = total_ignite / 3.0
		_burn_dps = maxf(_burn_dps, cand_dps)
		_burn_timer = 3.0

	# Frost: movement chill slow
	if f_rank > 0:
		var slow_amt: float = clampf(0.28 + 0.11 * float(f_rank), 0.0, 0.72)
		_frost_slow = maxf(_frost_slow, slow_amt)
		_frost_timer = maxf(_frost_timer, 2.5)

	if _hit_flash_timer <= 0.0:
		_refresh_body_material()


func receive_arc_damage(amount: float) -> void:
	if _is_dying or not _is_active_unit or amount <= 0.0:
		return
	if health_comp:
		health_comp.take_damage(amount, Vector3.ZERO)


func apply_external_slow(ratio: float, duration: float) -> void:
	if _is_dying or not _is_active_unit:
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
		if es == null or not es._is_active_unit or es._is_dying or not es.visible:
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


func _process(delta: float) -> void:
	if _is_dying:
		_death_timer -= delta
		if visual_root:
			visual_root.scale = visual_root.scale.lerp(Vector3.ZERO, clampf(18.0 * delta, 0.0, 1.0))
		if _death_timer <= 0.0:
			_release_to_pool()
		return

	if not _is_active_unit:
		return

	if _hit_flash_timer > 0.0:
		_hit_flash_timer -= delta
		if _hit_flash_timer <= 0.0:
			_refresh_body_material()

	_bob_phase += delta * 5.2
	if visual_root:
		var target_scale := Vector3.ONE * _base_radius
		if _lunge_timer > 0.0:
			target_scale = Vector3(_base_radius * 0.85, _base_radius * 0.85, _base_radius * 1.3)
		visual_root.scale = visual_root.scale.lerp(target_scale, clampf(14.0 * delta, 0.0, 1.0))
		visual_root.position.y = _base_radius + 0.06 + sin(_bob_phase) * 0.05


func _physics_process(delta: float) -> void:
	if not _is_active_unit or _is_dying or _archetype == null:
		return

	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	_tick_statuses(delta)
	if _is_dying or not _is_active_unit:
		return

	var combined_slow: float = clampf(maxf(_frost_slow, _external_slow), 0.0, 0.85)
	var speed_mult: float = 1.0 - combined_slow

	var target_player: Node3D = _find_nearest_player()
	var desired_vel := Vector3.ZERO

	if target_player:
		var to_target: Vector3 = target_player.global_position - global_position
		to_target.y = 0.0
		var dist: float = to_target.length()
		var dir: Vector3 = to_target / dist if dist > 0.05 else Vector3.ZERO

		if _archetype.can_lunge:
			if _lunge_timer > 0.0:
				_lunge_timer -= delta
				desired_vel = _lunge_dir * (_archetype.move_speed * 2.75 * speed_mult)
			else:
				_lunge_cooldown -= delta * speed_mult
				if _lunge_cooldown <= 0.0 and dist < 11.0 and dist > 1.5:
					_lunge_cooldown = 3.2
					_lunge_timer = 0.34
					_lunge_dir = dir
				elif dist > (_base_radius + 0.18):
					desired_vel = dir * (_archetype.move_speed * speed_mult)
		else:
			if dist > (_base_radius + 0.18):
				desired_vel = dir * (_archetype.move_speed * speed_mult)

		if dir.length_squared() > 0.01 and visual_root:
			visual_root.rotation.y = lerp_angle(visual_root.rotation.y, atan2(dir.x, dir.z), 12.0 * delta)

	velocity.x = move_toward(velocity.x, desired_vel.x, _archetype.acceleration * delta)
	velocity.z = move_toward(velocity.z, desired_vel.z, _archetype.acceleration * delta)
	velocity.y = 0.0

	move_and_slide()
	_check_player_contact_damage()


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
	if _players_root == null or not is_instance_valid(_players_root) or _archetype == null:
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
	if current_hp < max_hp and current_hp > 0.0:
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
	if sphere_mesh_inst:
		sphere_mesh_inst.material_override = ArchetypeScript.get_hit_flash_material()
	if visual_root:
		visual_root.scale = Vector3.ONE * (_base_radius * 1.38)

	defeated.emit(enemy_id, area_idx)
