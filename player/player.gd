extends CharacterBody3D

const CatalogScript = preload("res://scripts/data/combat_catalog.gd")
const StatsScript = preload("res://scripts/components/stats_component.gd")
const ZoneScript = preload("res://world/combat_zone_effect.gd")

signal player_defeated(peer_id: int)
signal dash_state_changed(
	charges: int,
	max_charges: int,
	charge_progress: float,
	inter_delay_remaining: float,
	charge_duration: float
)
signal loadout_changed()
signal item_replaced_for_drop(category: String, item_id: int, drop_origin: Vector3)

## Pre-allocated per-slot hit context passed to Projectile / CombatZoneEffect (zero per-shot allocation)
class WeaponHitContext:
	extends RefCounted
	var attack_damage: float = 10.0
	var ability_power: float = 10.0
	var poison_rank: int = 0
	var shock_rank: int = 0
	var burn_rank: int = 0
	var frost_rank: int = 0
	var dmg_mult: float = 1.0
	var cadence_mult: float = 1.0

const BASE_SPEED: float = 6.0
const ACCELERATION: float = 25.0
const DECELERATION_AFTER_DASH: float = 175.0

# Multi-charge Dash parameters (~6.2m burst, max 3 charges, 3.0s per charge, 1.0s between dashes)
const BASE_DASH_SPEED: float = 21.0
const DASH_DURATION: float = 0.24
const MAX_DASH_CHARGES: int = 3
const DASH_CHARGE_TIME: float = 3.0
const DASH_INTER_DELAY: float = 1.0
const DASH_BUFFER_WINDOW: float = 0.2
const DASH_POST_GRACE: float = 0.08

const CONTACT_INVULN_DURATION: float = 0.75
const INPUT_BUFFER_WINDOW: float = 0.16

const SHARDS_PER_WEAPON: int = 3
const RESERVE_SHARD_COUNT: int = 4

const PROJECTILE_SCENE: PackedScene = preload("res://player/projectile.tscn")
const OVERHEAD_BAR_SHADER: Shader = preload("res://shaders/OverheadBar.gdshader")
const OVERHEAD_HP_WIDTH: float = 0.78

enum HudSlot {
	WEAPON_LMB = 0,
	WEAPON_RMB = 1,
	ABILITY_Q = 2,
	ABILITY_E = 3,
	ARTIFACT_R = 4
}

@export var grass_displacement_size: float = 0.6
@export var max_health: float = 100.0

@onready var visual_root: Node3D = $VisualRoot
@onready var visual: MeshInstance3D = $VisualRoot/Visual
@onready var visor: MeshInstance3D = $VisualRoot/Visor
@onready var health_comp: HealthComponent = get_node_or_null("HealthComponent") as HealthComponent
@onready var stats_comp: Node = get_node_or_null("StatsComponent")
@onready var hp_bar_root: Node3D = get_node_or_null("HPBarRoot") as Node3D
@onready var hp_bg_mesh: MeshInstance3D = get_node_or_null("HPBarRoot/HPBg") as MeshInstance3D
@onready var hp_fill_mesh: MeshInstance3D = get_node_or_null("HPBarRoot/HPFill") as MeshInstance3D
@onready var name_tag: Label3D = $NameTag
@onready var synchronizer: MultiplayerSynchronizer = $MultiplayerSynchronizer

# Symmetric Loadout + Slottable Weapon Shards
var weapon_slots: Array[int] = [
	CatalogScript.WeaponId.PULSE_REPEATER,
	CatalogScript.WeaponId.RAIL_LANCE
]
var weapon_shards: Array = [
	[CatalogScript.ShardId.NONE, CatalogScript.ShardId.NONE, CatalogScript.ShardId.NONE],
	[CatalogScript.ShardId.NONE, CatalogScript.ShardId.NONE, CatalogScript.ShardId.NONE]
]
var reserve_shards: Array[int] = [
	CatalogScript.ShardId.NONE,
	CatalogScript.ShardId.NONE,
	CatalogScript.ShardId.NONE,
	CatalogScript.ShardId.NONE
]

var ability_slots: Array[int] = [
	CatalogScript.AbilityId.STARFALL_STRIKE,
	CatalogScript.AbilityId.SOUL_SIPHON
]
var artifact_id: int = CatalogScript.ArtifactId.NONE

var _weapon_hit_ctxs: Array = [WeaponHitContext.new(), WeaponHitContext.new()]
var _ability_hit_ctx: WeaponHitContext = WeaponHitContext.new()

var _weapon_timers: Array[float] = [0.0, 0.0]
var _weapon_max_timers: Array[float] = [0.24, 2.6]
var _weapon_buffers: Array[float] = [0.0, 0.0]

var _ability_timers: Array[float] = [0.0, 0.0]
var _ability_max_timers: Array[float] = [8.0, 10.0]
var _ability_buffers: Array[float] = [0.0, 0.0]

var _artifact_timer: float = 0.0
var _artifact_max_timer: float = 1.0
var _artifact_buffer: float = 0.0

var _temp_shield_timer: float = 0.0
var ui_input_blocked: bool = false
var _alt_inspect_active: bool = false
var _ui_unblock_grace: float = 0.0

var _move_dir: Vector3 = Vector3.ZERO
var _aim_dir: Vector3 = Vector3.FORWARD
var _aim_ground_pos: Vector3 = Vector3.ZERO
var _target_rotation_y: float = 0.0
var _dash_dir: Vector3 = Vector3.ZERO
var _dash_timer: float = 0.0
var _dash_charges: int = MAX_DASH_CHARGES
var _dash_charge_progress: float = 0.0
var _dash_inter_delay_timer: float = 0.0
var _dash_buffer_timer: float = 0.0
var _dash_grace_timer: float = 0.0
var _invuln_timer: float = 0.0
var _hit_flash_timer: float = 0.0
var _base_color: Color = Color(0.25, 0.6, 1.0)
var _body_mat: StandardMaterial3D = null
var is_dashing: bool = false
var dash_grants_invulnerability: bool = false

static var _shared_visor_mat: StandardMaterial3D = null
static var _shared_hp_quad: QuadMesh = null
static var _shared_hp_bar_mat: ShaderMaterial = null


static func _ensure_shared_visuals() -> void:
	if _shared_visor_mat != null:
		return

	_shared_visor_mat = StandardMaterial3D.new()
	_shared_visor_mat.albedo_color = Color(0.1, 0.12, 0.16)

	_shared_hp_quad = QuadMesh.new()
	_shared_hp_quad.size = Vector2(1.0, 1.0)

	_shared_hp_bar_mat = ShaderMaterial.new()
	_shared_hp_bar_mat.shader = OVERHEAD_BAR_SHADER
	_shared_hp_bar_mat.set_shader_parameter("fill_color", Color(0.941, 0.294, 0.263, 0.96))
	_shared_hp_bar_mat.set_shader_parameter("bg_color", Color(0.043, 0.063, 0.098, 0.76))
	_shared_hp_bar_mat.set_shader_parameter("border_color", Color(0.918, 0.894, 0.843, 0.36))


func _ready() -> void:
	wall_min_slide_angle = 0.0
	_ensure_shared_visuals()

	if stats_comp == null:
		stats_comp = StatsScript.new()
		stats_comp.name = "StatsComponent"
		add_child(stats_comp)
	if stats_comp.has_signal("stats_changed") and not stats_comp.is_connected("stats_changed", _on_stats_changed):
		stats_comp.connect("stats_changed", _on_stats_changed)

	_rebuild_hit_contexts()

	_body_mat = StandardMaterial3D.new()
	_body_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_body_mat.albedo_color = _base_color
	if visual:
		visual.material_override = _body_mat

	if visor:
		visor.material_override = _shared_visor_mat

	if hp_bg_mesh:
		hp_bg_mesh.visible = false

	if hp_fill_mesh:
		hp_fill_mesh.mesh = _shared_hp_quad
		hp_fill_mesh.material_override = _shared_hp_bar_mat
		hp_fill_mesh.scale = Vector3(OVERHEAD_HP_WIDTH, 0.065, 1.0)
		hp_fill_mesh.set_instance_shader_parameter("fill_ratio", 1.0)

	if health_comp:
		var init_hp: float = float(stats_comp.get("max_hp")) if stats_comp != null else max_health
		health_comp.setup_max_health(init_hp)
		if not health_comp.health_changed.is_connected(_on_health_changed):
			health_comp.health_changed.connect(_on_health_changed)
		if not health_comp.damaged.is_connected(_on_damaged):
			health_comp.damaged.connect(_on_damaged)
		if not health_comp.died.is_connected(_on_died):
			health_comp.died.connect(_on_died)


func setup(peer_id: int, info: Dictionary) -> void:
	name = str(peer_id)
	set_multiplayer_authority(peer_id)
	if synchronizer:
		synchronizer.set_multiplayer_authority(peer_id)

	var is_local: bool = is_multiplayer_authority()

	_base_color = info.get("color", Color(0.25, 0.6, 1.0)) as Color
	if _body_mat:
		_body_mat.albedo_color = _base_color

	if name_tag:
		var display_name: String = str(info.get("name", "Player %d" % peer_id))
		if is_local:
			display_name += " [YOU]"
		name_tag.text = display_name


func set_ui_input_blocked(blocked: bool) -> void:
	ui_input_blocked = blocked
	if blocked:
		_clear_action_buffers()
	else:
		_ui_unblock_grace = 0.14


func set_alt_inspect_active(active: bool) -> void:
	if _alt_inspect_active == active:
		return
	_alt_inspect_active = active
	if active:
		_weapon_buffers[0] = 0.0
		_weapon_buffers[1] = 0.0
	else:
		_ui_unblock_grace = 0.10


func _clear_action_buffers() -> void:
	_weapon_buffers[0] = 0.0
	_weapon_buffers[1] = 0.0
	_ability_buffers[0] = 0.0
	_ability_buffers[1] = 0.0
	_artifact_buffer = 0.0
	_dash_buffer_timer = 0.0


func get_health_component() -> HealthComponent:
	return health_comp


func get_stats_component() -> Node:
	return stats_comp


func get_dash_state() -> Dictionary:
	return {
		"charges": _dash_charges,
		"max_charges": MAX_DASH_CHARGES,
		"charge_progress": _dash_charge_progress,
		"inter_delay_remaining": _dash_inter_delay_timer,
		"charge_duration": DASH_CHARGE_TIME
	}


func _rebuild_hit_contexts() -> void:
	var ad_v: float = float(stats_comp.get("attack_damage")) if stats_comp != null else 10.0
	var ap_v: float = float(stats_comp.get("ability_power")) if stats_comp != null else 10.0
	var base_p: int = int(stats_comp.get("poison_rank")) if stats_comp != null else 0
	var base_s: int = int(stats_comp.get("shock_rank")) if stats_comp != null else 0
	var base_b: int = int(stats_comp.get("burn_rank")) if stats_comp != null else 0
	var base_f: int = int(stats_comp.get("frost_rank")) if stats_comp != null else 0

	var max_p: int = base_p
	var max_s: int = base_s
	var max_b: int = base_b
	var max_f: int = base_f

	for slot_i in range(2):
		var ctx: WeaponHitContext = _weapon_hit_ctxs[slot_i]
		ctx.attack_damage = ad_v
		ctx.ability_power = ap_v
		ctx.poison_rank = base_p
		ctx.shock_rank = base_s
		ctx.burn_rank = base_b
		ctx.frost_rank = base_f
		ctx.dmg_mult = 1.0
		ctx.cadence_mult = 1.0

		var sh_arr: Array = weapon_shards[slot_i] as Array
		for sid_var in sh_arr:
			var sid: int = int(sid_var)
			match sid:
				CatalogScript.ShardId.SHARD_VENOM:
					ctx.poison_rank += 1
				CatalogScript.ShardId.SHARD_STORM:
					ctx.shock_rank += 1
				CatalogScript.ShardId.SHARD_CINDER:
					ctx.burn_rank += 1
				CatalogScript.ShardId.SHARD_RIME:
					ctx.frost_rank += 1
				CatalogScript.ShardId.SHARD_KEEN:
					ctx.dmg_mult += 0.28
				CatalogScript.ShardId.SHARD_TEMPO:
					ctx.cadence_mult += 0.25

		max_p = maxi(max_p, ctx.poison_rank)
		max_s = maxi(max_s, ctx.shock_rank)
		max_b = maxi(max_b, ctx.burn_rank)
		max_f = maxi(max_f, ctx.frost_rank)

	_ability_hit_ctx.attack_damage = ad_v
	_ability_hit_ctx.ability_power = ap_v
	_ability_hit_ctx.poison_rank = max_p
	_ability_hit_ctx.shock_rank = max_s
	_ability_hit_ctx.burn_rank = max_b
	_ability_hit_ctx.frost_rank = max_f
	_ability_hit_ctx.dmg_mult = 1.0
	_ability_hit_ctx.cadence_mult = 1.0


## Swaps Left Click (Slot 0) and Right Click (Slot 1) weapons + their attached shards & live cooldowns.
func swap_weapons() -> void:
	var tmp_id: int = weapon_slots[0]
	weapon_slots[0] = weapon_slots[1]
	weapon_slots[1] = tmp_id

	var tmp_sh: Array = weapon_shards[0]
	weapon_shards[0] = weapon_shards[1]
	weapon_shards[1] = tmp_sh

	var tmp_t: float = _weapon_timers[0]
	_weapon_timers[0] = _weapon_timers[1]
	_weapon_timers[1] = tmp_t

	var tmp_max: float = _weapon_max_timers[0]
	_weapon_max_timers[0] = _weapon_max_timers[1]
	_weapon_max_timers[1] = tmp_max

	_weapon_buffers[0] = 0.0
	_weapon_buffers[1] = 0.0
	_rebuild_hit_contexts()
	loadout_changed.emit()


## Reorders / swaps Q (Slot 0) and E (Slot 1) tactical abilities + their live cooldowns.
func swap_abilities() -> void:
	var tmp_ab: int = ability_slots[0]
	ability_slots[0] = ability_slots[1]
	ability_slots[1] = tmp_ab

	var tmp_t: float = _ability_timers[0]
	_ability_timers[0] = _ability_timers[1]
	_ability_timers[1] = tmp_t

	var tmp_m: float = _ability_max_timers[0]
	_ability_max_timers[0] = _ability_max_timers[1]
	_ability_max_timers[1] = tmp_m

	_ability_buffers[0] = 0.0
	_ability_buffers[1] = 0.0
	loadout_changed.emit()


## Moves or swaps a Weapon Shard between any two sockets:
## group 0 = LMB shards (0..2), group 1 = RMB shards (0..2), group 2 = Reserve shards (0..3).
func move_or_swap_shard(from_group: int, from_idx: int, to_group: int, to_idx: int) -> void:
	if from_group == to_group and from_idx == to_idx:
		return
	var val_a: int = get_shard_at(from_group, from_idx)
	var val_b: int = get_shard_at(to_group, to_idx)
	_set_shard_at(from_group, from_idx, val_b)
	_set_shard_at(to_group, to_idx, val_a)
	_rebuild_hit_contexts()
	loadout_changed.emit()


## Slots a dragged/selected Shard directly onto target_weapon_slot (0 = LMB, 1 = RMB),
## picking the first empty socket on that weapon (or swapping with socket 0 if full).
func move_shard_to_weapon(from_group: int, from_idx: int, target_weapon_slot: int) -> void:
	var w_slot: int = clampi(target_weapon_slot, 0, 1)
	if from_group == w_slot:
		return
	var target_arr: Array = weapon_shards[w_slot] as Array
	var dest_idx: int = 0
	for i in range(target_arr.size()):
		if int(target_arr[i]) == CatalogScript.ShardId.NONE:
			dest_idx = i
			break
	move_or_swap_shard(from_group, from_idx, w_slot, dest_idx)


func get_shard_at(group: int, idx: int) -> int:
	if group == 0 or group == 1:
		var arr: Array = weapon_shards[group] as Array
		if idx >= 0 and idx < arr.size():
			return int(arr[idx])
	elif group == 2:
		if idx >= 0 and idx < reserve_shards.size():
			return reserve_shards[idx]
	return CatalogScript.ShardId.NONE


func _set_shard_at(group: int, idx: int, shard_id: int) -> void:
	if group == 0 or group == 1:
		var arr: Array = weapon_shards[group] as Array
		if idx >= 0 and idx < arr.size():
			arr[idx] = shard_id
	elif group == 2:
		if idx >= 0 and idx < reserve_shards.size():
			reserve_shards[idx] = shard_id


var _last_world_interact_frame: int = -1


func can_world_interact() -> bool:
	return not ui_input_blocked and _last_world_interact_frame != Engine.get_process_frames()


func consume_world_interact() -> void:
	_last_world_interact_frame = Engine.get_process_frames()


func equip_shard_at_socket(shard_id: int, weapon_slot: int, socket_idx: int) -> void:
	var w_slot: int = clampi(weapon_slot, 0, 1)
	var arr: Array = weapon_shards[w_slot] as Array
	var s_idx: int = clampi(socket_idx, 0, arr.size() - 1)
	if int(arr[s_idx]) == CatalogScript.ShardId.NONE:
		arr[s_idx] = shard_id
		_rebuild_hit_contexts()
		loadout_changed.emit()
		return
	for i in range(arr.size()):
		if int(arr[i]) == CatalogScript.ShardId.NONE:
			arr[i] = int(arr[s_idx])
			arr[s_idx] = shard_id
			_rebuild_hit_contexts()
			loadout_changed.emit()
			return
	var displaced_shard: int = int(arr[s_idx])
	arr[s_idx] = shard_id
	_rebuild_hit_contexts()
	loadout_changed.emit()
	if displaced_shard != CatalogScript.ShardId.NONE:
		item_replaced_for_drop.emit("shard", displaced_shard, global_position)


func equip_shard(shard_id: int, preferred_weapon_slot: int = 0) -> void:
	var pref: int = clampi(preferred_weapon_slot, 0, 1)
	var other: int = 1 - pref

	# 1. Try open socket on preferred weapon
	var pref_arr: Array = weapon_shards[pref] as Array
	for i in range(pref_arr.size()):
		if int(pref_arr[i]) == CatalogScript.ShardId.NONE:
			pref_arr[i] = shard_id
			_rebuild_hit_contexts()
			loadout_changed.emit()
			return

	# 2. Try open socket on the other weapon
	var other_arr: Array = weapon_shards[other] as Array
	for j in range(other_arr.size()):
		if int(other_arr[j]) == CatalogScript.ShardId.NONE:
			other_arr[j] = shard_id
			_rebuild_hit_contexts()
			loadout_changed.emit()
			return

	# 3. All 6 visible weapon sockets are full: replace last socket on preferred weapon and drop old shard
	var displaced_shard: int = int(pref_arr[pref_arr.size() - 1])
	pref_arr[pref_arr.size() - 1] = shard_id
	_rebuild_hit_contexts()
	loadout_changed.emit()
	if displaced_shard != CatalogScript.ShardId.NONE:
		item_replaced_for_drop.emit("shard", displaced_shard, global_position)


func equip_weapon(slot_idx: int, new_weapon_id: int) -> void:
	var idx: int = clampi(slot_idx, 0, 1)
	var other_idx: int = 1 - idx
	if weapon_slots[other_idx] == new_weapon_id:
		swap_weapons()
		return
	var old_weapon_id: int = weapon_slots[idx]
	weapon_slots[idx] = new_weapon_id
	_weapon_timers[idx] = 0.0
	var w: Dictionary = CatalogScript.get_weapon(new_weapon_id)
	_weapon_max_timers[idx] = float(w.get("cooldown", 1.0)) if bool(w.get("is_cooldown", false)) else float(w.get("interval", 0.25))
	_rebuild_hit_contexts()
	loadout_changed.emit()
	if old_weapon_id != CatalogScript.WeaponId.NONE and old_weapon_id != new_weapon_id:
		item_replaced_for_drop.emit("weapon", old_weapon_id, global_position)


func equip_ability(slot_idx: int, new_ability_id: int) -> void:
	var idx: int = clampi(slot_idx, 0, 1)
	var other_idx: int = 1 - idx
	if ability_slots[other_idx] == new_ability_id and new_ability_id != CatalogScript.AbilityId.NONE:
		swap_abilities()
		return
	var old_ability_id: int = ability_slots[idx]
	ability_slots[idx] = new_ability_id
	_ability_timers[idx] = 0.0
	var ab: Dictionary = CatalogScript.get_ability(new_ability_id)
	_ability_max_timers[idx] = maxf(0.5, float(ab.get("cooldown", 10.0)))
	loadout_changed.emit()
	if old_ability_id != CatalogScript.AbilityId.NONE and old_ability_id != new_ability_id:
		item_replaced_for_drop.emit("ability", old_ability_id, global_position)


func equip_artifact(new_artifact_id: int) -> void:
	var old_artifact_id: int = artifact_id
	artifact_id = new_artifact_id
	_artifact_timer = 0.0
	var art: Dictionary = CatalogScript.get_artifact(new_artifact_id)
	_artifact_max_timer = maxf(1.0, float(art.get("cooldown", 25.0)))
	loadout_changed.emit()
	if old_artifact_id != CatalogScript.ArtifactId.NONE and old_artifact_id != new_artifact_id:
		item_replaced_for_drop.emit("artifact", old_artifact_id, global_position)


func apply_trait_upgrade(trait_id: int) -> void:
	if stats_comp == null:
		return
	var hp_delta: float = float(stats_comp.call("apply_trait_upgrade", trait_id))
	if health_comp != null:
		var new_max: float = float(stats_comp.get("max_hp"))
		health_comp.max_health = new_max
		if hp_delta > 0.0 and not health_comp.is_dead:
			health_comp.current_health = minf(new_max, health_comp.current_health + hp_delta)
		health_comp.health_changed.emit(health_comp.current_health, health_comp.max_health)
	_rebuild_hit_contexts()
	loadout_changed.emit()


func heal_from_leech(amount: float) -> void:
	if health_comp == null or health_comp.is_dead or amount <= 0.05:
		return
	health_comp.heal(amount)


func grant_temporary_shield(amount: float, duration: float) -> void:
	if health_comp == null or health_comp.is_dead or amount <= 0.0:
		return
	health_comp.set_shield(maxf(health_comp.current_shield, amount))
	_temp_shield_timer = maxf(_temp_shield_timer, duration)


func has_active_slot_cooldowns() -> bool:
	for i in range(2):
		var w: Dictionary = CatalogScript.get_weapon(weapon_slots[i])
		if bool(w.get("is_cooldown", false)) and _weapon_timers[i] > 0.001:
			return true
		if _ability_timers[i] > 0.001:
			return true
	if _artifact_timer > 0.001:
		return true
	return false


func get_slot_recharge_progress(slot_code: int) -> float:
	match slot_code:
		HudSlot.WEAPON_LMB:
			var w0: Dictionary = CatalogScript.get_weapon(weapon_slots[0])
			if not bool(w0.get("is_cooldown", false)) or _weapon_timers[0] <= 0.001:
				return 1.0
			return clampf(1.0 - (_weapon_timers[0] / maxf(0.05, _weapon_max_timers[0])), 0.0, 1.0)
		HudSlot.WEAPON_RMB:
			var w1: Dictionary = CatalogScript.get_weapon(weapon_slots[1])
			if not bool(w1.get("is_cooldown", false)) or _weapon_timers[1] <= 0.001:
				return 1.0
			return clampf(1.0 - (_weapon_timers[1] / maxf(0.05, _weapon_max_timers[1])), 0.0, 1.0)
		HudSlot.ABILITY_Q:
			if ability_slots[0] == CatalogScript.AbilityId.NONE or _ability_timers[0] <= 0.001:
				return 1.0
			return clampf(1.0 - (_ability_timers[0] / maxf(0.05, _ability_max_timers[0])), 0.0, 1.0)
		HudSlot.ABILITY_E:
			if ability_slots[1] == CatalogScript.AbilityId.NONE or _ability_timers[1] <= 0.001:
				return 1.0
			return clampf(1.0 - (_ability_timers[1] / maxf(0.05, _ability_max_timers[1])), 0.0, 1.0)
		HudSlot.ARTIFACT_R:
			if artifact_id == CatalogScript.ArtifactId.NONE or _artifact_timer <= 0.001:
				return 1.0
			return clampf(1.0 - (_artifact_timer / maxf(0.05, _artifact_max_timer)), 0.0, 1.0)
	return 1.0


func _on_stats_changed() -> void:
	if health_comp != null and stats_comp != null:
		var target_max: float = float(stats_comp.get("max_hp"))
		if absf(health_comp.max_health - target_max) > 0.05:
			health_comp.max_health = target_max
			health_comp.current_health = minf(health_comp.current_health, target_max)
			health_comp.health_changed.emit(health_comp.current_health, health_comp.max_health)
	_rebuild_hit_contexts()
	loadout_changed.emit()


func _emit_dash_state() -> void:
	dash_state_changed.emit(
		_dash_charges,
		MAX_DASH_CHARGES,
		_dash_charge_progress,
		_dash_inter_delay_timer,
		DASH_CHARGE_TIME
	)


func reset_for_new_run() -> void:
	weapon_slots[0] = CatalogScript.WeaponId.PULSE_REPEATER
	weapon_slots[1] = CatalogScript.WeaponId.RAIL_LANCE
	weapon_shards[0] = [CatalogScript.ShardId.NONE, CatalogScript.ShardId.NONE, CatalogScript.ShardId.NONE]
	weapon_shards[1] = [CatalogScript.ShardId.NONE, CatalogScript.ShardId.NONE, CatalogScript.ShardId.NONE]
	reserve_shards = [
		CatalogScript.ShardId.NONE,
		CatalogScript.ShardId.NONE,
		CatalogScript.ShardId.NONE,
		CatalogScript.ShardId.NONE
	]
	ability_slots[0] = CatalogScript.AbilityId.STARFALL_STRIKE
	ability_slots[1] = CatalogScript.AbilityId.SOUL_SIPHON
	artifact_id = CatalogScript.ArtifactId.NONE
	if stats_comp and stats_comp.has_method("reset_for_new_run"):
		stats_comp.call("reset_for_new_run")
	if health_comp and stats_comp:
		health_comp.max_health = float(stats_comp.get("max_hp"))
	_rebuild_hit_contexts()
	restore_full_health()
	loadout_changed.emit()


func restore_full_health() -> void:
	_invuln_timer = 0.0
	_hit_flash_timer = 0.0
	_temp_shield_timer = 0.0
	is_dashing = false
	ui_input_blocked = false
	_alt_inspect_active = false
	velocity = Vector3.ZERO
	visible = true
	_dash_charges = MAX_DASH_CHARGES
	_dash_charge_progress = 0.0
	_dash_inter_delay_timer = 0.0
	_weapon_timers[0] = 0.0
	_weapon_timers[1] = 0.0
	_ability_timers[0] = 0.0
	_ability_timers[1] = 0.0
	_artifact_timer = 0.0
	if stats_comp and stats_comp.has_method("clear_temporary_buffs"):
		stats_comp.call("clear_temporary_buffs")
	if _body_mat:
		_body_mat.albedo_color = _base_color
	if hp_fill_mesh:
		hp_fill_mesh.set_instance_shader_parameter("fill_ratio", 1.0)
	if health_comp:
		if stats_comp:
			health_comp.max_health = float(stats_comp.get("max_hp"))
		health_comp.reset_health()
	_rebuild_hit_contexts()
	_emit_dash_state()
	loadout_changed.emit()


func try_apply_contact_damage(amount: float, hit_dir: Vector3 = Vector3.ZERO) -> bool:
	if amount <= 0.0:
		return false
	if _invuln_timer > 0.0:
		return false
	if dash_grants_invulnerability and (is_dashing or _dash_grace_timer > 0.0):
		return false
	if health_comp == null or health_comp.is_dead:
		return false

	_invuln_timer = CONTACT_INVULN_DURATION
	if multiplayer.has_multiplayer_peer():
		_rpc_receive_contact_damage.rpc(amount, hit_dir)
	else:
		_rpc_receive_contact_damage(amount, hit_dir)
	return true


@rpc("any_peer", "call_local", "reliable")
func _rpc_receive_contact_damage(amount: float, hit_dir: Vector3) -> void:
	_invuln_timer = CONTACT_INVULN_DURATION
	if health_comp and not health_comp.is_dead:
		health_comp.take_damage(amount, hit_dir)


func _on_health_changed(current_hp: float, p_max_hp: float) -> void:
	if hp_fill_mesh:
		var ratio: float = clampf(current_hp / maxf(1.0, p_max_hp), 0.0, 1.0)
		hp_fill_mesh.set_instance_shader_parameter("fill_ratio", ratio)


func _on_damaged(_amount: float, _hit_dir: Vector3) -> void:
	_hit_flash_timer = 0.14
	if _body_mat:
		_body_mat.albedo_color = Color(1.0, 0.36, 0.42, 1.0)
	if visual_root:
		visual_root.scale = Vector3(1.16, 0.84, 1.16)


func _on_died() -> void:
	is_dashing = false
	velocity = Vector3.ZERO
	visible = false
	var my_peer: int = int(name) if name.is_valid_int() else get_multiplayer_authority()
	player_defeated.emit(my_peer)


func _process(delta: float) -> void:
	if health_comp and health_comp.is_dead:
		return
	if _hit_flash_timer > 0.0:
		_hit_flash_timer = maxf(0.0, _hit_flash_timer - delta)
		if _hit_flash_timer <= 0.0 and _body_mat:
			_body_mat.albedo_color = _base_color.lightened(0.38) if (is_dashing and dash_grants_invulnerability) else _base_color
	elif _body_mat:
		if is_dashing and dash_grants_invulnerability:
			_body_mat.albedo_color = _base_color.lightened(0.38)
		else:
			_body_mat.albedo_color = _base_color

	if visual_root and is_multiplayer_authority():
		var allow_aim: bool = (not ui_input_blocked) and (not _alt_inspect_active) and (
			DisplayServer.window_is_focused() or (DebugTools == null or DebugTools.active_instance_count <= 1)
		)
		var cam: Camera3D = get_viewport().get_camera_3d()
		if cam and allow_aim:
			var mouse_pos: Vector2 = get_viewport().get_mouse_position()
			var ray_origin: Vector3 = cam.project_ray_origin(mouse_pos)
			var ray_normal: Vector3 = cam.project_ray_normal(mouse_pos)
			var ground_plane := Plane(Vector3.UP, global_position.y)
			var hit_pos: Variant = ground_plane.intersects_ray(ray_origin, ray_normal)
			if hit_pos != null:
				_aim_ground_pos = hit_pos as Vector3
				var look_vec: Vector3 = _aim_ground_pos - global_position
				look_vec.y = 0.0
				if look_vec.length_squared() > 0.04:
					_aim_dir = look_vec.normalized()
		else:
			_aim_ground_pos = global_position + _aim_dir * 5.0

		if _aim_dir.length() > 0.1:
			_target_rotation_y = atan2(_aim_dir.x, _aim_dir.z)
			visual_root.rotation.y = lerp_angle(visual_root.rotation.y, _target_rotation_y, 25.0 * delta)

	if visual_root:
		visual_root.scale = visual_root.scale.lerp(Vector3.ONE, 12.0 * delta)


func _physics_process(delta: float) -> void:
	if health_comp and health_comp.is_dead:
		return
	if _invuln_timer > 0.0:
		_invuln_timer = maxf(0.0, _invuln_timer - delta)
	if _dash_grace_timer > 0.0:
		_dash_grace_timer = maxf(0.0, _dash_grace_timer - delta)
	if _ui_unblock_grace > 0.0:
		_ui_unblock_grace = maxf(0.0, _ui_unblock_grace - delta)

	if _temp_shield_timer > 0.0:
		_temp_shield_timer = maxf(0.0, _temp_shield_timer - delta)
		if _temp_shield_timer <= 0.0 and health_comp and health_comp.current_shield > 0.0:
			health_comp.set_shield(0.0)

	if not is_multiplayer_authority():
		return

	var dash_notify: bool = false
	var cd_finished: bool = false

	if _dash_inter_delay_timer > 0.0:
		_dash_inter_delay_timer = maxf(0.0, _dash_inter_delay_timer - delta)
		if _dash_inter_delay_timer <= 0.0:
			dash_notify = true

	if _dash_charges < MAX_DASH_CHARGES:
		_dash_charge_progress += delta / DASH_CHARGE_TIME
		while _dash_charge_progress >= 1.0 and _dash_charges < MAX_DASH_CHARGES:
			_dash_charge_progress -= 1.0
			_dash_charges += 1
			dash_notify = true
		if _dash_charges >= MAX_DASH_CHARGES:
			_dash_charge_progress = 0.0

	if _dash_buffer_timer > 0.0:
		_dash_buffer_timer = maxf(0.0, _dash_buffer_timer - delta)

	for i in range(2):
		if _weapon_timers[i] > 0.0:
			_weapon_timers[i] = maxf(0.0, _weapon_timers[i] - delta)
			if _weapon_timers[i] <= 0.0:
				cd_finished = true
		if _weapon_buffers[i] > 0.0:
			_weapon_buffers[i] = maxf(0.0, _weapon_buffers[i] - delta)

		if _ability_timers[i] > 0.0:
			_ability_timers[i] = maxf(0.0, _ability_timers[i] - delta)
			if _ability_timers[i] <= 0.0:
				cd_finished = true
		if _ability_buffers[i] > 0.0:
			_ability_buffers[i] = maxf(0.0, _ability_buffers[i] - delta)

	if _artifact_timer > 0.0:
		_artifact_timer = maxf(0.0, _artifact_timer - delta)
		if _artifact_timer <= 0.0:
			cd_finished = true
	if _artifact_buffer > 0.0:
		_artifact_buffer = maxf(0.0, _artifact_buffer - delta)

	var focused: bool = DisplayServer.window_is_focused() or (DebugTools == null or DebugTools.active_instance_count <= 1)
	var alt_held_now: bool = _alt_inspect_active or Input.is_action_pressed("inspect_loadout") or Input.is_key_pressed(KEY_ALT) or Input.is_physical_key_pressed(KEY_ALT)
	if alt_held_now:
		_weapon_buffers[0] = 0.0
		_weapon_buffers[1] = 0.0
	var allow_keys: bool = (not ui_input_blocked) and focused
	var allow_mouse_weapons: bool = allow_keys and (not alt_held_now) and (_ui_unblock_grace <= 0.0)

	if allow_keys:
		if Input.is_action_just_pressed("swap_weapons"):
			swap_weapons()

		if Input.is_action_just_pressed("dash"):
			_dash_buffer_timer = DASH_BUFFER_WINDOW

		if not alt_held_now:
			if Input.is_action_just_pressed("ability_q"):
				_ability_buffers[0] = INPUT_BUFFER_WINDOW

			if Input.is_action_just_pressed("ability_e"):
				_ability_buffers[1] = INPUT_BUFFER_WINDOW

			if Input.is_action_just_pressed("artifact_r"):
				_artifact_buffer = INPUT_BUFFER_WINDOW

	if allow_mouse_weapons:
		if Input.is_action_just_pressed("attack") or Input.is_action_pressed("attack"):
			_weapon_buffers[0] = INPUT_BUFFER_WINDOW

		if Input.is_action_just_pressed("secondary_attack") or Input.is_action_pressed("secondary_attack"):
			_weapon_buffers[1] = INPUT_BUFFER_WINDOW

	var input_dir: Vector2 = Vector2.ZERO
	if not ui_input_blocked:
		input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")

	var cam: Camera3D = get_viewport().get_camera_3d()
	_move_dir = Vector3.ZERO
	if cam:
		var cam_right: Vector3 = cam.global_basis.x
		var cam_forward: Vector3 = -cam.global_basis.z
		var ground_right: Vector3 = Vector3(cam_right.x, 0.0, cam_right.z).normalized()
		var ground_forward: Vector3 = Vector3(cam_forward.x, 0.0, cam_forward.z).normalized()
		_move_dir = ground_right * input_dir.x - ground_forward * input_dir.y
	else:
		_move_dir = Vector3(input_dir.x, 0.0, input_dir.y)

	if _move_dir.length() > 1.0:
		_move_dir = _move_dir.normalized()

	var cur_move_speed: float = float(stats_comp.get("move_speed")) if stats_comp != null else BASE_SPEED
	var cur_dash_speed: float = BASE_DASH_SPEED * (cur_move_speed / BASE_SPEED)

	if _dash_buffer_timer > 0.0 and _dash_charges > 0 and _dash_inter_delay_timer <= 0.0 and not is_dashing:
		_dash_buffer_timer = 0.0
		_dash_charges -= 1
		_dash_inter_delay_timer = DASH_INTER_DELAY
		_dash_timer = DASH_DURATION
		_dash_grace_timer = DASH_POST_GRACE
		is_dashing = true

		if _move_dir.length() > 0.1:
			_dash_dir = _move_dir
		else:
			_dash_dir = _aim_dir

		_play_dash_effects.rpc(_dash_dir)
		dash_notify = true

	if dash_notify:
		_emit_dash_state()

	if is_dashing:
		_dash_timer -= delta
		_dash_grace_timer = DASH_POST_GRACE
		if _dash_timer <= 0.0:
			is_dashing = false
		velocity.x = _dash_dir.x * cur_dash_speed
		velocity.z = _dash_dir.z * cur_dash_speed
	else:
		var target_vel: Vector3 = _move_dir * cur_move_speed
		var accel: float = DECELERATION_AFTER_DASH if velocity.length() > cur_move_speed else ACCELERATION
		velocity.x = move_toward(velocity.x, target_vel.x, accel * delta)
		velocity.z = move_toward(velocity.z, target_vel.z, accel * delta)

	velocity.y = 0.0
	move_and_slide()

	if not is_dashing:
		for slot_i in range(2):
			if _weapon_buffers[slot_i] > 0.0 and _weapon_timers[slot_i] <= 0.0:
				_weapon_buffers[slot_i] = 0.0
				_fire_weapon_slot(slot_i)

		for ab_i in range(2):
			if _ability_buffers[ab_i] > 0.0 and _ability_timers[ab_i] <= 0.0 and ability_slots[ab_i] != CatalogScript.AbilityId.NONE:
				_ability_buffers[ab_i] = 0.0
				_cast_ability_slot(ab_i)

		if _artifact_buffer > 0.0 and _artifact_timer <= 0.0 and artifact_id != CatalogScript.ArtifactId.NONE:
			_artifact_buffer = 0.0
			_cast_artifact()

	if cd_finished:
		loadout_changed.emit()


func _get_clamped_aim_point(max_dist: float) -> Vector3:
	var offset: Vector3 = _aim_ground_pos - global_position
	offset.y = 0.0
	var d: float = offset.length()
	if d < 0.1:
		return global_position + _aim_dir * minf(4.5, max_dist)
	if d > max_dist:
		offset = (offset / d) * max_dist
	return Vector3(global_position.x + offset.x, 0.0, global_position.z + offset.z)


func _fire_weapon_slot(slot_idx: int) -> void:
	var wid: int = weapon_slots[slot_idx]
	var w: Dictionary = CatalogScript.get_weapon(wid)
	if w.is_empty():
		return

	var ctx: WeaponHitContext = _weapon_hit_ctxs[slot_idx]
	var is_cd: bool = bool(w.get("is_cooldown", false))
	var duration: float = 0.25
	if is_cd:
		var base_cd: float = float(w.get("cooldown", 2.5)) / maxf(0.5, ctx.cadence_mult)
		duration = float(stats_comp.call("compute_cooldown", base_cd)) if stats_comp != null else base_cd
	else:
		var base_int: float = float(w.get("interval", 0.24))
		var atk_spd: float = (float(stats_comp.get("attack_speed")) if stats_comp != null else 1.0) * ctx.cadence_mult
		duration = base_int / maxf(0.25, atk_spd)

	_weapon_timers[slot_idx] = duration
	_weapon_max_timers[slot_idx] = duration

	var ad_r: float = float(w.get("ad_ratio", 1.0))
	var ap_r: float = float(w.get("ap_ratio", 0.0))
	var raw_scaled: float = float(stats_comp.call("compute_scaled_damage", ad_r, ap_r, 0.0)) if stats_comp != null else (10.0 * ad_r + 10.0 * ap_r)
	var hit_dmg: float = raw_scaled * ctx.dmg_mult
	var proc_c: float = float(w.get("proc_coeff", 1.0))
	var spd: float = float(w.get("speed", 24.0))
	var rng: float = float(w.get("range", 12.5))
	var tint: Color = w.get("color", Color(1.0, 0.88, 0.42)) as Color
	var muzzle_pos: Vector3 = global_position + Vector3(0.0, 0.35, 0.0) + _aim_dir * 0.25
	var auth_id: int = get_multiplayer_authority()

	match wid:
		CatalogScript.WeaponId.PULSE_REPEATER:
			_rpc_spawn_combat_proj.rpc(auth_id, muzzle_pos, _aim_dir, spd, rng, hit_dmg, proc_c, 0, tint, slot_idx)

		CatalogScript.WeaponId.SCATTER_PRISM:
			var pellets: int = int(w.get("pellets", 5))
			var half_rad: float = deg_to_rad(float(w.get("spread_deg", 24.0)) * 0.5)
			for p in range(pellets):
				var frac: float = (float(p) / float(maxi(1, pellets - 1))) * 2.0 - 1.0 if pellets > 1 else 0.0
				var p_dir: Vector3 = _aim_dir.rotated(Vector3.UP, frac * half_rad)
				_rpc_spawn_combat_proj.rpc(auth_id, muzzle_pos, p_dir, spd, rng, hit_dmg, proc_c, 0, tint, slot_idx)
			if visual_root:
				visual_root.scale = Vector3(1.08, 0.94, 0.92)

		CatalogScript.WeaponId.ARCANE_CHAKRAM:
			_rpc_spawn_combat_proj.rpc(auth_id, muzzle_pos, _aim_dir, spd, rng, hit_dmg, proc_c, 2, tint, slot_idx)

		CatalogScript.WeaponId.RAIL_LANCE:
			_rpc_spawn_combat_proj.rpc(auth_id, muzzle_pos, _aim_dir, spd, rng, hit_dmg, proc_c, 1, tint, slot_idx)
			if visual_root:
				visual_root.scale = Vector3(0.88, 1.05, 1.16)

		CatalogScript.WeaponId.NOVA_MORTAR:
			var target_pt: Vector3 = _get_clamped_aim_point(rng)
			var rad: float = float(w.get("aoe_radius", 2.8))
			_rpc_spawn_zone.rpc(ZoneScript.ZoneMode.DELAYED_BLAST, target_pt, rad, hit_dmg, 0.50, "mortar", tint, 0.0, false, 0.0, slot_idx)

		CatalogScript.WeaponId.CHAIN_LASH:
			_rpc_spawn_zone.rpc(ZoneScript.ZoneMode.WHIP_ARC, global_position, rng, hit_dmg, 0.20, "whip", tint, 0.0, true, 0.0, slot_idx, _aim_dir)
			if visual_root:
				visual_root.scale = Vector3(1.14, 0.92, 0.94)

		CatalogScript.WeaponId.SWARM_PODS:
			var pod_count: int = int(w.get("pellets", 3))
			var pod_half: float = deg_to_rad(float(w.get("spread_deg", 56.0)) * 0.5)
			for p_i in range(pod_count):
				var frac_p: float = (float(p_i) / float(maxi(1, pod_count - 1))) * 2.0 - 1.0 if pod_count > 1 else 0.0
				var m_dir: Vector3 = _aim_dir.rotated(Vector3.UP, frac_p * pod_half)
				_rpc_spawn_combat_proj.rpc(auth_id, muzzle_pos, m_dir, spd, rng, hit_dmg, proc_c, 4, tint, slot_idx)

		CatalogScript.WeaponId.SIEGE_CANNON:
			_rpc_spawn_combat_proj.rpc(auth_id, muzzle_pos, _aim_dir, spd, rng, hit_dmg, proc_c, 5, tint, slot_idx)
			if visual_root:
				visual_root.scale = Vector3(0.84, 1.08, 1.22)

		CatalogScript.WeaponId.METEOR_FLAIL:
			var tip_pt: Vector3 = _get_clamped_aim_point(rng)
			var line_dist: float = maxf(2.0, Vector2(tip_pt.x - global_position.x, tip_pt.z - global_position.z).length())
			var line_dmg: float = hit_dmg * 0.52
			_rpc_spawn_combat_proj.rpc(auth_id, muzzle_pos, _aim_dir, spd, line_dist, line_dmg, 0.75, 1, tint, slot_idx)
			var slam_rad: float = float(w.get("aoe_radius", 2.3))
			_rpc_spawn_zone.rpc(ZoneScript.ZoneMode.DELAYED_BLAST, tip_pt, slam_rad, hit_dmg, 0.36, "flail", tint, 0.0, false, 0.0, slot_idx)
			if visual_root:
				visual_root.scale = Vector3(0.90, 1.06, 1.14)

		CatalogScript.WeaponId.CLUSTER_SEEKER:
			_rpc_spawn_combat_proj.rpc(auth_id, muzzle_pos, _aim_dir, spd, rng, hit_dmg, proc_c, 6, tint, slot_idx)

		CatalogScript.WeaponId.GAUSS_SNIPER:
			_rpc_spawn_combat_proj.rpc(auth_id, muzzle_pos, _aim_dir, spd, rng, hit_dmg, proc_c, 7, tint, slot_idx)
			if visual_root:
				visual_root.scale = Vector3(0.86, 1.04, 1.18)

	if is_cd:
		loadout_changed.emit()


func _cast_ability_slot(slot_idx: int) -> void:
	var ab_id: int = ability_slots[slot_idx]
	var ab: Dictionary = CatalogScript.get_ability(ab_id)
	if ab.is_empty():
		return

	var base_cd: float = float(ab.get("cooldown", 10.0))
	var cd: float = float(stats_comp.call("compute_cooldown", base_cd)) if stats_comp != null else base_cd
	_ability_timers[slot_idx] = cd
	_ability_max_timers[slot_idx] = cd

	var ap_val: float = float(stats_comp.get("ability_power")) if stats_comp != null else 10.0
	var col: Color = ab.get("color", Color.WHITE) as Color

	match ab_id:
		CatalogScript.AbilityId.AEGIS_BARRIER:
			grant_temporary_shield(25.0 + 2.0 * ap_val, 6.0)
			_rpc_spawn_zone.rpc(ZoneScript.ZoneMode.SELF_WARD, global_position, 2.2, 0.0, 0.45, "aegis", col, 0.0, true, 0.0, -1)

		CatalogScript.AbilityId.STARFALL_STRIKE:
			var pt: Vector3 = _get_clamped_aim_point(13.5)
			var dmg: float = 30.0 + 2.5 * ap_val
			_rpc_spawn_zone.rpc(ZoneScript.ZoneMode.DELAYED_BLAST, pt, 3.0, dmg, 0.51, "starfall", col, 0.0, false, 0.0, -1)

		CatalogScript.AbilityId.FROST_NOVA:
			var pt_f: Vector3 = _get_clamped_aim_point(12.0)
			var dmg_f: float = 18.0 + 1.5 * ap_val
			_rpc_spawn_zone.rpc(ZoneScript.ZoneMode.STASIS_FIELD, pt_f, 3.8, dmg_f, 3.5, "frost_nova", col, 0.55, false, 0.0, -1)

		CatalogScript.AbilityId.TEMPO_SURGE:
			if stats_comp and stats_comp.has_method("apply_temporary_overdrive"):
				stats_comp.call("apply_temporary_overdrive", 0.45, 0.25, 4.5)
			_rpc_spawn_zone.rpc(ZoneScript.ZoneMode.SELF_WARD, global_position, 2.4, 0.0, 0.45, "surge", col, 0.0, true, 0.0, -1)

		CatalogScript.AbilityId.SOUL_SIPHON:
			var pt_s: Vector3 = _get_clamped_aim_point(12.5)
			var dmg_s: float = 24.0 + 2.0 * ap_val
			_rpc_spawn_zone.rpc(ZoneScript.ZoneMode.DELAYED_BLAST, pt_s, 3.6, dmg_s, 0.44, "siphon", col, 0.0, false, 0.35, -1)

	loadout_changed.emit()


func _cast_artifact() -> void:
	var art: Dictionary = CatalogScript.get_artifact(artifact_id)
	if art.is_empty():
		return

	var base_cd: float = float(art.get("cooldown", 25.0))
	var cd: float = float(stats_comp.call("compute_cooldown", base_cd)) if stats_comp != null else base_cd
	_artifact_timer = cd
	_artifact_max_timer = cd

	var ad_val: float = float(stats_comp.get("attack_damage")) if stats_comp != null else 10.0
	var ap_val: float = float(stats_comp.get("ability_power")) if stats_comp != null else 10.0
	var col: Color = art.get("color", Color.WHITE) as Color

	match artifact_id:
		CatalogScript.ArtifactId.SOLAR_CONVERGENCE:
			var pt: Vector3 = _get_clamped_aim_point(14.0)
			var pulse_dmg: float = 45.0 + 3.5 * ap_val
			_rpc_spawn_zone.rpc(ZoneScript.ZoneMode.SOLAR_PILLAR, pt, 3.8, pulse_dmg, 1.55, "solar", col, 0.0, false, 0.0, -1)

		CatalogScript.ArtifactId.CHRONOSPHERE:
			grant_temporary_shield(40.0 + 1.5 * ap_val, 6.0)
			var init_dmg: float = 15.0 + 1.0 * ap_val
			_rpc_spawn_zone.rpc(ZoneScript.ZoneMode.STASIS_FIELD, global_position, 7.5, init_dmg, 5.0, "chrono", col, 0.80, false, 0.0, -1)

		CatalogScript.ArtifactId.SEEKER_BARRAGE:
			var missile_dmg: float = 14.0 + 0.8 * ad_val + 0.8 * ap_val
			var auth_id: int = get_multiplayer_authority()
			var center_launch: Vector3 = global_position + Vector3(0.0, 0.42, 0.0)
			for m in range(10):
				var ang: float = float(m) * (TAU / 10.0)
				var m_dir := Vector3(cos(ang), 0.0, sin(ang))
				_rpc_spawn_combat_proj.rpc(
					auth_id,
					center_launch + m_dir * 0.30,
					m_dir,
					20.5,
					18.0,
					missile_dmg,
					0.50,
					3,
					col,
					-1
				)

		CatalogScript.ArtifactId.SANGUINE_HARVEST:
			var pt_h: Vector3 = _get_clamped_aim_point(13.5)
			var pulse_h: float = 32.0 + 2.5 * ap_val
			_rpc_spawn_zone.rpc(ZoneScript.ZoneMode.SOLAR_PILLAR, pt_h, 4.0, pulse_h, 1.55, "harvest", col, 0.0, false, 0.25, -1)

	loadout_changed.emit()


@rpc("call_local", "reliable")
func _rpc_spawn_combat_proj(
	p_shooter_id: int,
	p_pos: Vector3,
	p_dir: Vector3,
	p_speed: float,
	p_range: float,
	p_dmg: float,
	p_proc: float,
	p_mode: int,
	p_tint: Color,
	p_slot_idx: int = -1
) -> void:
	var ctx_obj: Object = _ability_hit_ctx
	if p_slot_idx == 0 or p_slot_idx == 1:
		ctx_obj = _weapon_hit_ctxs[p_slot_idx]
	if ProjectilePool and ProjectilePool.has_method("spawn_combat_projectile"):
		ProjectilePool.call(
			"spawn_combat_projectile",
			p_shooter_id,
			p_pos,
			p_dir,
			p_speed,
			p_range,
			p_dmg,
			p_proc,
			p_mode,
			p_tint,
			self,
			ctx_obj
		)
	elif ProjectilePool:
		ProjectilePool.spawn(p_shooter_id, p_pos, p_dir, p_speed)
	else:
		var proj: Area3D = PROJECTILE_SCENE.instantiate() as Area3D
		get_parent().add_child(proj)
		proj.call("setup", p_shooter_id, p_pos, p_dir, p_speed)


@rpc("call_local", "reliable")
func _rpc_spawn_zone(
	p_mode: int,
	p_pos: Vector3,
	p_radius: float,
	p_dmg: float,
	p_duration: float,
	p_key: String,
	p_col: Color,
	p_slow: float,
	p_follow_self: bool,
	p_leech: float = 0.0,
	p_slot_idx: int = -1,
	p_aim_dir: Vector3 = Vector3.FORWARD
) -> void:
	var ctx_obj: Object = _ability_hit_ctx
	if p_slot_idx == 0 or p_slot_idx == 1:
		ctx_obj = _weapon_hit_ctxs[p_slot_idx]
	if ProjectilePool and ProjectilePool.has_method("spawn_zone_effect"):
		ProjectilePool.call(
			"spawn_zone_effect",
			p_mode,
			p_pos,
			p_radius,
			p_dmg,
			p_duration,
			p_key,
			p_col,
			ctx_obj,
			p_slow,
			self if p_follow_self else null,
			p_leech,
			self,
			p_aim_dir
		)


@rpc("call_local", "reliable")
func _play_dash_effects(p_dash_dir: Vector3) -> void:
	if visual_root and p_dash_dir.length_squared() > 0.001:
		var model_forward: Vector3 = visual_root.global_transform.basis.z.normalized()
		var norm_dash: Vector3 = p_dash_dir.normalized()
		var dot_forward: float = clampf(model_forward.dot(norm_dash), -1.0, 1.0)
		var abs_cos: float = absf(dot_forward)
		var abs_sin: float = sqrt(maxf(0.0, 1.0 - abs_cos * abs_cos))

		var scale_z: float = lerpf(0.72, 1.45, abs_cos)
		var scale_x: float = lerpf(0.72, 1.45, abs_sin)
		visual_root.scale = Vector3(scale_x, 0.78, scale_z)
	elif visual_root:
		visual_root.scale = Vector3(0.72, 0.78, 1.45)
