extends Node

## DebugTools: Automatic grid layout and instance detection for multi-instance debugging.
## Respects default 16:9 aspect ratio and dynamically places instances side-by-side.

const BASE_PORT: int = 5920
const MAX_SEARCH_INSTANCES: int = 8
const DEFAULT_ASPECT_RATIO: float = 16.0 / 9.0
const TITLE_BAR_HEIGHT: int = 34
const BORDER_MARGIN: int = 24

var instance_index: int = 0
var instance_socket: TCPServer = null
var active_instance_count: int = 1
var is_active: bool = false
var _poll_timer: Timer = null

func _init() -> void:
	if not OS.is_debug_build():
		return
	is_active = true
	detect_instance_index()

func detect_instance_index() -> void:
	instance_socket = TCPServer.new()
	for idx in range(MAX_SEARCH_INSTANCES):
		if instance_socket.listen(BASE_PORT + idx) == OK:
			instance_index = idx
			break

func _ready() -> void:
	if not is_active:
		return
	
	# If this is a secondary instance, ping instance 0 so it knows immediately
	if instance_index > 0:
		_notify_instance_zero()
	
	# Wait two frames for Godot's internal viewport and window creation to settle
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Initial layout check
	update_layout()
	
	# Check again after a brief moment for instances launched nearly simultaneously
	get_tree().create_timer(0.25).timeout.connect(update_layout)
	get_tree().create_timer(0.60).timeout.connect(update_layout)
	get_tree().create_timer(1.20).timeout.connect(update_layout)
	
	# Recurring monitor for dynamic instance changes
	_poll_timer = Timer.new()
	_poll_timer.wait_time = 1.5
	_poll_timer.autostart = true
	_poll_timer.timeout.connect(_on_periodic_poll)
	add_child(_poll_timer)

func _process(_delta: float) -> void:
	# If instance 0 receives connection from companion instance, immediately update
	if instance_socket and instance_socket.is_connection_available():
		var peer = instance_socket.take_connection()
		if peer:
			peer.disconnect_from_host()
		update_layout()

func _notify_instance_zero() -> void:
	# Secondary instances connect to instance 0's port to wake it up
	var client = StreamPeerTCP.new()
	client.connect_to_host("127.0.0.1", BASE_PORT)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if instance_socket:
			instance_socket.stop()
			instance_socket = null

func _on_periodic_poll() -> void:
	var probed = probe_active_instances()
	if probed != active_instance_count:
		active_instance_count = probed
		apply_grid_layout(active_instance_count)

func update_layout() -> void:
	active_instance_count = probe_active_instances()
	apply_grid_layout(active_instance_count)

func probe_active_instances() -> int:
	var count = 0
	for idx in range(MAX_SEARCH_INSTANCES):
		if idx == instance_index:
			count += 1
		else:
			var test_server = TCPServer.new()
			var err = test_server.listen(BASE_PORT + idx)
			if err != OK:
				# Port is occupied by another running debug instance
				count += 1
			else:
				test_server.stop()
	return maxi(count, 1)

func apply_grid_layout(total_instances: int) -> void:
	var screen_rect: Rect2i = DisplayServer.screen_get_usable_rect()
	if screen_rect.size.x <= 0 or screen_rect.size.y <= 0:
		var full_size = DisplayServer.screen_get_size()
		screen_rect = Rect2i(Vector2i.ZERO, full_size if full_size.x > 0 else Vector2i(1920, 1080))
		
	# Single instance: Center on screen with comfortable default 16:9 size (1280x720)
	if total_instances <= 1:
		var target_size = Vector2i(1280, 720)
		target_size.x = mini(target_size.x, screen_rect.size.x - BORDER_MARGIN * 2)
		target_size.y = int(target_size.x / DEFAULT_ASPECT_RATIO)
		
		var target_pos = screen_rect.position + (screen_rect.size - target_size) / 2
		target_pos.y = maxi(target_pos.y, screen_rect.position.y + TITLE_BAR_HEIGHT)
		_set_window_rect(target_size, target_pos)
		return

	# Two instances: Side-by-side maintaining 16:9 aspect ratio
	if total_instances == 2:
		var max_w: float = (float(screen_rect.size.x) / 2.0) - float(BORDER_MARGIN * 2)
		var max_h: float = float(screen_rect.size.y) - float(TITLE_BAR_HEIGHT) - float(BORDER_MARGIN * 2)
		
		# Fit 16:9 inside (max_w, max_h)
		var target_w = max_w
		var target_h = target_w / DEFAULT_ASPECT_RATIO
		if target_h > max_h:
			target_h = max_h
			target_w = target_h * DEFAULT_ASPECT_RATIO
			
		var win_size = Vector2i(int(target_w), int(target_h))
		
		# Center vertically in the usable screen
		var pos_y = screen_rect.position.y + int((screen_rect.size.y - win_size.y) / 2.0)
		pos_y = maxi(pos_y, screen_rect.position.y + TITLE_BAR_HEIGHT)
		
		# Center horizontally in left and right halves
		var half_w = screen_rect.size.x / 2
		var pos_x = 0
		if instance_index == 0:
			# Left half
			pos_x = screen_rect.position.x + (half_w - win_size.x) / 2
		else:
			# Right half
			pos_x = screen_rect.position.x + half_w + (half_w - win_size.x) / 2
			
		_set_window_rect(win_size, Vector2i(pos_x, pos_y))
		return

	# 3+ instances: Multi-column/row grid maintaining 16:9
	var cols: int = ceili(sqrt(total_instances))
	var rows: int = ceili(float(total_instances) / cols)
	
	var col_idx: int = instance_index % cols
	var row_idx: int = instance_index / cols
	
	var cell_w: float = float(screen_rect.size.x) / float(cols)
	var cell_h: float = float(screen_rect.size.y) / float(rows)
	
	var max_w: float = cell_w - float(BORDER_MARGIN * 2)
	var max_h: float = cell_h - float(TITLE_BAR_HEIGHT) - float(BORDER_MARGIN)
	
	var target_w = max_w
	var target_h = target_w / DEFAULT_ASPECT_RATIO
	if target_h > max_h:
		target_h = max_h
		target_w = target_h * DEFAULT_ASPECT_RATIO
		
	var win_size = Vector2i(int(target_w), int(target_h))
	
	var origin_x = screen_rect.position.x + int(col_idx * cell_w) + int((cell_w - win_size.x) / 2.0)
	var origin_y = screen_rect.position.y + int(row_idx * cell_h) + int((cell_h - win_size.y) / 2.0)
	origin_y = maxi(origin_y, screen_rect.position.y + TITLE_BAR_HEIGHT)
	
	_set_window_rect(win_size, Vector2i(origin_x, origin_y))

func _set_window_rect(target_size: Vector2i, target_pos: Vector2i) -> void:
	var win = get_window()
	if win:
		win.size = target_size
		win.position = target_pos
	DisplayServer.window_set_size(target_size)
	DisplayServer.window_set_position(target_pos)
