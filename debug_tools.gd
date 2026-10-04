extends Node

## DebugTools: Automatic grid layout and instance detection for multi-instance debugging.
## Respects base project aspect ratio (16:9) and dynamically arranges instances side-by-side.
## Works on both landscape and portrait screens, guarantees identical dimensions,
## and eliminates startup jitter.

const DEFAULT_BASE_PORT: int = 5920
const MAX_SEARCH_INSTANCES: int = 8
const WINDOW_SPACING: int = 16
const SCREEN_MARGIN: int = 24
const ESTIMATED_TITLE_BAR: int = 32
const PORTRAIT_TOP_PADDING: int = 16

const MSG_INSTANCE_COUNT: int = 101
const MSG_AUTO_JOIN: int = 102

signal auto_join_requested(port: int)
signal instance_count_updated(count: int)

var base_port: int = DEFAULT_BASE_PORT
var instance_index: int = 0
var instance_socket: TCPServer = null
var active_instance_count: int = 1
var is_active: bool = false

# Inter-instance TCP synchronization
var _connected_peers: Array[StreamPeerTCP] = []
var _client_peer: StreamPeerTCP = null
var _debounce_timer: SceneTreeTimer = null
var _stabilized: bool = false

func _init() -> void:
	if not OS.is_debug_build():
		return
	is_active = true
	_detect_instance_index()

func _detect_instance_index() -> void:
	var project_dir = ProjectSettings.globalize_path("res://")
	var offset = (abs(project_dir.hash()) % 50) * 10
	base_port = 5900 + offset
	
	instance_socket = TCPServer.new()
	for idx in range(MAX_SEARCH_INSTANCES):
		if instance_socket.listen(base_port + idx) == OK:
			instance_index = idx
			break
	print("[DebugTools] Instance initialized with index: ", instance_index, " (port ", base_port + instance_index, ")")

func _ready() -> void:
	if not is_active:
		return
	
	# Only skip automatic tiling if explicitly requested with --no-tiling
	for arg in OS.get_cmdline_args():
		if arg == "--no-tiling":
			print("[DebugTools] --no-tiling detected; skipping automatic layout")
			return
	
	if "--wid" in OS.get_cmdline_args():
		push_warning("[DebugTools] Instance is embedded in editor (--wid). To tile freely on desktop, uncheck 'Embed Game on Next Play' in Godot's Game tab.")
	
	# Debounce initial positioning so companion instances have time to boot and connect (~200ms).
	# This prevents the primary window from jumping to the center and then jumping to the side.
	if instance_index == 0:
		_debounce_timer = get_tree().create_timer(0.40)
		_debounce_timer.timeout.connect(_on_startup_debounce)
	else:
		# Secondary instances connect to Instance 0 to announce presence and receive current count
		_client_peer = StreamPeerTCP.new()
		_client_peer.connect_to_host("127.0.0.1", base_port)
		
		# Fallback probe in case Instance 0 was launched separately
		get_tree().create_timer(0.30).timeout.connect(func():
			if not _stabilized:
				_stabilized = true
				apply_grid_layout(maxi(active_instance_count, instance_index + 1))
				instance_count_updated.emit(maxi(active_instance_count, instance_index + 1))
		)

func _process(_delta: float) -> void:
	if not is_active:
		return
		
	if instance_index == 0:
		# Instance 0 acts as coordinator
		if instance_socket and instance_socket.is_connection_available():
			var peer = instance_socket.take_connection()
			if peer:
				_connected_peers.append(peer)
				print("[DebugTools Host] Companion connected. Total known: ", _connected_peers.size() + 1)
				if not _stabilized:
					# Reset debounce window to allow any additional launching instances to register
					if _debounce_timer and _debounce_timer.timeout.is_connected(_on_startup_debounce):
						_debounce_timer.timeout.disconnect(_on_startup_debounce)
					_debounce_timer = get_tree().create_timer(0.12)
					_debounce_timer.timeout.connect(_on_startup_debounce)
				else:
					_on_peers_changed()
		
		# Prune disconnected companions
		var had_disconnect = false
		for i in range(_connected_peers.size() - 1, -1, -1):
			if _connected_peers[i].get_status() != StreamPeerTCP.STATUS_CONNECTED:
				_connected_peers.remove_at(i)
				had_disconnect = true
		if had_disconnect:
			print("[DebugTools Host] Companion disconnected. Total remaining: ", _connected_peers.size() + 1)
			_on_peers_changed()
	else:
		# Secondary instances listen for updates from host
		if _client_peer:
			_client_peer.poll()
			if _client_peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
				while _client_peer.get_available_bytes() > 0:
					var msg = _client_peer.get_8()
					if msg == MSG_AUTO_JOIN:
						if _client_peer.get_available_bytes() >= 2:
							var port = _client_peer.get_16()
							print("[DebugTools Client ", instance_index, "] Received auto-join request for port: ", port)
							auto_join_requested.emit(port)
					elif msg in range(1, MAX_SEARCH_INSTANCES + 1):
						# Direct atomic instance count
						if msg != active_instance_count:
							active_instance_count = msg
							_stabilized = true
							print("[DebugTools Client ", instance_index, "] Received active count: ", active_instance_count)
							apply_grid_layout(active_instance_count)
							instance_count_updated.emit(active_instance_count)

func broadcast_auto_join(port: int) -> void:
	if instance_index != 0:
		return
	print("[DebugTools Host] Broadcasting auto-join request for port: ", port)
	for peer in _connected_peers:
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			peer.put_8(MSG_AUTO_JOIN)
			peer.put_16(port)

func _on_peers_changed() -> void:
	var total = _connected_peers.size() + 1
	active_instance_count = total
	_stabilized = true
	# Broadcast updated count to all companion instances atomically
	for peer in _connected_peers:
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			peer.put_8(total)
	apply_grid_layout(active_instance_count)
	instance_count_updated.emit(active_instance_count)

func _on_startup_debounce() -> void:
	if not _stabilized:
		_on_peers_changed()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _client_peer:
			_client_peer.disconnect_from_host()
			_client_peer = null
		if instance_socket:
			instance_socket.stop()
			instance_socket = null

func apply_grid_layout(total_instances: int) -> void:
	var current_screen = DisplayServer.window_get_current_screen()
	var screen_rect: Rect2i = DisplayServer.screen_get_usable_rect(current_screen)
	if screen_rect.size.x <= 0 or screen_rect.size.y <= 0:
		var full_size = DisplayServer.screen_get_size(current_screen)
		screen_rect = Rect2i(Vector2i.ZERO, full_size if full_size.x > 0 else Vector2i(1920, 1080))
		
	# Base spec aspect ratio from ProjectSettings (default 16:9)
	var base_w: float = float(ProjectSettings.get_setting("display/window/size/viewport_width", 1280))
	var base_h: float = float(ProjectSettings.get_setting("display/window/size/viewport_height", 720))
	var base_aspect: float = base_w / base_h
	
	var is_landscape: bool = screen_rect.size.x >= screen_rect.size.y
	var cols: int = 1
	var rows: int = 1
	
	if total_instances <= 1:
		# When running as a single instance, leave it at the engine's default placement
		# so it doesn't jump or twitch on launch.
		return
	elif total_instances == 2:
		if is_landscape:
			var avail_w_for_2 = (float(screen_rect.size.x) - 2.0 * SCREEN_MARGIN - WINDOW_SPACING) / 2.0
			if avail_w_for_2 >= 480.0:
				cols = 2
				rows = 1
			else:
				cols = 1
				rows = 2
		else:
			# On vertical / portrait monitor: stack vertically so instances are much bigger
			cols = 1
			rows = 2
	elif total_instances == 3:
		var avail_w_for_3 = (float(screen_rect.size.x) - 2.0 * SCREEN_MARGIN - 2.0 * WINDOW_SPACING) / 3.0
		if is_landscape and avail_w_for_3 >= 480.0:
			cols = 3
			rows = 1
		elif is_landscape:
			cols = 2
			rows = 2
		else:
			cols = 1
			rows = 3
	else: # 4+ instances
		if is_landscape:
			cols = ceili(sqrt(total_instances))
			rows = ceili(float(total_instances) / float(cols))
		else:
			cols = 2
			rows = ceili(float(total_instances) / 2.0)
			
	# Window size calculation: identical dimensions for all windows
	var max_avail_w = maxf(float(screen_rect.size.x - 2 * SCREEN_MARGIN - (cols - 1) * WINDOW_SPACING) / float(cols), 320.0)
	var max_avail_h = maxf(float(screen_rect.size.y - 2 * SCREEN_MARGIN - (rows - 1) * (WINDOW_SPACING + ESTIMATED_TITLE_BAR) - ESTIMATED_TITLE_BAR) / float(rows), 180.0)
	
	var target_w = max_avail_w
	var target_h = target_w / base_aspect
	if target_h > max_avail_h:
		target_h = max_avail_h
		target_w = target_h * base_aspect
		
	if not is_landscape and total_instances == 2:
		# Ensure top panel does not exceed top screen margin when bottom panel is centered
		var max_h_for_top = (float(screen_rect.size.y) / 2.0 - (WINDOW_SPACING + ESTIMATED_TITLE_BAR) - SCREEN_MARGIN) / 1.5
		if target_h > max_h_for_top:
			target_h = max_h_for_top
			target_w = target_h * base_aspect
		# Scale to 75% size for comfortable vertical viewing
		target_w *= 0.75
		target_h *= 0.75
	elif total_instances <= 2 and is_landscape:
		# Cap maximum size so windows don't needlessly fill the entire screen
		target_w = minf(target_w, 1152.0)
		target_h = target_w / base_aspect
	elif total_instances == 1:
		target_w = minf(target_w, 1280.0)
		target_h = target_w / base_aspect
		
	var win_size = Vector2i(int(target_w), int(target_h))
	
	var pos_x = 0
	var pos_y = 0
	
	if not is_landscape and total_instances == 2:
		# Vertical monitor 2-instance layout:
		# Horizontally centered, top window top-aligned with slight padding, bottom window directly below
		pos_x = screen_rect.position.x + (screen_rect.size.x - win_size.x) / 2
		var top_y = screen_rect.position.y + PORTRAIT_TOP_PADDING
		var bottom_y = top_y + win_size.y + (WINDOW_SPACING + ESTIMATED_TITLE_BAR)
		pos_y = top_y if instance_index == 0 else bottom_y
	else:
		# Center the entire layout group inside the usable screen
		var total_w = cols * win_size.x + (cols - 1) * WINDOW_SPACING
		var total_h = rows * win_size.y + (rows - 1) * (WINDOW_SPACING + ESTIMATED_TITLE_BAR)
		
		var start_x = screen_rect.position.x + (screen_rect.size.x - total_w) / 2
		var start_y = screen_rect.position.y + (screen_rect.size.y - total_h) / 2
		start_y = maxi(start_y, screen_rect.position.y)
		
		var col_idx = instance_index % cols
		var row_idx = instance_index / cols
		
		pos_x = start_x + col_idx * (win_size.x + WINDOW_SPACING)
		pos_y = start_y + row_idx * (win_size.y + WINDOW_SPACING + ESTIMATED_TITLE_BAR)
	
	_set_window_rect(win_size, Vector2i(pos_x, pos_y))

func _set_window_rect(target_size: Vector2i, target_pos: Vector2i) -> void:
	var win = get_window()
	if win:
		if win.size == target_size and win.position == target_pos:
			return
		win.size = target_size
		win.position = target_pos
	DisplayServer.window_set_size(target_size)
	DisplayServer.window_set_position(target_pos)
	print("[DebugTools ", instance_index, "] Positioned window: size=", target_size, " pos=", target_pos)
