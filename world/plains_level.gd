class_name PlainsLevel
extends Node3D

## Level controller for the procedurally generated plains.
## Orchestrates player spawning at generated spawn points,
## dynamic Camera3D tracking and overview inspection,
## and connects CharacterManager with the procedural grass.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const PlainsGeneratorScript = preload("res://world/plains_generator.gd")
const PlainsGraphScript = preload("res://world/plains_graph.gd")

@onready var generator: Node3D = $PlainsGenerator
@onready var players_container: Node3D = $Players
@onready var camera: Camera3D = $Camera3D
@onready var character_manager: Node = $CharacterManager

# HUD elements
@onready var info_label: Label = %InfoLabel
@onready var debug_overlay: MarginContainer = %DebugOverlay
@onready var stats_label: Label = %StatsLabel
@onready var overview_button: Button = %OverviewButton
@onready var regen_button: Button = %RegenButton
@onready var leave_button: Button = %LeaveButton

# Camera states
var camera_offset: Vector3 = Vector3(-400.0, 400.0, 400.0)
var is_overview_mode: bool = false
var normal_cam_size: float = 6.085
var overview_cam_size: float = 65.0
var map_center: Vector3 = Vector3.ZERO
var current_spawn_pos: Vector3 = Vector3.ZERO

func _ready() -> void:
	if not NetworkManager.peer:
		NetworkManager.host_game(0, "SoloPlayer")

	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)

	# Ensure buttons never capture keyboard focus so gameplay keys (e.g. Space for dash) are never hijacked
	leave_button.focus_mode = Control.FOCUS_NONE
	regen_button.focus_mode = Control.FOCUS_NONE
	overview_button.focus_mode = Control.FOCUS_NONE

	leave_button.pressed.connect(_on_leave_pressed)
	regen_button.pressed.connect(_on_regen_pressed)
	overview_button.pressed.connect(_on_overview_pressed)

	# Debug overlay and map overview are strictly for debug only
	if debug_overlay:
		debug_overlay.visible = OS.is_debug_build()

	generator.map_generated.connect(_on_map_generated)
	generator.graph_ready.connect(_on_graph_ready)

	if camera:
		camera.near = 1.0
		camera.far = 4000.0

	# If generator did not auto-run, trigger now
	if not generator.current_graph:
		generator.generate_map(generator.map_seed)

	_update_hud()
	NetworkManager.mark_client_ready()


func _physics_process(delta: float) -> void:
	if is_overview_mode:
		# Frame the whole map from the center
		var target_pos := map_center + camera_offset
		camera.global_position = camera.global_position.lerp(target_pos, clampf(8.0 * delta, 0.0, 1.0))
		camera.size = lerpf(camera.size, overview_cam_size, clampf(8.0 * delta, 0.0, 1.0))
	else:
		# Track local player
		var my_id: int = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
		var local_player: Node3D = players_container.get_node_or_null(str(my_id))
		if local_player and camera:
			var target_pos := local_player.global_position + camera_offset
			camera.global_position = camera.global_position.lerp(target_pos, clampf(10.0 * delta, 0.0, 1.0))
		camera.size = lerpf(camera.size, normal_cam_size, clampf(8.0 * delta, 0.0, 1.0))

func _on_map_generated(spawn_pos: Vector3, _goal_pos: Vector3) -> void:
	current_spawn_pos = spawn_pos

	# Connect CharacterManager to procedural foliage for physical step displacement
	if generator.foliage_multimesh_instance:
		character_manager.grass = generator.foliage_multimesh_instance

	_spawn_or_reposition_players()
	_update_stats_label()

func _on_graph_ready(graph: RefCounted) -> void:
	if graph.areas.is_empty():
		return
	var min_pt := Vector2(INF, INF)
	var max_pt := Vector2(-INF, -INF)
	for area in graph.areas:
		var half_sz: Vector2 = area.size * 0.5
		min_pt.x = minf(min_pt.x, area.center.x - half_sz.x)
		min_pt.y = minf(min_pt.y, area.center.y - half_sz.y)
		max_pt.x = maxf(max_pt.x, area.center.x + half_sz.x)
		max_pt.y = maxf(max_pt.y, area.center.y + half_sz.y)
	var center_2d: Vector2 = (min_pt + max_pt) * 0.5
	var span_2d: Vector2 = max_pt - min_pt
	var max_span: float = maxf(span_2d.x, span_2d.y)
	map_center = Vector3(center_2d.x, 0.0, center_2d.y)
	overview_cam_size = maxf(65.0, max_span * 0.95)

func _spawn_or_reposition_players() -> void:
	var player_dict := NetworkManager.players
	if player_dict.is_empty():
		# Solo fallback
		var solo_player := players_container.get_node_or_null("1")
		if not solo_player:
			solo_player = PLAYER_SCENE.instantiate()
			solo_player.name = "1"
			players_container.add_child(solo_player)
			solo_player.setup(1, {
				"name": "SoloPlayer",
				"color": Color(0.25, 0.6, 1.0)
			})
		solo_player.global_position = current_spawn_pos
	else:
		var peer_ids := player_dict.keys()
		var count: int = peer_ids.size()
		for i in range(count):
			var peer_id: int = peer_ids[i]
			var info: Dictionary = player_dict[peer_id]
			var p_node: Node3D = players_container.get_node_or_null(str(peer_id))
			if not p_node:
				p_node = PLAYER_SCENE.instantiate()
				p_node.name = str(peer_id)
				players_container.add_child(p_node)
				p_node.setup(peer_id, info)

			var angle := float(i) * (TAU / float(maxi(1, count)))
			var offset_v := Vector3(cos(angle) * 1.5, 0.0, sin(angle) * 1.5) if count > 1 else Vector3.ZERO
			p_node.global_position = current_spawn_pos + offset_v

	# Snap camera immediately to spawn location
	if camera and not is_overview_mode:
		camera.global_position = current_spawn_pos + camera_offset

func _update_hud() -> void:
	if not is_inside_tree() or not info_label:
		return
	var my_id: int = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	var total: int = NetworkManager.get_player_count()
	if total == 0:
		total = 1
	info_label.text = "Peer ID: %d | Players: %d" % [my_id, total]

func _update_stats_label() -> void:
	if not stats_label or not generator.current_graph:
		return
	var g = generator.current_graph
	var loop_count: int = 0
	for p in g.paths:
		if p.is_loop:
			loop_count += 1

	var grass_count: int = 0
	if generator.foliage_multimesh_instance and generator.foliage_multimesh_instance.multimesh:
		grass_count = generator.foliage_multimesh_instance.multimesh.instance_count

	stats_label.text = "[DEBUG] Seed: %d | Rooms: %d | Bridges: %d (%d Loops) | Grass: %d" % [
		generator.current_seed,
		g.areas.size(),
		g.paths.size(),
		loop_count,
		grass_count
	]

func _on_overview_pressed() -> void:
	is_overview_mode = not is_overview_mode
	if overview_button:
		overview_button.text = "Player View (Debug)" if is_overview_mode else "Map Overview (Debug)"


func _on_regen_pressed() -> void:
	generator.generate_map(0)

func _on_player_connected(peer_id: int, info: Dictionary) -> void:
	if not players_container.has_node(str(peer_id)):
		var player_instance := PLAYER_SCENE.instantiate()
		player_instance.name = str(peer_id)
		players_container.add_child(player_instance)
		player_instance.setup(peer_id, info)
		player_instance.global_position = current_spawn_pos
	_update_hud()

func _on_player_disconnected(peer_id: int) -> void:
	var player_node := players_container.get_node_or_null(str(peer_id))
	if player_node:
		player_node.queue_free()
	_update_hud()

func _on_server_disconnected() -> void:
	if get_tree() and get_tree().current_scene and get_tree().current_scene.scene_file_path != "res://ui/lobby.tscn":
		get_tree().change_scene_to_file("res://ui/lobby.tscn")

func _on_leave_pressed() -> void:
	NetworkManager.leave_game()
	get_tree().change_scene_to_file("res://ui/lobby.tscn")
