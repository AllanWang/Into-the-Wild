extends "res://scripts/node_pool.gd"

## Dedicated high-performance pool for combat projectiles and their trails.
## Can run as a global Autoload singleton or as a local level node.

const PROJECTILE_SCENE: PackedScene = preload("res://player/projectile.tscn")

func _init() -> void:
	scene = PROJECTILE_SCENE
	initial_size = 32
	max_size = 128
	can_grow = true

func _ready() -> void:
	super._ready()
	
	# Automatically return all bullets to the pool when disconnecting from a game session
	var net: Node = get_node_or_null("/root/NetworkManager")
	if net and net.has_signal("server_disconnected"):
		net.server_disconnected.connect(release_all)

## Convenience method to acquire and initialize a projectile in one call.
func spawn(p_shooter_id: int, p_pos: Vector3, p_dir: Vector3, p_speed: float = -1.0) -> Node:
	var proj := acquire()
	if not proj:
		return null
		
	if proj.has_method("activate"):
		proj.activate(p_shooter_id, p_pos, p_dir, p_speed)
	elif proj.has_method("setup"):
		proj.setup(p_shooter_id, p_pos, p_dir, p_speed)
		
	return proj
