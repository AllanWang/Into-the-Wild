extends Node3D

@export var bullet_speed: float = 14.0
@export_range(0.0, 1.0, 0.05) var trail_alpha: float = 0.2
@export var trail_width: float = 0.08
@export var trail_points: int = 24
@export var spawn_interval: float = 0.45
@export var record_gif_frames: bool = false
@export var max_frames_to_record: int = 40

const PROJ_SCENE = preload("res://player/projectile.tscn")

var _spawn_timer: float = 0.0
var _frame_count: int = 0

func _ready() -> void:
	_spawn()
	if record_gif_frames:
		_record_frames()

func _physics_process(delta: float) -> void:
	_spawn_timer += delta
	if _spawn_timer >= spawn_interval:
		_spawn_timer = 0.0
		_spawn()

func _spawn() -> void:
	var p: Area3D = PROJ_SCENE.instantiate()
	add_child(p)
	p.setup(0, Vector3(-2.2, 0.15, 0.0), Vector3.RIGHT, bullet_speed)
	
	# Apply configured trail properties to spawned projectile
	var trail: Trail3D = p.get_node_or_null("Trail3D") as Trail3D
	if trail:
		var col: Color = trail.trail_color
		col.a = trail_alpha
		trail.trail_color = col
		trail.trail_width = trail_width
		trail.max_points = trail_points

func _record_frames() -> void:
	for i in range(8):
		await RenderingServer.frame_post_draw
	
	var out_dir = "res://temp_frames"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	
	while _frame_count < max_frames_to_record:
		await RenderingServer.frame_post_draw
		var img = get_viewport().get_texture().get_image()
		if img and not img.is_empty():
			img.save_png("%s/frame_%03d.png" % [out_dir, _frame_count])
			_frame_count += 1
	print("RECORDING_FRAMES_FINISHED")
