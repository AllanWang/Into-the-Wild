extends Node2D

const PLAYER_SCENE = preload("res://player/player.tscn")

@onready var players_container: Node2D = $Players
@onready var info_label: Label = $HUD/MarginContainer/HBoxContainer/InfoLabel
@onready var leave_button: Button = $HUD/MarginContainer/HBoxContainer/LeaveButton

func _ready() -> void:
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	leave_button.pressed.connect(_on_leave_pressed)
	
	spawn_players()
	_update_hud()

func spawn_players() -> void:
	# Clear any existing players in container
	for child in players_container.get_children():
		child.queue_free()
		
	var player_dict = NetworkManager.players
	if player_dict.is_empty():
		# Direct scene run fallback (e.g. running Main.tscn standalone from editor)
		var solo_player = PLAYER_SCENE.instantiate()
		solo_player.name = "1"
		solo_player.position = Vector2.ZERO
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
		
		# Stagger spawn positions evenly around center so players don't overlap
		if count > 1:
			var angle = i * (TAU / count)
			player_instance.position = Vector2(cos(angle), sin(angle)) * 80.0
		else:
			player_instance.position = Vector2.ZERO
			
		players_container.add_child(player_instance)
		player_instance.setup(peer_id, info)

func _update_hud() -> void:
	if not is_inside_tree() or not info_label:
		return
	var my_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	var total = NetworkManager.get_player_count()
	if total == 0:
		total = 1
	info_label.text = "Peer ID: %d | Players: %d" % [my_id, total]

func _on_player_disconnected(peer_id: int) -> void:
	var player_node = players_container.get_node_or_null(str(peer_id))
	if player_node:
		player_node.queue_free()
	_update_hud()

func _on_server_disconnected() -> void:
	get_tree().change_scene_to_file("res://ui/lobby.tscn")

func _on_leave_pressed() -> void:
	NetworkManager.leave_game()
	get_tree().change_scene_to_file("res://ui/lobby.tscn")
