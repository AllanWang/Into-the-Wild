extends "res://scripts/node_pool.gd"

## Global Autoload pool managing player projectiles, AoE combat zones, and Shock lightning arcs.

const NodePoolScript = preload("res://scripts/node_pool.gd")
const PROJECTILE_SCENE: PackedScene = preload("res://player/projectile.tscn")
const ZONE_SCENE: PackedScene = preload("res://world/combat_zone_effect.tscn")
const ARC_SCENE: PackedScene = preload("res://world/lightning_arc_effect.tscn")

var _zone_pool: NodePool = null
var _arc_pool: NodePool = null


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


func release_all() -> void:
	super.release_all()
	if _zone_pool:
		_zone_pool.release_all()
	if _arc_pool:
		_arc_pool.release_all()


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
