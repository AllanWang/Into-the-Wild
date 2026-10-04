extends Control

func _ready() -> void:
	# Single-player debug: auto-host solo session and load Main world scene immediately
	var err = NetworkManager.start_single_player("SoloDev")
	if err != OK:
		push_error("[SinglePlayerDebug] Failed to start solo game: Error code %d" % err)
