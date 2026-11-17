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
@onready var debug_row: HBoxContainer = $CenterContainer/PanelContainer/MarginContainer/MainVBox/SetupPanel/DebugRow

static var _has_auto_joined_once: bool = false
var _auto_join_disabled: bool = false

func _ready() -> void:
	# Request window focus in standalone production builds only (skip when embedded or testing via editor/MCP)
	var is_emb: bool = Engine.is_embedded_in_editor() or ("--wid" in OS.get_cmdline_args()) or (DebugTools != null and DebugTools.is_embedded)
	if not is_emb and not EngineDebugger.is_active():
		DisplayServer.window_move_to_foreground()
	
	# Only show debug quick buttons in debug builds
	if not OS.is_debug_build():
		debug_row.visible = false
	
	# Assign clean default player name based on debug instance index
	if DebugTools and DebugTools.is_active:
		if DebugTools.instance_index == 0:
			name_input.text = "HostPlayer"
		else:
			name_input.text = "Player_%d" % (DebugTools.instance_index + 1)
	else:
		name_input.text = "Player_%d" % randi_range(100, 999)
	
	# Initialize port with discovered or worktree default port
	port_input.text = str(NetworkManager.get_discovered_host_port())
	
	# Connect NetworkManager signals
	NetworkManager.player_list_updated.connect(_update_player_list)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	
	# Connect companion instance auto-join signaling
	if DebugTools and DebugTools.is_active:
		DebugTools.auto_join_requested.connect(_on_auto_join_requested)
		DebugTools.instance_count_updated.connect(_on_instance_count_updated)
	
	_show_setup_panel()
	_setup_worktree_badge()
	_check_cli_args()
	
	if DebugTools and DebugTools.is_active and DebugTools.instance_index == 0 and DebugTools.active_instance_count == 2:
		_check_auto_join_2p()

func _setup_worktree_badge() -> void:
	var wt_name: String = _get_worktree_name()
	if wt_name.is_empty():
		return
		
	var container = MarginContainer.new()
	container.name = "WorktreeBadgeContainer"
	container.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	container.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	container.grow_vertical = Control.GROW_DIRECTION_BEGIN
	container.add_theme_constant_override("margin_right", 16)
	container.add_theme_constant_override("margin_bottom", 12)
	
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.14, 0.18, 0.85)
	style.border_color = Color(0.35, 0.5, 0.75, 0.7)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	
	var label = Label.new()
	label.text = "worktree: %s" % wt_name
	label.modulate = Color(0.75, 0.88, 1.0, 0.95)
	label.add_theme_font_size_override("font_size", 12)
	
	panel.add_child(label)
	container.add_child(panel)
	add_child(container)

func _get_worktree_name() -> String:
	if not OS.is_debug_build():
		return ""
	var git_path = "res://.git"
	var global_git = ProjectSettings.globalize_path(git_path)
	# If .git is a directory, this is the main repository root, so show nothing.
	if DirAccess.dir_exists_absolute(global_git):
		return ""
	# If .git is a file, this is an active Git worktree.
	if FileAccess.file_exists(git_path):
		var f = FileAccess.open(git_path, FileAccess.READ)
		if f:
			var content = f.get_as_text().strip_edges()
			f.close()
			if content.begins_with("gitdir:"):
				var raw_path = content.trim_prefix("gitdir:").strip_edges().replace("\\", "/")
				var parts = raw_path.split("/")
				if parts.size() > 0 and not parts[parts.size() - 1].is_empty():
					return parts[parts.size() - 1]
			return ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/").get_file()
	return ""

func _check_cli_args() -> void:
	var args = OS.get_cmdline_user_args()
	if args.is_empty():
		args = OS.get_cmdline_args()
		
	var custom_name = ""
	var should_host = false
	var should_join = false
	var should_autostart = false
	
	for i in range(args.size()):
		var arg = args[i]
		if arg == "--host":
			should_host = true
			_auto_join_disabled = true
		elif arg == "--client":
			should_join = true
			_auto_join_disabled = true
		elif arg == "--autostart":
			should_autostart = true
		elif arg == "--no-auto-join" or arg == "--no-autostart" or arg == "--manual":
			_auto_join_disabled = true
		elif arg == "--name" and i + 1 < args.size():
			custom_name = args[i + 1]
		elif (arg == "--port" or arg == "-p") and i + 1 < args.size():
			port_input.text = args[i + 1]
			
	if not custom_name.is_empty():
		name_input.text = custom_name
		
	if should_host:
		get_tree().create_timer(0.2).timeout.connect(func():
			_on_host_pressed()
			if should_autostart:
				NetworkManager.player_connected.connect(func(_id, _info):
					get_tree().create_timer(0.4).timeout.connect(_on_start_pressed)
				, CONNECT_ONE_SHOT)
		)
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
		port = NetworkManager.get_workspace_default_port()
		
	status_label.text = "Hosting server..."
	status_label.modulate = Color(0.3, 0.9, 0.4)
	
	var err = NetworkManager.host_game(port, p_name)
	if err == OK:
		port_input.text = str(NetworkManager.active_port)
		room_info_label.text = "Hosting on Port %d" % NetworkManager.active_port
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
		port = NetworkManager.get_discovered_host_port()
		
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

func _on_solo_debug_pressed() -> void:
	var p_name = name_input.text.strip_edges()
	if p_name.is_empty():
		p_name = "SoloPlayer"
	status_label.text = "Starting solo world..."
	status_label.modulate = Color(0.3, 0.9, 0.4)
	NetworkManager.start_single_player(p_name)

func _on_multi_debug_pressed() -> void:
	var p_name = name_input.text.strip_edges()
	if p_name.is_empty():
		p_name = "HostPlayer"
	var port = port_input.text.to_int()
	if port <= 0:
		port = NetworkManager.get_workspace_default_port()
		
	status_label.text = "Hosting and signaling companion instance to join..."
	status_label.modulate = Color(0.3, 0.9, 0.4)
	
	var err = NetworkManager.host_game(port, p_name)
	if err == OK:
		port_input.text = str(NetworkManager.active_port)
		room_info_label.text = "Hosting on Port %d" % NetworkManager.active_port
		_show_room_panel()
		
		# Signal companion window to join
		if DebugTools and DebugTools.is_active:
			DebugTools.broadcast_auto_join(NetworkManager.active_port)
			
		# Auto-start game once companion connects
		NetworkManager.player_connected.connect(func(_id, _info):
			status_label.text = "Companion joined! Auto-starting game..."
			get_tree().create_timer(0.3).timeout.connect(_on_start_pressed)
		, CONNECT_ONE_SHOT)
	else:
		status_label.text = "Failed to host: Error code %d" % err
		status_label.modulate = Color(1.0, 0.3, 0.3)

func _on_auto_join_requested(port: int) -> void:
	if _auto_join_disabled:
		print("[Lobby] Companion requested auto-join on port %d, but auto-join is disabled via CLI flag." % port)
		return
	print("[Lobby] Companion requested auto-join on port: ", port)
	port_input.text = str(port)
	ip_input.text = "127.0.0.1"
	status_label.text = "Companion host detected on port %d. Auto-joining..." % port
	status_label.modulate = Color(0.3, 0.8, 1.0)
	_on_join_pressed()

func _on_instance_count_updated(count: int) -> void:
	if count == 2 and DebugTools and DebugTools.instance_index == 0:
		_check_auto_join_2p()

func _check_auto_join_2p() -> void:
	if _has_auto_joined_once or _auto_join_disabled:
		return
	if NetworkManager.peer != null:
		return
	_has_auto_joined_once = true
	print("[Lobby] 2-window mode detected! Auto-initiating 2-Player Quick Join...")
	get_tree().create_timer(0.2).timeout.connect(_on_multi_debug_pressed)
