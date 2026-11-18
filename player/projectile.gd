extends Area3D

## Pooled player projectile supporting multiple combat flight modes:
## - BOLT (0): crisp straight bolt / scatter shard (despawns on first hit)
## - PIERCE (1): elongated Rail Lance piercing all enemies in a line (stops only on walls / max range)
## - BOOMERANG (2): flat Arcane Chakram disc that pierces outward and curves back to shooter
## - HOMING (3): Seeker Barrage missile that steers smoothly toward nearby active enemies

enum FlightMode {
	BOLT = 0,
	PIERCE = 1,
	BOOMERANG = 2,
	HOMING = 3,
	SWARM_HOMING = 4,     ## Swarm Pods micro-missile (0.14s outward fan -> smooth homing lock)
	EXPLOSIVE_SHELL = 5,  ## Siege Cannon heavy shell (detonates 2.8m shockwave on hit or max range)
	CLUSTER_WARHEAD = 6,  ## Cluster Seeker warhead (splits into 4 homing bomblets at 7.2m or impact)
	SNIPER_BOLT = 7       ## Gauss Longbow bolt (+45% bonus damage scaling with travel distance)
}

@export var speed: float = 24.0
@export var damage: float = 10.0
const DEFAULT_MAX_RANGE: float = 12.5

var direction: Vector3 = Vector3.FORWARD
var traveled_distance: float = 0.0
var shooter_id: int = 0
var _max_range: float = DEFAULT_MAX_RANGE
var _proc_coeff: float = 1.0
var _flight_mode: int = FlightMode.BOLT
var _returning: bool = false
var _lifetime: float = 0.0
var _shooter_node: Node3D = null
var _shooter_stats: Object = null
var _shooter_rid: RID = RID()
var _tint_color: Color = Color(1.0, 0.88, 0.42, 1.0)
var _payload_triggered: bool = false
var _is_active: bool = false

# Pre-allocated raycast query, exclude list & pierced enemy tracker (zero 60Hz GC allocations)
var _ray_query: PhysicsRayQueryParameters3D = null
var _exclude_rids: Array[RID] = []
var _hit_enemy_ids: Array[int] = []

static var _shooter_cache: Dictionary = {} # peer_id (int) -> CollisionObject3D
static var _tint_mats: Dictionary = {}     # color_html (String) -> StandardMaterial3D

var pool: Node = null

@onready var mesh_inst: MeshInstance3D = $MeshInstance3D
@onready var trail: Trail3D = $Trail3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D


static func _get_tint_mat(col: Color) -> StandardMaterial3D:
	var key: String = col.to_html(false)
	if _tint_mats.has(key):
		return _tint_mats[key] as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col.lightened(0.18)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 1.6
	_tint_mats[key] = mat
	return mat


func setup(p_shooter_id: int, p_start_pos: Vector3, p_dir: Vector3, p_speed: float = -1.0) -> void:
	activate(p_shooter_id, p_start_pos, p_dir, p_speed)


## Legacy activation signature
func activate(p_shooter_id: int, p_start_pos: Vector3, p_dir: Vector3, p_speed: float = -1.0) -> void:
	var use_spd: float = p_speed if p_speed > 0.0 else 24.0
	activate_combat(
		p_shooter_id,
		p_start_pos,
		p_dir,
		use_spd,
		DEFAULT_MAX_RANGE,
		10.0,
		1.0,
		FlightMode.BOLT,
		Color(1.0, 0.88, 0.42, 1.0),
		null,
		null
	)


## Full zero-allocation combat projectile activation
func activate_combat(
	p_shooter_id: int,
	p_start_pos: Vector3,
	p_dir: Vector3,
	p_speed: float,
	p_max_range: float,
	p_damage: float,
	p_proc_coeff: float,
	p_flight_mode: int,
	p_tint: Color,
	p_shooter_node: Node3D,
	p_shooter_stats: Object
) -> void:
	shooter_id = p_shooter_id
	_shooter_node = p_shooter_node
	_shooter_stats = p_shooter_stats
	if _shooter_node != null and is_instance_valid(_shooter_node) and _shooter_node is CollisionObject3D:
		_shooter_rid = (_shooter_node as CollisionObject3D).get_rid()
	else:
		_shooter_rid = _resolve_shooter_rid(p_shooter_id)

	_reset_ray_exclusions()
	_hit_enemy_ids.clear()

	speed = maxf(2.0, p_speed)
	_max_range = maxf(1.5, p_max_range)
	damage = maxf(0.1, p_damage)
	_proc_coeff = clampf(p_proc_coeff, 0.0, 2.0)
	_flight_mode = p_flight_mode
	_tint_color = p_tint
	_payload_triggered = false
	_returning = false
	_lifetime = 0.0
	traveled_distance = 0.0
	direction = p_dir.normalized() if p_dir.length_squared() > 0.0001 else Vector3.FORWARD

	_apply_mode_visuals(p_tint)

	if is_inside_tree():
		global_position = p_start_pos
		if direction.length_squared() > 0.001:
			look_at(global_position + direction, Vector3.UP)
		reset_physics_interpolation()
	else:
		position = p_start_pos
		if direction.length_squared() > 0.001:
			transform = transform.looking_at(position + direction, Vector3.UP)

	var trail_node: Trail3D = _get_trail_node()
	if trail_node:
		trail_node.trail_color = Color(p_tint.r, p_tint.g, p_tint.b, 0.30)
		trail_node.activate(p_start_pos, direction)

	_is_active = true
	visible = true
	set_physics_process(true)
	set_deferred("monitoring", true)
	set_deferred("monitorable", true)

	var col: CollisionShape3D = _get_col_shape()
	if col:
		col.set_deferred("disabled", false)


func _reset_ray_exclusions() -> void:
	_exclude_rids.clear()
	_exclude_rids.append(get_rid())
	if _shooter_rid.is_valid():
		_exclude_rids.append(_shooter_rid)

	if _ray_query == null:
		_ray_query = PhysicsRayQueryParameters3D.new()
		_ray_query.collide_with_areas = true
		_ray_query.collide_with_bodies = true
		_ray_query.hit_from_inside = true
	_ray_query.collision_mask = collision_mask
	_ray_query.exclude = _exclude_rids


func _apply_mode_visuals(tint: Color) -> void:
	if not mesh_inst:
		mesh_inst = get_node_or_null("MeshInstance3D") as MeshInstance3D
	var trail_node: Trail3D = _get_trail_node()

	if mesh_inst:
		mesh_inst.material_override = _get_tint_mat(tint)
		match _flight_mode:
			FlightMode.PIERCE:
				mesh_inst.scale = Vector3(0.85, 0.85, 3.4)
			FlightMode.BOOMERANG:
				mesh_inst.scale = Vector3(2.5, 0.30, 2.5)
			FlightMode.HOMING, FlightMode.SWARM_HOMING:
				mesh_inst.scale = Vector3(0.90, 0.90, 1.55)
			FlightMode.EXPLOSIVE_SHELL:
				mesh_inst.scale = Vector3(1.85, 1.85, 2.55)
			FlightMode.CLUSTER_WARHEAD:
				mesh_inst.scale = Vector3(1.55, 1.55, 2.15)
			FlightMode.SNIPER_BOLT:
				mesh_inst.scale = Vector3(0.72, 0.72, 4.20)
			_:
				mesh_inst.scale = Vector3.ONE

	if trail_node:
		match _flight_mode:
			FlightMode.PIERCE:
				trail_node.trail_width = 0.15
			FlightMode.BOOMERANG:
				trail_node.trail_width = 0.14
			FlightMode.HOMING, FlightMode.SWARM_HOMING:
				trail_node.trail_width = 0.09
			FlightMode.EXPLOSIVE_SHELL:
				trail_node.trail_width = 0.22
			FlightMode.CLUSTER_WARHEAD:
				trail_node.trail_width = 0.17
			FlightMode.SNIPER_BOLT:
				trail_node.trail_width = 0.18
			_:
				trail_node.trail_width = 0.08


func deactivate() -> void:
	_is_active = false
	_shooter_node = null
	_shooter_stats = null
	set_physics_process(false)
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	visible = false

	var col: CollisionShape3D = _get_col_shape()
	if col:
		col.set_deferred("disabled", true)

	var trail_node: Trail3D = _get_trail_node()
	if trail_node:
		trail_node.deactivate()


func despawn() -> void:
	if pool and pool.has_method("release"):
		pool.release(self)
	else:
		queue_free()


func on_pool_release() -> void:
	deactivate()


func _resolve_shooter_rid(p_shooter_id: int) -> RID:
	if _shooter_cache.has(p_shooter_id):
		var cached: Variant = _shooter_cache[p_shooter_id]
		if cached != null and is_instance_valid(cached):
			return (cached as CollisionObject3D).get_rid()
		_shooter_cache.erase(p_shooter_id)
	if is_inside_tree():
		var target_name: String = str(p_shooter_id)
		for ch in get_tree().get_nodes_in_group("characters"):
			if ch.name == target_name and ch is CollisionObject3D:
				_shooter_cache[p_shooter_id] = ch
				return (ch as CollisionObject3D).get_rid()
	return RID()


func _get_col_shape() -> CollisionShape3D:
	if not collision_shape:
		collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	return collision_shape


func _get_trail_node() -> Trail3D:
	if not trail:
		trail = get_node_or_null("Trail3D") as Trail3D
	return trail


func _ready() -> void:
	collision_mask = 5 # Layer 1 (World & VineBarriers) + Layer 3 (Enemies & Hurtboxes)
	_ray_query = PhysicsRayQueryParameters3D.new()
	_ray_query.collide_with_areas = true
	_ray_query.collide_with_bodies = true
	_ray_query.hit_from_inside = true
	_ray_query.collision_mask = collision_mask

	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	if not _is_active:
		return

	_lifetime += delta
	if _lifetime > 4.5:
		despawn()
		return

	# Steering updates for Boomerang & Homing modes
	if _flight_mode == FlightMode.BOOMERANG and _returning:
		if _shooter_node != null and is_instance_valid(_shooter_node) and _shooter_node.visible:
			var to_player: Vector3 = (_shooter_node.global_position + Vector3(0.0, 0.35, 0.0)) - global_position
			to_player.y = 0.0
			var dist_back: float = to_player.length()
			if dist_back <= 0.65:
				despawn()
				return
			direction = direction.lerp(to_player / dist_back, clampf(14.0 * delta, 0.0, 1.0)).normalized()
		else:
			if traveled_distance >= _max_range * 2.1:
				despawn()
				return
	elif _flight_mode == FlightMode.HOMING or (_flight_mode == FlightMode.SWARM_HOMING and _lifetime >= 0.14):
		var target_enemy: Node3D = _find_nearest_enemy(18.0)
		if target_enemy != null:
			var to_e: Vector3 = (target_enemy.global_position + Vector3(0.0, 0.35, 0.0)) - global_position
			to_e.y = 0.0
			if to_e.length_squared() > 0.01:
				var turn_rate: float = 14.5 if _flight_mode == FlightMode.SWARM_HOMING else 11.5
				direction = direction.lerp(to_e.normalized(), clampf(turn_rate * delta, 0.0, 1.0)).normalized()

	if direction.length_squared() > 0.001 and _flight_mode != FlightMode.BOOMERANG:
		look_at(global_position + direction, Vector3.UP)

	var step: float = speed * delta
	var cur_from: Vector3 = global_position
	var next_pos: Vector3 = cur_from + direction * step
	var is_piercing: bool = (_flight_mode == FlightMode.PIERCE or _flight_mode == FlightMode.BOOMERANG)

	if is_inside_tree():
		var dome_bosses: Array[Node] = get_tree().get_nodes_in_group("aegis_dome_bosses")
		for db in dome_bosses:
			if db == null or not is_instance_valid(db):
				continue
			if db.has_method("is_aegis_dome_active") and bool(db.call("is_aegis_dome_active")):
				var dome_r: float = float(db.call("get_aegis_dome_radius"))
				var shooter_outside: bool = true
				if _shooter_node != null and is_instance_valid(_shooter_node):
					var s_dx: float = _shooter_node.global_position.x - (db as Node3D).global_position.x
					var s_dz: float = _shooter_node.global_position.z - (db as Node3D).global_position.z
					shooter_outside = (s_dx * s_dx + s_dz * s_dz) > (dome_r * dome_r)
				if shooter_outside:
					var n_dx: float = next_pos.x - (db as Node3D).global_position.x
					var n_dz: float = next_pos.z - (db as Node3D).global_position.z
					if (n_dx * n_dx + n_dz * n_dz) <= (dome_r + 0.28) * (dome_r + 0.28):
						if db.has_method("notify_dome_deflect"):
							db.call("notify_dome_deflect", next_pos)
						despawn()
						return

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space_state and _ray_query:
		var safety: int = 0
		while safety < 5:
			safety += 1
			_ray_query.from = cur_from
			_ray_query.to = next_pos
			_ray_query.exclude = _exclude_rids
			var hit: Dictionary = space_state.intersect_ray(_ray_query)
			if hit.is_empty():
				break

			var collider: Object = hit.get("collider", null)
			var hit_pos: Vector3 = hit["position"]
			var hit_is_enemy: bool = _is_enemy_collider(collider)

			if hit_is_enemy:
				_apply_enemy_hit(collider)
				if not is_piercing:
					global_position = hit_pos
					_trigger_impact_payload(hit_pos)
					despawn()
					return
				# Piercing / Boomerang continues through enemies!
				cur_from = hit_pos + direction * 0.02
				continue
			else:
				# Hit Layer 1 World Wall or VineBarrier
				if _flight_mode == FlightMode.BOOMERANG and not _returning:
					global_position = hit_pos - direction * 0.08
					_begin_boomerang_return()
					return
				global_position = hit_pos
				_trigger_impact_payload(hit_pos)
				despawn()
				return

	global_position = next_pos
	traveled_distance += step

	if _flight_mode == FlightMode.CLUSTER_WARHEAD and traveled_distance >= 7.2:
		_trigger_impact_payload(global_position)
		despawn()
		return

	if _flight_mode == FlightMode.BOOMERANG:
		if not _returning and traveled_distance >= _max_range:
			_begin_boomerang_return()
		elif _returning and traveled_distance >= _max_range * 2.4:
			despawn()
	else:
		if traveled_distance >= _max_range:
			_trigger_impact_payload(global_position)
			despawn()


func _trigger_impact_payload(impact_pos: Vector3) -> void:
	if _payload_triggered:
		return
	if _flight_mode == FlightMode.EXPLOSIVE_SHELL:
		_payload_triggered = true
		if ProjectilePool and ProjectilePool.has_method("spawn_zone_effect"):
			ProjectilePool.call(
				"spawn_zone_effect",
				5, # ZoneMode.INSTANT_BLAST
				impact_pos,
				2.8,
				damage * 0.65,
				0.26,
				"cannon_blast",
				_tint_color,
				_shooter_stats,
				0.0,
				null,
				0.0,
				_shooter_node,
				direction
			)
	elif _flight_mode == FlightMode.CLUSTER_WARHEAD:
		_payload_triggered = true
		if ProjectilePool and ProjectilePool.has_method("spawn_combat_projectile"):
			var sub_dmg: float = damage * 0.45
			var s_id: int = shooter_id
			var s_node: Node3D = _shooter_node
			var s_stats: Object = _shooter_stats
			var s_col: Color = _tint_color.lightened(0.15)
			for k in range(4):
				var ang: float = float(k) * (TAU / 4.0) + 0.4
				var b_dir := Vector3(cos(ang), 0.0, sin(ang))
				ProjectilePool.call(
					"spawn_combat_projectile",
					s_id,
					impact_pos + Vector3(0.0, 0.25, 0.0) + b_dir * 0.22,
					b_dir,
					21.5,
					12.0,
					sub_dmg,
					0.40,
					FlightMode.SWARM_HOMING,
					s_col,
					s_node,
					s_stats
				)


func _begin_boomerang_return() -> void:
	_returning = true
	_hit_enemy_ids.clear()
	_reset_ray_exclusions()
	direction = -direction


func _find_nearest_enemy(max_dist: float) -> Node3D:
	if not is_inside_tree():
		return null
	var best: Node3D = null
	var best_d2: float = max_dist * max_dist
	var enemies: Array[Node] = get_tree().get_nodes_in_group("active_enemies")
	for e_node in enemies:
		var e3d: Node3D = e_node as Node3D
		if e3d == null or not e3d.visible:
			continue
		var dx: float = e3d.global_position.x - global_position.x
		var dz: float = e3d.global_position.z - global_position.z
		var d2: float = dx * dx + dz * dz
		if d2 < best_d2:
			best_d2 = d2
			best = e3d
	return best


func _is_enemy_collider(target: Object) -> bool:
	if target == null:
		return false
	if target is EnemySphere or target is HurtboxComponent:
		return true
	if target.has_method("is_targetable_prop") and bool(target.call("is_targetable_prop")):
		return true
	return false


func _resolve_enemy_sphere(target: Object) -> EnemySphere:
	if target is EnemySphere:
		return target as EnemySphere
	if target is HurtboxComponent:
		var p: Node = (target as Node).get_parent()
		if p is EnemySphere:
			return p as EnemySphere
	return null


func _apply_enemy_hit(target: Object) -> bool:
	if target == null:
		return false

	var effective_dmg: float = damage
	if _flight_mode == FlightMode.SNIPER_BOLT:
		effective_dmg = damage * lerpf(1.0, 1.45, clampf(traveled_distance / 15.0, 0.0, 1.0))

	var atk_pos: Vector3 = _shooter_node.global_position if (_shooter_node != null and is_instance_valid(_shooter_node)) else global_position

	var es: EnemySphere = _resolve_enemy_sphere(target)
	if es != null:
		if _hit_enemy_ids.has(es.enemy_id):
			_exclude_enemy_rids(es)
			return false
		_hit_enemy_ids.append(es.enemy_id)
		_exclude_enemy_rids(es)
		if es.has_method("apply_combat_hit"):
			es.call("apply_combat_hit", effective_dmg, direction, _proc_coeff, _shooter_stats, atk_pos)
		elif es.hurtbox_comp:
			es.hurtbox_comp.apply_hit(effective_dmg, direction)
		return true

	var hit_obj: Node = null
	if target is HurtboxComponent:
		var p_node: Node = (target as Node).get_parent()
		if p_node != null and p_node.has_method("apply_combat_hit"):
			hit_obj = p_node
	elif target is Node and (target as Node).has_method("apply_combat_hit"):
		hit_obj = target as Node

	if hit_obj != null:
		var inst_key: int = -(int(hit_obj.get_instance_id()) & 0x7FFFFFFF)
		if _hit_enemy_ids.has(inst_key):
			return false
		_hit_enemy_ids.append(inst_key)
		if hit_obj is CollisionObject3D:
			var hr: RID = (hit_obj as CollisionObject3D).get_rid()
			if hr.is_valid() and not _exclude_rids.has(hr):
				_exclude_rids.append(hr)
		var hb_var: Variant = hit_obj.get("hurtbox_comp")
		if hb_var is CollisionObject3D:
			var hbr: RID = (hb_var as CollisionObject3D).get_rid()
			if hbr.is_valid() and not _exclude_rids.has(hbr):
				_exclude_rids.append(hbr)
		hit_obj.call("apply_combat_hit", effective_dmg, direction, _proc_coeff, _shooter_stats, atk_pos)
		return true

	if target is HurtboxComponent:
		if target is CollisionObject3D:
			var r: RID = (target as CollisionObject3D).get_rid()
			if r.is_valid() and not _exclude_rids.has(r):
				_exclude_rids.append(r)
		(target as HurtboxComponent).apply_hit(effective_dmg, direction)
		return true

	return false


func _exclude_enemy_rids(es: EnemySphere) -> void:
	var body_rid: RID = es.get_rid()
	if body_rid.is_valid() and not _exclude_rids.has(body_rid):
		_exclude_rids.append(body_rid)
	if es.hurtbox_comp != null:
		var hb_rid: RID = es.hurtbox_comp.get_rid()
		if hb_rid.is_valid() and not _exclude_rids.has(hb_rid):
			_exclude_rids.append(hb_rid)


func _on_body_entered(body: Node) -> void:
	if not _is_active:
		return
	if body.name == str(shooter_id):
		return

	if _is_enemy_collider(body):
		_apply_enemy_hit(body)
		if _flight_mode != FlightMode.PIERCE and _flight_mode != FlightMode.BOOMERANG:
			_trigger_impact_payload(global_position)
			despawn()
	else:
		if _flight_mode == FlightMode.BOOMERANG and not _returning:
			_begin_boomerang_return()
		else:
			_trigger_impact_payload(global_position)
			despawn()


func _on_area_entered(area: Area3D) -> void:
	if not _is_active:
		return
	if _is_enemy_collider(area):
		_apply_enemy_hit(area)
		if _flight_mode != FlightMode.PIERCE and _flight_mode != FlightMode.BOOMERANG:
			_trigger_impact_payload(global_position)
			despawn()
