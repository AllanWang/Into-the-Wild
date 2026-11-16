class_name StatsComponent
extends Node

## Manages player stats (Max HP, AD, AP, Attack Speed, Ability Haste, Move Speed),
## temporary timed buffs, and stackable Elemental On-Hit Trait ranks (Poison, Shock, Burn, Frost).

const CatalogScript = preload("res://scripts/data/combat_catalog.gd")

signal stats_changed()

const BASE_MAX_HP: float = 100.0
const BASE_AD: float = 10.0
const BASE_AP: float = 10.0
const BASE_ATK_SPEED: float = 1.0
const BASE_ABILITY_HASTE: float = 0.0
const BASE_MOVE_SPEED: float = 6.0

# Permanent additive bonuses accumulated during a run
var bonus_max_hp: float = 0.0
var bonus_ad: float = 0.0
var bonus_ap: float = 0.0
var bonus_atk_speed_pct: float = 0.0
var bonus_ability_haste: float = 0.0
var bonus_move_speed_pct: float = 0.0

# Elemental trait ranks (0 = unlearned, 1+ = active & scaling)
var poison_rank: int = 0
var shock_rank: int = 0
var burn_rank: int = 0
var frost_rank: int = 0

# Active temporary buff (e.g. Tempo Surge)
var _temp_atk_speed_pct: float = 0.0
var _temp_move_speed_pct: float = 0.0
var _temp_buff_timer: float = 0.0

# Cached effective stats (zero allocation reads during combat)
var max_hp: float = BASE_MAX_HP
var attack_damage: float = BASE_AD
var ability_power: float = BASE_AP
var attack_speed: float = BASE_ATK_SPEED
var ability_haste: float = BASE_ABILITY_HASTE
var move_speed: float = BASE_MOVE_SPEED


func _ready() -> void:
	set_process(false)
	_recalculate()


func reset_for_new_run() -> void:
	bonus_max_hp = 0.0
	bonus_ad = 0.0
	bonus_ap = 0.0
	bonus_atk_speed_pct = 0.0
	bonus_ability_haste = 0.0
	bonus_move_speed_pct = 0.0
	poison_rank = 0
	shock_rank = 0
	burn_rank = 0
	frost_rank = 0
	_temp_atk_speed_pct = 0.0
	_temp_move_speed_pct = 0.0
	_temp_buff_timer = 0.0
	set_process(false)
	_recalculate()


func clear_temporary_buffs() -> void:
	if _temp_buff_timer > 0.0:
		_temp_atk_speed_pct = 0.0
		_temp_move_speed_pct = 0.0
		_temp_buff_timer = 0.0
		set_process(false)
		_recalculate()


func apply_temporary_overdrive(atk_spd_bonus: float, move_spd_bonus: float, duration: float) -> void:
	_temp_atk_speed_pct = maxf(_temp_atk_speed_pct, atk_spd_bonus)
	_temp_move_speed_pct = maxf(_temp_move_speed_pct, move_spd_bonus)
	_temp_buff_timer = maxf(_temp_buff_timer, duration)
	set_process(true)
	_recalculate()


func apply_trait_upgrade(trait_id: int) -> float:
	var hp_delta: float = 0.0
	match trait_id:
		CatalogScript.TraitId.STAT_AD:
			bonus_ad += 4.0
		CatalogScript.TraitId.STAT_AP:
			bonus_ap += 6.0
		CatalogScript.TraitId.STAT_HP:
			bonus_max_hp += 25.0
			hp_delta = 25.0
		CatalogScript.TraitId.STAT_ATK_SPD:
			bonus_atk_speed_pct += 0.22
		CatalogScript.TraitId.STAT_HASTE:
			bonus_ability_haste += 25.0
		CatalogScript.TraitId.STAT_MOVE_SPD:
			bonus_move_speed_pct += 0.12
		CatalogScript.TraitId.ELEM_POISON:
			poison_rank += 1
		CatalogScript.TraitId.ELEM_SHOCK:
			shock_rank += 1
		CatalogScript.TraitId.ELEM_BURN:
			burn_rank += 1
		CatalogScript.TraitId.ELEM_FROST:
			frost_rank += 1
	_recalculate()
	return hp_delta


func compute_cooldown(base_cooldown: float) -> float:
	if base_cooldown <= 0.0:
		return 0.0
	return base_cooldown * (100.0 / (100.0 + maxf(0.0, ability_haste)))


func compute_scaled_damage(ad_ratio: float, ap_ratio: float, flat_base: float = 0.0) -> float:
	return flat_base + attack_damage * ad_ratio + ability_power * ap_ratio


func _process(delta: float) -> void:
	if _temp_buff_timer > 0.0:
		_temp_buff_timer = maxf(0.0, _temp_buff_timer - delta)
		if _temp_buff_timer <= 0.0:
			_temp_atk_speed_pct = 0.0
			_temp_move_speed_pct = 0.0
			set_process(false)
			_recalculate()
	else:
		set_process(false)


func _recalculate() -> void:
	max_hp = BASE_MAX_HP + bonus_max_hp
	attack_damage = BASE_AD + bonus_ad
	ability_power = BASE_AP + bonus_ap
	attack_speed = BASE_ATK_SPEED * (1.0 + bonus_atk_speed_pct + _temp_atk_speed_pct)
	ability_haste = BASE_ABILITY_HASTE + bonus_ability_haste
	move_speed = BASE_MOVE_SPEED * (1.0 + bonus_move_speed_pct + _temp_move_speed_pct)
	stats_changed.emit()
