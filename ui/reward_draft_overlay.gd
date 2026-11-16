class_name RewardDraftOverlay
extends Control

## Upgrade Pedestal Pickup UI (Breath of the Wild × Shape of Dreams).
## - Shows 3 uncluttered cards (Ability/Artifact, Weapon Shard/Weapon, Stat Trait).
## - Stat Traits & [R] Artifacts apply immediately in 1 click.
## - Weapon Shards, Weapons, and Q/E Abilities dismiss the modal and zoom the actual
##   bottom-left HUD up so you click directly onto the target HUD socket to place it!

const CatalogScript = preload("res://scripts/data/combat_catalog.gd")

const COL_BACKDROP := Color(0.024, 0.036, 0.062, 0.72)
const COL_CARD_BG := Color(0.043, 0.063, 0.098, 0.90)
const COL_CARD_HOVER := Color(0.082, 0.118, 0.178, 0.96)
const COL_IVORY_LINE := Color(0.918, 0.894, 0.843, 0.34)
const COL_IVORY_TEXT := Color(0.961, 0.945, 0.910, 1.0)
const COL_IVORY_MUTED := Color(0.918, 0.894, 0.843, 0.68)
const COL_BTN_BG := Color(0.075, 0.106, 0.161, 0.88)
const COL_BTN_HOVER := Color(0.135, 0.192, 0.275, 0.96)

var _title_lbl: Label = null
var _cards_hbox: HBoxContainer = null
var _footer_btn: Button = null

var _hud_bar: Control = null
var _active_pedestal: Node3D = null
var _active_player: Node = null
var _current_cards: Array = []
var _pending_spec: Dictionary = {}
var _is_open: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_shell()
	close_draft()


func bind_hud_bar(hud: Control) -> void:
	_hud_bar = hud


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

	_render_cards()
	visible = true


func _render_cards() -> void:
	_pending_spec = {}
	_title_lbl.text = "CHOOSE AN UPGRADE"
	_footer_btn.text = "Leave  [Esc]"

	for ch in _cards_hbox.get_children():
		ch.queue_free()

	for i in range(_current_cards.size()):
		var spec: Dictionary = _current_cards[i] as Dictionary
		_cards_hbox.add_child(_build_card(i, spec))


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

	# Shards, Weapons, and Q/E Abilities zoom the bottom-left HUD up so you click
	# directly on the HUD slot to place it (Shape of Dreams style)!
	_pending_spec = spec.duplicate(true)
	if _hud_bar != null and is_instance_valid(_hud_bar) and _hud_bar.has_method("begin_pickup_placement"):
		_is_open = false
		visible = false
		_hud_bar.call(
			"begin_pickup_placement",
			_pending_spec,
			Callable(self, "_on_hud_placement_committed"),
			Callable(self, "_on_hud_placement_cancelled")
		)
	else:
		# Fallback if HUD bar isn't bound
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
	_is_open = true
	if _active_player.has_method("set_ui_input_blocked"):
		_active_player.call("set_ui_input_blocked", true)
	_render_cards()
	visible = true


func close_draft() -> void:
	if _hud_bar != null and is_instance_valid(_hud_bar) and _hud_bar.has_method("cancel_pickup_placement"):
		_hud_bar.call("cancel_pickup_placement", false)
	_is_open = false
	_pending_spec = {}
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
