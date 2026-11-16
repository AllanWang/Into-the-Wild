class_name RewardDraftOverlay
extends Control

## Upgrade Pedestal Pickup UI (Breath of the Wild × Shape of Dreams).
## - Step 1: 3 uncluttered cards (Ability/Artifact, Weapon Shard/Weapon, Stat Trait).
## - Stat Traits & [R] Artifacts claim immediately in 1 click.
## - Shards, Weapons, and Q/E Abilities zoom the bottom-left HUD up and display a crisp,
##   stationary Preview Card right above it while valid HUD slots pulse (normal cursor).

const CatalogScript = preload("res://scripts/data/combat_catalog.gd")

const COL_BACKDROP := Color(0.024, 0.036, 0.062, 0.72)
const COL_CARD_BG := Color(0.043, 0.063, 0.098, 0.92)
const COL_CARD_HOVER := Color(0.082, 0.118, 0.178, 0.96)
const COL_IVORY_LINE := Color(0.918, 0.894, 0.843, 0.34)
const COL_IVORY_TEXT := Color(0.961, 0.945, 0.910, 1.0)
const COL_IVORY_MUTED := Color(0.918, 0.894, 0.843, 0.68)
const COL_BTN_BG := Color(0.075, 0.106, 0.161, 0.90)
const COL_BTN_HOVER := Color(0.135, 0.192, 0.275, 0.98)

var _backdrop: ColorRect = null
var _center_container: CenterContainer = null
var _title_lbl: Label = null
var _cards_hbox: HBoxContainer = null
var _footer_btn: Button = null

# Stationary Preview Card shown above the zoomed bottom-left HUD during slot placement
var _preview_card: PanelContainer = null
var _preview_style: StyleBoxFlat = null
var _preview_cat_lbl: Label = null
var _preview_name_lbl: Label = null
var _preview_desc_lbl: Label = null
var _preview_back_btn: Button = null

var _hud_bar: Control = null
var _active_pedestal: Node3D = null
var _active_player: Node = null
var _current_cards: Array = []
var _pending_spec: Dictionary = {}
var _is_open: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_shell()
	close_draft()


func bind_hud_bar(hud: Control) -> void:
	_hud_bar = hud


func _build_shell() -> void:
	if _cards_hbox != null:
		return

	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.color = COL_BACKDROP
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)

	_center_container = CenterContainer.new()
	_center_container.name = "CenterContainer"
	_center_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_center_container.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_center_container)

	var root_vbox := VBoxContainer.new()
	root_vbox.name = "DraftVBox"
	root_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	root_vbox.add_theme_constant_override("separation", 16)
	_center_container.add_child(root_vbox)

	_title_lbl = Label.new()
	_title_lbl.name = "HeaderTitle"
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_lbl.add_theme_font_size_override("font_size", 24)
	_title_lbl.add_theme_color_override("font_color", COL_IVORY_TEXT)
	_title_lbl.add_theme_color_override("font_shadow_color", Color(0.02, 0.03, 0.06, 0.85))
	_title_lbl.add_theme_constant_override("shadow_offset_y", 2)
	root_vbox.add_child(_title_lbl)

	_cards_hbox = HBoxContainer.new()
	_cards_hbox.name = "CardsRow"
	_cards_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards_hbox.add_theme_constant_override("separation", 18)
	root_vbox.add_child(_cards_hbox)

	var footer_center := HBoxContainer.new()
	footer_center.alignment = BoxContainer.ALIGNMENT_CENTER
	root_vbox.add_child(footer_center)

	_footer_btn = _make_small_button("FooterButton", "Leave  [Esc]")
	_footer_btn.custom_minimum_size = Vector2(168.0, 34.0)
	_footer_btn.pressed.connect(close_draft)
	footer_center.add_child(_footer_btn)

	_build_stationary_preview_card()


func _build_stationary_preview_card() -> void:
	_preview_card = PanelContainer.new()
	_preview_card.name = "StationaryPreviewCard"
	# Anchored bottom-left right above the 1.86x zoomed Loadout Cluster (x = 73, top y = 530 in 1280x720)
	_preview_card.anchor_left = 0.0
	_preview_card.anchor_right = 0.0
	_preview_card.anchor_top = 1.0
	_preview_card.anchor_bottom = 1.0
	_preview_card.offset_left = 73.0
	_preview_card.offset_right = 419.0
	_preview_card.offset_top = -340.0
	_preview_card.offset_bottom = -204.0
	_preview_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_preview_card.visible = false

	_preview_style = StyleBoxFlat.new()
	_preview_style.bg_color = COL_CARD_BG
	_preview_style.border_width_left = 1
	_preview_style.border_width_right = 1
	_preview_style.border_width_bottom = 1
	_preview_style.border_width_top = 3
	_preview_style.border_color = Color(0.56, 0.92, 1.0, 0.90)
	_preview_style.corner_radius_top_left = 2
	_preview_style.corner_radius_top_right = 2
	_preview_style.corner_radius_bottom_left = 2
	_preview_style.corner_radius_bottom_right = 2
	_preview_card.add_theme_stylebox_override("panel", _preview_style)

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 16)
	m.add_theme_constant_override("margin_right", 14)
	m.add_theme_constant_override("margin_top", 12)
	m.add_theme_constant_override("margin_bottom", 12)
	_preview_card.add_child(m)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	m.add_child(vb)

	var top_row := HBoxContainer.new()
	top_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	vb.add_child(top_row)

	_preview_cat_lbl = Label.new()
	_preview_cat_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_cat_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_preview_cat_lbl.add_theme_font_size_override("font_size", 11)
	top_row.add_child(_preview_cat_lbl)

	_preview_back_btn = _make_small_button("PreviewBackButton", "← Back  [Esc]")
	_preview_back_btn.custom_minimum_size = Vector2(104.0, 24.0)
	_preview_back_btn.add_theme_font_size_override("font_size", 11)
	_preview_back_btn.pressed.connect(func() -> void:
		if _hud_bar != null and is_instance_valid(_hud_bar) and _hud_bar.has_method("cancel_pickup_placement"):
			_hud_bar.call("cancel_pickup_placement", true)
		else:
			_on_hud_placement_cancelled()
	)
	top_row.add_child(_preview_back_btn)

	_preview_name_lbl = Label.new()
	_preview_name_lbl.add_theme_font_size_override("font_size", 18)
	_preview_name_lbl.add_theme_color_override("font_color", COL_IVORY_TEXT)
	vb.add_child(_preview_name_lbl)

	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0.0, 1.0)
	sep.color = COL_IVORY_LINE
	vb.add_child(sep)

	_preview_desc_lbl = Label.new()
	_preview_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_desc_lbl.add_theme_font_size_override("font_size", 12)
	_preview_desc_lbl.add_theme_color_override("font_color", COL_IVORY_MUTED)
	vb.add_child(_preview_desc_lbl)

	add_child(_preview_card)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var ke: InputEventKey = event as InputEventKey
		if ke.keycode == KEY_ESCAPE or ke.keycode == KEY_BACKSPACE:
			close_draft()
			get_viewport().set_input_as_handled()


func open_for_pedestal(pedestal: Node3D, player_node: Node) -> void:
	if pedestal == null or player_node == null:
		return
	if _hud_bar != null and _hud_bar.has_method("cancel_pickup_placement"):
		_hud_bar.call("cancel_pickup_placement", false)

	_build_shell()
	_active_pedestal = pedestal
	_active_player = player_node
	_is_open = true

	if _active_player.has_method("set_ui_input_blocked"):
		_active_player.call("set_ui_input_blocked", true)

	_current_cards = []
	if pedestal.has_method("get_or_roll_cards"):
		_current_cards = pedestal.call("get_or_roll_cards", player_node) as Array

	_show_draft_cards_view()


func _show_draft_cards_view() -> void:
	_pending_spec = {}
	_is_open = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.visible = true
	_center_container.visible = true
	_preview_card.visible = false

	_title_lbl.text = "CHOOSE AN UPGRADE"
	_footer_btn.text = "Leave  [Esc]"

	for ch in _cards_hbox.get_children():
		ch.queue_free()

	for i in range(_current_cards.size()):
		var spec: Dictionary = _current_cards[i] as Dictionary
		_cards_hbox.add_child(_build_card(i, spec))

	visible = true


func _show_stationary_preview_for(spec: Dictionary) -> void:
	var cat: String = str(spec.get("category", "shard"))
	var item_id: int = int(spec.get("id", 1))
	var info: Dictionary = _lookup_info(cat, item_id)
	var accent: Color = info.get("color", Color(0.56, 0.92, 1.0, 1.0)) as Color

	_preview_style.border_color = Color(accent.r, accent.g, accent.b, 0.92)
	_preview_cat_lbl.text = str(info.get("subtitle", "Upgrade")).to_upper()
	_preview_cat_lbl.add_theme_color_override("font_color", accent.lightened(0.18))
	_preview_name_lbl.text = str(info.get("name", "Upgrade"))
	_preview_desc_lbl.text = str(info.get("desc", ""))

	_is_open = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.visible = false
	_center_container.visible = false
	_preview_card.visible = true
	visible = true


func _on_card_clicked(spec: Dictionary) -> void:
	var category: String = str(spec.get("category", "trait"))
	var item_id: int = int(spec.get("id", 1))

	# Stat Traits & [R] Artifacts apply immediately in 1 click!
	if category == "trait":
		_claim_and_close(func(p: Node) -> void:
			if p.has_method("apply_trait_upgrade"):
				p.call("apply_trait_upgrade", item_id)
		)
		return

	if category == "artifact":
		_claim_and_close(func(p: Node) -> void:
			if p.has_method("equip_artifact"):
				p.call("equip_artifact", item_id)
		)
		return

	# Shards, Weapons, and Q/E Abilities show the stationary Preview Card right above the
	# zoomed HUD while target slots pulse below (normal cursor)!
	_pending_spec = spec.duplicate(true)
	if _hud_bar != null and is_instance_valid(_hud_bar) and _hud_bar.has_method("begin_pickup_placement"):
		_show_stationary_preview_for(_pending_spec)
		_hud_bar.call(
			"begin_pickup_placement",
			_pending_spec,
			Callable(self, "_on_hud_placement_committed"),
			Callable(self, "_on_hud_placement_cancelled")
		)
	else:
		_on_hud_placement_committed(0, -1)


func _on_hud_placement_committed(target_slot: int, sub_socket: int) -> void:
	var category: String = str(_pending_spec.get("category", "shard"))
	var item_id: int = int(_pending_spec.get("id", 1))
	_claim_and_close(func(p: Node) -> void:
		if category == "shard":
			if sub_socket >= 0 and p.has_method("equip_shard_at_socket"):
				p.call("equip_shard_at_socket", item_id, target_slot, sub_socket)
			elif p.has_method("equip_shard"):
				p.call("equip_shard", item_id, target_slot)
		elif category == "weapon" and p.has_method("equip_weapon"):
			p.call("equip_weapon", target_slot, item_id)
		elif category == "ability" and p.has_method("equip_ability"):
			p.call("equip_ability", target_slot, item_id)
	)


func _on_hud_placement_cancelled() -> void:
	if _active_pedestal == null or not is_instance_valid(_active_pedestal) or _active_player == null or not is_instance_valid(_active_player):
		close_draft()
		return
	if _active_player.has_method("set_ui_input_blocked"):
		_active_player.call("set_ui_input_blocked", true)
	_show_draft_cards_view()


func close_draft() -> void:
	if _hud_bar != null and is_instance_valid(_hud_bar) and _hud_bar.has_method("cancel_pickup_placement"):
		_hud_bar.call("cancel_pickup_placement", false)
	_is_open = false
	_pending_spec = {}
	if _preview_card:
		_preview_card.visible = false
	visible = false
	if _active_player != null and is_instance_valid(_active_player) and _active_player.has_method("set_ui_input_blocked"):
		_active_player.call("set_ui_input_blocked", false)
	_active_pedestal = null
	_active_player = null


func _claim_and_close(action_cb: Callable) -> void:
	var p: Node = _active_player
	var ped: Node3D = _active_pedestal
	if p != null and is_instance_valid(p):
		action_cb.call(p)
	if ped != null and is_instance_valid(ped) and ped.has_method("consume_pedestal"):
		ped.call("consume_pedestal")
	close_draft()


func _build_card(card_idx: int, spec: Dictionary) -> Button:
	var category: String = str(spec.get("category", "trait"))
	var item_id: int = int(spec.get("id", 1))
	var info: Dictionary = _lookup_info(category, item_id)

	var accent_col: Color = info.get("color", Color(0.56, 0.92, 1.0, 1.0)) as Color
	var title_txt: String = str(info.get("name", "Upgrade"))
	var sub_txt: String = str(info.get("subtitle", "Trait"))
	var desc_txt: String = str(info.get("desc", ""))

	var card_btn := _make_whole_card_button("DraftCard_%d" % card_idx, Vector2(256.0, 232.0), accent_col)
	card_btn.pressed.connect(func() -> void: _on_card_clicked(spec))

	var vbox: VBoxContainer = card_btn.get_node("CardMargin/CardVBox") as VBoxContainer

	var cat_lbl := Label.new()
	cat_lbl.text = sub_txt.to_upper()
	cat_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cat_lbl.add_theme_font_size_override("font_size", 11)
	cat_lbl.add_theme_color_override("font_color", accent_col.lightened(0.15))
	vbox.add_child(cat_lbl)

	var name_lbl := Label.new()
	name_lbl.text = title_txt
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.add_theme_font_size_override("font_size", 19)
	name_lbl.add_theme_color_override("font_color", COL_IVORY_TEXT)
	vbox.add_child(name_lbl)

	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0.0, 1.0)
	sep.color = COL_IVORY_LINE
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sep)

	var desc_lbl := Label.new()
	desc_lbl.text = desc_txt
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc_lbl.add_theme_font_size_override("font_size", 13)
	desc_lbl.add_theme_color_override("font_color", COL_IVORY_MUTED)
	vbox.add_child(desc_lbl)

	return card_btn


func _make_whole_card_button(card_name: String, min_sz: Vector2, accent_col: Color) -> Button:
	var btn := Button.new()
	btn.name = card_name
	btn.text = ""
	btn.custom_minimum_size = min_sz
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var normal_sb := StyleBoxFlat.new()
	normal_sb.bg_color = COL_CARD_BG
	normal_sb.border_width_left = 1
	normal_sb.border_width_right = 1
	normal_sb.border_width_bottom = 1
	normal_sb.border_width_top = 3
	normal_sb.border_color = Color(accent_col.r, accent_col.g, accent_col.b, 0.72)
	normal_sb.corner_radius_top_left = 2
	normal_sb.corner_radius_top_right = 2
	normal_sb.corner_radius_bottom_left = 2
	normal_sb.corner_radius_bottom_right = 2

	var hover_sb := normal_sb.duplicate() as StyleBoxFlat
	hover_sb.bg_color = COL_CARD_HOVER
	hover_sb.border_color = Color(accent_col.r, accent_col.g, accent_col.b, 1.0)
	hover_sb.border_width_left = 2
	hover_sb.border_width_right = 2
	hover_sb.border_width_bottom = 2

	btn.add_theme_stylebox_override("normal", normal_sb)
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_stylebox_override("pressed", hover_sb)

	var margin := MarginContainer.new()
	margin.name = "CardMargin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	btn.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.name = "CardVBox"
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	return btn


func _lookup_info(category: String, item_id: int) -> Dictionary:
	match category:
		"weapon":
			return CatalogScript.get_weapon(item_id)
		"ability":
			return CatalogScript.get_ability(item_id)
		"artifact":
			return CatalogScript.get_artifact(item_id)
		"shard":
			return CatalogScript.get_shard(item_id)
		_:
			return CatalogScript.get_trait(item_id)


func _make_small_button(btn_name: String, label_text: String) -> Button:
	var btn := Button.new()
	btn.name = btn_name
	btn.text = label_text
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", COL_IVORY_TEXT)

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
	hover_sb.border_color = Color(0.96, 0.94, 0.90, 0.72)

	btn.add_theme_stylebox_override("normal", normal_sb)
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_stylebox_override("pressed", hover_sb)
	return btn
