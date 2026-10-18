extends Node3D

const PLAYER_SCENE = preload("res://player/player.tscn")

@onready var players_container: Node3D = $Players
@onready var camera: Camera3D = $Camera3D
@onready var info_label: Label = $HUD/MarginContainer/HBoxContainer/InfoLabel
@onready var leave_button: Button = $HUD/MarginContainer/HBoxContainer/LeaveButton
@onready var cam_button: Button = $HUD/MarginContainer/HBoxContainer.get_node_or_null("CamButton")
@onready var teleport_button: Button = $HUD/MarginContainer/HBoxContainer.get_node_or_null("TeleportButton")

# Locked isometric offset from target on ground (Y=0) to Camera3D
var camera_offset: Vector3 = Vector3(-10.0, 10.0, 10.0)
var is_overview: bool = false
var overview_pos: Vector3 = Vector3(-35.0, 35.0, 17.0)
var overview_size: float = 65.0
var default_camera_size: float = 6.085
var in_area_2: bool = false

@export var overview_mode: bool = false:
	set(val):
		overview_mode = val
		is_overview = val
		if cam_button:
			cam_button.text = "Player Cam" if is_overview else "Overview Cam"

func _ready() -> void:
	if not NetworkManager.peer:
		NetworkManager.host_game(0, "SoloPlayer")
		
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	leave_button.pressed.connect(_on_leave_pressed)
	if cam_button:
		cam_button.pressed.connect(_on_cam_button_pressed)
		cam_button.text = "Player Cam" if is_overview else "Overview Cam"
	current_loc_idx = spawn_location
	if teleport_button:
		teleport_button.pressed.connect(_on_teleport_pressed)
		_update_teleport_button_label()
	
	spawn_players()
	_update_hud()
	NetworkManager.mark_client_ready()
	
	if is_overview and camera:
		camera.size = overview_size
		camera.global_position = overview_pos

func _process(delta: float) -> void:
	if is_overview:
		if camera:
			camera.size = lerpf(camera.size, overview_size, clampf(6.0 * delta, 0.0, 1.0))
			camera.global_position = camera.global_position.lerp(overview_pos, clampf(6.0 * delta, 0.0, 1.0))
	else:
		if camera:
			camera.size = lerpf(camera.size, default_camera_size, clampf(8.0 * delta, 0.0, 1.0))
			var my_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
			var local_player = players_container.get_node_or_null(str(my_id))
			if local_player:
				var target_pos = local_player.global_position + camera_offset
				camera.global_position = camera.global_position.lerp(target_pos, clampf(10.0 * delta, 0.0, 1.0))

func _on_cam_button_pressed() -> void:
	overview_mode = not overview_mode

@export var spawn_location: int = 1 # 0: Area 1, 1: Bridge, 2: Area 2

func spawn_players() -> void:
	# Clear any existing players in container
	for child in players_container.get_children():
		child.queue_free()
		
	var player_dict = NetworkManager.players
	if player_dict.is_empty():
		# Direct scene run fallback (e.g. running Main.tscn standalone from editor)
		var solo_player = PLAYER_SCENE.instantiate()
		solo_player.name = "1"
		if spawn_location == 1:
			solo_player.position = Vector3(0, 0, -18)
		elif spawn_location == 2:
			solo_player.position = Vector3(0, 0, -36)
		else:
			solo_player.position = Vector3(0, 0, 6)
		players_container.add_child(solo_player)
		solo_player.setup(1, {
			"name": "SoloPlayer",
			"color": Color(0.25, 0.6, 1.0)
		})
		return
		
	var peer_ids = player_dict.keys()
	var count = peer_ids.size()
	
	for i in range(count):
		var peer_id = peer_ids[i]
		var info = player_dict[peer_id]
		
		var player_instance = PLAYER_SCENE.instantiate()
		player_instance.name = str(peer_id)
		
		# Stagger spawn positions around center
		if count > 1:
			var angle = i * (TAU / count)
			player_instance.position = Vector3(cos(angle) * 2.0, 0, sin(angle) * 2.0)
		else:
			if spawn_location == 1:
				player_instance.position = Vector3(0, 0, -18)
			elif spawn_location == 2:
				player_instance.position = Vector3(0, 0, -36)
			else:
				player_instance.position = Vector3(0, 0, 6)
			
		players_container.add_child(player_instance)
		player_instance.setup(peer_id, info)
	
	var my_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	var local_player = players_container.get_node_or_null(str(my_id))
	if local_player and camera:
		camera.global_position = local_player.global_position + camera_offset

func _update_hud() -> void:
	if not is_inside_tree() or not info_label:
		return
	var my_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	var total = NetworkManager.get_player_count()
	if total == 0:
		total = 1
	info_label.text = "Peer ID: %d | Players: %d" % [my_id, total]

func _on_player_connected(peer_id: int, info: Dictionary) -> void:
	if not players_container.has_node(str(peer_id)):
		var player_instance = PLAYER_SCENE.instantiate()
		player_instance.name = str(peer_id)
		var angle = (peer_id % 8) * (TAU / 8.0)
		player_instance.position = Vector3(cos(angle) * 2.0, 0, sin(angle) * 2.0)
		players_container.add_child(player_instance)
		player_instance.setup(peer_id, info)
	_update_hud()

func _on_player_disconnected(peer_id: int) -> void:
	var player_node = players_container.get_node_or_null(str(peer_id))
	if player_node:
		player_node.queue_free()
	_update_hud()

func _on_server_disconnected() -> void:
	if get_tree() and get_tree().current_scene and get_tree().current_scene.scene_file_path != "res://ui/lobby.tscn":
		get_tree().change_scene_to_file("res://ui/lobby.tscn")

func _on_leave_pressed() -> void:
	NetworkManager.leave_game()
	get_tree().change_scene_to_file("res://ui/lobby.tscn")

var current_loc_idx: int = 1 # 0: Area 1, 1: Bridge, 2: Area 2

func _update_teleport_button_label() -> void:
	if not teleport_button:
		return
	if current_loc_idx == 0:
		teleport_button.text = "Go to Bridge"
	elif current_loc_idx == 1:
		teleport_button.text = "Go to Area 2"
	else:
		teleport_button.text = "Go to Area 1"

func _on_teleport_pressed() -> void:
	current_loc_idx = (current_loc_idx + 1) % 3
	var my_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	var local_player = players_container.get_node_or_null(str(my_id))
	var target_pos = Vector3(0.0, 0.0, 6.0)
	if current_loc_idx == 1:
		target_pos = Vector3(0.0, 0.0, -18.0)
	elif current_loc_idx == 2:
		target_pos = Vector3(0.0, 0.0, -36.0)
	else:
		target_pos = Vector3(0.0, 0.0, 6.0)
		
	if local_player:
		local_player.global_position = target_pos
	_update_teleport_button_label()
