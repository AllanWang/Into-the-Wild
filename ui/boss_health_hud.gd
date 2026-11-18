class_name BossHealthHud
extends Control

## Top-center Hades-inspired Boss Health & Phase-Gate HUD bar.
## Displays Boss Title + Epithet, Remaining Life-Stock Diamond Pips,
## crimson HP fill with smooth damage trail, golden Armor overlay,
## and gleaming Impervious Barrier feedback during phase shifts.

const HUD_W: float = 520.0
const HUD_H: float = 72.0
const BAR_X: float = 18.0
const BAR_Y: float = 38.0
const BAR_W: float = 484.0
const BAR_H: float = 12.0

const COL_BG_PANEL := Color(0.036, 0.052, 0.084, 0.80)
const COL_IVORY_LINE := Color(0.918, 0.894, 0.843, 0.34)
const COL_IVORY_TEXT := Color(0.961, 0.945, 0.910, 1.0)
const COL_GOLD := Color(1.0, 0.82, 0.28, 0.98)
const COL_CRIMSON := Color(0.92, 0.22, 0.28, 1.0)
const COL_CRIMSON_LOW := Color(1.0, 0.18, 0.24, 1.0)
const COL_TRAIL := Color(0.98, 0.86, 0.44, 0.88)
const COL_SHIELD := Color(0.36, 0.88, 1.0, 0.90)
const COL_IMPERVIOUS := Color(1.0, 0.94, 0.64, 0.96)
const COL_PIP_EMPTY := Color(0.05, 0.07, 0.11, 0.78)
const COL_SHADOW := Color(0.02, 0.03, 0.06, 0.90)

var _boss_health: HealthComponent = null
var _max_hp: float = 100.0
var _current_hp: float = 100.0
var _max_armor: float = 0.0
var _current_armor: float = 0.0
var _current_shield: float = 0.0

var _hp_ratio: float = 1.0
var _trail_ratio: float = 1.0
var _armor_ratio: float = 0.0
var _shield_ratio: float = 0.0

var _total_bars: int = 3
var _remaining_bars: int = 3
var _is_impervious: bool = false
var _hit_flash: float = 0.0
var _bar_flash: float = 0.0

var _name_label: Label = null
var _epithet_label: Label = null
var _status_label: Label = null

var _scratch_quad := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _scratch_closed := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(HUD_W, HUD_H)
	custom_minimum_size = Vector2(HUD_W, HUD_H)
	_build_labels_if_needed()
	_recenter()
	visible = false
	set_process(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_VISIBILITY_CHANGED:
		_recenter()


func _recenter() -> void:
	var vp: Viewport = get_viewport()
	if vp == null:
		return
	var vp_w: float = vp.get_visible_rect().size.x
	position = Vector2((vp_w - HUD_W) * 0.5, 92.0)


func is_bound() -> bool:
	return _boss_health != null and is_instance_valid(_boss_health) and not _boss_health.is_dead


## Binds the top-center Boss HUD to an active Boss unit and displays its phase bars & armor.
func bind_boss(boss_node: Node, boss_name: String, epithet: String = "") -> void:
	_disconnect_boss()
	_build_labels_if_needed()
	if boss_node == null or not is_instance_valid(boss_node):
		visible = false
		return

	var hc: HealthComponent = boss_node.get("health_comp") as HealthComponent
	if hc == null:
		visible = false
		return

	_boss_health = hc
	_max_hp = maxf(1.0, hc.max_health)
	_current_hp = clampf(hc.current_health, 0.0, _max_hp)
	_hp_ratio = _current_hp / _max_hp
	_trail_ratio = _hp_ratio
	_max_armor = maxf(0.0, hc.max_armor)
	_current_armor = maxf(0.0, hc.current_armor)
	_armor_ratio = clampf(_current_armor / maxf(1.0, _max_armor), 0.0, 1.0) if _current_armor > 0.01 else 0.0
	_current_shield = maxf(0.0, hc.current_shield)
	_shield_ratio = clampf(_current_shield / _max_hp, 0.0, 1.0)
	_total_bars = maxi(1, hc.total_bars)
	_remaining_bars = clampi(hc.current_bar_index, 1, _total_bars)
	_is_impervious = hc.is_impervious()
	_hit_flash = 0.0
	_bar_flash = 0.0

	if not hc.health_changed.is_connected(_on_hp_changed):
		hc.health_changed.connect(_on_hp_changed)
	if not hc.armor_changed.is_connected(_on_armor_changed):
		hc.armor_changed.connect(_on_armor_changed)
	if not hc.shield_changed.is_connected(_on_shield_changed):
		hc.shield_changed.connect(_on_shield_changed)
	if not hc.bar_broken.is_connected(_on_bar_broken):
		hc.bar_broken.connect(_on_bar_broken)
	if not hc.phase_gate_changed.is_connected(_on_phase_gate_changed):
		hc.phase_gate_changed.connect(_on_phase_gate_changed)
	if not hc.died.is_connected(_on_boss_died):
		hc.died.connect(_on_boss_died)

	if _name_label:
		_name_label.text = boss_name.to_upper()
	if _epithet_label:
		_epithet_label.text = epithet.to_upper()
		_epithet_label.visible = not epithet.is_empty()

	_refresh_status_label()
	_recenter()
	visible = true
	set_process(true)
	queue_redraw()


func clear_boss() -> void:
	_disconnect_boss()
	visible = false
	set_process(false)


func _disconnect_boss() -> void:
	if _boss_health != null and is_instance_valid(_boss_health):
		if _boss_health.health_changed.is_connected(_on_hp_changed):
			_boss_health.health_changed.disconnect(_on_hp_changed)
		if _boss_health.armor_changed.is_connected(_on_armor_changed):
			_boss_health.armor_changed.disconnect(_on_armor_changed)
		if _boss_health.shield_changed.is_connected(_on_shield_changed):
			_boss_health.shield_changed.disconnect(_on_shield_changed)
		if _boss_health.bar_broken.is_connected(_on_bar_broken):
			_boss_health.bar_broken.disconnect(_on_bar_broken)
		if _boss_health.phase_gate_changed.is_connected(_on_phase_gate_changed):
			_boss_health.phase_gate_changed.disconnect(_on_phase_gate_changed)
		if _boss_health.died.is_connected(_on_boss_died):
			_boss_health.died.disconnect(_on_boss_died)
	_boss_health = null


func _process(delta: float) -> void:
	if _boss_health == null or not is_instance_valid(_boss_health):
		clear_boss()
		return

	_recenter()
	var dirty: bool = false
	if _trail_ratio > _hp_ratio:
		_trail_ratio = move_toward(_trail_ratio, _hp_ratio, delta * 0.65)
		dirty = true
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta)
		dirty = true
	if _bar_flash > 0.0:
		_bar_flash = maxf(0.0, _bar_flash - delta)
		dirty = true
	if dirty:
		queue_redraw()


func _on_hp_changed(cur_hp: float, max_hp: float) -> void:
	_max_hp = maxf(1.0, max_hp)
	_current_hp = clampf(cur_hp, 0.0, _max_hp)
	var new_ratio: float = _current_hp / _max_hp
	if new_ratio < _hp_ratio:
		_hit_flash = 0.08
	elif new_ratio > _trail_ratio:
		_trail_ratio = new_ratio
	_hp_ratio = new_ratio
	_refresh_status_label()
	queue_redraw()


func _on_armor_changed(cur_armor: float, max_arm: float) -> void:
	_max_armor = maxf(_max_armor, max_arm)
	_current_armor = maxf(0.0, cur_armor)
	_armor_ratio = clampf(_current_armor / maxf(1.0, _max_armor), 0.0, 1.0) if _current_armor > 0.01 else 0.0
	_hit_flash = 0.07
	_refresh_status_label()
	queue_redraw()


func _on_shield_changed(cur_shield: float, max_hp: float) -> void:
	_max_hp = maxf(1.0, max_hp)
	_current_shield = maxf(0.0, cur_shield)
	_shield_ratio = clampf(_current_shield / _max_hp, 0.0, 1.0)
	queue_redraw()


func _on_bar_broken(remaining_bars: int, total_bars: int, bar_max_hp: float) -> void:
	_total_bars = maxi(1, total_bars)
	_remaining_bars = clampi(remaining_bars, 1, _total_bars)
	_max_hp = maxf(1.0, bar_max_hp)
	_current_hp = _max_hp
	_hp_ratio = 1.0
	_trail_ratio = 1.0
	_bar_flash = 0.35
	_refresh_status_label()
	queue_redraw()


func _on_phase_gate_changed(is_imp: bool, remaining_bars: int) -> void:
	_is_impervious = is_imp
	_remaining_bars = clampi(remaining_bars, 1, _total_bars)
	_refresh_status_label()
	queue_redraw()


func _on_boss_died() -> void:
	clear_boss()


func _refresh_status_label() -> void:
	if _status_label == null:
		return
	var phase_num: int = clampi((_total_bars - _remaining_bars) + 1, 1, _total_bars)
	if _is_impervious:
		_status_label.text = "IMPERVIOUS — PHASE SHIFT"
		_status_label.add_theme_color_override("font_color", COL_IMPERVIOUS)
	elif _armor_ratio > 0.005:
		_status_label.text = "Phase %d / %d  |  ARMOR: %d  |  HP: %d / %d" % [
			phase_num, _total_bars, int(ceilf(_current_armor)), int(ceilf(_current_hp)), int(roundf(_max_hp))
		]
		_status_label.add_theme_color_override("font_color", COL_GOLD)
	else:
		_status_label.text = "Phase %d / %d  |  %d / %d" % [
			phase_num, _total_bars, int(ceilf(_current_hp)), int(roundf(_max_hp))
		]
		_status_label.add_theme_color_override("font_color", Color(0.918, 0.894, 0.843, 0.84))


func _build_labels_if_needed() -> void:
	if _name_label != null:
		return

	_epithet_label = _make_clean_label(10, COL_GOLD)
	_epithet_label.name = "BossEpithetLabel"
	_epithet_label.position = Vector2(BAR_X + 6.0, 2.0)
	_epithet_label.custom_minimum_size = Vector2(300.0, 14.0)
	add_child(_epithet_label)

	_name_label = _make_clean_label(15, COL_IVORY_TEXT)
	_name_label.name = "BossNameLabel"
	_name_label.position = Vector2(BAR_X + 6.0, 14.0)
	_name_label.custom_minimum_size = Vector2(320.0, 22.0)
	add_child(_name_label)

	_status_label = _make_clean_label(11, COL_IVORY_TEXT)
	_status_label.name = "BossStatusLabel"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.position = Vector2(BAR_X, BAR_Y + BAR_H + 5.0)
	_status_label.custom_minimum_size = Vector2(BAR_W, 16.0)
	add_child(_status_label)


func _make_clean_label(font_sz: int, col: Color) -> Label:
	var lbl := Label.new()
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", font_sz)
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_color_override("font_shadow_color", COL_SHADOW)
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	return lbl


func _draw() -> void:
	if not visible:
		return

	# Track backdrop
	draw_rect(Rect2(BAR_X, BAR_Y, BAR_W, BAR_H), COL_BG_PANEL, true)

	# Smooth delayed damage trail
	var trail_w: float = BAR_W * clampf(_trail_ratio, 0.0, 1.0)
	if trail_w > 1.0:
		draw_rect(Rect2(BAR_X, BAR_Y + 1.5, trail_w, BAR_H - 3.0), COL_TRAIL, true)

	# Crimson health fill
	var hp_w: float = BAR_W * clampf(_hp_ratio, 0.0, 1.0)
	if hp_w > 1.0:
		var fill_col: Color = COL_CRIMSON_LOW if _hp_ratio <= 0.25 else COL_CRIMSON
		if _bar_flash > 0.0 or _hit_flash > 0.0:
			fill_col = Color(1.0, 0.94, 0.88, 1.0)
		draw_rect(Rect2(BAR_X, BAR_Y + 1.5, hp_w, BAR_H - 3.0), fill_col, true)

	# Hades-style Golden Armor strip across upper half while armor > 0
	if _armor_ratio > 0.005:
		var arm_w: float = BAR_W * clampf(_armor_ratio, 0.0, 1.0)
		draw_rect(Rect2(BAR_X, BAR_Y + 1.5, arm_w, (BAR_H - 3.0) * 0.56), COL_GOLD, true)

	# Shield segment overlay if any shield is active
	if _shield_ratio > 0.01:
		var sh_w: float = clampf(BAR_W * _shield_ratio, 3.0, BAR_W)
		draw_rect(Rect2(BAR_X + BAR_W - sh_w, BAR_Y + 1.5, sh_w, BAR_H - 3.0), COL_SHIELD, true)

	# Quarter tick marks for clear burst chunk reading
	for q in range(1, 4):
		var tx: float = BAR_X + BAR_W * (float(q) * 0.25)
		draw_line(Vector2(tx, BAR_Y + 1.5), Vector2(tx, BAR_Y + BAR_H - 1.5), Color(0.03, 0.04, 0.07, 0.55), 1.0, false)

	var frame_col: Color = COL_IMPERVIOUS if _is_impervious else (COL_GOLD if _armor_ratio > 0.005 else COL_IVORY_LINE)
	var frame_w: float = 2.0 if (_is_impervious or _armor_ratio > 0.005) else 1.2
	draw_line(Vector2(BAR_X, BAR_Y), Vector2(BAR_X + BAR_W, BAR_Y), frame_col, frame_w, true)
	draw_line(Vector2(BAR_X, BAR_Y + BAR_H), Vector2(BAR_X + BAR_W, BAR_Y + BAR_H), frame_col, frame_w, true)

	var mid_y: float = BAR_Y + BAR_H * 0.5
	_draw_diamond(Vector2(BAR_X, mid_y), 7.5, COL_BG_PANEL, frame_col, 1.4)
	_draw_diamond(Vector2(BAR_X + BAR_W, mid_y), 7.5, COL_BG_PANEL, frame_col, 1.4)

	# Life-Stock Diamond Pips at top-right above the bar
	var pip_start_x: float = BAR_X + BAR_W - 10.0 - float(maxi(0, _total_bars - 1)) * 18.0
	var pip_y: float = 24.0
	for p_i in range(_total_bars):
		var c := Vector2(pip_start_x + float(p_i) * 18.0, pip_y)
		if p_i < _remaining_bars:
			var p_fill: Color = COL_GOLD if _is_impervious else COL_CRIMSON
			_draw_diamond(c, 6.2, p_fill, COL_GOLD, 1.3)
		else:
			_draw_diamond(c, 5.2, COL_PIP_EMPTY, Color(0.92, 0.89, 0.84, 0.28), 1.0)


func _draw_diamond(center: Vector2, half_diag: float, fill_col: Color, stroke_col: Color, stroke_w: float) -> void:
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
	draw_polyline(_scratch_closed, stroke_col, stroke_w, true)
