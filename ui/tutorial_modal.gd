class_name TutorialModal
extends Control

## Dedicated Tutorial & Controls Guide (keeps gameplay HUD and pickup cards clutter-free).

const COL_BACKDROP := Color(0.020, 0.032, 0.056, 0.76)
const COL_PANEL_BG := Color(0.043, 0.063, 0.098, 0.94)
const COL_CARD_BG := Color(0.058, 0.082, 0.128, 0.88)
const COL_IVORY_LINE := Color(0.918, 0.894, 0.843, 0.32)
const COL_IVORY_TEXT := Color(0.961, 0.945, 0.910, 1.0)
const COL_IVORY_MUTED := Color(0.918, 0.894, 0.843, 0.70)
const COL_ACCENT_CYAN := Color(0.52, 0.92, 1.0, 1.0)
const COL_ACCENT_GOLD := Color(1.0, 0.86, 0.42, 1.0)
const COL_ACCENT_GREEN := Color(0.42, 1.0, 0.68, 1.0)
const COL_BTN_BG := Color(0.075, 0.106, 0.161, 0.90)
const COL_BTN_HOVER := Color(0.135, 0.192, 0.275, 0.98)

var _bound_player: Node = null
var _is_open: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	close_modal()


func is_open() -> bool:
	return _is_open


func toggle_for_player(player_node: Node) -> void:
	if _is_open:
		close_modal()
	else:
		open_for_player(player_node)


func open_for_player(player_node: Node) -> void:
	_bound_player = player_node
	_is_open = true
	visible = true
	if _bound_player != null and is_instance_valid(_bound_player) and _bound_player.has_method("set_ui_input_blocked"):
		_bound_player.call("set_ui_input_blocked", true)


func close_modal() -> void:
	_is_open = false
	visible = false
	if _bound_player != null and is_instance_valid(_bound_player) and _bound_player.has_method("set_ui_input_blocked"):
		_bound_player.call("set_ui_input_blocked", false)
	_bound_player = null


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var ke: InputEventKey = event as InputEventKey
		if ke.keycode == KEY_ESCAPE or ke.keycode == KEY_F1 or ke.keycode == KEY_H:
			close_modal()
			get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = COL_BACKDROP
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			close_modal()
	)
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var outer := PanelContainer.new()
	outer.name = "TutorialCard"
	outer.custom_minimum_size = Vector2(780.0, 340.0)
	outer.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL_BG
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_width_top = 2
	sb.border_color = COL_IVORY_LINE
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	outer.add_theme_stylebox_override("panel", sb)
	center.add_child(outer)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 18)
	outer.add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 16)
	margin.add_child(root_vbox)

	var title_lbl := Label.new()
	title_lbl.text = "TUTORIAL & CONTROLS"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 21)
	title_lbl.add_theme_color_override("font_color", COL_IVORY_TEXT)
	root_vbox.add_child(title_lbl)

	var cols := HBoxContainer.new()
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	cols.add_theme_constant_override("separation", 14)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(cols)

	cols.add_child(_make_section(
		"COMBAT & MOVEMENT",
		COL_ACCENT_CYAN,
		"WASD — Move\n"
		+ "Space — Dash (3 charges)\n"
		+ "LMB / RMB — Fire Weapons\n"
		+ "X — Quick-swap LMB & RMB\n"
		+ "Q / E — Cast Abilities\n"
		+ "R — Cast Artifact\n"
		+ "F — Interact"
	))

	cols.add_child(_make_section(
		"LOADOUT & SHARDS",
		COL_ACCENT_GOLD,
		"Press [Tab] — Toggle Edit + Attributes mode (drag Shards, Weapons, and Q & E freely without holding a key).\n\n"
		+ "Hold [Alt] — Quick-zoom the HUD while held.\n\n"
		+ "Picking up a Shard, Weapon, or Ability zooms the HUD so you click a glowing slot directly."
	))

	cols.add_child(_make_section(
		"UPGRADES & HEALING",
		COL_ACCENT_GREEN,
		"Stat Traits buff AD, AP, Haste, or Speed across all weapons.\n\n"
		+ "Weapon Shards add on-hit effects to whichever weapon holds them.\n\n"
		+ "Healing Wells restore 45% Max HP (2 charges) and remain open if you backtrack."
	))

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	root_vbox.add_child(footer)

	var close_btn := Button.new()
	close_btn.name = "CloseTutorialButton"
	close_btn.text = "Close  [Esc]"
	close_btn.custom_minimum_size = Vector2(148.0, 32.0)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_btn.add_theme_font_size_override("font_size", 13)
	close_btn.add_theme_color_override("font_color", COL_IVORY_TEXT)

	var b_sb := StyleBoxFlat.new()
	b_sb.bg_color = COL_BTN_BG
	b_sb.border_width_left = 1
	b_sb.border_width_top = 1
	b_sb.border_width_right = 1
	b_sb.border_width_bottom = 1
	b_sb.border_color = COL_IVORY_LINE
	b_sb.corner_radius_top_left = 2
	b_sb.corner_radius_top_right = 2
	b_sb.corner_radius_bottom_left = 2
	b_sb.corner_radius_bottom_right = 2
	var b_hov := b_sb.duplicate() as StyleBoxFlat
	b_hov.bg_color = COL_BTN_HOVER
	close_btn.add_theme_stylebox_override("normal", b_sb)
	close_btn.add_theme_stylebox_override("hover", b_hov)
	close_btn.add_theme_stylebox_override("pressed", b_hov)
	close_btn.pressed.connect(close_modal)
	footer.add_child(close_btn)


func _make_section(heading: String, accent: Color, body: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(232.0, 210.0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_CARD_BG
	sb.border_width_top = 2
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.58)
	sb.corner_radius_top_left = 2
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2
	sb.corner_radius_bottom_right = 2
	card.add_theme_stylebox_override("panel", sb)

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 14)
	m.add_theme_constant_override("margin_right", 14)
	m.add_theme_constant_override("margin_top", 12)
	m.add_theme_constant_override("margin_bottom", 12)
	card.add_child(m)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	m.add_child(vb)

	var h_lbl := Label.new()
	h_lbl.text = heading
	h_lbl.add_theme_font_size_override("font_size", 11)
	h_lbl.add_theme_color_override("font_color", accent)
	vb.add_child(h_lbl)

	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0.0, 1.0)
	sep.color = COL_IVORY_LINE
	vb.add_child(sep)

	var b_lbl := Label.new()
	b_lbl.text = body
	b_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b_lbl.add_theme_font_size_override("font_size", 12)
	b_lbl.add_theme_color_override("font_color", COL_IVORY_MUTED)
	vb.add_child(b_lbl)

	return card
