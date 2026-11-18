extends "res://network/network_transport_provider.gd"

## Solo-only OfflineMultiplayerPeer transport provider for static Web builds.
## Avoids UDP sockets and res:// filesystem writes while preserving the MultiplayerPeer surface.


func get_provider_name() -> String:
	return "offline"


func supports_online_multiplayer() -> bool:
	return false


func create_host_peer(_requested_port: int, _default_port: int, _max_clients: int, _scan_attempts: int) -> Dictionary:
	var offline_peer := OfflineMultiplayerPeer.new()
	return {
		"error": OK,
		"peer": offline_peer,
		"bound_port": 0,
	}


func create_client_peer(_address: String, _port: int) -> Dictionary:
	return {
		"error": ERR_UNAVAILABLE,
		"peer": null,
		"port": 0,
	}


func get_discovered_port(_default_port: int) -> int:
	return 0
