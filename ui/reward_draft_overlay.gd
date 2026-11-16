class_name RewardDraftOverlay
extends Control

## Breath of the Wild × Shape of Dreams 3-Card Upgrade Draft Overlay.
## Presents 3 distinct upgrades from an interacted RewardPedestal:
## - Symmetric Weapons offer [Equip LMB] and [Equip RMB]
## - Tactical Abilities offer [Equip Q] and [Equip E]
## - Active Artifacts offer [Equip Artifact R]
## - Stat & Elemental Traits offer [Claim Trait]

const CatalogScript = preload("res://scripts/data/combat_catalog.gd")

const COL_BACKDROP := Color(0.024, 0.036, 0.062, 0.72)
const COL_CARD_BG := Color(0.043, 0.063, 0.098, 0.88)
const COL_IVORY_LINE := Color(0.918, 0.894, 0.843, 0.34)
const COL_IVORY_TEXT := Color(0.961, 0.945, 0.910, 1.0)
const COL_IVORY_MUTED := Color(0.918, 0.894, 0.843, 0.68)
const COL_BTN_BG := Color(0.075, 0.106, 0.161, 0.88)
const COL_BTN_HOVER := Color(0.135, 0.192, 0.275, 0.96)
const COL_BTN_PRESSED := Color(0.055, 0.078, 0.122, 0.95)

var _cards_hbox: HBoxContainer = null
var _active_pedestal: Node3D = null
var _active_player: Node = null
var _is_open: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_shell()
	close_draft()


func _build_shell() -> void:
	if _cards_hbox != null:
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

	var root_vbox := VBoxContainer.new()
	root_vbox.name = "DraftVBox"
	root_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	root_vbox.add_theme_constant_override("separation", 16)
	center.add_child(root_vbox)

	var header_box := VBoxContainer.new()
	header_box.alignment = BoxContainer.ALIGNMENT_CENTER
	header_box.add_theme_constant_override("separation", 4)
	root_vbox.add_child(header_box)

	var title_lbl := Label.new()
	title_lbl.text = "CHOOSE AN UPGRADE"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 24)
	title_lbl.add_theme_color_override("font_color", COL_IVORY_TEXT)
	title_lbl.add_theme_color_override("font_shadow_color", Color(0.02, 0.03, 0.06, 0.85))
	title_lbl.add_theme_constant_override("shadow_offset_y", 2)
	header_box.add_child(title_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = "Hold [Alt] anytime to zoom the HUD, reorder abilities, and move Weapon Shards between LMB & RMB"
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.add_theme_font_size_override("font_size", 13)
	sub_lbl.add_theme_color_override("font_color", COL_IVORY_MUTED)
	header_box.add_child(sub_lbl)

	_cards_hbox = HBoxContainer.new()
	_cards_hbox.name = "CardsRow"
	_cards_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards_hbox.add_theme_constant_override("separation", 18)
	root_vbox.add_child(_cards_hbox)

	var footer_center := HBoxContainer.new()
	footer_center.alignment = BoxContainer.ALIGNMENT_CENTER
	root_vbox.add_child(footer_center)

	var close_btn := _make_styled_button("CloseDraftButton", "Decide Later  [Esc]", Color(0.918, 0.894, 0.843, 0.45))
	close_btn.custom_minimum_size = Vector2(190.0, 34.0)
	close_btn.pressed.connect(close_draft)
	footer_center.add_child(close_btn)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var ke: InputEventKey = event as InputEventKey
		if ke.keycode == KEY_ESCAPE:
			close_draft()
			get_viewport().set_input_as_handled()


func open_for_pedestal(pedestal: Node3D, player_node: Node) -> void:
	if pedestal == null or player_node == null:
		return
	_build_shell()
	_active_pedestal = pedestal
	_active_player = player_node
	_is_open = true

	if _active_player.has_method("set_ui_input_blocked"):
		_active_player.call("set_ui_input_blocked", true)

	for ch in _cards_hbox.get_children():
		ch.queue_free()

	var cards: Array = []
	if pedestal.has_method("get_or_roll_cards"):
		cards = pedestal.call("get_or_roll_cards", player_node) as Array

	for i in range(cards.size()):
		var cdict: Dictionary = cards[i] as Dictionary
		var card_ctrl: Control = _build_card(i, cdict)
		_cards_hbox.add_child(card_ctrl)

	visible = true


func close_draft() -> void:
	_is_open = false
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


func _build_card(card_idx: int, spec: Dictionary) -> Control:
	var category: String = str(spec.get("category", "trait"))
	var item_id: int = int(spec.get("id", 1))
	var info: Dictionary = _lookup_info(category, item_id)

	var accent_col: Color = info.get("color", Color(0.56, 0.92, 1.0, 1.0)) as Color
	var title_txt: String = str(info.get("name", "Upgrade"))
	var sub_txt: String = str(info.get("subtitle", "Trait"))
	var desc_txt: String = str(info.get("desc", ""))

	var panel := PanelContainer.new()
	panel.name = "DraftCard_%d" % card_idx
	panel.custom_minimum_size = Vector2(268.0, 292.0)

	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_CARD_BG
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_width_top = 3
	sb.border_color = accent_col
	sb.corner_radius_top_left = 2
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2
	sb.corner_radius_bottom_right = 2
	panel.add_theme_stylebox_override("panel", sb)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var cat_lbl := Label.new()
	cat_lbl.text = sub_txt.to_upper()
	cat_lbl.add_theme_font_size_override("font_size", 11)
	cat_lbl.add_theme_color_override("font_color", accent_col.lightened(0.15))
	vbox.add_child(cat_lbl)

	var name_lbl := Label.new()
	name_lbl.text = title_txt
	name_lbl.add_theme_font_size_override("font_size", 19)
	name_lbl.add_theme_color_override("font_color", COL_IVORY_TEXT)
	vbox.add_child(name_lbl)

	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0.0, 1.0)
	sep.color = COL_IVORY_LINE
	vbox.add_child(sep)

	var desc_lbl := Label.new()
	desc_lbl.text = desc_txt
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc_lbl.add_theme_font_size_override("font_size", 13)
	desc_lbl.add_theme_color_override("font_color", COL_IVORY_MUTED)
	vbox.add_child(desc_lbl)

	if category == "weapon":
		var btn_row := HBoxContainer.new()
		btn_row.add_theme_constant_override("separation", 8)
		vbox.add_child(btn_row)

		var lmb_btn := _make_styled_button("EquipLMB_%d" % card_idx, "Equip LMB", accent_col)
		lmb_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lmb_btn.pressed.connect(func() -> void:
			_claim_and_close(func(p: Node) -> void:
				if p.has_method("equip_weapon"):
					p.call("equip_weapon", 0, item_id)
			)
		)
		btn_row.add_child(lmb_btn)

		var rmb_btn := _make_styled_button("EquipRMB_%d" % card_idx, "Equip RMB", accent_col)
		rmb_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rmb_btn.pressed.connect(func() -> void:
			_claim_and_close(func(p: Node) -> void:
				if p.has_method("equip_weapon"):
					p.call("equip_weapon", 1, item_id)
			)
		)
		btn_row.add_child(rmb_btn)

	elif category == "ability":
		var ab_row := HBoxContainer.new()
		ab_row.add_theme_constant_override("separation", 8)
		vbox.add_child(ab_row)

		var q_btn := _make_styled_button("EquipQ_%d" % card_idx, "Equip [Q]", accent_col)
		q_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		q_btn.pressed.connect(func() -> void:
			_claim_and_close(func(p: Node) -> void:
				if p.has_method("equip_ability"):
					p.call("equip_ability", 0, item_id)
			)
		)
		ab_row.add_child(q_btn)

		var e_btn := _make_styled_button("EquipE_%d" % card_idx, "Equip [E]", accent_col)
		e_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		e_btn.pressed.connect(func() -> void:
			_claim_and_close(func(p: Node) -> void:
				if p.has_method("equip_ability"):
					p.call("equip_ability", 1, item_id)
			)
		)
		ab_row.add_child(e_btn)

	elif category == "artifact":
		var art_btn := _make_styled_button("EquipR_%d" % card_idx, "Equip Artifact [R]", accent_col)
		art_btn.pressed.connect(func() -> void:
			_claim_and_close(func(p: Node) -> void:
				if p.has_method("equip_artifact"):
					p.call("equip_artifact", item_id)
			)
		)
		vbox.add_child(art_btn)

	elif category == "shard":
		var sh_row := HBoxContainer.new()
		sh_row.add_theme_constant_override("separation", 8)
		vbox.add_child(sh_row)

		var sh_lmb_btn := _make_styled_button("SlotShardLMB_%d" % card_idx, "Slot on LMB", accent_col)
		sh_lmb_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sh_lmb_btn.pressed.connect(func() -> void:
			_claim_and_close(func(p: Node) -> void:
				if p.has_method("equip_shard"):
					p.call("equip_shard", item_id, 0)
			)
		)
		sh_row.add_child(sh_lmb_btn)

		var sh_rmb_btn := _make_styled_button("SlotShardRMB_%d" % card_idx, "Slot on RMB", accent_col)
		sh_rmb_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sh_rmb_btn.pressed.connect(func() -> void:
			_claim_and_close(func(p: Node) -> void:
				if p.has_method("equip_shard"):
					p.call("equip_shard", item_id, 1)
			)
		)
		sh_row.add_child(sh_rmb_btn)

	else:
		var tr_btn := _make_styled_button("ClaimTrait_%d" % card_idx, "Claim Upgrade", accent_col)
		tr_btn.pressed.connect(func() -> void:
			_claim_and_close(func(p: Node) -> void:
				if p.has_method("apply_trait_upgrade"):
					p.call("apply_trait_upgrade", item_id)
			)
		)
		vbox.add_child(tr_btn)

	return panel


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


func _make_styled_button(btn_name: String, label_text: String, border_accent: Color) -> Button:
	var btn := Button.new()
	btn.name = btn_name
	btn.text = label_text
	btn.custom_minimum_size = Vector2(0.0, 36.0)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", COL_IVORY_TEXT)
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.98, 0.94, 1.0))

	var normal_sb := StyleBoxFlat.new()
	normal_sb.bg_color = COL_BTN_BG
	normal_sb.border_width_left = 1
	normal_sb.border_width_top = 1
	normal_sb.border_width_right = 1
	normal_sb.border_width_bottom = 1
	normal_sb.border_color = Color(border_accent.r, border_accent.g, border_accent.b, 0.55)
	normal_sb.corner_radius_top_left = 2
	normal_sb.corner_radius_top_right = 2
	normal_sb.corner_radius_bottom_left = 2
	normal_sb.corner_radius_bottom_right = 2

	var hover_sb := normal_sb.duplicate() as StyleBoxFlat
	hover_sb.bg_color = COL_BTN_HOVER
	hover_sb.border_color = Color(border_accent.r, border_accent.g, border_accent.b, 0.95)

	var pressed_sb := normal_sb.duplicate() as StyleBoxFlat
	pressed_sb.bg_color = COL_BTN_PRESSED

	btn.add_theme_stylebox_override("normal", normal_sb)
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_stylebox_override("pressed", pressed_sb)
	return btn
