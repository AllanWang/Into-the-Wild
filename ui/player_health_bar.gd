class_name PlayerHealthBar
extends Control

## Ethereal Lattice Bottom-Left Player HUD inspired by Breath of the Wild × Shape of Dreams.
## - Normal Mode (1.0x): [Dash ◆ (◆ ◆ ◆)] | [LMB ◆ (◆ ◆ ◆)] [RMB ◆ (◆ ◆ ◆)] | [Q ◆] [E ◆] | [R ◆]
## - Press [Tab] (Toggle): Toggles zoomed Edit + Attributes mode (1.92x) — drag Shards, Weapons,
##   and Abilities freely with normal Left-Click (no key held down), press Tab or Esc to close.
## - Hold [Alt]: Quick-zooms the HUD (1.92x) while held for fast Shard/Weapon/Ability dragging.
## - Pickup Placement Mode: Scales the HUD up with glowing target sockets while a stationary
##   Preview Card sits above the HUD (normal pointer — nothing stuck to your cursor).

const CatalogScript = preload("res://scripts/data/combat_catalog.gd")

var _bound_health: HealthComponent = null
var _bound_player: Node = null
var _bound_stats: Node = null

var _max_hp: float = 100.0
var _current_hp: float = 100.0
var _current_shield: float = 0.0
var _target_hp_ratio: float = 1.0
var _trail_hp_ratio: float = 1.0
var _hit_flash_timer: float = 0.0
var _heal_flash_timer: float = 0.0

var _dash_charges: int = 3
var _max_dash_charges: int = 3
var _dash_charge_progress: float = 0.0
var _dash_inter_delay: float = 0.0
var _dash_charge_duration: float = 3.0
var _dash_ready_flash: float = 0.0

# Cached loadout display state
var _slot_glyphs: Array[int] = [0, 0, 0, 0, 0] # LMB, RMB, Q, E, R
var _slot_colors: Array[Color] = [
	Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE
]
var _slot_names: Array[String] = ["", "", "", "", ""]
var _slot_equipped: Array[bool] = [true, true, false, false, false]
var _slot_progress: Array[float] = [1.0, 1.0, 1.0, 1.0, 1.0]
var _weapon_shard_ids: Array = [[0, 0, 0], [0, 0, 0]]

# Edit Mode ([Tab] toggle + [Alt] hold) & Pickup Placement zoom state
var _tab_toggled_open: bool = false
var _alt_held: bool = false
var _was_edit_mode: bool = false
var _alt_zoom_t: float = 0.0
var _pulse_phase: float = 0.0
var _sockets: Array[Dictionary] = []
var _hovered_socket_idx: int = -1
var _dragging: bool = false
var _drag_from_idx: int = -1
var _selected_socket_idx: int = -1

# Event-driven canvas mouse position (avoids Godot Embedded Game View's toolbar offset
# in get_viewport().get_mouse_position() / get_local_mouse_position()!)
var _last_canvas_mouse: Vector2 = Vector2(140.0, 620.0)
var _mouse_local: Vector2 = Vector2.ZERO
var _drag_attempted_this_press: bool = false
var _prev_polled_lmb: bool = false

# Pickup Placement Mode state
var _placement_active: bool = false
var _placement_spec: Dictionary = {}
var _placement_on_placed: Callable = Callable()
var _placement_on_cancel: Callable = Callable()
var _placement_arm_frames: int = 0

var _hp_num_label: Label = null
var _hp_max_label: Label = null
var _shield_label: Label = null
var _stats_panel: PanelContainer = null
var _stats_body_label: Label = null
var _slot_key_labels: Array[Label] = []

var _scratch_quad := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _scratch_closed := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])

# Layout geometry constants (within 308 x 116 bottom-left footprint)
const BAR_X: float = 8.0
const BAR_Y: float = 92.0
const BAR_W: float = 284.0
const BAR_H: float = 9.0
const CAP_HALF_DIAG: float = 5.5

const ROW_Y: float = 20.0
const DASH_CENTER := Vector2(24.0, ROW_Y)
const DIAMOND_HALF_DIAG: float = 16.5
const ARTIFACT_HALF_DIAG: float = 18.0

const SLOT_CENTERS_X: Array[float] = [77.0, 122.0, 175.0, 218.0, 273.0]
const SEPARATOR_X: Array[float] = [51.0, 149.0, 245.0]
const SLOT_KEYS_TEXT: Array[String] = ["LMB", "RMB", "Q", "E", "R"]

const CHARGE_PIP_Y_OFFSET: float = 7.5
const CHARGE_PIP_SPACING: float = 9.2
const CHARGE_PIP_HALF_DIAG: float = 3.1

const SHARD_PIP_Y: float = 55.5
const SHARD_PIP_SPACING: float = 12.6
const SHARD_PIP_HALF_DIAG: float = 5.4

const ALT_ZOOM_SCALE: float = 1.92

# Palette (Breath of the Wild × Shape of Dreams)
const COL_GLASS_DARK := Color(0.043, 0.063, 0.098, 0.72)
const COL_GLASS_EMPTY := Color(0.035, 0.051, 0.082, 0.50)
const COL_CAP_DARK := Color(0.051, 0.071, 0.110, 0.84)
const COL_IVORY_LINE := Color(0.918, 0.894, 0.843, 0.30)
const COL_IVORY_DIM := Color(0.918, 0.894, 0.843, 0.18)
const COL_IVORY_CAP := Color(0.918, 0.894, 0.843, 0.50)
const COL_IVORY_TEXT := Color(0.961, 0.945, 0.910, 1.0)
const COL_IVORY_MUTED := Color(0.918, 0.894, 0.843, 0.64)
const COL_TEXT_SHADOW := Color(0.024, 0.039, 0.063, 0.82)
const COL_GOLD_HIGHLIGHT := Color(1.0, 0.86, 0.42, 0.98)

const COL_HP_CRIMSON := Color(0.941, 0.294, 0.263, 1.0)
const COL_HP_CRITICAL := Color(1.0, 0.220, 0.255, 1.0)
const COL_HP_FLASH := Color(1.0, 0.945, 0.910, 1.0)
const COL_HP_HEAL := Color(0.42, 1.0, 0.68, 1.0)
const COL_MENISCUS := Color(1.0, 0.965, 0.925, 0.95)
const COL_TRAIL_GOLD := Color(0.965, 0.827, 0.396, 0.86)
const COL_SHIELD_CYAN := Color(0.361, 0.882, 1.0, 0.86)
const COL_SHIELD_DIVIDER := Color(0.961, 0.945, 0.910, 0.78)

const COL_DASH_FULL_RIM := Color(0.392, 1.0, 0.561, 0.68)
const COL_DASH_PROGRESS := Color(0.392, 1.0, 0.561, 0.96)
const COL_DASH_PIP_ACTIVE := Color(0.392, 1.0, 0.561, 0.92)
const COL_DASH_PIP_EMPTY := Color(0.051, 0.071, 0.110, 0.72)
const COL_GLYPH_READY := Color(0.955, 0.935, 0.895, 0.96)
const COL_GLYPH_LOCKED := Color(0.918, 0.894, 0.843, 0.28)
const COL_MICRO_TICK := Color(0.035, 0.051, 0.078, 0.46)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(308.0, 116.0)
	pivot_offset = Vector2(0.0, 116.0)
	_init_socket_table()
	_build_labels_if_needed()
	_refresh_labels()
	set_process(false)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		pivot_offset = Vector2(0.0, size.y)
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		Input.action_release("inspect_loadout")
		if _alt_held:
			_alt_held = false
			_sync_edit_mode_transition()


func _canvas_to_local(canvas_pt: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * canvas_pt


func _is_alt_pressed() -> bool:
	if _placement_active:
		return false
	if _bound_player != null and is_instance_valid(_bound_player) and ("ui_input_blocked" in _bound_player):
		if bool(_bound_player.get("ui_input_blocked")):
			return false
	return (
		Input.is_action_pressed("inspect_loadout")
		or Input.is_key_pressed(KEY_ALT)
		or Input.is_physical_key_pressed(KEY_ALT)
	)


func _is_edit_mode() -> bool:
	return (_tab_toggled_open or _alt_held) and not _placement_active


func _is_interactive_zoom() -> bool:
	return _tab_toggled_open or _alt_held or _placement_active


func is_pickup_placement_active() -> bool:
	return _placement_active


func close_tab_edit_mode() -> void:
	if _tab_toggled_open:
		_tab_toggled_open = false
		_sync_edit_mode_transition()


## Enters Pickup Placement Mode: zooms the HUD up and pulses valid target sockets
## (while RewardDraftOverlay shows a stationary Preview Card above — no gem stuck to cursor).
func begin_pickup_placement(spec: Dictionary, on_placed_cb: Callable, on_cancel_cb: Callable) -> void:
	_tab_toggled_open = false
	_alt_held = false
	_sync_edit_mode_transition()

	_placement_active = true
	_placement_spec = spec.duplicate(true)
	_placement_on_placed = on_placed_cb
	_placement_on_cancel = on_cancel_cb
	_placement_arm_frames = 2
	_dragging = false
	_drag_from_idx = -1
	_selected_socket_idx = -1
	pivot_offset = Vector2(0.0, size.y if size.y > 1.0 else 116.0)
	_mouse_local = _canvas_to_local(_last_canvas_mouse)
	_hovered_socket_idx = _resolve_placement_socket(_mouse_local)
	if _stats_panel:
		_stats_panel.visible = false
	if _bound_player != null and is_instance_valid(_bound_player) and _bound_player.has_method("set_ui_input_blocked"):
		_bound_player.call("set_ui_input_blocked", true)
	set_process(true)
	queue_redraw()


func cancel_pickup_placement(notify_cancel: bool = true) -> void:
	if not _placement_active:
		return
	var cb: Callable = _placement_on_cancel
	_placement_active = false
	_placement_spec.clear()
	_placement_on_placed = Callable()
	_placement_on_cancel = Callable()
	_hovered_socket_idx = -1
	if not notify_cancel:
		if _bound_player != null and is_instance_valid(_bound_player) and _bound_player.has_method("set_ui_input_blocked"):
			_bound_player.call("set_ui_input_blocked", false)
	set_process(true)
	queue_redraw()
	if notify_cancel and cb.is_valid():
		cb.call()


func _commit_pickup_placement_socket(sock_idx: int) -> void:
	if not _placement_active or sock_idx < 0 or sock_idx >= _sockets.size():
		return
	if not _is_valid_placement_socket(sock_idx):
		return
	var sock: Dictionary = _sockets[sock_idx]
	var kind: String = str(sock["kind"])
	var target_slot: int = int(sock["group"])
	var sub_socket: int = int(sock["idx"]) if kind == "shard" else -1
	var cb: Callable = _placement_on_placed

	_placement_active = false
	_placement_spec.clear()
	_placement_on_placed = Callable()
	_placement_on_cancel = Callable()
	_hovered_socket_idx = -1
	if _bound_player != null and is_instance_valid(_bound_player) and _bound_player.has_method("set_ui_input_blocked"):
		_bound_player.call("set_ui_input_blocked", false)

	set_process(true)
	queue_redraw()
	if cb.is_valid():
		cb.call(target_slot, sub_socket)


func _init_socket_table() -> void:
	_sockets.clear()
	# Indices 0..5: The 6 Shard sockets beneath LMB & RMB (checked first for crisp priority!)
	for w_grp in range(2):
		var base_cx: float = SLOT_CENTERS_X[w_grp]
		var tag_prefix: String = "LMB" if w_grp == 0 else "RMB"
		for s_i in range(3):
			var sx: float = base_cx + float(s_i - 1) * SHARD_PIP_SPACING
			_sockets.append({
				"kind": "shard",
				"group": w_grp,
				"idx": s_i,
				"pos": Vector2(sx, SHARD_PIP_Y),
				"hit_diag": 11.5,
				"draw_diag": SHARD_PIP_HALF_DIAG,
				"tag": "%s Shard" % tag_prefix
			})

	# Indices 6..10: Main Diamonds (LMB=6, RMB=7, Q=8, E=9, R=10)
	_sockets.append({"kind": "weapon", "slot_idx": 0, "group": 0, "idx": 0, "pos": Vector2(SLOT_CENTERS_X[0], ROW_Y), "hit_diag": 21.5, "draw_diag": DIAMOND_HALF_DIAG, "tag": "LMB"})
	_sockets.append({"kind": "weapon", "slot_idx": 1, "group": 1, "idx": 1, "pos": Vector2(SLOT_CENTERS_X[1], ROW_Y), "hit_diag": 21.5, "draw_diag": DIAMOND_HALF_DIAG, "tag": "RMB"})
	_sockets.append({"kind": "ability", "slot_idx": 2, "group": 0, "idx": 0, "pos": Vector2(SLOT_CENTERS_X[2], ROW_Y), "hit_diag": 21.5, "draw_diag": DIAMOND_HALF_DIAG, "tag": "Q"})
	_sockets.append({"kind": "ability", "slot_idx": 3, "group": 1, "idx": 1, "pos": Vector2(SLOT_CENTERS_X[3], ROW_Y), "hit_diag": 21.5, "draw_diag": DIAMOND_HALF_DIAG, "tag": "E"})
	_sockets.append({"kind": "artifact", "slot_idx": 4, "group": 0, "idx": 0, "pos": Vector2(SLOT_CENTERS_X[4], ROW_Y), "hit_diag": 22.0, "draw_diag": ARTIFACT_HALF_DIAG, "tag": "R"})


func _input(event: InputEvent) -> void:
	# Always record accurate viewport-canvas mouse coords from InputEventMouse!
	if event is InputEventMouse:
		_last_canvas_mouse = (event as InputEventMouse).position

	# If another modal (Pedestal Draft / Tutorial / Game Over) is blocking UI input, close Tab edit
	var player_ui_blocked: bool = false
	if _bound_player != null and is_instance_valid(_bound_player) and ("ui_input_blocked" in _bound_player):
		player_ui_blocked = bool(_bound_player.get("ui_input_blocked"))
	if player_ui_blocked and not _placement_active and _tab_toggled_open:
		_tab_toggled_open = false
		_sync_edit_mode_transition()

	# Toggle [Tab] Edit + Attributes Mode on press!
	if event is InputEventKey and event.pressed and not event.echo:
		var ke_top: InputEventKey = event as InputEventKey
		if ke_top.is_action("show_stats") or ke_top.keycode == KEY_TAB:
			if not _placement_active and not player_ui_blocked:
				_tab_toggled_open = not _tab_toggled_open
				_sync_edit_mode_transition()
				get_viewport().set_input_as_handled()
				return
		elif ke_top.keycode == KEY_ESCAPE and _tab_toggled_open and not _placement_active:
			_tab_toggled_open = false
			_sync_edit_mode_transition()
			get_viewport().set_input_as_handled()
			return

	# Consume raw Alt key events so Windows / Editor menu bar doesn't steal focus!
	if event is InputEventKey:
		var ke_alt: InputEventKey = event as InputEventKey
		if ke_alt.keycode == KEY_ALT or ke_alt.physical_keycode == KEY_ALT:
			var alt_now: bool = (_is_alt_pressed() or ke_alt.pressed) and ke_alt.pressed and not _placement_active and not player_ui_blocked
			if alt_now != _alt_held:
				_alt_held = alt_now
				_sync_edit_mode_transition()
			get_viewport().set_input_as_handled()
			return

	var live_alt_check: bool = _is_alt_pressed()
	if live_alt_check != _alt_held:
		_alt_held = live_alt_check
		_sync_edit_mode_transition()

	# 1. Pickup Placement Mode input (click glowing slot on zoomed HUD!)
	if _placement_active:
		if event is InputEventKey and event.pressed and not event.echo:
			var pke: InputEventKey = event as InputEventKey
			if pke.keycode == KEY_ESCAPE or pke.keycode == KEY_BACKSPACE:
				cancel_pickup_placement(true)
				get_viewport().set_input_as_handled()
				return
			var pcat: String = str(_placement_spec.get("category", ""))
			if pcat == "ability":
				if pke.keycode == KEY_Q:
					_commit_pickup_placement_socket(8)
					get_viewport().set_input_as_handled()
					return
				elif pke.keycode == KEY_E:
					_commit_pickup_placement_socket(9)
					get_viewport().set_input_as_handled()
					return

		if event is InputEventMouseMotion:
			var pmm: InputEventMouseMotion = make_input_local(event) as InputEventMouseMotion
			_mouse_local = pmm.position if pmm != null else _canvas_to_local(_last_canvas_mouse)
			_hovered_socket_idx = _resolve_placement_socket(_mouse_local)
			queue_redraw()
		elif event is InputEventMouseButton and _placement_arm_frames <= 0:
			var pmb: InputEventMouseButton = event as InputEventMouseButton
			if pmb.pressed and pmb.button_index == MOUSE_BUTTON_RIGHT:
				cancel_pickup_placement(true)
				get_viewport().set_input_as_handled()
				return
			if pmb.pressed and pmb.button_index == MOUSE_BUTTON_LEFT:
				var lmb_ev: InputEventMouseButton = make_input_local(event) as InputEventMouseButton
				_mouse_local = lmb_ev.position if lmb_ev != null else _canvas_to_local(_last_canvas_mouse)
				var target_sock: int = _resolve_placement_socket(_mouse_local)
				if target_sock >= 0 and _is_valid_placement_socket(target_sock):
					_commit_pickup_placement_socket(target_sock)
					get_viewport().set_input_as_handled()
		return

	# 2. Edit Mode ([Tab] toggle OR [Alt] hold) Drag & Drop
	if not _is_edit_mode():
		return

	if event is InputEventMouseMotion:
		var mm_raw: InputEventMouseMotion = event as InputEventMouseMotion
		var local_mm: InputEventMouseMotion = make_input_local(event) as InputEventMouseMotion
		_mouse_local = local_mm.position if local_mm != null else _canvas_to_local(_last_canvas_mouse)

		# Fallback if Windows swallowed the initial WM_LBUTTONDOWN on Alt press:
		# the very first motion event with Left Button held starts the drag cleanly!
		if (mm_raw.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and not _dragging and not _drag_attempted_this_press:
			_drag_attempted_this_press = true
			_prev_polled_lmb = true
			_handle_edit_press(_mouse_local)

		_hovered_socket_idx = _resolve_hover_or_drop_preview(_mouse_local)
		queue_redraw()

	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			var local_mb: InputEventMouseButton = make_input_local(event) as InputEventMouseButton
			_mouse_local = local_mb.position if local_mb != null else _canvas_to_local(_last_canvas_mouse)
			if mb.pressed:
				_drag_attempted_this_press = true
				_prev_polled_lmb = true
				if _handle_edit_press(_mouse_local):
					get_viewport().set_input_as_handled()
			else:
				_drag_attempted_this_press = false
				_prev_polled_lmb = false
				if _handle_edit_release(_mouse_local):
					get_viewport().set_input_as_handled()


func _handle_edit_press(pt: Vector2) -> bool:
	var inside_hud_zone: bool = Rect2(-18.0, -32.0, 344.0, 162.0).has_point(pt)
	if not inside_hud_zone:
		_selected_socket_idx = -1
		queue_redraw()
		return false

	# If a socket was already click-selected, clicking a valid target drops immediately!
	var drop_candidate: int = _resolve_drop_target_socket(_selected_socket_idx, pt) if _selected_socket_idx >= 0 else -1
	if _selected_socket_idx >= 0 and drop_candidate >= 0 and drop_candidate != _selected_socket_idx and _can_drop_onto(_selected_socket_idx, drop_candidate):
		_perform_drop(_selected_socket_idx, drop_candidate)
		_selected_socket_idx = -1
		queue_redraw()
		return true

	var start_idx: int = _resolve_drag_start_socket(pt)
	if start_idx >= 0 and _can_start_drag(start_idx):
		_dragging = true
		_drag_from_idx = start_idx
		_hovered_socket_idx = start_idx
		queue_redraw()
		return true

	_selected_socket_idx = -1
	queue_redraw()
	return true


func _handle_edit_release(pt: Vector2) -> bool:
	if not _dragging:
		return false
	var from_idx: int = _drag_from_idx
	_dragging = false
	_drag_from_idx = -1

	var target_idx: int = _resolve_drop_target_socket(from_idx, pt)
	if target_idx >= 0 and target_idx != from_idx and _can_drop_onto(from_idx, target_idx):
		_perform_drop(from_idx, target_idx)
		_selected_socket_idx = -1
	elif target_idx == from_idx:
		if _selected_socket_idx >= 0 and _selected_socket_idx != target_idx and _can_drop_onto(_selected_socket_idx, target_idx):
			_perform_drop(_selected_socket_idx, target_idx)
			_selected_socket_idx = -1
		else:
			_selected_socket_idx = target_idx if _selected_socket_idx != target_idx else -1

	_hovered_socket_idx = _hit_test_socket(pt)
	queue_redraw()
	return true


func _sync_edit_mode_transition() -> void:
	var now_edit: bool = _is_edit_mode()
	pivot_offset = Vector2(0.0, size.y if size.y > 1.0 else 116.0)

	if _stats_panel != null:
		var show_stats_card: bool = _tab_toggled_open and not _placement_active
		if show_stats_card and not _stats_panel.visible:
			_refresh_stats_sheet_text()
		_stats_panel.visible = show_stats_card

	if now_edit == _was_edit_mode:
		set_process(true)
		queue_redraw()
		return

	if not now_edit and _dragging:
		# Release-order forgiveness: releasing Alt right before releasing LMB still drops cleanly!
		_mouse_local = _canvas_to_local(_last_canvas_mouse)
		_handle_edit_release(_mouse_local)

	_was_edit_mode = now_edit
	_prev_polled_lmb = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	_drag_attempted_this_press = _prev_polled_lmb

	if not now_edit:
		_dragging = false
		_drag_from_idx = -1
		_selected_socket_idx = -1
		_hovered_socket_idx = -1
	else:
		_mouse_local = _canvas_to_local(_last_canvas_mouse)
		_hovered_socket_idx = _hit_test_socket(_mouse_local)

	if _bound_player != null and is_instance_valid(_bound_player) and _bound_player.has_method("set_alt_inspect_active"):
		_bound_player.call("set_alt_inspect_active", now_edit)

	set_process(true)
	queue_redraw()


func _hit_test_socket(pt: Vector2) -> int:
	# 1. Check Shard sockets (0..5) first — closest diamond wins
	var best_sh: int = -1
	var best_sh_d: float = INF
	for i in range(6):
		var s: Dictionary = _sockets[i]
		var c: Vector2 = s["pos"] as Vector2
		var md: float = absf(pt.x - c.x) + absf(pt.y - c.y)
		if md <= float(s["hit_diag"]) and md < best_sh_d:
			best_sh_d = md
			best_sh = i
	if best_sh >= 0:
		return best_sh

	# 2. Check Main Weapon / Ability / Artifact diamonds (6..10)
	for j in range(6, _sockets.size()):
		var m: Dictionary = _sockets[j]
		var mc: Vector2 = m["pos"] as Vector2
		if (absf(pt.x - mc.x) + absf(pt.y - mc.y)) <= float(m["hit_diag"]):
			return j
	return -1


## Forgiving start-drag resolver: clicking anywhere in a weapon's shard row near an
## equipped shard (even slightly off-center or on an adjacent empty pip) grabs that shard!
func _resolve_drag_start_socket(pt: Vector2) -> int:
	var direct: int = _hit_test_socket(pt)
	if direct >= 0 and _can_start_drag(direct):
		return direct

	if pt.y >= 38.0 and pt.y <= 76.0:
		var grp: int = -1
		if pt.x >= 46.0 and pt.x <= 99.5:
			grp = 0
		elif pt.x > 99.5 and pt.x <= 154.0:
			grp = 1
		if grp >= 0:
			var best_idx: int = -1
			var best_dist: float = 26.0
			for s_i in range(3):
				var sock_i: int = grp * 3 + s_i
				if _can_start_drag(sock_i):
					var spos: Vector2 = _sockets[sock_i]["pos"] as Vector2
					var d: float = pt.distance_to(spos)
					if d < best_dist:
						best_dist = d
						best_idx = sock_i
			if best_idx >= 0:
				return best_idx

	return direct


func _resolve_drop_target_socket(from_idx: int, pt: Vector2) -> int:
	if from_idx < 0 or from_idx >= _sockets.size():
		return -1
	var direct: int = _hit_test_socket(pt)
	if direct >= 0 and direct != from_idx and _can_drop_onto(from_idx, direct):
		return direct

	var k_from: String = str(_sockets[from_idx]["kind"])
	if pt.y >= -18.0 and pt.y <= 88.0:
		if k_from == "shard" or k_from == "weapon":
			if pt.x >= 44.0 and pt.x <= 99.5:
				return 6 # LMB Weapon column
			if pt.x > 99.5 and pt.x <= 156.0:
				return 7 # RMB Weapon column
		elif k_from == "ability":
			if pt.x >= 151.0 and pt.x <= 196.5:
				return 8 # Q Ability column
			if pt.x > 196.5 and pt.x <= 244.0:
				return 9 # E Ability column
	return direct


func _resolve_hover_or_drop_preview(pt: Vector2) -> int:
	if _dragging and _drag_from_idx >= 0:
		return _resolve_drop_target_socket(_drag_from_idx, pt)
	return _hit_test_socket(pt)


func _resolve_placement_socket(pt: Vector2) -> int:
	var direct: int = _hit_test_socket(pt)
	if direct >= 0 and _is_valid_placement_socket(direct):
		return direct

	var cat: String = str(_placement_spec.get("category", ""))
	if pt.y >= -18.0 and pt.y <= 88.0:
		if cat == "shard" or cat == "weapon":
			if pt.x >= 44.0 and pt.x <= 99.5:
				return 6 # LMB
			if pt.x > 99.5 and pt.x <= 156.0:
				return 7 # RMB
		elif cat == "ability":
			if pt.x >= 151.0 and pt.x <= 196.5:
				return 8 # Q
			if pt.x > 196.5 and pt.x <= 244.0:
				return 9 # E
	return -1


func _is_valid_placement_socket(sock_idx: int) -> bool:
	if not _placement_active or sock_idx < 0 or sock_idx >= _sockets.size():
		return false
	var cat: String = str(_placement_spec.get("category", ""))
	var kind: String = str(_sockets[sock_idx]["kind"])
	if cat == "shard":
		return kind == "shard" or kind == "weapon"
	if cat == "weapon":
		return kind == "weapon"
	if cat == "ability":
		return kind == "ability"
	return false


func _can_start_drag(sock_idx: int) -> bool:
	if sock_idx < 0 or sock_idx >= _sockets.size():
		return false
	var s: Dictionary = _sockets[sock_idx]
	var kind: String = str(s["kind"])
	if kind == "shard":
		return _get_cached_shard(int(s["group"]), int(s["idx"])) != CatalogScript.ShardId.NONE
	if kind == "weapon":
		return true
	if kind == "ability":
		return _slot_equipped[int(s["slot_idx"])]
	return false


func _can_drop_onto(from_idx: int, to_idx: int) -> bool:
	if from_idx < 0 or to_idx < 0 or from_idx == to_idx:
		return false
	var k_from: String = str(_sockets[from_idx]["kind"])
	var k_to: String = str(_sockets[to_idx]["kind"])
	if k_from == "shard":
		return k_to == "shard" or k_to == "weapon"
	if k_from == "weapon":
		return k_to == "weapon"
	if k_from == "ability":
		return k_to == "ability"
	return false


func _perform_drop(from_idx: int, to_idx: int) -> void:
	if _bound_player == null or not is_instance_valid(_bound_player):
		return
	var s_from: Dictionary = _sockets[from_idx]
	var s_to: Dictionary = _sockets[to_idx]
	var k_from: String = str(s_from["kind"])
	var k_to: String = str(s_to["kind"])

	if k_from == "shard":
		if k_to == "shard" and _bound_player.has_method("move_or_swap_shard"):
			_bound_player.call("move_or_swap_shard", int(s_from["group"]), int(s_from["idx"]), int(s_to["group"]), int(s_to["idx"]))
		elif k_to == "weapon" and _bound_player.has_method("move_shard_to_weapon"):
			_bound_player.call("move_shard_to_weapon", int(s_from["group"]), int(s_from["idx"]), int(s_to["group"]))
	elif k_from == "weapon" and _bound_player.has_method("swap_weapons"):
		_bound_player.call("swap_weapons")
	elif k_from == "ability" and _bound_player.has_method("swap_abilities"):
		_bound_player.call("swap_abilities")


func _get_cached_shard(group: int, idx: int) -> int:
	if group == 0 or group == 1:
		var arr: Array = _weapon_shard_ids[group] as Array
		if idx >= 0 and idx < arr.size():
			return int(arr[idx])
	return CatalogScript.ShardId.NONE


func _build_labels_if_needed() -> void:
	if _hp_num_label != null:
		return

	_slot_key_labels.clear()
	for i in range(SLOT_CENTERS_X.size()):
		var klbl := _make_clean_label(9, COL_IVORY_MUTED)
		klbl.name = "SlotKey_%d" % i
		klbl.text = SLOT_KEYS_TEXT[i]
		klbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var half_w: float = 18.0
		var y_off: float = ROW_Y + (ARTIFACT_HALF_DIAG if i == 4 else DIAMOND_HALF_DIAG) + 0.5
		klbl.position = Vector2(SLOT_CENTERS_X[i] - half_w, y_off)
		klbl.custom_minimum_size = Vector2(half_w * 2.0, 12.0)
		add_child(klbl)
		_slot_key_labels.append(klbl)

	var num_row := HBoxContainer.new()
	num_row.name = "VitalityReadout"
	num_row.position = Vector2(BAR_X + 2.0, BAR_Y - 23.0)
	num_row.add_theme_constant_override("separation", 4)
	num_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(num_row)

	_hp_num_label = _make_clean_label(15, COL_IVORY_TEXT)
	_hp_num_label.name = "HPValueLabel"
	_hp_num_label.size_flags_vertical = Control.SIZE_SHRINK_END
	num_row.add_child(_hp_num_label)

	_hp_max_label = _make_clean_label(12, COL_IVORY_MUTED)
	_hp_max_label.name = "HPMaxLabel"
	_hp_max_label.size_flags_vertical = Control.SIZE_SHRINK_END
	num_row.add_child(_hp_max_label)

	_shield_label = _make_clean_label(12, Color(0.486, 0.910, 1.0, 0.96))
	_shield_label.name = "ShieldValueLabel"
	_shield_label.size_flags_vertical = Control.SIZE_SHRINK_END
	_shield_label.visible = false
	num_row.add_child(_shield_label)

	_stats_panel = PanelContainer.new()
	_stats_panel.name = "StatsSheetPanel"
	_stats_panel.position = Vector2(4.0, -118.0)
	_stats_panel.custom_minimum_size = Vector2(310.0, 178.0)
	_stats_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats_panel.visible = false

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.038, 0.056, 0.090, 0.90)
	sb.border_width_left = 1
	sb.border_width_top = 2
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = COL_IVORY_CAP
	sb.corner_radius_top_left = 2
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2
	sb.corner_radius_bottom_right = 2
	_stats_panel.add_theme_stylebox_override("panel", sb)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_stats_panel.add_child(margin)

	_stats_body_label = _make_clean_label(12, COL_IVORY_TEXT)
	_stats_body_label.name = "StatsBodyLabel"
	_stats_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	margin.add_child(_stats_body_label)

	add_child(_stats_panel)


func _make_clean_label(font_px: int, font_col: Color) -> Label:
	var lbl := Label.new()
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", font_px)
	lbl.add_theme_color_override("font_color", font_col)
	lbl.add_theme_color_override("font_shadow_color", COL_TEXT_SHADOW)
	lbl.add_theme_constant_override("shadow_offset_x", 0)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.add_theme_constant_override("outline_size", 0)
	return lbl


func bind_player(player_node: Node) -> void:
	_build_labels_if_needed()
	if _bound_player != null and is_instance_valid(_bound_player):
		if _bound_player.has_signal("dash_state_changed"):
			var old_cb := Callable(self, "_on_dash_state_changed")
			if _bound_player.is_connected("dash_state_changed", old_cb):
				_bound_player.disconnect("dash_state_changed", old_cb)
		if _bound_player.has_signal("loadout_changed"):
			var old_lcb := Callable(self, "_on_loadout_changed")
			if _bound_player.is_connected("loadout_changed", old_lcb):
				_bound_player.disconnect("loadout_changed", old_lcb)

	_bound_player = player_node
	_bound_stats = null
	if _bound_player == null:
		return

	if _bound_player.has_method("get_stats_component"):
		_bound_stats = _bound_player.call("get_stats_component") as Node

	if _bound_player.has_signal("dash_state_changed"):
		var cb := Callable(self, "_on_dash_state_changed")
		if not _bound_player.is_connected("dash_state_changed", cb):
			_bound_player.connect("dash_state_changed", cb)

	if _bound_player.has_signal("loadout_changed"):
		var lcb := Callable(self, "_on_loadout_changed")
		if not _bound_player.is_connected("loadout_changed", lcb):
			_bound_player.connect("loadout_changed", lcb)

	if _bound_player.has_method("get_dash_state"):
		var d: Dictionary = _bound_player.call("get_dash_state") as Dictionary
		_on_dash_state_changed(
			int(d.get("charges", 3)),
			int(d.get("max_charges", 3)),
			float(d.get("charge_progress", 0.0)),
			float(d.get("inter_delay_remaining", 0.0)),
			float(d.get("charge_duration", 3.0))
		)

	if _bound_player.has_method("get_health_component"):
		var hc: HealthComponent = _bound_player.call("get_health_component") as HealthComponent
		if hc:
			bind_health_component(hc)

	_sync_loadout_metadata()
	queue_redraw()


func bind_health_component(hc: HealthComponent) -> void:
	_build_labels_if_needed()
	if _bound_health != null and is_instance_valid(_bound_health):
		if _bound_health.health_changed.is_connected(_on_health_changed):
			_bound_health.health_changed.disconnect(_on_health_changed)
		if _bound_health.shield_changed.is_connected(_on_shield_changed):
			_bound_health.shield_changed.disconnect(_on_shield_changed)
		if _bound_health.damaged.is_connected(_on_damaged):
			_bound_health.damaged.disconnect(_on_damaged)
		if _bound_health.healed.is_connected(_on_healed):
			_bound_health.healed.disconnect(_on_healed)

	_bound_health = hc
	if _bound_health == null:
		return

	_bound_health.health_changed.connect(_on_health_changed)
	_bound_health.shield_changed.connect(_on_shield_changed)
	_bound_health.damaged.connect(_on_damaged)
	_bound_health.healed.connect(_on_healed)

	_max_hp = maxf(1.0, _bound_health.max_health)
	_current_hp = clampf(_bound_health.current_health, 0.0, _max_hp)
	_current_shield = maxf(0.0, _bound_health.current_shield)
	_target_hp_ratio = _current_hp / _max_hp
	_trail_hp_ratio = _target_hp_ratio
	_refresh_labels()
	queue_redraw()


func _on_loadout_changed() -> void:
	_sync_loadout_metadata()
	if _stats_panel and _stats_panel.visible:
		_refresh_stats_sheet_text()
	if _bound_player != null and is_instance_valid(_bound_player) and _bound_player.has_method("has_active_slot_cooldowns"):
		if bool(_bound_player.call("has_active_slot_cooldowns")):
			set_process(true)
	queue_redraw()


func _sync_loadout_metadata() -> void:
	if _bound_player == null or not is_instance_valid(_bound_player):
		return

	var w_slots: Array = _bound_player.get("weapon_slots") as Array
	var ab_slots: Array = _bound_player.get("ability_slots") as Array
	var art_id: int = int(_bound_player.get("artifact_id"))

	for i in range(2):
		var wid: int = int(w_slots[i]) if i < w_slots.size() else 0
		var w: Dictionary = CatalogScript.get_weapon(wid)
		_slot_equipped[i] = not w.is_empty()
		_slot_glyphs[i] = int(w.get("glyph", 0))
		_slot_colors[i] = w.get("color", COL_IVORY_TEXT) as Color
		_slot_names[i] = str(w.get("name", "Empty"))

	for j in range(2):
		var abid: int = int(ab_slots[j]) if j < ab_slots.size() else 0
		var ab: Dictionary = CatalogScript.get_ability(abid)
		_slot_equipped[2 + j] = not ab.is_empty()
		_slot_glyphs[2 + j] = int(ab.get("glyph", 0))
		_slot_colors[2 + j] = ab.get("color", COL_SHIELD_CYAN) as Color
		_slot_names[2 + j] = str(ab.get("name", "Empty"))

	var art: Dictionary = CatalogScript.get_artifact(art_id)
	_slot_equipped[4] = not art.is_empty()
	_slot_glyphs[4] = int(art.get("glyph", 0))
	_slot_colors[4] = art.get("color", COL_TRAIL_GOLD) as Color
	_slot_names[4] = str(art.get("name", "Empty"))

	if "weapon_shards" in _bound_player:
		var ws: Array = _bound_player.get("weapon_shards") as Array
		if ws.size() >= 2:
			_weapon_shard_ids[0] = (ws[0] as Array).duplicate()
			_weapon_shard_ids[1] = (ws[1] as Array).duplicate()

	_poll_slot_progress()


func _poll_slot_progress() -> bool:
	var any_recharging: bool = false
	if _bound_player == null or not is_instance_valid(_bound_player) or not _bound_player.has_method("get_slot_recharge_progress"):
		for k in range(5):
			_slot_progress[k] = 1.0
		return false
	for k in range(5):
		var prog: float = float(_bound_player.call("get_slot_recharge_progress", k))
		_slot_progress[k] = prog
		if prog < 0.999:
			any_recharging = true
	return any_recharging


func _refresh_stats_sheet_text() -> void:
	if _stats_body_label == null or _bound_player == null or not is_instance_valid(_bound_player):
		return

	var w0_sh: String = _format_shard_names(_weapon_shard_ids[0] as Array)
	var w1_sh: String = _format_shard_names(_weapon_shard_ids[1] as Array)

	var ad_v: float = 10.0
	var ap_v: float = 10.0
	var as_v: float = 1.0
	var ah_v: float = 0.0
	var ms_v: float = 6.0

	if _bound_stats == null and _bound_player.has_method("get_stats_component"):
		_bound_stats = _bound_player.call("get_stats_component") as Node
	if _bound_stats != null and is_instance_valid(_bound_stats):
		ad_v = float(_bound_stats.get("attack_damage"))
		ap_v = float(_bound_stats.get("ability_power"))
		as_v = float(_bound_stats.get("attack_speed"))
		ah_v = float(_bound_stats.get("ability_haste"))
		ms_v = float(_bound_stats.get("move_speed"))

	_stats_body_label.text = (
		"LOADOUT\n"
		+ "LMB: %s (%s)\n" % [_slot_names[0], w0_sh]
		+ "RMB: %s (%s)\n" % [_slot_names[1], w1_sh]
		+ "Q: %s  |  E: %s  |  R: %s\n\n" % [_slot_names[2], _slot_names[3], _slot_names[4]]
		+ "ATTRIBUTES\n"
		+ "AD: %.0f   AP: %.0f   Atk Spd: %.2fx\n" % [ad_v, ap_v, as_v]
		+ "Haste: %.0f   Move Spd: %.1f m/s" % [ah_v, ms_v]
	)


func _format_shard_names(arr: Array) -> String:
	var names: Array[String] = []
	for sid_v in arr:
		var sid: int = int(sid_v)
		if sid != 0:
			names.append(str(CatalogScript.get_shard(sid).get("name", "Shard")).replace(" Shard", ""))
	if names.is_empty():
		return "No Shards"
	return "+".join(names)


func _on_health_changed(current_hp: float, max_hp: float) -> void:
	_max_hp = maxf(1.0, max_hp)
	_current_hp = clampf(current_hp, 0.0, _max_hp)
	var new_ratio: float = _current_hp / _max_hp
	if new_ratio > _trail_hp_ratio:
		_trail_hp_ratio = new_ratio
	_target_hp_ratio = new_ratio
	_refresh_labels()
	set_process(true)
	queue_redraw()


func _on_shield_changed(current_shield: float, max_hp: float) -> void:
	_max_hp = maxf(1.0, max_hp)
	_current_shield = maxf(0.0, current_shield)
	_refresh_labels()
	queue_redraw()


func _on_damaged(_amount: float, _hit_dir: Vector3) -> void:
	_hit_flash_timer = 0.11
	set_process(true)
	queue_redraw()


func _on_healed(_amount: float) -> void:
	_heal_flash_timer = 0.24
	set_process(true)
	queue_redraw()


func _on_dash_state_changed(
	charges: int,
	max_charges: int,
	charge_progress: float,
	inter_delay_remaining: float,
	charge_duration: float
) -> void:
	var gained_charge: bool = charges > _dash_charges
	_max_dash_charges = maxi(1, max_charges)
	_dash_charges = clampi(charges, 0, _max_dash_charges)
	_dash_charge_progress = clampf(charge_progress, 0.0, 1.0)
	_dash_inter_delay = maxf(0.0, inter_delay_remaining)
	_dash_charge_duration = maxf(0.1, charge_duration)
	if gained_charge:
		_dash_ready_flash = 0.22
	if _dash_charges < _max_dash_charges or _dash_inter_delay > 0.0 or _dash_ready_flash > 0.0:
		set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	var active_anim: bool = false
	_pulse_phase += delta * 5.0

	if _placement_active and _placement_arm_frames > 0:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_placement_arm_frames -= 1

	var live_alt: bool = _is_alt_pressed()
	if live_alt != _alt_held:
		_alt_held = live_alt
		_sync_edit_mode_transition()

	var want_zoom: bool = _is_interactive_zoom()
	var target_zoom: float = 1.0 if want_zoom else 0.0
	if absf(_alt_zoom_t - target_zoom) > 0.004:
		_alt_zoom_t = move_toward(_alt_zoom_t, target_zoom, 11.5 * delta)
		active_anim = true
	else:
		_alt_zoom_t = target_zoom

	# Smoothly scale the actual PlayerHealthBar Control up in-place from its bottom-left pivot!
	var eased_z: float = 1.0 - (1.0 - _alt_zoom_t) * (1.0 - _alt_zoom_t)
	var cur_scale: float = lerpf(1.0, ALT_ZOOM_SCALE, eased_z)
	scale = Vector2(cur_scale, cur_scale)

	# Counter-scale the Tab Attributes panel so its typography stays crisp at 1.0x above the zoomed HUD!
	if _stats_panel != null and _stats_panel.visible:
		var inv_s: float = 1.0 / maxf(0.01, cur_scale)
		_stats_panel.scale = Vector2(inv_s, inv_s)
		_stats_panel.position = Vector2(0.0, -194.0 * inv_s - 18.0)

	# Update local cursor exclusively from event-captured _last_canvas_mouse (zero Embedded toolbar offset!)
	if want_zoom:
		_mouse_local = _canvas_to_local(_last_canvas_mouse)
		if _placement_active:
			_hovered_socket_idx = _resolve_placement_socket(_mouse_local)
		elif _is_edit_mode():
			_hovered_socket_idx = _resolve_hover_or_drop_preview(_mouse_local)
			var lmb_now: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)
			if lmb_now and not _prev_polled_lmb and not _drag_attempted_this_press:
				_prev_polled_lmb = true
				_drag_attempted_this_press = true
				_handle_edit_press(_mouse_local)
			elif not lmb_now and _prev_polled_lmb:
				_prev_polled_lmb = false
				_drag_attempted_this_press = false
				if _dragging:
					_handle_edit_release(_mouse_local)

	if _hit_flash_timer > 0.0:
		_hit_flash_timer = maxf(0.0, _hit_flash_timer - delta)
		active_anim = true

	if _heal_flash_timer > 0.0:
		_heal_flash_timer = maxf(0.0, _heal_flash_timer - delta)
		active_anim = true

	if _trail_hp_ratio > _target_hp_ratio + 0.001:
		_trail_hp_ratio = move_toward(_trail_hp_ratio, _target_hp_ratio, 0.55 * delta)
		active_anim = true
	else:
		_trail_hp_ratio = _target_hp_ratio

	if _dash_inter_delay > 0.0:
		_dash_inter_delay = maxf(0.0, _dash_inter_delay - delta)
		active_anim = true

	if _dash_charges < _max_dash_charges:
		_dash_charge_progress += delta / _dash_charge_duration
		while _dash_charge_progress >= 1.0 and _dash_charges < _max_dash_charges:
			_dash_charge_progress -= 1.0
			_dash_charges += 1
			_dash_ready_flash = 0.22
		if _dash_charges >= _max_dash_charges:
			_dash_charge_progress = 0.0
		else:
			active_anim = true

	if _dash_ready_flash > 0.0:
		_dash_ready_flash = maxf(0.0, _dash_ready_flash - delta)
		active_anim = true

	if _poll_slot_progress():
		active_anim = true

	if want_zoom:
		active_anim = true

	queue_redraw()

	if not active_anim:
		set_process(false)


func _refresh_labels() -> void:
	if _hp_num_label:
		_hp_num_label.text = "%d" % ceili(_current_hp)
	if _hp_max_label:
		_hp_max_label.text = "/ %d" % roundi(_max_hp)
	if _shield_label:
		if _current_shield > 0.05:
			_shield_label.text = " (+%d)" % ceili(_current_shield)
			_shield_label.visible = true
		else:
			_shield_label.visible = false


func _draw() -> void:
	_draw_diamond_socket_row()
	_draw_vitality_and_shield_bar()
	if _alt_zoom_t > 0.12:
		_draw_zoom_caption_and_active_drag_ghost()


func _draw_diamond_socket_row() -> void:
	var at_max_charges: bool = _dash_charges >= _max_dash_charges
	var can_dash_now: bool = _dash_charges > 0 and _dash_inter_delay <= 0.02

	var base_rim: Color = COL_DASH_FULL_RIM if at_max_charges else COL_IVORY_LINE
	if _dash_ready_flash > 0.0 and at_max_charges:
		base_rim = COL_DASH_FULL_RIM.lightened(0.35)
	_draw_diamond(DASH_CENTER, DIAMOND_HALF_DIAG, COL_GLASS_DARK, base_rim, 1.5 if at_max_charges else 1.1)

	if not at_max_charges:
		var prog_col: Color = COL_DASH_PROGRESS.lightened(0.25) if _dash_ready_flash > 0.0 else COL_DASH_PROGRESS
		_draw_diamond_perimeter_progress(DASH_CENTER, DIAMOND_HALF_DIAG, _dash_charge_progress, prog_col)

	var glyph_col: Color = COL_GLYPH_READY if can_dash_now else COL_GLYPH_LOCKED
	_draw_minimal_wind_glyph(DASH_CENTER, glyph_col)

	var pip_y: float = DASH_CENTER.y + DIAMOND_HALF_DIAG + CHARGE_PIP_Y_OFFSET
	for i in range(_max_dash_charges):
		var offset_x: float = (float(i) - float(_max_dash_charges - 1) * 0.5) * CHARGE_PIP_SPACING
		var pip_center := Vector2(DASH_CENTER.x + offset_x, pip_y)
		if i < _dash_charges:
			_draw_diamond_filled_only(pip_center, CHARGE_PIP_HALF_DIAG, COL_DASH_PIP_ACTIVE)
		else:
			_draw_diamond(pip_center, CHARGE_PIP_HALF_DIAG, COL_DASH_PIP_EMPTY, COL_IVORY_LINE, 1.0)

	for sx in SEPARATOR_X:
		draw_line(
			Vector2(sx, ROW_Y - 11.0),
			Vector2(sx, ROW_Y + 11.0),
			Color(0.918, 0.894, 0.843, 0.22),
			1.0,
			true
		)

	var in_edit: bool = _is_edit_mode()
	var active_src: int = _drag_from_idx if _dragging else _selected_socket_idx
	var pulse_a: float = 0.65 + 0.35 * sin(_pulse_phase)

	# Draw Main Loadout Diamonds (indices 6..10 in _sockets correspond to slot 0..4)
	for idx in range(SLOT_CENTERS_X.size()):
		var sock_idx: int = 6 + idx
		var cx: float = SLOT_CENTERS_X[idx]
		var center := Vector2(cx, ROW_Y)
		var h_diag: float = ARTIFACT_HALF_DIAG if idx == 4 else DIAMOND_HALF_DIAG
		var equipped: bool = _slot_equipped[idx]
		var accent: Color = _slot_colors[idx]
		var prog: float = _slot_progress[idx]
		var is_ready: bool = equipped and prog >= 0.999

		var is_hov: bool = _is_interactive_zoom() and (_hovered_socket_idx == sock_idx)
		var is_sel: bool = in_edit and (active_src == sock_idx)
		var is_valid_target: bool = false
		if _placement_active:
			is_valid_target = _is_valid_placement_socket(sock_idx)
		elif in_edit and active_src >= 0 and active_src != sock_idx:
			is_valid_target = _can_drop_onto(active_src, sock_idx)

		var fill_c: Color = COL_GLASS_DARK if equipped else COL_GLASS_EMPTY
		var rim_c: Color = COL_IVORY_DIM
		var rim_w: float = 1.0
		if equipped:
			if is_ready:
				rim_c = Color(accent.r, accent.g, accent.b, 0.74)
				rim_w = 1.45
			else:
				rim_c = COL_IVORY_LINE
				rim_w = 1.1

		if is_sel or (is_hov and (is_valid_target or in_edit)):
			rim_c = COL_GOLD_HIGHLIGHT
			rim_w = 2.1
		elif is_valid_target:
			rim_c = Color(0.52, 0.96, 1.0, pulse_a)
			rim_w = 1.85

		_draw_diamond(center, h_diag, fill_c, rim_c, rim_w)

		if equipped and not is_ready:
			var bar_col := Color(accent.r, accent.g, accent.b, 0.95)
			_draw_diamond_perimeter_progress(center, h_diag, prog, bar_col)

		if equipped:
			var g_col: Color = Color(accent.r, accent.g, accent.b, 0.95).lightened(0.32) if is_ready else COL_GLYPH_LOCKED
			if _dragging and _drag_from_idx == sock_idx:
				g_col.a *= 0.38
			_draw_slot_glyph(center, _slot_glyphs[idx], g_col, 1.0)
		else:
			_draw_diamond_filled_only(center, 2.0, COL_IVORY_DIM)

	# Draw Slotted Weapon Shard Sockets (indices 0..5 in _sockets) beneath LMB & RMB
	for sh_sock_i in range(6):
		var sh_sock: Dictionary = _sockets[sh_sock_i]
		var scenter: Vector2 = sh_sock["pos"] as Vector2
		var sid: int = _get_cached_shard(int(sh_sock["group"]), int(sh_sock["idx"]))
		var s_hov: bool = _is_interactive_zoom() and (_hovered_socket_idx == sh_sock_i)
		var s_sel: bool = in_edit and (active_src == sh_sock_i)
		var s_target: bool = false
		if _placement_active:
			s_target = _is_valid_placement_socket(sh_sock_i)
		elif in_edit and active_src >= 0 and active_src != sh_sock_i:
			s_target = _can_drop_onto(active_src, sh_sock_i)

		var p_diag: float = SHARD_PIP_HALF_DIAG if _alt_zoom_t > 0.05 else 3.4
		var s_fill: Color = COL_DASH_PIP_EMPTY
		var s_rim: Color = COL_IVORY_LINE if _is_interactive_zoom() else COL_IVORY_DIM
		var s_rw: float = 1.0

		if sid != 0:
			var scol: Color = CatalogScript.get_shard(sid).get("color", COL_GOLD_HIGHLIGHT) as Color
			s_fill = scol
			if _dragging and _drag_from_idx == sh_sock_i:
				s_fill.a = 0.28
			s_rim = COL_IVORY_CAP
			s_rw = 1.15

		if s_sel or (s_hov and (sid != 0 or s_target)):
			s_rim = COL_GOLD_HIGHLIGHT
			s_rw = 1.75
		elif s_target:
			s_rim = Color(0.52, 0.96, 1.0, pulse_a)
			s_rw = 1.45

		_draw_diamond(scenter, p_diag, s_fill, s_rim, s_rw)


func _draw_zoom_caption_and_active_drag_ghost() -> void:
	# During Pickup Placement Mode, the stationary Preview Card sits cleanly above the HUD
	# and the cursor stays a normal pointer (nothing stuck to the cursor!).
	if _placement_active:
		return

	var a: float = clampf(_alt_zoom_t, 0.0, 1.0)
	var font: Font = ThemeDB.fallback_font
	var caption: String = _get_live_caption()

	if not caption.is_empty():
		draw_string(
			font,
			Vector2(8.5, -5.5),
			caption,
			HORIZONTAL_ALIGNMENT_LEFT,
			280.0,
			9,
			Color(0.02, 0.03, 0.05, 0.88 * a)
		)
		draw_string(
			font,
			Vector2(8.0, -6.0),
			caption,
			HORIZONTAL_ALIGNMENT_LEFT,
			280.0,
			9,
			Color(COL_IVORY_TEXT.r, COL_IVORY_TEXT.g, COL_IVORY_TEXT.b, a)
		)

	# Only draw a drag ghost while the mouse button is actively held down in a drag!
	if _dragging and _drag_from_idx >= 0:
		var ds: Dictionary = _sockets[_drag_from_idx]
		var dk: String = str(ds["kind"])
		if dk == "shard":
			var d_sid: int = _get_cached_shard(int(ds["group"]), int(ds["idx"]))
			var d_col: Color = CatalogScript.get_shard(d_sid).get("color", COL_GOLD_HIGHLIGHT) as Color
			_draw_diamond(_mouse_local, 6.8, Color(d_col.r, d_col.g, d_col.b, 0.94), COL_IVORY_TEXT, 1.6)
		else:
			var sl_i: int = int(ds["slot_idx"])
			var m_col: Color = _slot_colors[sl_i]
			_draw_diamond(_mouse_local, 12.5, COL_GLASS_DARK, m_col, 1.6)
			_draw_slot_glyph(_mouse_local, _slot_glyphs[sl_i], m_col.lightened(0.3), 0.85)


func _get_live_caption() -> String:
	var idx: int = _hovered_socket_idx
	if _dragging and _drag_from_idx >= 0:
		idx = _drag_from_idx
	elif idx < 0:
		idx = _selected_socket_idx
	if idx < 0 or idx >= _sockets.size():
		return ""

	var s: Dictionary = _sockets[idx]
	var kind: String = str(s["kind"])
	if kind == "shard":
		var sid: int = _get_cached_shard(int(s["group"]), int(s["idx"]))
		if sid == 0:
			return ""
		var sh_info: Dictionary = CatalogScript.get_shard(sid)
		var sname: String = str(sh_info.get("name", "Shard"))
		var sshort: String = str(sh_info.get("short", ""))
		return "%s  ·  %s" % [sname, sshort] if not sshort.is_empty() else sname
	var sl_idx: int = int(s["slot_idx"])
	if not _slot_equipped[sl_idx]:
		return ""
	return "%s" % _slot_names[sl_idx]


func _draw_slot_glyph(c: Vector2, glyph_kind: int, col: Color, scale_mult: float = 1.0) -> void:
	var s: float = scale_mult
	match glyph_kind:
		CatalogScript.GlyphKind.BOLT:
			draw_line(c + Vector2(-5.5, 5.5) * s, c + Vector2(5.0, -5.0) * s, col, 1.5 * s, true)
			draw_line(c + Vector2(0.5, -5.0) * s, c + Vector2(5.0, -5.0) * s, col, 1.5 * s, true)
			draw_line(c + Vector2(5.0, -5.0) * s, c + Vector2(5.0, -0.5) * s, col, 1.5 * s, true)

		CatalogScript.GlyphKind.SCATTER:
			draw_line(c + Vector2(-4.5, 4.5) * s, c + Vector2(5.5, -5.5) * s, col, 1.3 * s, true)
			draw_line(c + Vector2(-4.5, 4.5) * s, c + Vector2(6.0, -0.5) * s, col, 1.3 * s, true)
			draw_line(c + Vector2(-4.5, 4.5) * s, c + Vector2(-0.5, -6.0) * s, col, 1.3 * s, true)

		CatalogScript.GlyphKind.CHAKRAM:
			draw_arc(c, 5.2 * s, 0.0, TAU, 16, col, 1.4 * s, true)
			_draw_diamond_filled_only(c, 2.2 * s, col)

		CatalogScript.GlyphKind.LANCE:
			draw_line(c + Vector2(-7.0, 0.0) * s, c + Vector2(7.0, 0.0) * s, col, 1.7 * s, true)
			draw_line(c + Vector2(2.5, -3.6) * s, c + Vector2(7.0, 0.0) * s, col, 1.4 * s, true)
			draw_line(c + Vector2(2.5, 3.6) * s, c + Vector2(7.0, 0.0) * s, col, 1.4 * s, true)

		CatalogScript.GlyphKind.MORTAR:
			draw_arc(c, 5.5 * s, 0.0, TAU, 16, col, 1.2 * s, true)
			draw_line(c + Vector2(-3.0, 0.0) * s, c + Vector2(3.0, 0.0) * s, col, 1.3 * s, true)
			draw_line(c + Vector2(0.0, -3.0) * s, c + Vector2(0.0, 3.0) * s, col, 1.3 * s, true)

		CatalogScript.GlyphKind.SHIELD:
			draw_line(c + Vector2(0.0, -6.0) * s, c + Vector2(5.2, -3.2) * s, col, 1.4 * s, true)
			draw_line(c + Vector2(5.2, -3.2) * s, c + Vector2(3.8, 2.8) * s, col, 1.4 * s, true)
			draw_line(c + Vector2(3.8, 2.8) * s, c + Vector2(0.0, 6.2) * s, col, 1.4 * s, true)
			draw_line(c + Vector2(0.0, 6.2) * s, c + Vector2(-3.8, 2.8) * s, col, 1.4 * s, true)
			draw_line(c + Vector2(-3.8, 2.8) * s, c + Vector2(-5.2, -3.2) * s, col, 1.4 * s, true)
			draw_line(c + Vector2(-5.2, -3.2) * s, c + Vector2(0.0, -6.0) * s, col, 1.4 * s, true)

		CatalogScript.GlyphKind.STAR:
			draw_line(c + Vector2(0.0, -6.5) * s, c + Vector2(0.0, 6.5) * s, col, 1.4 * s, true)
			draw_line(c + Vector2(-6.5, 0.0) * s, c + Vector2(6.5, 0.0) * s, col, 1.4 * s, true)
			draw_line(c + Vector2(-3.5, -3.5) * s, c + Vector2(3.5, 3.5) * s, col, 1.1 * s, true)
			draw_line(c + Vector2(3.5, -3.5) * s, c + Vector2(-3.5, 3.5) * s, col, 1.1 * s, true)

		CatalogScript.GlyphKind.FROST:
			for a_i in range(3):
				var ang: float = float(a_i) * (PI / 3.0)
				var d := Vector2(cos(ang), sin(ang)) * (6.0 * s)
				draw_line(c - d, c + d, col, 1.3 * s, true)

		CatalogScript.GlyphKind.SURGE:
			draw_line(c + Vector2(-4.5, 1.5) * s, c + Vector2(0.0, -3.5) * s, col, 1.5 * s, true)
			draw_line(c + Vector2(0.0, -3.5) * s, c + Vector2(4.5, 1.5) * s, col, 1.5 * s, true)
			draw_line(c + Vector2(-4.5, 5.5) * s, c + Vector2(0.0, 0.5) * s, col, 1.5 * s, true)
			draw_line(c + Vector2(0.0, 0.5) * s, c + Vector2(4.5, 5.5) * s, col, 1.5 * s, true)

		CatalogScript.GlyphKind.SOLAR:
			draw_arc(c, 3.6 * s, 0.0, TAU, 14, col, 1.5 * s, true)
			draw_line(c + Vector2(0.0, -7.2) * s, c + Vector2(0.0, -5.0) * s, col, 1.4 * s, true)
			draw_line(c + Vector2(0.0, 5.0) * s, c + Vector2(0.0, 7.2) * s, col, 1.4 * s, true)
			draw_line(c + Vector2(-7.2, 0.0) * s, c + Vector2(-5.0, 0.0) * s, col, 1.4 * s, true)
			draw_line(c + Vector2(5.0, 0.0) * s, c + Vector2(7.2, 0.0) * s, col, 1.4 * s, true)

		CatalogScript.GlyphKind.CHRONO:
			draw_arc(c, 6.0 * s, 0.0, TAU, 18, col, 1.4 * s, true)
			draw_line(c, c + Vector2(0.0, -4.0) * s, col, 1.4 * s, true)
			draw_line(c, c + Vector2(3.2, 1.5) * s, col, 1.4 * s, true)

		CatalogScript.GlyphKind.SEEKER:
			_draw_diamond_filled_only(c + Vector2(0.0, -4.2) * s, 2.3 * s, col)
			_draw_diamond_filled_only(c + Vector2(-4.2, 3.2) * s, 2.1 * s, col)
			_draw_diamond_filled_only(c + Vector2(4.2, 3.2) * s, 2.1 * s, col)

		CatalogScript.GlyphKind.SIPHON:
			_draw_diamond_filled_only(c, 2.6 * s, col)
			draw_arc(c, 5.6 * s, -PI * 0.85, -PI * 0.15, 10, col, 1.4 * s, true)
			draw_arc(c, 5.6 * s, PI * 0.15, PI * 0.85, 10, col, 1.4 * s, true)

		CatalogScript.GlyphKind.HARVEST:
			draw_arc(c + Vector2(-1.2, 0.0) * s, 5.6 * s, -PI * 0.65, PI * 0.65, 12, col, 1.5 * s, true)
			draw_arc(c + Vector2(1.2, 0.0) * s, 5.6 * s, PI * 0.35, PI * 1.65, 12, col, 1.5 * s, true)
			_draw_diamond_filled_only(c, 2.2 * s, col)


func _draw_diamond_perimeter_progress(center: Vector2, half_diag: float, ratio: float, stroke_col: Color) -> void:
	var r: float = clampf(ratio, 0.0, 1.0)
	if r <= 0.005:
		return

	var v_top := Vector2(center.x, center.y - half_diag)
	var v_right := Vector2(center.x + half_diag, center.y)
	var v_bottom := Vector2(center.x, center.y + half_diag)
	var v_left := Vector2(center.x - half_diag, center.y)

	var scaled: float = r * 4.0
	var tip: Vector2 = v_top

	if scaled >= 1.0:
		draw_line(v_top, v_right, stroke_col, 2.2, true)
		tip = v_right
	else:
		tip = v_top.lerp(v_right, scaled)
		draw_line(v_top, tip, stroke_col, 2.2, true)
		draw_circle(tip, 1.8, COL_MENISCUS)
		return

	if scaled >= 2.0:
		draw_line(v_right, v_bottom, stroke_col, 2.2, true)
		tip = v_bottom
	else:
		tip = v_right.lerp(v_bottom, scaled - 1.0)
		draw_line(v_right, tip, stroke_col, 2.2, true)
		draw_circle(tip, 1.8, COL_MENISCUS)
		return

	if scaled >= 3.0:
		draw_line(v_bottom, v_left, stroke_col, 2.2, true)
		tip = v_left
	else:
		tip = v_bottom.lerp(v_left, scaled - 2.0)
		draw_line(v_bottom, tip, stroke_col, 2.2, true)
		draw_circle(tip, 1.8, COL_MENISCUS)
		return

	tip = v_left.lerp(v_top, scaled - 3.0)
	draw_line(v_left, tip, stroke_col, 2.2, true)
	draw_circle(tip, 1.8, COL_MENISCUS)


func _draw_vitality_and_shield_bar() -> void:
	var track_rect := Rect2(BAR_X, BAR_Y, BAR_W, BAR_H)
	draw_rect(track_rect, COL_GLASS_DARK, true)

	var trail_w: float = BAR_W * clampf(_trail_hp_ratio, 0.0, 1.0)
	if trail_w > 0.5:
		draw_rect(Rect2(BAR_X, BAR_Y + 1.0, trail_w, BAR_H - 2.0), COL_TRAIL_GOLD, true)

	var hp_clamped: float = clampf(_target_hp_ratio, 0.0, 1.0)
	var hp_w: float = BAR_W * hp_clamped
	if hp_w > 0.5:
		var fill_col: Color = COL_HP_CRIMSON
		if _hit_flash_timer > 0.0:
			fill_col = COL_HP_FLASH
		elif _heal_flash_timer > 0.0:
			fill_col = COL_HP_HEAL
		elif hp_clamped <= 0.25:
			fill_col = COL_HP_CRITICAL
		draw_rect(Rect2(BAR_X, BAR_Y + 1.0, hp_w, BAR_H - 2.0), fill_col, true)

		if hp_clamped > 0.02 and hp_clamped < 0.995:
			var edge_x: float = BAR_X + hp_w
			draw_line(
				Vector2(edge_x, BAR_Y + 1.0),
				Vector2(edge_x, BAR_Y + BAR_H - 1.0),
				COL_MENISCUS,
				1.4,
				true
			)

	if _current_shield > 0.05:
		var sh_ratio: float = clampf(_current_shield / maxf(1.0, _max_hp), 0.0, 1.0)
		var sh_w: float = maxf(3.0, BAR_W * sh_ratio)
		var sh_x: float = BAR_X + hp_w
		if sh_x + sh_w > BAR_X + BAR_W:
			sh_x = maxf(BAR_X, BAR_X + BAR_W - sh_w)
			sh_w = (BAR_X + BAR_W) - sh_x
		draw_rect(Rect2(sh_x, BAR_Y + 1.0, sh_w, BAR_H - 2.0), COL_SHIELD_CYAN, true)
		draw_line(
			Vector2(sh_x, BAR_Y + 1.0),
			Vector2(sh_x, BAR_Y + BAR_H - 1.0),
			COL_SHIELD_DIVIDER,
			1.1,
			true
		)

	for q in range(1, 4):
		var tx: float = BAR_X + BAR_W * (float(q) * 0.25)
		draw_line(
			Vector2(tx, BAR_Y + 1.0),
			Vector2(tx, BAR_Y + BAR_H - 1.0),
			COL_MICRO_TICK,
			1.0,
			false
		)

	draw_line(Vector2(BAR_X, BAR_Y), Vector2(BAR_X + BAR_W, BAR_Y), COL_IVORY_LINE, 1.0, true)
	draw_line(Vector2(BAR_X, BAR_Y + BAR_H), Vector2(BAR_X + BAR_W, BAR_Y + BAR_H), COL_IVORY_LINE, 1.0, true)

	var mid_y: float = BAR_Y + BAR_H * 0.5
	_draw_diamond(Vector2(BAR_X, mid_y), CAP_HALF_DIAG, COL_CAP_DARK, COL_IVORY_CAP, 1.1)
	_draw_diamond(Vector2(BAR_X + BAR_W, mid_y), CAP_HALF_DIAG, COL_CAP_DARK, COL_IVORY_CAP, 1.1)


func _draw_diamond(center: Vector2, half_diag: float, fill_col: Color, stroke_col: Color, width: float = 1.1) -> void:
	_scratch_quad[0] = Vector2(center.x, center.y - half_diag)
	_scratch_quad[1] = Vector2(center.x + half_diag, center.y)
	_scratch_quad[2] = Vector2(center.x, center.y + half_diag)
	_scratch_quad[3] = Vector2(center.x - half_diag, center.y)
	draw_colored_polygon(_scratch_quad, fill_col)
	_scratch_closed[0] = _scratch_quad[0]
	_scratch_closed[1] = _scratch_quad[1]
	_scratch_closed[2] = _scratch_quad[2]
	_scratch_closed[3] = _scratch_quad[3]
	_scratch_closed[4] = _scratch_quad[0]
	draw_polyline(_scratch_closed, stroke_col, width, true)


func _draw_diamond_filled_only(center: Vector2, half_diag: float, fill_col: Color) -> void:
	_scratch_quad[0] = Vector2(center.x, center.y - half_diag)
	_scratch_quad[1] = Vector2(center.x + half_diag, center.y)
	_scratch_quad[2] = Vector2(center.x, center.y + half_diag)
	_scratch_quad[3] = Vector2(center.x - half_diag, center.y)
	draw_colored_polygon(_scratch_quad, fill_col)


func _draw_minimal_wind_glyph(c: Vector2, col: Color) -> void:
	draw_line(Vector2(c.x - 6.0, c.y - 2.5), Vector2(c.x + 4.5, c.y - 2.5), col, 1.3, true)
	draw_arc(Vector2(c.x + 4.5, c.y - 4.3), 1.8, -PI * 0.75, PI * 0.5, 10, col, 1.3, true)
	draw_line(Vector2(c.x - 7.0, c.y + 1.2), Vector2(c.x + 6.0, c.y + 1.2), col, 1.3, true)
	draw_arc(Vector2(c.x + 6.0, c.y + 3.0), 1.8, -PI * 0.5, PI * 0.75, 10, col, 1.3, true)
	draw_line(Vector2(c.x - 4.0, c.y + 4.6), Vector2(c.x + 1.5, c.y + 4.6), col, 1.3, true)
