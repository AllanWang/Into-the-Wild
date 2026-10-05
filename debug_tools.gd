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
const MSG_HOST_RECT: int = 103

signal auto_join_requested(port: int)
signal instance_count_updated(count: int)

var base_port: int = DEFAULT_BASE_PORT
var instance_index: int = 0
var instance_socket: TCPServer = null
var active_instance_count: int = 1
var is_active: bool = false
var is_embedded: bool = false
var host_window_rect: Rect2i = Rect2i()

# Inter-instance TCP synchronization
var _connected_peers: Array[StreamPeerTCP] = []
var _client_peer: StreamPeerTCP = null
var _debounce_timer: SceneTreeTimer = null
var _stabilized: bool = false
var host_is_embedded: bool = false

func _init() -> void:
	if not OS.is_debug_build():
		return
	is_active = true
	_detect_embedded_status()
	_detect_instance_index()

func _detect_embedded_status() -> void:
	var args = OS.get_cmdline_args()
	for i in range(args.size()):
		var arg = args[i]
		if arg == "--wid" or arg.begins_with("--wid="):
			is_embedded = true
		elif arg == "--position" and i + 1 < args.size():
			var parts = args[i + 1].replace("\"", "").replace("'", "").split(",")
			if parts.size() == 2:
				host_window_rect.position = Vector2i(int(parts[0]), int(parts[1]))
		elif arg == "--resolution" and i + 1 < args.size():
			var parts = args[i + 1].replace("\"", "").replace("'", "").to_lower().split("x")
			if parts.size() == 2:
				host_window_rect.size = Vector2i(int(parts[0]), int(parts[1]))

	# In Godot 4, check if the window is an embedded subwindow or embedded in editor
	var win = get_window()
	if win and win.is_embedded():
		is_embedded = true

	if is_embedded:
		print("[DebugTools] Detected embedded in editor. Initial rect estimate: ", host_window_rect)

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
	
	if is_embedded:
		print("[DebugTools] Instance is embedded in editor (--wid).")
	
	# Only skip automatic tiling if explicitly requested with --no-tiling
	for arg in OS.get_cmdline_args():
		if arg == "--no-tiling":
			print("[DebugTools] --no-tiling detected; skipping automatic layout")
			return
	
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
					elif msg == MSG_HOST_RECT:
						# Read host window rect: x (32), y (32), w (32), h (32), is_embedded (8)
						if _client_peer.get_available_bytes() >= 17:
							var hx = _client_peer.get_32()
							var hy = _client_peer.get_32()
							var hw = _client_peer.get_32()
							var hh = _client_peer.get_32()
							host_is_embedded = (_client_peer.get_8() == 1)
							host_window_rect = Rect2i(hx, hy, hw, hh)
							print("[DebugTools Client ", instance_index, "] Received Host Rect: ", host_window_rect, " Host Embedded: ", host_is_embedded)
							apply_grid_layout(active_instance_count)
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

func broadcast_host_rect() -> void:
	if instance_index != 0:
		return
	var win = get_window()
	var pos: Vector2i = DisplayServer.window_get_position()
	var size: Vector2i = DisplayServer.window_get_size()
	if win:
		pos = win.position
		size = win.size
	# If embedded, fallback to command line rect if DisplayServer returned (0,0)
	if is_embedded:
		if size.x <= 0 or size.y <= 0:
			size = host_window_rect.size
		if pos == Vector2i.ZERO and host_window_rect.position != Vector2i.ZERO:
			pos = host_window_rect.position
	host_window_rect = Rect2i(pos, size)
	for peer in _connected_peers:
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			peer.put_8(MSG_HOST_RECT)
			peer.put_32(pos.x)
			peer.put_32(pos.y)
			peer.put_32(size.x)
			peer.put_32(size.y)
			peer.put_8(1 if is_embedded else 0)

func _on_peers_changed() -> void:
	var total = _connected_peers.size() + 1
	active_instance_count = total
	_stabilized = true
	# Broadcast host rect and count to all companion instances
	broadcast_host_rect()
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
	# If Instance 0 is embedded in the editor, it must never be moved or floated.
	if instance_index == 0 and is_embedded:
		print("[DebugTools Host] Embedded in editor; leaving Host window embedded and untouched.")
		return

	if total_instances <= 1:
		return

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
	
	if total_instances == 2:
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
	
	# Embedded Host handling (e.g. running embedded inside the Godot editor):
	# If Instance 0 is embedded, it cannot and should not be moved.
	# Companion instances will adapt to Instance 0's actual dimensions and place directly beneath it.
	if instance_index == 0 and is_embedded:
		print("[DebugTools Host] Embedded in editor; leaving Host window in place.")
		return
		
	if instance_index == 1 and (host_is_embedded or (host_window_rect.size.x > 0 and host_window_rect.size.y > 0)):
		# When the host is embedded (or has sent its rect), companion window matches its exact size
		# and aligns directly below it (following portrait orientation).
		var companion_size: Vector2i = host_window_rect.size if host_window_rect.size.x > 0 else win_size
		var companion_pos: Vector2i = Vector2i(
			host_window_rect.position.x if host_window_rect.position.x > 0 else screen_rect.position.x + (screen_rect.size.x - companion_size.x) / 2,
			host_window_rect.position.y + companion_size.y + WINDOW_SPACING
		)
		
		# If positioning below would push the window off the bottom of the screen, clamp safely
		if companion_pos.y + companion_size.y > screen_rect.position.y + screen_rect.size.y:
			companion_pos.y = screen_rect.position.y + screen_rect.size.y - companion_size.y - SCREEN_MARGIN
			
		_set_window_rect(companion_size, companion_pos, true)
		return

	if not is_landscape and total_instances == 2:
		# Vertical monitor 2-instance layout (both floating):
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
	
	_set_window_rect(win_size, Vector2i(pos_x, pos_y), instance_index > 0)

func _set_window_rect(target_size: Vector2i, target_pos: Vector2i, bring_to_top: bool = false) -> void:
	if is_embedded:
		return
	var win = get_window()
	if win:
		win.size = target_size
		win.position = target_pos
	DisplayServer.window_set_size(target_size)
	DisplayServer.window_set_position(target_pos)
	
	if bring_to_top:
		# Bring window to foreground on launch without keeping it permanently locked ALWAYS_ON_TOP.
		# Momentarily set ALWAYS_ON_TOP so Windows raises it cleanly above the editor and other windows,
		# then release the flag so other clicked apps can pop over it.
		DisplayServer.window_move_to_foreground()
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
		get_tree().create_timer(0.25).timeout.connect(func():
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, false)
		)
		
	print("[DebugTools ", instance_index, "] Positioned window: size=", target_size, " pos=", target_pos, " initial_top=", bring_to_top)

