extends Control

@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel
@onready var start_now_button: Button = $CenterContainer/VBoxContainer/StartNowButton
@onready var back_button: Button = $CenterContainer/VBoxContainer/BackButton

var _is_host: bool = false
var _retry_count: int = 0
const MAX_RETRIES: int = 5

func _ready() -> void:
	start_now_button.pressed.connect(_on_start_now_pressed)
	back_button.pressed.connect(_on_back_pressed)
	
	var is_companion: bool = (DebugTools and DebugTools.is_active and DebugTools.instance_index > 0)
	
	if is_companion:
		_setup_client()
	else:
		_setup_host()

func _setup_host() -> void:
	_is_host = true
	var port = NetworkManager.get_workspace_default_port()
	var err = NetworkManager.host_game(port, "HostPlayer")
	if err == OK:
		status_label.text = "Hosting on Port %d\nWaiting for companion player..." % NetworkManager.active_port
		if DebugTools and DebugTools.is_active:
			DebugTools.broadcast_auto_join(NetworkManager.active_port)
			
		NetworkManager.player_connected.connect(_on_companion_connected, CONNECT_ONE_SHOT)
	else:
		status_label.text = "Failed to host: Error code %d" % err

func _setup_client() -> void:
	_is_host = false
	start_now_button.visible = false
	status_label.text = "Connecting to host..."
	# Brief delay to ensure host socket is bound and host_port file written
	get_tree().create_timer(0.35).timeout.connect(_attempt_join)

func _attempt_join() -> void:
	var port = NetworkManager.get_discovered_host_port()
	var client_name = "Player_%d" % (DebugTools.instance_index + 1) if (DebugTools and DebugTools.is_active) else "ClientPlayer"
	status_label.text = "Connecting to 127.0.0.1:%d as %s..." % [port, client_name]
	
	NetworkManager.connection_succeeded.connect(_on_client_connected, CONNECT_ONE_SHOT)
	NetworkManager.connection_failed.connect(_on_client_failed, CONNECT_ONE_SHOT)
	
	var err = NetworkManager.join_game("127.0.0.1", port, client_name)
	if err != OK:
		_on_client_failed()

func _on_client_connected() -> void:
	status_label.text = "Connected! Waiting for host to launch world..."

func _on_client_failed() -> void:
	_retry_count += 1
	if _retry_count <= MAX_RETRIES:
		status_label.text = "Connection attempt %d failed. Retrying..." % _retry_count
		get_tree().create_timer(0.4).timeout.connect(_attempt_join)
	else:
		status_label.text = "Failed to connect to host. Make sure host instance is running."

func _on_companion_connected(_peer_id: int, info: Dictionary) -> void:
	var p_name = info.get("name", "Companion")
	status_label.text = "%s connected! Launching world..." % p_name
	get_tree().create_timer(0.25).timeout.connect(func():
		NetworkManager.start_game()
	)

func _on_start_now_pressed() -> void:
	if _is_host:
		NetworkManager.start_game()

func _on_back_pressed() -> void:
	NetworkManager.leave_game()
	get_tree().change_scene_to_file("res://ui/lobby.tscn")
