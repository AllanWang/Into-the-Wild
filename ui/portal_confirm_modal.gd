class_name PortalConfirmModal
extends Control

## Confirmation dialog surfaced when a player activates the Rift Portal while one or more
## spawned Upgrade Pedestals remain unclaimed on the current map.

signal proceed_confirmed()
signal cancelled()

const COL_BACKDROP := Color(0.020, 0.030, 0.054, 0.76)
const COL_PANEL_BG := Color(0.042, 0.060, 0.098, 0.96)
const COL_PORTAL_ACCENT := Color(0.66, 0.78, 1.0, 0.95)
const COL_IVORY_LINE := Color(0.918, 0.894, 0.843, 0.34)
const COL_IVORY_TEXT := Color(0.961, 0.945, 0.910, 1.0)
const COL_IVORY_MUTED := Color(0.918, 0.894, 0.843, 0.76)

var _body_lbl: Label = null
var _stay_btn: Button = null
var _proceed_btn: Button = null
var _active_player: Node = null
var _is_open: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	close_modal()


func is_open() -> bool:
	return _is_open


func _build_ui() -> void:
	if _body_lbl != null:
		return

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = COL_BACKDROP
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var center := CenterContainer.new()
	center.name = "CenterContainer"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)

	var panel := PanelContainer.new()
	panel.name = "ConfirmPanel"
	panel.custom_minimum_size = Vector2(468.0, 214.0)
	center.add_child(panel)

	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL_BG
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_width_top = 3
	sb.border_color = COL_PORTAL_ACCENT
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	panel.add_theme_stylebox_override("panel", sb)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	margin.add_child(vb)

	var sub_lbl := Label.new()
	sub_lbl.text = "RIFT PORTAL"
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.add_theme_font_size_override("font_size", 11)
	sub_lbl.add_theme_color_override("font_color", COL_PORTAL_ACCENT)
	vb.add_child(sub_lbl)

	var title_lbl := Label.new()
	title_lbl.text = "UNCLAIMED UPGRADES REMAIN"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", COL_IVORY_TEXT)
	vb.add_child(title_lbl)

	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0.0, 1.0)
	sep.color = COL_IVORY_LINE
	vb.add_child(sep)

	_body_lbl = Label.new()
	_body_lbl.name = "BodyLabel"
	_body_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_lbl.add_theme_font_size_override("font_size", 14)
	_body_lbl.add_theme_color_override("font_color", COL_IVORY_MUTED)
	vb.add_child(_body_lbl)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vb.add_child(btn_row)

	_stay_btn = _make_button("StayButton", "Stay & Claim  [Esc]", false)
	_stay_btn.custom_minimum_size = Vector2(188.0, 38.0)
	_stay_btn.pressed.connect(_on_stay_pressed)
	btn_row.add_child(_stay_btn)

	_proceed_btn = _make_button("ProceedButton", "Proceed Anyway", true)
	_proceed_btn.custom_minimum_size = Vector2(188.0, 38.0)
	_proceed_btn.pressed.connect(_on_proceed_pressed)
	btn_row.add_child(_proceed_btn)


func _make_button(btn_name: String, label_text: String, is_primary: bool) -> Button:
	var btn := Button.new()
	btn.name = btn_name
	btn.text = label_text
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", COL_IVORY_TEXT)

	var normal_sb := StyleBoxFlat.new()
	normal_sb.bg_color = Color(0.14, 0.19, 0.34, 0.94) if is_primary else Color(0.075, 0.106, 0.161, 0.92)
	normal_sb.border_width_left = 1
	normal_sb.border_width_top = 1
	normal_sb.border_width_right = 1
	normal_sb.border_width_bottom = 1
	normal_sb.border_color = COL_PORTAL_ACCENT if is_primary else COL_IVORY_LINE
	normal_sb.corner_radius_top_left = 2
	normal_sb.corner_radius_top_right = 2
	normal_sb.corner_radius_bottom_left = 2
	normal_sb.corner_radius_bottom_right = 2

	var hover_sb := normal_sb.duplicate() as StyleBoxFlat
	hover_sb.bg_color = Color(0.22, 0.30, 0.50, 0.98) if is_primary else Color(0.135, 0.192, 0.275, 0.98)
	hover_sb.border_color = Color(0.76, 0.94, 1.0, 1.0) if is_primary else Color(0.96, 0.94, 0.90, 0.78)

	btn.add_theme_stylebox_override("normal", normal_sb)
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_stylebox_override("pressed", hover_sb)
	return btn


func open_for_unclaimed(unclaimed_count: int, player_node: Node) -> void:
	_build_ui()
	_active_player = player_node
	_is_open = true
	if _active_player != null and is_instance_valid(_active_player) and _active_player.has_method("set_ui_input_blocked"):
		_active_player.call("set_ui_input_blocked", true)

	if unclaimed_count == 1:
		_body_lbl.text = "You still have 1 unclaimed Upgrade Pedestal on this map.\nEnter the Rift Portal anyway without claiming it?"
	else:
		_body_lbl.text = "You still have %d unclaimed Upgrade Pedestals on this map.\nEnter the Rift Portal anyway without claiming them?" % unclaimed_count

	visible = true


func close_modal() -> void:
	_is_open = false
	visible = false
	if _active_player != null and is_instance_valid(_active_player) and _active_player.has_method("set_ui_input_blocked"):
		_active_player.call("set_ui_input_blocked", false)
	_active_player = null


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var ke: InputEventKey = event as InputEventKey
		if ke.keycode == KEY_ESCAPE or ke.keycode == KEY_BACKSPACE:
			_on_stay_pressed()
			get_viewport().set_input_as_handled()


func _on_stay_pressed() -> void:
	close_modal()
	cancelled.emit()


func _on_proceed_pressed() -> void:
	close_modal()
	proceed_confirmed.emit()
