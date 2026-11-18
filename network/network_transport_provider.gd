extends RefCounted

## Base contract for NetworkManager transport providers.
## Allows swapping ENet (Desktop UDP multiplayer) and Offline (Static Web Solo)
## while keeping NetworkManager's public MultiplayerPeer interface identical.


func get_provider_name() -> String:
	return "base"


func supports_online_multiplayer() -> bool:
	return false


func create_host_peer(_requested_port: int, _default_port: int, _max_clients: int, _scan_attempts: int) -> Dictionary:
	return {
		"error": ERR_UNAVAILABLE,
		"peer": null,
		"bound_port": 0,
	}


func create_client_peer(_address: String, _port: int) -> Dictionary:
	return {
		"error": ERR_UNAVAILABLE,
		"peer": null,
		"port": 0,
	}


func get_discovered_port(default_port: int) -> int:
	return default_port


func on_host_started(_bound_port: int) -> void:
	pass


func on_host_stopped() -> void:
	pass
