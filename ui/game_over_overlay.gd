class_name GameOverOverlay
extends Control

## Breath of the Wild × Shape of Dreams Game Over Overlay.
## Keeps the 3D game world active underneath while smoothly desaturating it to grayscale
## and fading brightness via `GameOverPost.gdshader`, presenting restart dialog options.

signal restart_new_map_requested()
signal retry_sanctuary_requested()
signal return_to_lobby_requested()

const POST_SHADER: Shader = preload("res://shaders/GameOverPost.gdshader")

var _post_rect: ColorRect = null
var _post_mat: ShaderMaterial = null
var _dialog_card: Control = null
var _card_margin: MarginContainer = null
var _divider_spacer: Control = null
var _restart_new_btn: Button = null
var _retry_sanctuary_btn: Button = null
var _lobby_btn: Button = null

var _fade_t: float = 0.0
var _is_showing: bool = false
var _online_lobby_available: bool = true

const FADE_DURATION: float = 0.55

const COL_CARD_BG := Color(0.043, 0.063, 0.098, 0.82)
const COL_IVORY_LINE := Color(0.918, 0.894, 0.843, 0.34)
const COL_IVORY_INNER := Color(0.918, 0.894, 0.843, 0.14)
const COL_IVORY_TEXT := Color(0.961, 0.945, 0.910, 1.0)
const COL_IVORY_MUTED := Color(0.918, 0.894, 0.843, 0.68)
const COL_CRIMSON_CREST := Color(0.941, 0.294, 0.263, 0.95)
const COL_BTN_BG := Color(0.075, 0.106, 0.161, 0.85)
const COL_BTN_HOVER := Color(0.125, 0.176, 0.255, 0.94)
const COL_BTN_PRESSED := Color(0.055, 0.078, 0.122, 0.95)
const COL_GOLD_ACCENT := Color(0.965, 0.827, 0.396, 0.82)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui_if_needed()
	hide_instant()


func _build_ui_if_needed() -> void:
	if _post_rect != null:
		return

	# 1. Full-screen live grayscale + dim fade shader rect
	_post_rect = ColorRect.new()
	_post_rect.name = "GrayscalePostRect"
	_post_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_post_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_post_mat = ShaderMaterial.new()
	_post_mat.shader = POST_SHADER
	_post_mat.set_shader_parameter("effect_amount", 0.0)
	_post_rect.material = _post_mat
	add_child(_post_rect)

	# 2. Centered architectural dialog card
	var center_wrap := CenterContainer.new()
	center_wrap.name = "CenterContainer"
	center_wrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_wrap.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center_wrap)

	_dialog_card = _DialogPanel.new()
	_dialog_card.name = "DialogCard"
	(_dialog_card as _DialogPanel).owner_overlay = self
	_dialog_card.custom_minimum_size = Vector2(390.0, 272.0)
	center_wrap.add_child(_dialog_card)

	_card_margin = MarginContainer.new()
	_card_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card_margin.add_theme_constant_override("margin_left", 32)
	_card_margin.add_theme_constant_override("margin_right", 32)
	_card_margin.add_theme_constant_override("margin_top", 28)
	_card_margin.add_theme_constant_override("margin_bottom", 26)
	_dialog_card.add_child(_card_margin)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 10)
	_card_margin.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.name = "TitleLabel"
	title_lbl.text = "GAME OVER"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 26)
	title_lbl.add_theme_color_override("font_color", COL_IVORY_TEXT)
	title_lbl.add_theme_color_override("font_shadow_color", Color(0.02, 0.03, 0.06, 0.85))
	title_lbl.add_theme_constant_override("shadow_offset_y", 2)
	vbox.add_child(title_lbl)

	var sub_lbl := Label.new()
	sub_lbl.name = "SubtitleLabel"
	sub_lbl.text = "You were defeated in combat."
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.add_theme_font_size_override("font_size", 13)
	sub_lbl.add_theme_color_override("font_color", COL_IVORY_MUTED)
	vbox.add_child(sub_lbl)

	_divider_spacer = Control.new()
	_divider_spacer.custom_minimum_size = Vector2(0.0, 14.0)
	vbox.add_child(_divider_spacer)
	vbox.sort_children.connect(func() -> void:
		if _dialog_card:
			if _card_margin:
				_dialog_card.custom_minimum_size = Vector2(390.0, maxf(272.0, _card_margin.get_combined_minimum_size().y + 6.0))
			_dialog_card.queue_redraw()
	)

	_restart_new_btn = _make_dialog_button("RestartNewButton", "Restart Run  (New Map)")
	_restart_new_btn.pressed.connect(func() -> void: restart_new_map_requested.emit())
	vbox.add_child(_restart_new_btn)

	_retry_sanctuary_btn = _make_dialog_button("RetrySanctuaryButton", "Retry From Sanctuary  (Same Map)")
	_retry_sanctuary_btn.pressed.connect(func() -> void: retry_sanctuary_requested.emit())
	vbox.add_child(_retry_sanctuary_btn)

	_lobby_btn = _make_dialog_button("ReturnLobbyButton", "Return to Lobby")
	_lobby_btn.visible = _online_lobby_available
	_lobby_btn.pressed.connect(func() -> void: return_to_lobby_requested.emit())
	vbox.add_child(_lobby_btn)


func _make_dialog_button(p_name: String, p_text: String) -> Button:
	var btn := Button.new()
	btn.name = p_name
	btn.text = p_text
	btn.custom_minimum_size = Vector2(310.0, 38.0)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var normal_sb := StyleBoxFlat.new()
	normal_sb.bg_color = COL_BTN_BG
	normal_sb.border_width_left = 1
	normal_sb.border_width_top = 1
	normal_sb.border_width_right = 1
	normal_sb.border_width_bottom = 1
	normal_sb.border_color = COL_IVORY_LINE
	normal_sb.corner_radius_top_left = 2
	normal_sb.corner_radius_top_right = 2
	normal_sb.corner_radius_bottom_left = 2
	normal_sb.corner_radius_bottom_right = 2

	var hover_sb := normal_sb.duplicate() as StyleBoxFlat
	hover_sb.bg_color = COL_BTN_HOVER
	hover_sb.border_color = COL_GOLD_ACCENT

	var pressed_sb := normal_sb.duplicate() as StyleBoxFlat
	pressed_sb.bg_color = COL_BTN_PRESSED
	pressed_sb.border_color = COL_GOLD_ACCENT

	btn.add_theme_stylebox_override("normal", normal_sb)
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_stylebox_override("pressed", pressed_sb)
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", COL_IVORY_TEXT)
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.78, 1.0))
	return btn


func set_online_lobby_available(available: bool) -> void:
	_online_lobby_available = available
	if _lobby_btn:
		_lobby_btn.visible = _online_lobby_available
	if _dialog_card:
		if _card_margin:
			_dialog_card.custom_minimum_size = Vector2(390.0, maxf(272.0, _card_margin.get_combined_minimum_size().y + 6.0))
		_dialog_card.queue_redraw()


func show_game_over() -> void:
	_build_ui_if_needed()
	_is_showing = true
	_fade_t = 0.0
	if _post_mat:
		_post_mat.set_shader_parameter("effect_amount", 0.0)
	if _dialog_card:
		_dialog_card.modulate = Color(1.0, 1.0, 1.0, 0.0)
	visible = true
	set_process(true)


func hide_instant() -> void:
	_is_showing = false
	_fade_t = 0.0
	if _post_mat:
		_post_mat.set_shader_parameter("effect_amount", 0.0)
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	if not _is_showing:
		set_process(false)
		return

	_fade_t = minf(1.0, _fade_t + delta / FADE_DURATION)
	var inv: float = 1.0 - _fade_t
	var eased: float = 1.0 - inv * inv * inv

	if _post_mat:
		_post_mat.set_shader_parameter("effect_amount", eased)
	if _dialog_card:
		var card_t: float = clampf((_fade_t - 0.12) / 0.88, 0.0, 1.0)
		_dialog_card.modulate = Color(1.0, 1.0, 1.0, card_t)

	if _fade_t >= 1.0:
		set_process(false)


class _DialogPanel:
	extends Control

	var owner_overlay: GameOverOverlay = null
	var _diamond_pts := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	var _diamond_closed := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])

	func _draw() -> void:
		var s: Vector2 = size
		# Outer smoked-slate architectural frame + inset double hairline
		draw_rect(Rect2(Vector2.ZERO, s), GameOverOverlay.COL_CARD_BG, true)
		draw_rect(Rect2(Vector2.ZERO, s), GameOverOverlay.COL_IVORY_LINE, false, 1.0)
		draw_rect(Rect2(Vector2(4.0, 4.0), s - Vector2(8.0, 8.0)), GameOverOverlay.COL_IVORY_INNER, false, 1.0)

		# Subtle divider rule with center crimson 45-degree diamond crest beneath subtitle
		var line_y: float = 96.0
		if owner_overlay != null and owner_overlay._divider_spacer != null and is_instance_valid(owner_overlay._divider_spacer):
			var sp: Control = owner_overlay._divider_spacer
			if sp.size.y > 0.5:
				line_y = (sp.global_position.y - global_position.y) + sp.size.y * 0.5
		var mid_x: float = s.x * 0.5
		draw_line(Vector2(36.0, line_y), Vector2(mid_x - 12.0, line_y), GameOverOverlay.COL_IVORY_LINE, 1.0, true)
		draw_line(Vector2(mid_x + 12.0, line_y), Vector2(s.x - 36.0, line_y), GameOverOverlay.COL_IVORY_LINE, 1.0, true)

		var r: float = 5.0
		_diamond_pts[0] = Vector2(mid_x, line_y - r)
		_diamond_pts[1] = Vector2(mid_x + r, line_y)
		_diamond_pts[2] = Vector2(mid_x, line_y + r)
		_diamond_pts[3] = Vector2(mid_x - r, line_y)
		draw_colored_polygon(_diamond_pts, GameOverOverlay.COL_CRIMSON_CREST)
		_diamond_closed[0] = _diamond_pts[0]
		_diamond_closed[1] = _diamond_pts[1]
		_diamond_closed[2] = _diamond_pts[2]
		_diamond_closed[3] = _diamond_pts[3]
		_diamond_closed[4] = _diamond_pts[0]
		draw_polyline(_diamond_closed, GameOverOverlay.COL_IVORY_LINE, 1.0, true)
