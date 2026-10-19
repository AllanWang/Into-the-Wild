extends Area3D

@export var speed: float = 14.0
const MAX_RANGE: float = 10.0

var direction: Vector3 = Vector3.FORWARD
var traveled_distance: float = 0.0
var shooter_id: int = 0

func setup(p_shooter_id: int, p_start_pos: Vector3, p_dir: Vector3, p_speed: float = -1.0) -> void:
	shooter_id = p_shooter_id
	direction = p_dir.normalized()
	if is_inside_tree():
		global_position = p_start_pos
		if direction.length_squared() > 0.001:
			look_at(global_position + direction, Vector3.UP)
	else:
		position = p_start_pos
		if direction.length_squared() > 0.001:
			transform = transform.looking_at(position + direction, Vector3.UP)
	if p_speed > 0.0:
		speed = p_speed

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
			queue_free()
			return
	
	global_position = next_pos
	traveled_distance += step
	if traveled_distance >= MAX_RANGE:
		queue_free()

func _on_body_entered(body: Node) -> void:
	# Ignore shooter if body matches shooter peer ID
	if body.name == str(shooter_id):
		return
	queue_free()

func _on_area_entered(_area: Area3D) -> void:
	# Despawn on impact with other combat areas/hitboxes
	queue_free()
