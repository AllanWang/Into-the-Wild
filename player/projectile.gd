extends Area3D

const SPEED: float = 22.0
const MAX_RANGE: float = 10.0

var direction: Vector3 = Vector3.FORWARD
var traveled_distance: float = 0.0
var shooter_id: int = 0

func setup(p_shooter_id: int, p_start_pos: Vector3, p_dir: Vector3) -> void:
	shooter_id = p_shooter_id
	direction = p_dir.normalized()
	global_position = p_start_pos
	# Point projectile mesh along travel direction
	if direction.length_squared() > 0.001:
		look_at(global_position + direction, Vector3.UP)

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func _physics_process(delta: float) -> void:
	var step = SPEED * delta
	global_position += direction * step
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
