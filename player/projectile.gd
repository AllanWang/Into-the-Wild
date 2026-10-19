extends Area3D

@export var speed: float = 14.0
const MAX_RANGE: float = 10.0

var direction: Vector3 = Vector3.FORWARD
var traveled_distance: float = 0.0
var shooter_id: int = 0

var pool: Node = null

@onready var trail: Trail3D = $Trail3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

func setup(p_shooter_id: int, p_start_pos: Vector3, p_dir: Vector3, p_speed: float = -1.0) -> void:
	activate(p_shooter_id, p_start_pos, p_dir, p_speed)

## Activates the projectile when acquired from an object pool or spawned.
func activate(p_shooter_id: int, p_start_pos: Vector3, p_dir: Vector3, p_speed: float = -1.0) -> void:
	shooter_id = p_shooter_id
	direction = p_dir.normalized()
	traveled_distance = 0.0
	if p_speed > 0.0:
		speed = p_speed
		
	if is_inside_tree():
		global_position = p_start_pos
		if direction.length_squared() > 0.001:
			look_at(global_position + direction, Vector3.UP)
	else:
		position = p_start_pos
		if direction.length_squared() > 0.001:
			transform = transform.looking_at(position + direction, Vector3.UP)
			
	visible = true
	set_physics_process(true)
	monitoring = true
	monitorable = true
	
	var col := _get_col_shape()
	if col:
		col.set_deferred("disabled", false)
		
	var tr := _get_trail_node()
	if tr:
		tr.activate()

## Deactivates the projectile when returned to an object pool.
func deactivate() -> void:
	set_physics_process(false)
	monitoring = false
	monitorable = false
	visible = false
	
	var col := _get_col_shape()
	if col:
		col.set_deferred("disabled", true)
		
	var tr := _get_trail_node()
	if tr:
		tr.deactivate()

## Returns to pool if pooled, otherwise frees instance.
func despawn() -> void:
	if pool and pool.has_method("release"):
		pool.release(self)
	else:
		queue_free()

func on_pool_release() -> void:
	deactivate()

func _get_col_shape() -> CollisionShape3D:
	if not collision_shape:
		collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	return collision_shape

func _get_trail_node() -> Trail3D:
	if not trail:
		trail = get_node_or_null("Trail3D") as Trail3D
	return trail

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func _physics_process(delta: float) -> void:
	var step = speed * delta
	var next_pos = global_position + direction * step
	
	# Raycast check along step vector to prevent tunneling through thin walls / boundary geometry
	var space_state = get_world_3d().direct_space_state
	if space_state:
		var query = PhysicsRayQueryParameters3D.create(global_position, next_pos, collision_mask)
		var exclude_rids: Array[RID] = [get_rid()]
		var shooter = get_node_or_null(NodePath("../" + str(shooter_id)))
		if shooter and shooter is CollisionObject3D:
			exclude_rids.append(shooter.get_rid())
		query.exclude = exclude_rids
		
		var hit = space_state.intersect_ray(query)
		if not hit.is_empty():
			global_position = hit.position
			despawn()
			return
	
	global_position = next_pos
	traveled_distance += step
	if traveled_distance >= MAX_RANGE:
		despawn()

func _on_body_entered(body: Node) -> void:
	# Ignore shooter if body matches shooter peer ID
	if body.name == str(shooter_id):
		return
	despawn()

func _on_area_entered(_area: Area3D) -> void:
	# Despawn on impact with other combat areas/hitboxes
	despawn()
