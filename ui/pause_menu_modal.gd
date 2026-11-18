class_name PauseMenuModal
extends Control

## Escape menu inspired by Don't Starve Together:
## - Single player: pauses the SceneTree and displays "Paused".
## - Multiplayer (2+ players): keeps the world live and displays "Not paused. Seriously, it's not."
## Includes Resume, Tutorial & Controls, an extensible Debug Tools drawer (debug builds), and Main Menu.

signal resume_requested()
signal tutorial_requested()
signal web_quality_cycle_requested()
signal main_menu_requested()
signal debug_biome_requested()
signal debug_preset_requested()
signal debug_regen_requested()
signal debug_teleport_requested()
signal debug_overview_requested()
signal debug_god_mode_requested()

const COL_BACKDROP := Color(0.016, 0.024, 0.044, 0.72)
const COL_PANEL_BG := Color(0.040, 0.056, 0.092, 0.96)
const COL_DRAWER_BG := Color(0.028, 0.040, 0.068, 0.94)
const COL_IVORY_LINE := Color(0.918, 0.894, 0.843, 0.30)
const COL_IVORY_TEXT := Color(0.961, 0.945, 0.910, 1.0)
const COL_IVORY_MUTED := Color(0.918, 0.894, 0.843, 0.72)
const COL_SOLO_ACCENT := Color(0.52, 0.90, 1.0, 1.0)
const COL_MULTI_ACCENT := Color(1.0, 0.72, 0.38, 1.0)
const COL_DANGER_ACCENT := Color(0.98, 0.42, 0.48, 0.92)

const URL_GITHUB := "https://github.com/AllanWang/Into-the-Wild"
const URL_GAME_PAGE := "https://allanwang.github.io/Into-the-Wild/"
const URL_ATTRIBUTIONS := "https://github.com/AllanWang/Into-the-Wild/blob/main/Attribution.md"

var _panel_style: StyleBoxFlat = null
var _status_badge_lbl: Label = null
var _title_lbl: Label = null
var _debug_toggle_btn: Button = null
var _debug_drawer: PanelContainer = null
var _debug_god_btn: Button = null
var _web_quality_btn: Button = null
var _menu_btn: Button = null

var _bound_player: Node = null
var _is_open: bool = false
var _is_solo_paused: bool = false
var _online_lobby_available: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	close_menu()


func _exit_tree() -> void:
	if is_inside_tree() and get_tree() != null and get_tree().paused:
		get_tree().paused = false


func set_online_lobby_available(available: bool) -> void:
	_online_lobby_available = available
	if _menu_btn:
		_menu_btn.text = "Main Menu" if _online_lobby_available else "Restart Run"


func set_web_quality_label(label_text: String) -> void:
	if _web_quality_btn:
		_web_quality_btn.text = label_text


func set_debug_god_mode_label(enabled: bool) -> void:
	if _debug_god_btn:
		_debug_god_btn.text = "God Mode: ON  [F2]" if enabled else "God Mode: OFF  [F2]"


func is_open() -> bool:
	return _is_open


func open_menu(player_node: Node, is_solo: bool) -> void:
	_build_ui()
	_bound_player = player_node
	_is_open = true
	visible = true
	if _debug_drawer:
		_debug_drawer.visible = false
	if _debug_toggle_btn:
		_debug_toggle_btn.text = "Debug Tools  [+]"
	refresh_pause_mode(is_solo)


func refresh_pause_mode(is_solo: bool) -> void:
	_is_solo_paused = is_solo
	if not _is_open:
		return

	if is_solo:
		if is_inside_tree() and get_tree() != null:
			get_tree().paused = true
		if _title_lbl:
			_title_lbl.text = "Paused"
		if _status_badge_lbl:
			_status_badge_lbl.text = "SOLO SESSION  ·  GAME PAUSED"
			_status_badge_lbl.add_theme_color_override("font_color", COL_SOLO_ACCENT)
		if _panel_style:
			_panel_style.border_color = COL_SOLO_ACCENT
		if _bound_player != null and is_instance_valid(_bound_player) and _bound_player.has_method("set_ui_input_blocked"):
			_bound_player.call("set_ui_input_blocked", false)
	else:
		if is_inside_tree() and get_tree() != null:
			get_tree().paused = false
		if _title_lbl:
			_title_lbl.text = "Not paused. Seriously, it's not."
		if _status_badge_lbl:
			_status_badge_lbl.text = "MULTIPLAYER SESSION  ·  WORLD STILL RUNNING"
			_status_badge_lbl.add_theme_color_override("font_color", COL_MULTI_ACCENT)
		if _panel_style:
			_panel_style.border_color = COL_MULTI_ACCENT
		if _bound_player != null and is_instance_valid(_bound_player) and _bound_player.has_method("set_ui_input_blocked"):
			_bound_player.call("set_ui_input_blocked", true)


func close_menu() -> void:
	_is_open = false
	_is_solo_paused = false
	visible = false
	if _debug_drawer:
		_debug_drawer.visible = false
	if _debug_toggle_btn:
		_debug_toggle_btn.text = "Debug Tools  [+]"
	if is_inside_tree() and get_tree() != null and get_tree().paused:
		get_tree().paused = false
	if _bound_player != null and is_instance_valid(_bound_player) and _bound_player.has_method("set_ui_input_blocked"):
		_bound_player.call("set_ui_input_blocked", false)
	_bound_player = null


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var ke: InputEventKey = event as InputEventKey
		if ke.keycode == KEY_ESCAPE:
			close_menu()
			resume_requested.emit()
			get_viewport().set_input_as_handled()


func _build_ui() -> void:
	if _title_lbl != null:
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
	panel.name = "PausePanel"
	panel.custom_minimum_size = Vector2(420.0, 260.0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)

	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = COL_PANEL_BG
	_panel_style.border_width_left = 1
	_panel_style.border_width_right = 1
	_panel_style.border_width_bottom = 1
	_panel_style.border_width_top = 3
	_panel_style.border_color = COL_SOLO_ACCENT
	_panel_style.corner_radius_top_left = 4
	_panel_style.corner_radius_top_right = 4
	_panel_style.corner_radius_bottom_left = 4
	_panel_style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", _panel_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)

	var vb := VBoxContainer.new()
	vb.name = "MenuVBox"
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)

	_status_badge_lbl = Label.new()
	_status_badge_lbl.name = "StatusBadgeLabel"
	_status_badge_lbl.text = "SOLO SESSION  ·  GAME PAUSED"
	_status_badge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_badge_lbl.add_theme_font_size_override("font_size", 11)
	_status_badge_lbl.add_theme_color_override("font_color", COL_SOLO_ACCENT)
	vb.add_child(_status_badge_lbl)

	_title_lbl = Label.new()
	_title_lbl.name = "PauseTitleLabel"
	_title_lbl.text = "Paused"
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_lbl.add_theme_font_size_override("font_size", 22)
	_title_lbl.add_theme_color_override("font_color", COL_IVORY_TEXT)
	vb.add_child(_title_lbl)

	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0.0, 1.0)
	sep.color = COL_IVORY_LINE
	vb.add_child(sep)

	var resume_btn := _make_menu_button("ResumeButton", "Resume  [Esc]", true, false)
	resume_btn.pressed.connect(func() -> void:
		close_menu()
		resume_requested.emit()
	)
	vb.add_child(resume_btn)

	var tutorial_btn := _make_menu_button("TutorialButton", "Tutorial & Controls", false, false)
	tutorial_btn.pressed.connect(func() -> void:
		close_menu()
		tutorial_requested.emit()
	)
	vb.add_child(tutorial_btn)

	_web_quality_btn = _make_menu_button("WebQualityButton", "Graphics: Crisp (2x AA)", false, false)
	_web_quality_btn.visible = OS.has_feature("web")
	_web_quality_btn.pressed.connect(func() -> void:
		web_quality_cycle_requested.emit()
	)
	vb.add_child(_web_quality_btn)

	_debug_toggle_btn = _make_menu_button("DebugToggleButton", "Debug Tools  [+]", false, false)
	_debug_toggle_btn.visible = OS.is_debug_build()
	_debug_toggle_btn.pressed.connect(_on_debug_toggle_pressed)
	vb.add_child(_debug_toggle_btn)

	_debug_drawer = PanelContainer.new()
	_debug_drawer.name = "DebugDrawer"
	_debug_drawer.visible = false
	var d_sb := StyleBoxFlat.new()
	d_sb.bg_color = COL_DRAWER_BG
	d_sb.border_width_left = 1
	d_sb.border_width_right = 1
	d_sb.border_width_top = 1
	d_sb.border_width_bottom = 1
	d_sb.border_color = COL_IVORY_LINE
	d_sb.corner_radius_top_left = 3
	d_sb.corner_radius_top_right = 3
	d_sb.corner_radius_bottom_left = 3
	d_sb.corner_radius_bottom_right = 3
	_debug_drawer.add_theme_stylebox_override("panel", d_sb)
	vb.add_child(_debug_drawer)

	var d_margin := MarginContainer.new()
	d_margin.add_theme_constant_override("margin_left", 10)
	d_margin.add_theme_constant_override("margin_right", 10)
	d_margin.add_theme_constant_override("margin_top", 8)
	d_margin.add_theme_constant_override("margin_bottom", 8)
	_debug_drawer.add_child(d_margin)

	var d_grid := GridContainer.new()
	d_grid.columns = 2
	d_grid.add_theme_constant_override("h_separation", 8)
	d_grid.add_theme_constant_override("v_separation", 6)
	d_margin.add_child(d_grid)

	_add_debug_action(d_grid, "DebugBiomeButton", "Cycle Biome", debug_biome_requested)
	_add_debug_action(d_grid, "DebugPresetButton", "Cycle Map Mode", debug_preset_requested)
	_add_debug_action(d_grid, "DebugRegenButton", "New Map Seed", debug_regen_requested)
	_add_debug_action(d_grid, "DebugTeleportButton", "Teleport Next Room", debug_teleport_requested)
	_add_debug_action(d_grid, "DebugOverviewButton", "Toggle Overview Cam", debug_overview_requested)
	_debug_god_btn = _make_menu_button("DebugGodModeButton", "God Mode: OFF  [F2]", false, false, 32.0, 12)
	_debug_god_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_debug_god_btn.pressed.connect(func() -> void:
		debug_god_mode_requested.emit()
	)
	d_grid.add_child(_debug_god_btn)

	_menu_btn = _make_menu_button("MainMenuButton", "Main Menu" if _online_lobby_available else "Restart Run", false, true)
	_menu_btn.pressed.connect(func() -> void:
		close_menu()
		main_menu_requested.emit()
	)
	vb.add_child(_menu_btn)

	var links_sep := ColorRect.new()
	links_sep.custom_minimum_size = Vector2(0.0, 1.0)
	links_sep.color = COL_IVORY_LINE
	vb.add_child(links_sep)

	var links_row := HBoxContainer.new()
	links_row.name = "LinksRow"
	links_row.alignment = BoxContainer.ALIGNMENT_CENTER
	links_row.add_theme_constant_override("separation", 6)
	vb.add_child(links_row)
	_add_external_link_button(links_row, "GitHubLinkButton", "GitHub", URL_GITHUB)
	_add_external_link_button(links_row, "GamePageLinkButton", "Game Page", URL_GAME_PAGE)
	_add_external_link_button(links_row, "AttributionsLinkButton", "Attributions", URL_ATTRIBUTIONS)


func _add_external_link_button(parent: Control, btn_name: String, label_text: String, target_url: String) -> void:
	var btn := _make_menu_button(btn_name, label_text, false, false, 26.0, 11)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_color_override("font_color", COL_IVORY_MUTED)
	btn.tooltip_text = target_url
	btn.pressed.connect(func() -> void:
		OS.shell_open(target_url)
	)
	parent.add_child(btn)


func _add_debug_action(parent: Control, btn_name: String, label_text: String, sig: Signal) -> void:
	var btn := _make_menu_button(btn_name, label_text, false, false, 32.0, 12)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(func() -> void:
		close_menu()
		sig.emit()
	)
	parent.add_child(btn)


func _on_debug_toggle_pressed() -> void:
	if _debug_drawer == null:
		return
	_debug_drawer.visible = not _debug_drawer.visible
	if _debug_toggle_btn:
		_debug_toggle_btn.text = "Debug Tools  [-]" if _debug_drawer.visible else "Debug Tools  [+]"


func _make_menu_button(
	btn_name: String,
	label_text: String,
	is_primary: bool,
	is_danger: bool,
	min_h: float = 38.0,
	font_sz: int = 14
) -> Button:
	var btn := Button.new()
	btn.name = btn_name
	btn.text = label_text
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.custom_minimum_size = Vector2(0.0, min_h)
	btn.add_theme_font_size_override("font_size", font_sz)
	btn.add_theme_color_override("font_color", COL_IVORY_TEXT)

	var normal_sb := StyleBoxFlat.new()
	if is_primary:
		normal_sb.bg_color = Color(0.14, 0.22, 0.36, 0.94)
		normal_sb.border_color = COL_SOLO_ACCENT
	elif is_danger:
		normal_sb.bg_color = Color(0.16, 0.08, 0.12, 0.92)
		normal_sb.border_color = COL_DANGER_ACCENT
	else:
		normal_sb.bg_color = Color(0.075, 0.106, 0.161, 0.92)
		normal_sb.border_color = COL_IVORY_LINE
	normal_sb.set_border_width_all(1)
	normal_sb.set_corner_radius_all(3)

	var hover_sb := normal_sb.duplicate() as StyleBoxFlat
	if is_primary:
		hover_sb.bg_color = Color(0.22, 0.34, 0.54, 0.98)
		hover_sb.border_color = Color(0.76, 0.94, 1.0, 1.0)
	elif is_danger:
		hover_sb.bg_color = Color(0.28, 0.12, 0.18, 0.98)
		hover_sb.border_color = Color(1.0, 0.62, 0.68, 1.0)
	else:
		hover_sb.bg_color = Color(0.135, 0.192, 0.275, 0.98)
		hover_sb.border_color = Color(0.96, 0.94, 0.90, 0.78)

	btn.add_theme_stylebox_override("normal", normal_sb)
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_stylebox_override("pressed", hover_sb)
	return btn
