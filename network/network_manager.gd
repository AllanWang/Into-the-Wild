extends Node

signal player_connected(peer_id: int, player_info: Dictionary)
signal player_disconnected(peer_id: int)
signal player_list_updated
signal connection_succeeded
signal connection_failed
signal server_disconnected
signal game_started
signal match_ready

const DEFAULT_PORT: int = 7777
const MAX_CLIENTS: int = 8
const PORT_SCAN_ATTEMPTS: int = 20
const PORT_RANGE_START: int = 7000
const PORT_RANGE_SIZE: int = 5000
const HOST_PORT_FILE: String = "res://.godot/host_port"

const PLAYER_COLORS: Array[Color] = [
	Color(0.25, 0.6, 1.0),   # Blue (Host)
	Color(1.0, 0.4, 0.4),   # Coral Red
	Color(0.3, 0.85, 0.45), # Emerald Green
	Color(1.0, 0.75, 0.2),  # Golden Yellow
	Color(0.8, 0.45, 1.0),  # Purple
	Color(0.2, 0.85, 0.85), # Cyan
	Color(1.0, 0.55, 0.2),  # Orange
	Color(0.9, 0.4, 0.65),  # Pink
]

var peer: ENetMultiplayerPeer = null
var players: Dictionary = {}
var local_player_name: String = "Player"
var clients_ready: Dictionary = {}
var is_match_ready: bool = false
var is_game_running: bool = false
var active_port: int = 0
var _is_hosting: bool = false

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if _is_hosting:
			_remove_host_port_file()
			_is_hosting = false

## Returns a deterministic base port (7000-11999) calculated from the workspace directory path.
func get_workspace_default_port() -> int:
	var project_dir: String = ProjectSettings.globalize_path("res://")
	var offset: int = abs(project_dir.hash()) % PORT_RANGE_SIZE
	return PORT_RANGE_START + offset

## Returns the active host port if written to .godot/host_port, otherwise falls back to workspace default.
func get_discovered_host_port() -> int:
	if FileAccess.file_exists(HOST_PORT_FILE):
		var f: FileAccess = FileAccess.open(HOST_PORT_FILE, FileAccess.READ)
		if f:
			var txt: String = f.get_as_text().strip_edges()
			f.close()
			var p: int = txt.to_int()
			if p > 0:
				return p
	return get_workspace_default_port()

func _write_host_port_file(port: int) -> void:
	var godot_dir: String = ProjectSettings.globalize_path("res://.godot")
	if not DirAccess.dir_exists_absolute(godot_dir):
		DirAccess.make_dir_absolute(godot_dir)
	var f: FileAccess = FileAccess.open(HOST_PORT_FILE, FileAccess.WRITE)
	if f:
		f.store_string(str(port))
		f.close()

func _remove_host_port_file() -> void:
	if FileAccess.file_exists(HOST_PORT_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(HOST_PORT_FILE))

func host_game(port: int = 0, player_name: String = "Host") -> Error:
	leave_game()
	local_player_name = player_name
	
	var starting_port: int = port if port > 0 else get_workspace_default_port()
	var error: Error = FAILED
	var bound_port: int = 0
	
	for attempt in range(PORT_SCAN_ATTEMPTS):
		var test_port: int = starting_port + attempt
		peer = ENetMultiplayerPeer.new()
		error = peer.create_server(test_port, MAX_CLIENTS)
		if error == OK:
			bound_port = test_port
			break
		peer = null
		
	if error != OK or bound_port == 0:
		peer = null
		return error
		
	active_port = bound_port
	_is_hosting = true
	if is_inside_tree() and multiplayer:
		multiplayer.multiplayer_peer = peer
	_write_host_port_file(bound_port)
	
	# Register host locally
	var host_info = {
		"name": local_player_name,
		"color": PLAYER_COLORS[0],
		"is_host": true
	}
	players[1] = host_info
	player_list_updated.emit()
	return OK

func join_game(address: String = "127.0.0.1", port: int = 0, player_name: String = "Client") -> Error:
	leave_game()
	local_player_name = player_name
	
	var target_port: int = port if port > 0 else get_discovered_host_port()
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, target_port)
	if error != OK:
		peer = null
		return error
		
	active_port = target_port
	if is_inside_tree() and multiplayer:
		multiplayer.multiplayer_peer = peer
	return OK

func leave_game() -> void:
	if _is_hosting:
		_remove_host_port_file()
		_is_hosting = false
	active_port = 0
	if peer:
		peer.close()
		peer = null
	if is_inside_tree() and multiplayer:
		multiplayer.multiplayer_peer = null
	players.clear()
	clients_ready.clear()
	is_match_ready = false
	is_game_running = false
	player_list_updated.emit()

func start_game() -> void:
	if not multiplayer.is_server():
		return
	is_game_running = true
	clients_ready.clear()
	is_match_ready = false
	_load_game_scene.rpc()

@rpc("call_local", "reliable")
func _load_game_scene() -> void:
	game_started.emit()
	get_tree().change_scene_to_file("res://Main.tscn")

func mark_client_ready() -> void:
	if not multiplayer.has_multiplayer_peer() or players.size() <= 1:
		is_match_ready = true
		match_ready.emit()
		return
		
	if multiplayer.is_server():
		clients_ready[1] = true
		_check_all_ready()
	else:
		var my_id = multiplayer.get_unique_id()
		_notify_server_ready.rpc_id(1, my_id)

@rpc("any_peer", "call_local", "reliable")
func _notify_server_ready(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	clients_ready[peer_id] = true
	_check_all_ready()

func _check_all_ready() -> void:
	for p_id in players:
		if not clients_ready.get(p_id, false):
			return
	_all_ready_start.rpc()

@rpc("call_local", "reliable")
func _all_ready_start() -> void:
	is_match_ready = true
	match_ready.emit()

func _on_connected_to_server() -> void:
	var my_id = multiplayer.get_unique_id()
	var my_info = {
		"name": local_player_name,
		"is_host": false
	}
	_register_player_to_server.rpc_id(1, my_id, my_info)
	connection_succeeded.emit()

func _on_connection_failed() -> void:
	leave_game()
	connection_failed.emit()

func _on_server_disconnected() -> void:
	leave_game()
	server_disconnected.emit()
	if get_tree() and get_tree().current_scene and get_tree().current_scene.scene_file_path != "res://ui/lobby.tscn":
		get_tree().change_scene_to_file("res://ui/lobby.tscn")

func _on_peer_connected(id: int) -> void:
	# Handled via registration RPC
	pass

func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		if players.has(id):
			players.erase(id)
			_sync_all_players.rpc(players)
	player_disconnected.emit(id)
	player_list_updated.emit()

@rpc("any_peer", "call_local", "reliable")
func _register_player_to_server(id: int, info: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	
	# Assign distinct color based on current player count
	var color_idx = players.size() % PLAYER_COLORS.size()
	info["color"] = PLAYER_COLORS[color_idx]
	players[id] = info
	
	_sync_all_players.rpc(players)
	player_connected.emit(id, info)
	
	if is_game_running:
		_load_game_scene.rpc_id(id)

@rpc("call_local", "reliable")
func _sync_all_players(updated_players: Dictionary) -> void:
	var old_keys = players.keys()
	players = updated_players
	player_list_updated.emit()
	for p_id in players:
		if not old_keys.has(p_id):
			player_connected.emit(p_id, players[p_id])

func get_player_count() -> int:
	return players.size()

func is_host() -> bool:
	if not peer or not is_inside_tree() or not multiplayer:
		return false
	return multiplayer.is_server() if multiplayer.has_multiplayer_peer() else false
