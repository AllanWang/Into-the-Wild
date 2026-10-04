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

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func host_game(port: int = DEFAULT_PORT, player_name: String = "Host") -> Error:
	leave_game()
	local_player_name = player_name
	
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_CLIENTS)
	if error != OK:
		peer = null
		return error
		
	multiplayer.multiplayer_peer = peer
	
	# Register host locally
	var host_info = {
		"name": local_player_name,
		"color": PLAYER_COLORS[0],
		"is_host": true
	}
	players[1] = host_info
	player_list_updated.emit()
	return OK

func join_game(address: String = "127.0.0.1", port: int = DEFAULT_PORT, player_name: String = "Client") -> Error:
	leave_game()
	local_player_name = player_name
	
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, port)
	if error != OK:
		peer = null
		return error
		
	multiplayer.multiplayer_peer = peer
	return OK

func leave_game() -> void:
	if peer:
		peer.close()
		peer = null
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
	return multiplayer.is_server() if multiplayer.has_multiplayer_peer() else false
