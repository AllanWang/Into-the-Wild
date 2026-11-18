extends "res://network/network_transport_provider.gd"

## Desktop ENet (UDP) transport provider with workspace port-file discovery.

const HOST_PORT_FILE: String = "res://.godot/host_port"


func get_provider_name() -> String:
	return "enet"


func supports_online_multiplayer() -> bool:
	return true


func create_host_peer(requested_port: int, default_port: int, max_clients: int, scan_attempts: int) -> Dictionary:
	var starting_port: int = requested_port if requested_port > 0 else default_port
	var last_err: Error = FAILED

	for attempt in range(maxi(1, scan_attempts)):
		var test_port: int = starting_port + attempt
		var candidate := ENetMultiplayerPeer.new()
		last_err = candidate.create_server(test_port, max_clients)
		if last_err == OK:
			return {
				"error": OK,
				"peer": candidate,
				"bound_port": test_port,
			}

	return {
		"error": last_err,
		"peer": null,
		"bound_port": 0,
	}


func create_client_peer(address: String, port: int) -> Dictionary:
	var candidate := ENetMultiplayerPeer.new()
	var err: Error = candidate.create_client(address, port)
	if err != OK:
		return {
			"error": err,
			"peer": null,
			"port": port,
		}
	return {
		"error": OK,
		"peer": candidate,
		"port": port,
	}


func _can_use_port_file() -> bool:
	return OS.has_feature("editor") or (OS.is_debug_build() and not OS.has_feature("web"))


func get_discovered_port(default_port: int) -> int:
	if _can_use_port_file() and FileAccess.file_exists(HOST_PORT_FILE):
		var f: FileAccess = FileAccess.open(HOST_PORT_FILE, FileAccess.READ)
		if f:
			var txt: String = f.get_as_text().strip_edges()
			f.close()
			var p: int = txt.to_int()
			if p > 0:
				return p
	return default_port


func on_host_started(bound_port: int) -> void:
	if not _can_use_port_file() or bound_port <= 0:
		return
	var godot_dir: String = ProjectSettings.globalize_path("res://.godot")
	if not DirAccess.dir_exists_absolute(godot_dir):
		DirAccess.make_dir_absolute(godot_dir)
	var f: FileAccess = FileAccess.open(HOST_PORT_FILE, FileAccess.WRITE)
	if f:
		f.store_string(str(bound_port))
		f.close()


func on_host_stopped() -> void:
	if not _can_use_port_file():
		return
	if FileAccess.file_exists(HOST_PORT_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(HOST_PORT_FILE))
