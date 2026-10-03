extends Control

@onready var setup_panel: VBoxContainer = $CenterContainer/PanelContainer/MarginContainer/MainVBox/SetupPanel
@onready var room_panel: VBoxContainer = $CenterContainer/PanelContainer/MarginContainer/MainVBox/RoomPanel
@onready var name_input: LineEdit = $CenterContainer/PanelContainer/MarginContainer/MainVBox/SetupPanel/NameRow/NameInput
@onready var ip_input: LineEdit = $CenterContainer/PanelContainer/MarginContainer/MainVBox/SetupPanel/ConnectionRow/IPInput
@onready var port_input: LineEdit = $CenterContainer/PanelContainer/MarginContainer/MainVBox/SetupPanel/ConnectionRow/PortInput
@onready var status_label: Label = $CenterContainer/PanelContainer/MarginContainer/MainVBox/StatusLabel
@onready var room_info_label: Label = $CenterContainer/PanelContainer/MarginContainer/MainVBox/RoomPanel/RoomInfoLabel
@onready var player_list_container: VBoxContainer = $CenterContainer/PanelContainer/MarginContainer/MainVBox/RoomPanel/PlayerListScroll/PlayerList
@onready var start_button: Button = $CenterContainer/PanelContainer/MarginContainer/MainVBox/RoomPanel/ActionsRow/StartButton

func _ready() -> void:
	# Request window focus on desktop
	DisplayServer.window_move_to_foreground()
	
	# Assign clean default player name based on debug instance index
	if DebugTools and DebugTools.is_active:
		if DebugTools.instance_index == 0:
			name_input.text = "HostPlayer"
		else:
			name_input.text = "Player_%d" % (DebugTools.instance_index + 1)
	else:
		name_input.text = "Player_%d" % randi_range(100, 999)
	
	# Connect NetworkManager signals
	NetworkManager.player_list_updated.connect(_update_player_list)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	
	_show_setup_panel()
	_check_cli_args()

func _check_cli_args() -> void:
	var args = OS.get_cmdline_user_args()
	if args.is_empty():
		args = OS.get_cmdline_args()
		
	var custom_name = ""
	var should_host = false
	var should_join = false
	
	for i in range(args.size()):
		var arg = args[i]
		if arg == "--host":
			should_host = true
		elif arg == "--client":
			should_join = true
		elif arg == "--name" and i + 1 < args.size():
			custom_name = args[i + 1]
			
	if not custom_name.is_empty():
		name_input.text = custom_name
		
	if should_host:
		get_tree().create_timer(0.2).timeout.connect(_on_host_pressed)
	elif should_join:
		get_tree().create_timer(0.5).timeout.connect(_on_join_pressed)

func _show_setup_panel() -> void:
	setup_panel.visible = true
	room_panel.visible = false
	status_label.text = "Ready to connect. Enter name and select Host or Join."
	status_label.modulate = Color(0.8, 0.8, 0.9)

func _show_room_panel() -> void:
	setup_panel.visible = false
	room_panel.visible = true
	_update_player_list()

func _on_host_pressed() -> void:
	var p_name = name_input.text.strip_edges()
	if p_name.is_empty():
		p_name = "Host"
	var port = port_input.text.to_int()
	if port <= 0:
		port = NetworkManager.DEFAULT_PORT
		
	status_label.text = "Hosting server on port %d..." % port
	status_label.modulate = Color(0.3, 0.9, 0.4)
	
	var err = NetworkManager.host_game(port, p_name)
	if err == OK:
		room_info_label.text = "Hosting on Port %d" % port
		_show_room_panel()
	else:
		status_label.text = "Failed to host: Error code %d" % err
		status_label.modulate = Color(1.0, 0.3, 0.3)

func _on_join_pressed() -> void:
	var p_name = name_input.text.strip_edges()
	if p_name.is_empty():
		p_name = "Client"
	var ip = ip_input.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	var port = port_input.text.to_int()
	if port <= 0:
		port = NetworkManager.DEFAULT_PORT
		
	status_label.text = "Connecting to %s:%d..." % [ip, port]
	status_label.modulate = Color(0.9, 0.8, 0.2)
	
	var err = NetworkManager.join_game(ip, port, p_name)
	if err != OK:
		status_label.text = "Failed to initiate connection: Error %d" % err
		status_label.modulate = Color(1.0, 0.3, 0.3)

func _on_connection_succeeded() -> void:
	status_label.text = "Connected successfully!"
	status_label.modulate = Color(0.3, 0.9, 0.4)
	room_info_label.text = "Connected to %s:%s" % [ip_input.text, port_input.text]
	_show_room_panel()

func _on_connection_failed() -> void:
	status_label.text = "Connection failed! Check IP/Port and make sure host is running."
	status_label.modulate = Color(1.0, 0.3, 0.3)
	_show_setup_panel()

func _on_server_disconnected() -> void:
	status_label.text = "Host disconnected."
	status_label.modulate = Color(1.0, 0.4, 0.4)
	_show_setup_panel()

func _update_player_list() -> void:
	# Clear existing items
	for child in player_list_container.get_children():
		child.queue_free()
		
	for peer_id in NetworkManager.players:
		var p_info = NetworkManager.players[peer_id]
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)
		
		# Color swatch
		var swatch = ColorRect.new()
		swatch.custom_minimum_size = Vector2(20, 20)
		swatch.color = p_info.get("color", Color.WHITE)
		hbox.add_child(swatch)
		
		# Name and info
		var name_label = Label.new()
		var is_host_badge = " (Host)" if p_info.get("is_host", false) else ""
		var is_you_badge = " [YOU]" if peer_id == multiplayer.get_unique_id() else ""
		name_label.text = "%s%s%s (ID: %d)" % [p_info.get("name", "Unknown"), is_host_badge, is_you_badge, peer_id]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(name_label)
		
		player_list_container.add_child(hbox)
		
	# Host controls start button
	var is_host = NetworkManager.is_host()
	start_button.visible = is_host
	start_button.disabled = not is_host

func _on_start_pressed() -> void:
	if NetworkManager.is_host():
		NetworkManager.start_game()

func _on_leave_pressed() -> void:
	NetworkManager.leave_game()
	_show_setup_panel()

func _on_quick_host_pressed() -> void:
	name_input.text = "HostPlayer"
	ip_input.text = "127.0.0.1"
	port_input.text = "7777"
	_on_host_pressed()

func _on_quick_join_pressed() -> void:
	name_input.text = "ClientPlayer"
	ip_input.text = "127.0.0.1"
	port_input.text = "7777"
	_on_join_pressed()
