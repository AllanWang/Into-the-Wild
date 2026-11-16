class_name PlayerHealthBar
extends Control

## Ethereal Lattice Bottom-Left Player HUD inspired by Breath of the Wild × Shape of Dreams.
## - Normal Mode: [Dash ◆ (◆ ◆ ◆)] | [LMB ◆ (◆ ◆ ◆)] [RMB ◆ (◆ ◆ ◆)] | [Q ◆] [E ◆] | [R ◆]
##   with clockwise perimeter recharge bars, slotted Weapon Shard pips, and Health + Shield bar.
## - Hold [Alt]: Smoothly zooms out an interactive Tactical Loadout Lattice where players can
##   drag-and-drop (or click-to-swap) Weapons (LMB ↔ RMB), Abilities (Q ↔ E), and Weapon Shards!
## - Hold [Tab]: Displays the live Attributes & Loadout summary card.

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
var _slot_descs: Array[String] = ["", "", "", "", ""]
var _slot_equipped: Array[bool] = [true, true, false, false, false]
var _slot_progress: Array[float] = [1.0, 1.0, 1.0, 1.0, 1.0]

var _weapon_shard_ids: Array = [[0, 0, 0], [0, 0, 0]]
var _reserve_shard_ids: Array[int] = [0, 0, 0, 0]

# Hold [Alt] interactive zoomed lattice state
var _alt_held: bool = false
var _alt_zoom_t: float = 0.0
var _interactive_nodes: Array[Dictionary] = []
var _hovered_node_idx: int = -1
var _dragging: bool = false
var _drag_from_idx: int = -1
var _selected_node_idx: int = -1
var _mouse_local: Vector2 = Vector2.ZERO

var _hp_num_label: Label = null
var _hp_max_label: Label = null
var _shield_label: Label = null
var _stats_panel: PanelContainer = null
var _stats_body_label: Label = null
var _slot_key_labels: Array[Label] = []
var _swap_hint_label: Label = null

var _scratch_quad := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _scratch_closed := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])

# Compact layout constants (within 308 x 116 bottom-left footprint)
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

# Zoomed [Alt] panel layout constants (local coords above the HP bar)
const ZOOM_PANEL_RECT := Rect2(0.0, -214.0, 564.0, 276.0)
const Z_ROW_Y: float = -128.0
const Z_SHARD_Y: float = -48.0
const Z_MAIN_DIAG: float = 26.0
const Z_SHARD_DIAG: float = 11.5

# Palette (Breath of the Wild × Shape of Dreams)
const COL_GLASS_DARK := Color(0.043, 0.063, 0.098, 0.72)
const COL_GLASS_PANEL := Color(0.035, 0.052, 0.086, 0.92)
const COL_GLASS_EMPTY := Color(0.035, 0.051, 0.082, 0.50)
const COL_CAP_DARK := Color(0.051, 0.071, 0.110, 0.84)
const COL_IVORY_LINE := Color(0.918, 0.894, 0.843, 0.30)
const COL_IVORY_DIM := Color(0.918, 0.894, 0.843, 0.16)
const COL_IVORY_CAP := Color(0.918, 0.894, 0.843, 0.50)
const COL_IVORY_TEXT := Color(0.961, 0.945, 0.910, 1.0)
const COL_IVORY_MUTED := Color(0.918, 0.894, 0.843, 0.64)
const COL_TEXT_SHADOW := Color(0.024, 0.039, 0.063, 0.78)
const COL_GOLD_HIGHLIGHT := Color(1.0, 0.86, 0.42, 0.96)

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
	_init_zoom_socket_table()
	_build_labels_if_needed()
	_refresh_labels()
	set_process(false)
	queue_redraw()


func _init_zoom_socket_table() -> void:
	_interactive_nodes.clear()
	# 0: LMB Weapon, 1: RMB Weapon
	_interactive_nodes.append({"kind": "weapon", "group": 0, "idx": 0, "pos": Vector2(74.0, Z_ROW_Y), "diag": Z_MAIN_DIAG, "tag": "LMB"})
	_interactive_nodes.append({"kind": "weapon", "group": 1, "idx": 1, "pos": Vector2(188.0, Z_ROW_Y), "diag": Z_MAIN_DIAG, "tag": "RMB"})
	# 2: Q Ability, 3: E Ability
	_interactive_nodes.append({"kind": "ability", "group": 0, "idx": 0, "pos": Vector2(306.0, Z_ROW_Y), "diag": Z_MAIN_DIAG, "tag": "Q"})
	_interactive_nodes.append({"kind": "ability", "group": 1, "idx": 1, "pos": Vector2(394.0, Z_ROW_Y), "diag": Z_MAIN_DIAG, "tag": "E"})
	# 4: R Artifact (inspectable tooltip)
	_interactive_nodes.append({"kind": "artifact", "group": 0, "idx": 0, "pos": Vector2(504.0, Z_ROW_Y), "diag": Z_MAIN_DIAG + 2.0, "tag": "R"})

	# 5..7: LMB 3 Shard sockets
	for i in range(3):
		var sx: float = 74.0 + float(i - 1) * 28.0
		_interactive_nodes.append({"kind": "shard", "group": 0, "idx": i, "pos": Vector2(sx, Z_SHARD_Y), "diag": Z_SHARD_DIAG, "tag": "LMB Shard"})

	# 8..10: RMB 3 Shard sockets
	for j in range(3):
		var rx: float = 188.0 + float(j - 1) * 28.0
		_interactive_nodes.append({"kind": "shard", "group": 1, "idx": j, "pos": Vector2(rx, Z_SHARD_Y), "diag": Z_SHARD_DIAG, "tag": "RMB Shard"})

	# 11..14: Reserve 4 Shard sockets
	for r in range(4):
		var res_x: float = 306.0 + float(r) * 30.0
		_interactive_nodes.append({"kind": "shard", "group": 2, "idx": r, "pos": Vector2(res_x, Z_SHARD_Y), "diag": Z_SHARD_DIAG, "tag": "Reserve"})


func _input(event: InputEvent) -> void:
	var now_alt: bool = Input.is_action_pressed("inspect_loadout") or Input.is_key_pressed(KEY_ALT)
	if now_alt != _alt_held:
		_set_alt_mode(now_alt)

	if event.is_action("show_stats") and _stats_panel != null:
		var want_show: bool = Input.is_action_pressed("show_stats") and not _alt_held
		if _stats_panel.visible != want_show:
			if want_show:
				_refresh_stats_sheet_text()
			_stats_panel.visible = want_show

	if not _alt_held:
		return

	if event is InputEventMouseMotion:
		var local_mm: InputEventMouseMotion = make_input_local(event) as InputEventMouseMotion
		_mouse_local = local_mm.position if local_mm != null else get_local_mouse_position()
		_hovered_node_idx = _hit_test_zoom_socket(_mouse_local)
		queue_redraw()

	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var local_mb: InputEventMouseButton = make_input_local(event) as InputEventMouseButton
			_mouse_local = local_mb.position if local_mb != null else get_local_mouse_position()
			var hit_idx: int = _hit_test_zoom_socket(_mouse_local)
			if mb.pressed:
				if ZOOM_PANEL_RECT.has_point(_mouse_local):
					if hit_idx >= 0 and _can_initiate_move(hit_idx):
						_dragging = true
						_drag_from_idx = hit_idx
					elif hit_idx >= 0 and _selected_node_idx >= 0 and _are_nodes_compatible(_selected_node_idx, hit_idx):
						_execute_node_swap(_selected_node_idx, hit_idx)
						_selected_node_idx = -1
					else:
						_selected_node_idx = -1
					queue_redraw()
					get_viewport().set_input_as_handled()
			else:
				if _dragging:
					var from_idx: int = _drag_from_idx
					_dragging = false
					_drag_from_idx = -1
					if hit_idx >= 0 and hit_idx != from_idx and _are_nodes_compatible(from_idx, hit_idx):
						_execute_node_swap(from_idx, hit_idx)
						_selected_node_idx = -1
					elif hit_idx == from_idx:
						if _selected_node_idx >= 0 and _selected_node_idx != hit_idx and _are_nodes_compatible(_selected_node_idx, hit_idx):
							_execute_node_swap(_selected_node_idx, hit_idx)
							_selected_node_idx = -1
						else:
							_selected_node_idx = hit_idx if _selected_node_idx != hit_idx else -1
					queue_redraw()
					get_viewport().set_input_as_handled()


func _set_alt_mode(active: bool) -> void:
	_alt_held = active
	if not active:
		_dragging = false
		_drag_from_idx = -1
		_selected_node_idx = -1
		_hovered_node_idx = -1
	else:
		_mouse_local = get_local_mouse_position()
		_hovered_node_idx = _hit_test_zoom_socket(_mouse_local)
		if _stats_panel:
			_stats_panel.visible = false

	if _bound_player != null and is_instance_valid(_bound_player) and _bound_player.has_method("set_alt_inspect_active"):
		_bound_player.call("set_alt_inspect_active", active)

	set_process(true)
	queue_redraw()


func _hit_test_zoom_socket(pt: Vector2) -> int:
	for i in range(_interactive_nodes.size()):
		var n: Dictionary = _interactive_nodes[i]
		var c: Vector2 = n["pos"] as Vector2
		var diag: float = float(n["diag"]) + 4.0
		# Manhattan distance check matches 45-degree rotated diamond exactly!
		if (absf(pt.x - c.x) + absf(pt.y - c.y)) <= diag:
			return i
	return -1


func _can_initiate_move(node_idx: int) -> bool:
	if node_idx < 0 or node_idx >= _interactive_nodes.size():
		return false
	var n: Dictionary = _interactive_nodes[node_idx]
	var kind: String = str(n["kind"])
	if kind == "weapon":
		return true
	if kind == "ability":
		var ab_idx: int = int(n["idx"])
		return _slot_equipped[2 + ab_idx]
	if kind == "shard":
		return _get_cached_shard(int(n["group"]), int(n["idx"])) != CatalogScript.ShardId.NONE
	return false


func _are_nodes_compatible(idx_a: int, idx_b: int) -> bool:
	if idx_a < 0 or idx_b < 0 or idx_a == idx_b:
		return false
	var ka: String = str(_interactive_nodes[idx_a]["kind"])
	var kb: String = str(_interactive_nodes[idx_b]["kind"])
	if ka != kb:
		return false
	return ka == "weapon" or ka == "ability" or ka == "shard"


func _execute_node_swap(idx_a: int, idx_b: int) -> void:
	if _bound_player == null or not is_instance_valid(_bound_player):
		return
	var na: Dictionary = _interactive_nodes[idx_a]
	var nb: Dictionary = _interactive_nodes[idx_b]
	var kind: String = str(na["kind"])
	if kind == "weapon" and _bound_player.has_method("swap_weapons"):
		_bound_player.call("swap_weapons")
	elif kind == "ability" and _bound_player.has_method("swap_abilities"):
		_bound_player.call("swap_abilities")
	elif kind == "shard" and _bound_player.has_method("move_or_swap_shard"):
		_bound_player.call("move_or_swap_shard", int(na["group"]), int(na["idx"]), int(nb["group"]), int(nb["idx"]))


func _get_cached_shard(group: int, idx: int) -> int:
	if group == 0 or group == 1:
		var arr: Array = _weapon_shard_ids[group] as Array
		if idx >= 0 and idx < arr.size():
			return int(arr[idx])
	elif group == 2:
		if idx >= 0 and idx < _reserve_shard_ids.size():
			return _reserve_shard_ids[idx]
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
		var y_off: float = ROW_Y + (ARTIFACT_HALF_DIAG if i == 4 else DIAMOND_HALF_DIAG) + 1.0
		klbl.position = Vector2(SLOT_CENTERS_X[i] - half_w, y_off)
		klbl.custom_minimum_size = Vector2(half_w * 2.0, 12.0)
		add_child(klbl)
		_slot_key_labels.append(klbl)

	_swap_hint_label = _make_clean_label(8, Color(0.918, 0.894, 0.843, 0.46))
	_swap_hint_label.name = "SwapHintLabel"
	_swap_hint_label.text = "X"
	_swap_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_swap_hint_label.position = Vector2(93.5, ROW_Y - 6.0)
	_swap_hint_label.custom_minimum_size = Vector2(12.0, 12.0)
	add_child(_swap_hint_label)

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

	var tab_hint := _make_clean_label(10, Color(0.918, 0.894, 0.843, 0.44))
	tab_hint.name = "TabStatsHint"
	tab_hint.text = "[Alt] Edit  [Tab] Stats"
	tab_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tab_hint.position = Vector2(BAR_X + BAR_W - 118.0, BAR_Y - 20.0)
	tab_hint.custom_minimum_size = Vector2(116.0, 14.0)
	add_child(tab_hint)

	_stats_panel = PanelContainer.new()
	_stats_panel.name = "StatsSheetPanel"
	_stats_panel.position = Vector2(6.0, -206.0)
	_stats_panel.custom_minimum_size = Vector2(292.0, 194.0)
	_stats_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats_panel.visible = false

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.038, 0.056, 0.090, 0.88)
	sb.border_width_left = 1
	sb.border_width_top = 1
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
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
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
		_slot_descs[i] = str(w.get("desc", ""))

	for j in range(2):
		var abid: int = int(ab_slots[j]) if j < ab_slots.size() else 0
		var ab: Dictionary = CatalogScript.get_ability(abid)
		_slot_equipped[2 + j] = not ab.is_empty()
		_slot_glyphs[2 + j] = int(ab.get("glyph", 0))
		_slot_colors[2 + j] = ab.get("color", COL_SHIELD_CYAN) as Color
		_slot_names[2 + j] = str(ab.get("name", "Empty"))
		_slot_descs[2 + j] = str(ab.get("desc", "Empty ability socket — claim an Ability from a Pedestal."))

	var art: Dictionary = CatalogScript.get_artifact(art_id)
	_slot_equipped[4] = not art.is_empty()
	_slot_glyphs[4] = int(art.get("glyph", 0))
	_slot_colors[4] = art.get("color", COL_TRAIL_GOLD) as Color
	_slot_names[4] = str(art.get("name", "Empty"))
	_slot_descs[4] = str(art.get("desc", "Empty artifact socket — claim an Active Artifact [R] from a Pedestal."))

	if "weapon_shards" in _bound_player:
		var ws: Array = _bound_player.get("weapon_shards") as Array
		if ws.size() >= 2:
			_weapon_shard_ids[0] = (ws[0] as Array).duplicate()
			_weapon_shard_ids[1] = (ws[1] as Array).duplicate()
	if "reserve_shards" in _bound_player:
		var rs: Array = _bound_player.get("reserve_shards") as Array
		_reserve_shard_ids.clear()
		for r_val in rs:
			_reserve_shard_ids.append(int(r_val))
		while _reserve_shard_ids.size() < 4:
			_reserve_shard_ids.append(0)

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
		"LOADOUT  ([X] Swap  |  Hold [Alt] Edit)\n"
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

	# Keep Alt state synced even if focus/action state changes without a key event
	var live_alt: bool = Input.is_action_pressed("inspect_loadout") or Input.is_key_pressed(KEY_ALT)
	if live_alt != _alt_held:
		_set_alt_mode(live_alt)

	var target_zoom: float = 1.0 if _alt_held else 0.0
	if absf(_alt_zoom_t - target_zoom) > 0.005:
		_alt_zoom_t = move_toward(_alt_zoom_t, target_zoom, 9.5 * delta)
		active_anim = true
	else:
		_alt_zoom_t = target_zoom

	var show_compact_labels: bool = (_alt_zoom_t < 0.35)
	for kl in _slot_key_labels:
		if kl.visible != show_compact_labels:
			kl.visible = show_compact_labels
	if _swap_hint_label and _swap_hint_label.visible != show_compact_labels:
		_swap_hint_label.visible = show_compact_labels

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

	if _alt_held:
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
	if _alt_zoom_t < 0.35:
		_draw_compact_diamond_socket_row()
	_draw_vitality_and_shield_bar()
	if _alt_zoom_t >= 0.05:
		_draw_zoomed_alt_lattice(_alt_zoom_t)


func _draw_compact_diamond_socket_row() -> void:
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

	for idx in range(SLOT_CENTERS_X.size()):
		var cx: float = SLOT_CENTERS_X[idx]
		var center := Vector2(cx, ROW_Y)
		var h_diag: float = ARTIFACT_HALF_DIAG if idx == 4 else DIAMOND_HALF_DIAG
		var equipped: bool = _slot_equipped[idx]
		var accent: Color = _slot_colors[idx]
		var prog: float = _slot_progress[idx]
		var is_ready: bool = equipped and prog >= 0.999

		var fill_c: Color = COL_GLASS_DARK if equipped else COL_GLASS_EMPTY
		var rim_c: Color = COL_IVORY_DIM
		var rim_w: float = 1.0
		if equipped:
			if is_ready:
				rim_c = Color(accent.r, accent.g, accent.b, 0.72)
				rim_w = 1.45
			else:
				rim_c = COL_IVORY_LINE
				rim_w = 1.1

		_draw_diamond(center, h_diag, fill_c, rim_c, rim_w)

		if equipped and not is_ready:
			var bar_col := Color(accent.r, accent.g, accent.b, 0.95)
			_draw_diamond_perimeter_progress(center, h_diag, prog, bar_col)

		if equipped:
			var g_col: Color = Color(accent.r, accent.g, accent.b, 0.95).lightened(0.32) if is_ready else COL_GLYPH_LOCKED
			_draw_slot_glyph(center, _slot_glyphs[idx], g_col, 1.0)
		else:
			_draw_diamond_filled_only(center, 2.0, COL_IVORY_DIM)

		# Slotted Weapon Shard mini-diamonds (◆ ◆ ◆) underneath LMB (0) and RMB (1)
		if idx == 0 or idx == 1:
			var sh_list: Array = _weapon_shard_ids[idx] as Array
			var sh_y: float = ROW_Y + DIAMOND_HALF_DIAG + 17.5
			for s_i in range(3):
				var sh_x: float = cx + float(s_i - 1) * 8.4
				var sid: int = int(sh_list[s_i]) if s_i < sh_list.size() else 0
				if sid != 0:
					var s_col: Color = CatalogScript.get_shard(sid).get("color", COL_GOLD_HIGHLIGHT) as Color
					_draw_diamond(Vector2(sh_x, sh_y), 3.0, s_col, COL_IVORY_CAP, 0.9)
				else:
					_draw_diamond(Vector2(sh_x, sh_y), 2.7, COL_DASH_PIP_EMPTY, COL_IVORY_DIM, 0.9)


func _draw_zoomed_alt_lattice(alpha_t: float) -> void:
	var a: float = clampf(alpha_t, 0.0, 1.0)
	var font: Font = ThemeDB.fallback_font
	var bg_col := Color(COL_GLASS_PANEL.r, COL_GLASS_PANEL.g, COL_GLASS_PANEL.b, COL_GLASS_PANEL.a * a)
	var line_col := Color(COL_IVORY_CAP.r, COL_IVORY_CAP.g, COL_IVORY_CAP.b, 0.55 * a)

	draw_rect(ZOOM_PANEL_RECT, bg_col, true)
	draw_rect(ZOOM_PANEL_RECT, line_col, false, 1.2)

	# Header
	draw_string(
		font,
		Vector2(16.0, -191.0),
		"LOADOUT & WEAPON SHARDS  —  Drag or Click Diamonds to Reorder",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		13,
		Color(COL_IVORY_TEXT.r, COL_IVORY_TEXT.g, COL_IVORY_TEXT.b, a)
	)
	draw_line(Vector2(14.0, -181.0), Vector2(550.0, -181.0), Color(0.92, 0.89, 0.84, 0.22 * a), 1.0, true)

	# Vertical section dividers: Weapons | Abilities | Artifact
	draw_line(Vector2(250.0, -162.0), Vector2(250.0, -28.0), Color(0.92, 0.89, 0.84, 0.20 * a), 1.0, true)
	draw_line(Vector2(448.0, -162.0), Vector2(448.0, -84.0), Color(0.92, 0.89, 0.84, 0.20 * a), 1.0, true)

	draw_string(
		font,
		Vector2(304.0, -66.0),
		"RESERVE SHARDS",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		10,
		Color(COL_IVORY_MUTED.r, COL_IVORY_MUTED.g, COL_IVORY_MUTED.b, a * 0.85)
	)

	var active_source_idx: int = _drag_from_idx if _dragging else _selected_node_idx

	for i in range(_interactive_nodes.size()):
		var n: Dictionary = _interactive_nodes[i]
		var kind: String = str(n["kind"])
		var c: Vector2 = n["pos"] as Vector2
		var diag: float = float(n["diag"])
		var is_hovered: bool = (i == _hovered_node_idx)
		var is_selected: bool = (i == active_source_idx)
		var is_valid_drop: bool = (active_source_idx >= 0 and active_source_idx != i and _are_nodes_compatible(active_source_idx, i))

		if kind == "shard":
			var sid: int = _get_cached_shard(int(n["group"]), int(n["idx"]))
			var fill_s := Color(COL_GLASS_EMPTY.r, COL_GLASS_EMPTY.g, COL_GLASS_EMPTY.b, 0.78 * a)
			var rim_s := Color(COL_IVORY_LINE.r, COL_IVORY_LINE.g, COL_IVORY_LINE.b, 0.36 * a)
			var rw_s: float = 1.2
			if sid != 0:
				var sc: Color = CatalogScript.get_shard(sid).get("color", COL_GOLD_HIGHLIGHT) as Color
				fill_s = Color(sc.r, sc.g, sc.b, 0.86 * a)
				rim_s = Color(1.0, 0.97, 0.92, 0.88 * a)
				rw_s = 1.6
			if is_selected or is_hovered:
				rim_s = Color(COL_GOLD_HIGHLIGHT.r, COL_GOLD_HIGHLIGHT.g, COL_GOLD_HIGHLIGHT.b, a)
				rw_s = 2.2
			elif is_valid_drop:
				rim_s = Color(0.56, 0.95, 1.0, 0.85 * a)
				rw_s = 1.8
			_draw_diamond(c, diag, fill_s, rim_s, rw_s)
			if sid != 0:
				_draw_diamond_filled_only(c, 3.6, Color(1.0, 0.98, 0.94, 0.92 * a))
		else:
			# Main Weapon / Ability / Artifact socket (indices 0..4 map directly to _slot_* 0..4!)
			var eq: bool = _slot_equipped[i]
			var acc: Color = _slot_colors[i]
			var prog: float = _slot_progress[i]
			var ready_now: bool = eq and prog >= 0.999

			var fill_m := Color(COL_GLASS_DARK.r, COL_GLASS_DARK.g, COL_GLASS_DARK.b, 0.90 * a) if eq else Color(COL_GLASS_EMPTY.r, COL_GLASS_EMPTY.g, COL_GLASS_EMPTY.b, 0.65 * a)
			var rim_m := Color(acc.r, acc.g, acc.b, 0.82 * a) if eq else Color(COL_IVORY_DIM.r, COL_IVORY_DIM.g, COL_IVORY_DIM.b, 0.35 * a)
			var rw_m: float = 1.8 if eq else 1.1
			if is_selected or is_hovered:
				rim_m = Color(COL_GOLD_HIGHLIGHT.r, COL_GOLD_HIGHLIGHT.g, COL_GOLD_HIGHLIGHT.b, a)
				rw_m = 2.4
			elif is_valid_drop:
				rim_m = Color(0.56, 0.95, 1.0, 0.90 * a)
				rw_m = 2.0

			_draw_diamond(c, diag, fill_m, rim_m, rw_m)
			if eq and not ready_now:
				_draw_diamond_perimeter_progress(c, diag, prog, Color(acc.r, acc.g, acc.b, 0.95 * a))
			if eq:
				var gc: Color = Color(acc.r, acc.g, acc.b, a).lightened(0.32)
				_draw_slot_glyph(c, _slot_glyphs[i], gc, 1.45)

			# Key tag above diamond & item title below
			draw_string(
				font,
				Vector2(c.x - 28.0, c.y - diag - 7.0),
				str(n["tag"]),
				HORIZONTAL_ALIGNMENT_CENTER,
				56.0,
				11,
				Color(COL_IVORY_MUTED.r, COL_IVORY_MUTED.g, COL_IVORY_MUTED.b, a)
			)
			var short_title: String = _slot_names[i]
			var name_y: float = c.y + diag + 14.0
			draw_string(
				font,
				Vector2(c.x - 52.0, name_y),
				short_title,
				HORIZONTAL_ALIGNMENT_CENTER,
				104.0,
				11,
				Color(COL_IVORY_TEXT.r, COL_IVORY_TEXT.g, COL_IVORY_TEXT.b, a * (0.95 if eq else 0.45))
			)

	# Bottom Tooltip / Instruction Strip inside Zoomed Panel
	draw_line(Vector2(14.0, -20.0), Vector2(550.0, -20.0), Color(0.92, 0.89, 0.84, 0.22 * a), 1.0, true)
	var tip_lines: Array[String] = _get_zoom_tooltip_lines()
	draw_string(
		font,
		Vector2(16.0, 0.0),
		tip_lines[0],
		HORIZONTAL_ALIGNMENT_LEFT,
		532.0,
		13,
		Color(COL_GOLD_HIGHLIGHT.r, COL_GOLD_HIGHLIGHT.g, COL_GOLD_HIGHLIGHT.b, a)
	)
	draw_string(
		font,
		Vector2(16.0, 20.0),
		tip_lines[1],
		HORIZONTAL_ALIGNMENT_LEFT,
		532.0,
		11,
		Color(COL_IVORY_MUTED.r, COL_IVORY_MUTED.g, COL_IVORY_MUTED.b, a)
	)

	# Floating cursor diamond ghost while dragging
	if _dragging and _drag_from_idx >= 0:
		var dn: Dictionary = _interactive_nodes[_drag_from_idx]
		var ghost_col := COL_GOLD_HIGHLIGHT
		if str(dn["kind"]) == "shard":
			var d_sid: int = _get_cached_shard(int(dn["group"]), int(dn["idx"]))
			ghost_col = CatalogScript.get_shard(d_sid).get("color", COL_GOLD_HIGHLIGHT) as Color
		elif _drag_from_idx < 5:
			ghost_col = _slot_colors[_drag_from_idx]
		_draw_diamond(_mouse_local, 13.0, Color(ghost_col.r, ghost_col.g, ghost_col.b, 0.85), COL_IVORY_TEXT, 2.0)


func _get_zoom_tooltip_lines() -> Array[String]:
	var inspect_idx: int = _hovered_node_idx
	if inspect_idx < 0:
		inspect_idx = _drag_from_idx if _dragging else _selected_node_idx
	if inspect_idx < 0 or inspect_idx >= _interactive_nodes.size():
		return [
			"Hold [Alt]: Drag Weapons (LMB ↔ RMB), Abilities (Q ↔ E), or Weapon Shards (◆)",
			"Shards attach to LMB or RMB weapon slots — swap weapons freely with zero level loss."
		]

	var n: Dictionary = _interactive_nodes[inspect_idx]
	var kind: String = str(n["kind"])
	if kind == "shard":
		var sid: int = _get_cached_shard(int(n["group"]), int(n["idx"]))
		if sid == 0:
			return [
				"%s Socket — Empty" % str(n["tag"]),
				"Drag or click any Weapon Shard here to attach its effect."
			]
		var s_info: Dictionary = CatalogScript.get_shard(sid)
		return [
			"%s  (%s)" % [str(s_info.get("name", "Shard")), str(n["tag"])],
			str(s_info.get("desc", ""))
		]

	return [
		"[%s] %s" % [str(n["tag"]), _slot_names[inspect_idx]],
		_slot_descs[inspect_idx]
	]


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
