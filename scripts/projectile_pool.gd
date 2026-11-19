extends "res://scripts/node_pool.gd"

## Global Autoload pool managing player projectiles, AoE combat zones, and Shock lightning arcs.

const NodePoolScript = preload("res://scripts/node_pool.gd")
const PROJECTILE_SCENE: PackedScene = preload("res://player/projectile.tscn")
const ZONE_SCENE: PackedScene = preload("res://world/combat_zone_effect.tscn")
const ARC_SCENE: PackedScene = preload("res://world/lightning_arc_effect.tscn")
const EnemyHazardScript = preload("res://world/enemy_hazard_effect.gd")

var _zone_pool: NodePool = null
var _arc_pool: NodePool = null
var _enemy_hazards: Array[Node3D] = []


func _init() -> void:
	scene = PROJECTILE_SCENE
	initial_size = 48
	max_size = 160
	can_grow = true


func _ready() -> void:
	super._ready()
	_ensure_sub_pools()

	var net: Node = get_node_or_null("/root/NetworkManager")
	if net and net.has_signal("server_disconnected"):
		net.server_disconnected.connect(release_all)


func _ensure_sub_pools() -> void:
	if _zone_pool != null:
		return

	_zone_pool = NodePoolScript.new()
	_zone_pool.name = "CombatZonePool"
	_zone_pool.scene = ZONE_SCENE
	_zone_pool.initial_size = 10
	_zone_pool.max_size = 32
	_zone_pool.can_grow = true
	add_child(_zone_pool)

	_arc_pool = NodePoolScript.new()
	_arc_pool.name = "LightningArcPool"
	_arc_pool.scene = ARC_SCENE
	_arc_pool.initial_size = 14
	_arc_pool.max_size = 48
	_arc_pool.can_grow = true
	add_child(_arc_pool)

	for i in range(24):
		_create_enemy_hazard(i)


func _create_enemy_hazard(idx: int) -> Node3D:
	var hz: Node3D = EnemyHazardScript.new() as Node3D
	hz.name = "EnemyHazard_%d" % idx
	add_child(hz)
	if hz.has_method("deactivate"):
		hz.call("deactivate")
	_enemy_hazards.append(hz)
	return hz


func _acquire_enemy_hazard() -> Node3D:
	_ensure_sub_pools()
	for h in _enemy_hazards:
		if h != null and is_instance_valid(h) and h.has_method("is_available") and bool(h.call("is_available")):
			return h
	return _create_enemy_hazard(_enemy_hazards.size())


func release_all() -> void:
	super.release_all()
	if _zone_pool:
		_zone_pool.release_all()
	if _arc_pool:
		_arc_pool.release_all()
	for h in _enemy_hazards:
		if h != null and is_instance_valid(h) and h.has_method("deactivate"):
			h.call("deactivate")


func spawn_enemy_orb(
	p_start: Vector3,
	p_dir: Vector3,
	p_speed: float,
	p_range: float,
	p_damage: float,
	p_color: Color,
	p_is_lance: bool,
	p_players_root: Node3D
) -> Node3D:
	var hz: Node3D = _acquire_enemy_hazard()
	if hz and hz.has_method("activate_orb"):
		hz.call("activate_orb", p_start, p_dir, p_speed, p_range, p_damage, p_color, p_is_lance, p_players_root)
	return hz


func spawn_enemy_sightline(
	p_origin: Vector3,
	p_dir: Vector3,
	p_length: float,
	p_duration: float,
	p_color: Color
) -> Node3D:
	var hz: Node3D = _acquire_enemy_hazard()
	if hz and hz.has_method("activate_sightline"):
		hz.call("activate_sightline", p_origin, p_dir, p_length, p_duration, p_color)
	return hz


func spawn_enemy_ground_hazard(
	p_mode: int,
	p_origin: Vector3,
	p_target: Vector3,
	p_radius: float,
	p_inner_radius: float,
	p_damage: float,
	p_telegraph_s: float,
	p_pool_duration_s: float,
	p_color: Color,
	p_shake: float,
	p_players_root: Node3D
) -> Node3D:
	var hz: Node3D = _acquire_enemy_hazard()
	if hz and hz.has_method("activate_ground_hazard"):
		hz.call(
			"activate_ground_hazard",
			p_mode,
			p_origin,
			p_target,
			p_radius,
			p_inner_radius,
			p_damage,
			p_telegraph_s,
			p_pool_duration_s,
			p_color,
			p_shake,
			p_players_root
		)
	return hz


func spawn_enemy_clock_sector(
	p_center: Vector3,
	p_radius: float,
	p_safe_angle: float,
	p_safe_half_width: float,
	p_damage: float,
	p_telegraph_s: float,
	p_color: Color,
	p_shake: float,
	p_players_root: Node3D
) -> Node3D:
	var hz: Node3D = _acquire_enemy_hazard()
	if hz and hz.has_method("activate_clock_sector"):
		hz.call(
			"activate_clock_sector",
			p_center,
			p_radius,
			p_safe_angle,
			p_safe_half_width,
			p_damage,
			p_telegraph_s,
			p_color,
			p_shake,
			p_players_root
		)
	return hz


func spawn_enemy_clock_safe_circle(
	p_center: Vector3,
	p_radius: float,
	p_safe_pos: Vector3,
	p_safe_radius: float,
	p_damage: float,
	p_telegraph_s: float,
	p_color: Color,
	p_shake: float,
	p_players_root: Node3D
) -> Node3D:
	var hz: Node3D = _acquire_enemy_hazard()
	if hz and hz.has_method("activate_clock_safe_circle"):
		hz.call(
			"activate_clock_safe_circle",
			p_center,
			p_radius,
			p_safe_pos,
			p_safe_radius,
			p_damage,
			p_telegraph_s,
			p_color,
			p_shake,
			p_players_root
		)
	return hz


func spawn_enemy_vine_slam_ribbon(
	p_origin: Vector3,
	p_dir: Vector3,
	p_length: float,
	p_width: float,
	p_damage: float,
	p_telegraph_s: float,
	p_color: Color,
	p_shake: float,
	p_players_root: Node3D
) -> Node3D:
	var hz: Node3D = _acquire_enemy_hazard()
	if hz and hz.has_method("activate_vine_slam_ribbon"):
		hz.call(
			"activate_vine_slam_ribbon",
			p_origin,
			p_dir,
			p_length,
			p_width,
			p_damage,
			p_telegraph_s,
			p_color,
			p_shake,
			p_players_root
		)
	return hz


## Legacy simple spawn signature
func spawn(p_shooter_id: int, p_pos: Vector3, p_dir: Vector3, p_speed: float = -1.0) -> Node:
	var proj := acquire()
	if not proj:
		return null
	if proj.has_method("activate"):
		proj.call("activate", p_shooter_id, p_pos, p_dir, p_speed)
	return proj


## Rich zero-allocation weapon/artifact projectile spawn
func spawn_combat_projectile(
	p_shooter_id: int,
	p_pos: Vector3,
	p_dir: Vector3,
	p_speed: float,
	p_max_range: float,
	p_damage: float,
	p_proc_coeff: float,
	p_flight_mode: int,
	p_tint: Color,
	p_shooter_node: Node3D,
	p_shooter_stats: Object
) -> Node:
	var proj := acquire()
	if not proj:
		return null
	if proj.has_method("activate_combat"):
		proj.call(
			"activate_combat",
			p_shooter_id,
			p_pos,
			p_dir,
			p_speed,
			p_max_range,
			p_damage,
			p_proc_coeff,
			p_flight_mode,
			p_tint,
			p_shooter_node,
			p_shooter_stats
		)
	return proj


func spawn_zone_effect(
	p_mode: int,
	p_pos: Vector3,
	p_radius: float,
	p_damage: float,
	p_duration: float,
	p_color_key: String,
	p_color: Color,
	p_shooter_stats: Object = null,
	p_slow_ratio: float = 0.0,
	p_follow_target: Node3D = null,
	p_leech_ratio: float = 0.0,
	p_caster_node: Node3D = null,
	p_aim_dir: Vector3 = Vector3.FORWARD
) -> Node:
	_ensure_sub_pools()
	var z := _zone_pool.acquire()
	if z and z.has_method("activate_zone"):
		z.call(
			"activate_zone",
			p_mode,
			p_pos,
			p_radius,
			p_damage,
			p_duration,
			p_color_key,
			p_color,
			p_shooter_stats,
			p_slow_ratio,
			p_follow_target,
			p_leech_ratio,
			p_caster_node,
			p_aim_dir
		)
	return z


func spawn_lightning_arc(from_pos: Vector3, to_pos: Vector3) -> Node:
	_ensure_sub_pools()
	var arc := _arc_pool.acquire()
	if arc and arc.has_method("activate_arc"):
		arc.call("activate_arc", from_pos, to_pos)
	return arc
