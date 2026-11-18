class_name BossArenaDirector
extends Node3D

## Orchestrates biome-matched signature Boss Battle mechanics, interactive props,
## phase intermissions, environmental shelter checks, and Boss HUD callouts.

const BossPropScript = preload("res://world/boss_mechanic_prop.gd")
const ArchetypeScript = preload("res://enemies/enemy_archetype_data.gd")
const HazardScript = preload("res://world/enemy_hazard_effect.gd")
const HAZARD_SHADER: Shader = preload("res://shaders/EnemyHazard.gdshader")

signal callout_changed(text: String, color: Color, duration: float)
signal reinforcements_requested(specs: Array)

const COL_GOLD := Color(1.0, 0.84, 0.34, 1.0)
const COL_EMERALD := Color(0.46, 0.98, 0.58, 1.0)
const COL_CYAN := Color(0.46, 0.92, 1.0, 1.0)
const COL_ASTRAL := Color(0.86, 0.64, 1.0, 1.0)
const COL_MAGMA := Color(1.0, 0.48, 0.22, 1.0)
const COL_DANGER := Color(1.0, 0.28, 0.36, 1.0)

var _active: bool = false
var _boss: EnemySphere = null
var _boss_arch_id: int = -1
var _arena_center: Vector3 = Vector3.ZERO
var _players_root: Node3D = null
var _biome_id: int = 0
var _prog_mult: float = 1.0
var _current_phase: int = 1
var _props: Array[BossMechanicProp] = []

var _pillar_anchors: Array[Vector3] = [
	Vector3(-8.2, 0.0, -7.6),
	Vector3(8.2, 0.0, -7.6),
	Vector3(8.2, 0.0, 7.6),
	Vector3(-8.2, 0.0, 7.6)
]
var _obelisk_anchors: Array[Vector3] = [
	Vector3(-8.5, 0.0, -8.5),
	Vector3(8.5, 0.0, -8.5),
	Vector3(8.5, 0.0, 8.5),
	Vector3(-8.5, 0.0, 8.5)
]

# Blightweaver state
var _conduit_count_remaining: int = 0
var _spore_phase_unlocked: bool = false
var _spore_spawn_timer: float = 0.0
var _spore_angle_cursor: int = 0

# Cryo-Archon state
var _aegis_cd_timer: float = 4.2
var _whiteout_cd_timer: float = 999.0
var _whiteout_active: bool = false
var _whiteout_timer: float = 0.0
var _whiteout_tick_timer: float = 0.0
var _whiteout_disc: MeshInstance3D = null
var _whiteout_mat: ShaderMaterial = null

# Chronomancer state
var _rewind_active: bool = false
var _rewind_timer: float = 0.0
var _beacon_count_remaining: int = 0
var _mirage_active: bool = false
var _mirage_hits_left: int = 0
var _pending_p3_mirage: bool = false


func _ready() -> void:
	set_process(false)
	_ensure_whiteout_disc()


func _ensure_whiteout_disc() -> void:
	if _whiteout_disc != null:
		return
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)
	_whiteout_mat = ShaderMaterial.new()
	_whiteout_mat.shader = HAZARD_SHADER
	_whiteout_mat.set_shader_parameter("hazard_color", Color(0.46, 0.90, 1.0, 1.0))
	_whiteout_mat.set_shader_parameter("border_danger_color", Color(1.0, 0.18, 0.28, 1.0))
	_whiteout_mat.set_shader_parameter("inner_ratio", 0.0)
	_whiteout_mat.set_shader_parameter("progress", 0.0)
	_whiteout_mat.set_shader_parameter("hazard_stage", 4)
	_whiteout_mat.set_shader_parameter("fade_out", 1.0)

	_whiteout_disc = MeshInstance3D.new()
	_whiteout_disc.name = "WhiteoutStormDisc"
	_whiteout_disc.mesh = plane
	_whiteout_disc.material_override = _whiteout_mat
	_whiteout_disc.scale = Vector3(18.5, 1.0, 18.5)
	_whiteout_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_whiteout_disc.visible = false
	add_child(_whiteout_disc)


func is_boss_active() -> bool:
	return _active and _boss != null and is_instance_valid(_boss) and not _boss._is_dying


func get_active_boss() -> EnemySphere:
	return _boss if is_boss_active() else null


func begin_boss_encounter(
	boss: EnemySphere,
	area_center: Vector3,
	biome_id: int,
	players_root: Node3D,
	prog_mult: float
) -> void:
	clear_boss_encounter()
	if boss == null or not is_instance_valid(boss):
		return

	_ensure_whiteout_disc()
	_boss = boss
	_boss_arch_id = boss._archetype.archetype_id if boss._archetype != null else ArchetypeScript.ArchetypeId.BOSS
	_arena_center = Vector3(area_center.x, 0.0, area_center.z)
	_biome_id = biome_id
	_players_root = players_root
	_prog_mult = maxf(1.0, prog_mult)
	_current_phase = 1
	_active = true

	_conduit_count_remaining = 0
	_spore_phase_unlocked = false
	_spore_spawn_timer = 0.0
	_spore_angle_cursor = 0
	_aegis_cd_timer = 2.4
	_whiteout_cd_timer = 999.0
	_whiteout_active = false
	_whiteout_timer = 0.0
	_rewind_active = false
	_rewind_timer = 0.0
	_beacon_count_remaining = 0
	_mirage_active = false
	_mirage_hits_left = 0
	_pending_p3_mirage = false

	match _boss_arch_id:
		ArchetypeScript.ArchetypeId.BOSS_BLIGHTWEAVER:
			callout_changed.emit("VERDANT BROODMOTHER — PURE VITALITY DUEL", COL_EMERALD, 3.2)

		ArchetypeScript.ArchetypeId.BOSS_CRYO_ARCHON:
			if _boss.health_comp:
				_boss.health_comp.set_armor_dr(0.25)
			callout_changed.emit("RIMEBLADE SOVEREIGN — WATCH FOR GLACIAL AEGIS DOME", COL_CYAN, 3.2)

		ArchetypeScript.ArchetypeId.BOSS_CHRONOMANCER:
			callout_changed.emit("COSMIC TIMEWEAVER — READ STARFALL & SAFE-EYE SUPERNOVA", COL_ASTRAL, 3.2)

		ArchetypeScript.ArchetypeId.BOSS:
			if _boss.health_comp:
				_boss.health_comp.set_armor_dr(0.55)
			_spawn_basalt_pillars_to_target(4)
			callout_changed.emit("MONOLITH ARMOR (55% DR) — BAIT BULL-RUSH INTO A BASALT PILLAR!", COL_MAGMA, 4.5)

	set_process(true)


func clear_boss_encounter() -> void:
	_active = false
	_whiteout_active = false
	_rewind_active = false
	_mirage_active = false
	_pending_p3_mirage = false
	set_process(false)
	if _whiteout_disc:
		_whiteout_disc.visible = false
	for p in _props:
		if p != null and is_instance_valid(p):
			p.cleanup_and_free()
	_props.clear()
	if _players_root != null and is_instance_valid(_players_root):
		for i in range(_players_root.get_child_count()):
			var pl: Node = _players_root.get_child(i)
			if pl != null and pl.has_method("clear_temporal_locks"):
				pl.call("clear_temporal_locks")
	_boss = null
	_boss_arch_id = -1


func _process(delta: float) -> void:
	if not _active or _boss == null or not is_instance_valid(_boss) or _boss._is_dying:
		return

	_prune_invalid_props()

	match _boss_arch_id:
		ArchetypeScript.ArchetypeId.BOSS_BLIGHTWEAVER:
			if _spore_phase_unlocked and not _boss.health_comp.is_impervious():
				_spore_spawn_timer -= delta
				if _spore_spawn_timer <= 0.0:
					_spore_spawn_timer = 7.5
					_spawn_spore_sac()

		ArchetypeScript.ArchetypeId.BOSS_CRYO_ARCHON:
			_step_cryo_archon(delta)

		ArchetypeScript.ArchetypeId.BOSS_CHRONOMANCER:
			_step_chronomancer(delta)


func _step_cryo_archon(delta: float) -> void:
	if _whiteout_active:
		_whiteout_timer -= delta
		_whiteout_tick_timer -= delta
		if _whiteout_disc:
			_whiteout_disc.global_position = Vector3(_boss.global_position.x, 0.04, _boss.global_position.z)
		if _whiteout_mat:
			_whiteout_mat.set_shader_parameter("progress", clampf(1.0 - _whiteout_timer / 3.5, 0.0, 1.0))
		for p in _props:
			if p != null and is_instance_valid(p) and p.prop_kind == BossPropScript.PropKind.ICE_OBELISK:
				p.set_whiteout_shadow(true, _boss.global_position)
		if _whiteout_tick_timer <= 0.0:
			_whiteout_tick_timer = 0.45
			_apply_whiteout_exposure(false)
		if _whiteout_timer <= 0.0:
			_end_whiteout_storm()
		return

	if _boss._stagger_timer <= 0.0 and not _boss.is_aegis_dome_active() and not _boss.health_comp.is_impervious():
		_aegis_cd_timer -= delta
		if _aegis_cd_timer <= 0.0:
			_aegis_cd_timer = 14.0
			_boss.activate_aegis_dome(8.2, 6.5)
			callout_changed.emit("GLACIAL AEGIS — DASH INSIDE THE DOME TO ATTACK!", COL_CYAN, 4.2)

	if _current_phase >= 2 and not _boss.health_comp.is_impervious() and not _boss.is_aegis_dome_active():
		_whiteout_cd_timer -= delta
		if _whiteout_cd_timer <= 0.0:
			_whiteout_cd_timer = 15.0
			_start_whiteout_storm()


func _start_whiteout_storm() -> void:
	_whiteout_active = true
	_whiteout_timer = 3.5
	_whiteout_tick_timer = 0.55
	if _whiteout_disc:
		_whiteout_disc.global_position = Vector3(_boss.global_position.x, 0.04, _boss.global_position.z)
		_whiteout_disc.visible = true
	if _whiteout_mat:
		_whiteout_mat.set_shader_parameter("fade_out", 1.0)
	for p in _props:
		if p != null and is_instance_valid(p) and p.prop_kind == BossPropScript.PropKind.ICE_OBELISK:
			p.set_whiteout_shadow(true, _boss.global_position)
	callout_changed.emit("WHITEOUT STORM — TAKE COVER BEHIND AN ICE OBELISK!", COL_DANGER, 0.0)


func _end_whiteout_storm() -> void:
	_apply_whiteout_exposure(true)
	_whiteout_active = false
	if _whiteout_disc:
		_whiteout_disc.visible = false
	for p in _props:
		if p != null and is_instance_valid(p) and p.prop_kind == BossPropScript.PropKind.ICE_OBELISK:
			p.set_whiteout_shadow(false, _boss.global_position)
	callout_changed.emit("", COL_CYAN, 0.0)


func _apply_whiteout_exposure(is_climax: bool) -> void:
	if _players_root == null or not is_instance_valid(_players_root) or _boss == null:
		return
	var boss_2d := Vector2(_boss.global_position.x, _boss.global_position.z)
	for i in range(_players_root.get_child_count()):
		var p3d: Node3D = _players_root.get_child(i) as Node3D
		if p3d == null or not p3d.visible:
			continue
		var pl_2d := Vector2(p3d.global_position.x, p3d.global_position.z)
		if _is_point_sheltered(pl_2d, boss_2d):
			continue
		if not is_climax and p3d.has_method("apply_boss_slow"):
			p3d.call("apply_boss_slow", 0.35, 1.2)
		if p3d.has_method("try_apply_contact_damage"):
			var away: Vector3 = p3d.global_position - _boss.global_position
			away.y = 0.0
			away = away.normalized() if away.length_squared() > 0.01 else Vector3.FORWARD
			p3d.call("try_apply_contact_damage", 22.0 if is_climax else 4.0, away)


func _is_point_sheltered(pt_2d: Vector2, boss_2d: Vector2) -> bool:
	for prop in _props:
		if prop == null or not is_instance_valid(prop) or prop.prop_kind != BossPropScript.PropKind.ICE_OBELISK:
			continue
		var ob_2d := Vector2(prop.global_position.x, prop.global_position.z)
		var bo: Vector2 = ob_2d - boss_2d
		var bo_len: float = bo.length()
		if bo_len < 0.5:
			continue
		var dir_bo: Vector2 = bo / bo_len
		var bp: Vector2 = pt_2d - boss_2d
		var proj: float = bp.dot(dir_bo)
		if proj < bo_len - 0.15 or proj > bo_len + 9.6:
			continue
		var perp_dist: float = absf(bp.x * dir_bo.y - bp.y * dir_bo.x)
		if perp_dist <= 1.45:
			return true
	return false


func _step_chronomancer(delta: float) -> void:
	if not _rewind_active:
		return
	_rewind_timer -= delta
	callout_changed.emit(
		"TIME REWIND (%.1fs) — STAND IN OR SHOOT BEACONS (%d LEFT)" % [maxf(0.0, _rewind_timer), _beacon_count_remaining],
		COL_GOLD,
		0.0
	)
	if _rewind_timer <= 0.0:
		_rewind_active = false
		for i in range(_props.size() - 1, -1, -1):
			var p: BossMechanicProp = _props[i]
			if p != null and is_instance_valid(p) and p.prop_kind == BossPropScript.PropKind.STAR_BEACON:
				p.cleanup_and_free()
				_props.remove_at(i)
		if _boss.health_comp:
			_boss.health_comp.set_impervious_locked(false)
			_boss.health_comp.heal(_boss.health_comp.max_health * 0.25)
		callout_changed.emit("TIME REWOUND! CHRONOMANCER RESTORED HP", COL_DANGER, 2.8)
		if _pending_p3_mirage:
			_pending_p3_mirage = false
			_activate_astral_mirage()


func on_boss_phase_changed(boss: EnemySphere, new_phase: int) -> void:
	if not _active or boss != _boss:
		return
	_current_phase = new_phase

	match _boss_arch_id:
		ArchetypeScript.ArchetypeId.BOSS_BLIGHTWEAVER:
			_boss.force_return_to_point(_arena_center)
			if _boss.health_comp:
				_boss.health_comp.set_impervious_locked(true)
			var c_count: int = 4 if new_phase >= 3 else 3
			_spawn_ring_props(BossPropScript.PropKind.BLIGHT_CONDUIT, c_count, 9.6, 115.0 * _prog_mult)
			_conduit_count_remaining = c_count
			if new_phase == 2:
				_request_minions([ArchetypeScript.ArchetypeId.CHASER, ArchetypeScript.ArchetypeId.DASHER], 7.0)
			callout_changed.emit("IMPERVIOUS — DESTROY BLIGHT CONDUITS (%d LEFT)" % c_count, COL_EMERALD, 0.0)

		ArchetypeScript.ArchetypeId.BOSS_CRYO_ARCHON:
			if _boss.health_comp:
				var missing: float = maxf(0.0, 220.0 * _prog_mult - _boss.health_comp.current_armor)
				if missing > 0.1:
					_boss.health_comp.grant_armor(missing)
				_boss.health_comp.set_armor_dr(0.25)
			_replenish_ice_obelisks(4)
			_whiteout_cd_timer = 4.2 if new_phase == 2 else 3.8
			callout_changed.emit("ICE OBELISKS DEPLOYED — SHELTER FROM WHITEOUT OR SHATTER WITH LANCES!", COL_CYAN, 3.6)

		ArchetypeScript.ArchetypeId.BOSS_CHRONOMANCER:
			_boss.force_return_to_point(_arena_center)
			if _boss.health_comp:
				_boss.health_comp.set_impervious_locked(true)
			_rewind_active = true
			_rewind_timer = 10.0
			_pending_p3_mirage = (new_phase >= 3)
			_spawn_ring_props(BossPropScript.PropKind.STAR_BEACON, 3, 9.2, 95.0 * _prog_mult)
			_beacon_count_remaining = 3
			callout_changed.emit("TIME REWIND (10.0s) — STAND IN OR SHOOT BEACONS (3 LEFT)", COL_GOLD, 0.0)

		ArchetypeScript.ArchetypeId.BOSS:
			if _boss.health_comp:
				var target_arm: float = (400.0 if new_phase >= 3 else 360.0) * _prog_mult
				var add_arm: float = maxf(0.0, target_arm - _boss.health_comp.current_armor)
				if add_arm > 0.1:
					_boss.health_comp.grant_armor(add_arm)
				_boss.health_comp.set_armor_dr(0.55)
			if new_phase == 2:
				_request_minions([ArchetypeScript.ArchetypeId.LUNGER, ArchetypeScript.ArchetypeId.LUNGER], 7.5)
				callout_changed.emit("MONOLITH ARMOR RESTORED — BAIT BULL-RUSH INTO A BASALT PILLAR!", COL_MAGMA, 3.8)
			elif new_phase >= 3:
				_spawn_basalt_pillars_to_target(2)
				callout_changed.emit("VOLCANIC OVERDRIVE — SEISMIC CROSS & MONOLITH ARMOR!", COL_MAGMA, 3.8)


func on_boss_armor_broken(boss: EnemySphere) -> void:
	if not _active or boss != _boss:
		return
	if _boss_arch_id == ArchetypeScript.ArchetypeId.BOSS or _boss_arch_id == ArchetypeScript.ArchetypeId.BOSS_CRYO_ARCHON:
		callout_changed.emit("ARMOR SHATTERED! STAGGERED & EXPOSED (+40% DMG)", COL_GOLD, 2.5)


func on_boss_pillar_collision(boss: EnemySphere, collider: Object) -> bool:
	if not _active or boss != _boss:
		return false
	if collider is BossMechanicProp and (collider as BossMechanicProp).prop_kind == BossPropScript.PropKind.BASALT_PILLAR:
		var prop: BossMechanicProp = collider as BossMechanicProp
		prop.take_boss_charge_impact()
		_boss.trigger_boss_stagger(2.8, 1.50, true)
		if is_inside_tree():
			get_tree().call_group("world_camera_shake", "add_camera_shake", 0.65)
		callout_changed.emit("ARMOR SHATTERED! STAGGERED & EXPOSED (+50% DMG)", COL_GOLD, 3.0)
		return true
	return false


func on_boss_dash_pos(boss: EnemySphere, dash_pos: Vector3) -> void:
	if not _active or boss != _boss or _boss_arch_id != ArchetypeScript.ArchetypeId.BOSS_CRYO_ARCHON:
		return
	for p in _props:
		if p == null or not is_instance_valid(p) or p.prop_kind != BossPropScript.PropKind.ICE_OBELISK:
			continue
		var dx: float = p.global_position.x - dash_pos.x
		var dz: float = p.global_position.z - dash_pos.z
		if (dx * dx + dz * dz) <= 2.35 * 2.35:
			p.on_lance_hit(dash_pos)
			return


func notify_clock_sector_cast(telegraph_s: float) -> void:
	if _active and _boss_arch_id == ArchetypeScript.ArchetypeId.BOSS_CHRONOMANCER:
		callout_changed.emit("CLOCK-DIAL JUDGMENT — STEP INTO THE GOLDEN SAFE SECTOR!", COL_GOLD, telegraph_s)


func notify_true_chronomancer_hit() -> void:
	if not _active or not _mirage_active:
		return
	_mirage_hits_left -= 1
	if _mirage_hits_left <= 0:
		_mirage_active = false
		if _players_root != null and is_instance_valid(_players_root):
			for i in range(_players_root.get_child_count()):
				var pl: Node = _players_root.get_child(i)
				if pl != null and pl.has_method("clear_temporal_locks"):
					pl.call("clear_temporal_locks")
		if is_inside_tree():
			var enemies: Array[Node] = get_tree().get_nodes_in_group("active_enemies")
			for n in enemies:
				if n is EnemySphere and bool((n as EnemySphere).is_astral_clone):
					(n as EnemySphere).force_despawn_clone()
		callout_changed.emit("MIRAGE BROKEN — ABILITY LOCK CLEARED!", COL_CYAN, 2.4)


func _activate_astral_mirage() -> void:
	_mirage_active = true
	_mirage_hits_left = 3
	_request_minions([ArchetypeScript.ArchetypeId.BOSS_CHRONOMANCER, ArchetypeScript.ArchetypeId.BOSS_CHRONOMANCER], 8.2, true)
	if _players_root != null and is_instance_valid(_players_root):
		for i in range(_players_root.get_child_count()):
			var pl: Node = _players_root.get_child(i)
			if pl != null and pl.has_method("apply_temporal_ability_lock"):
				pl.call("apply_temporal_ability_lock", 0, 4.0)
	callout_changed.emit("ASTRAL MIRAGE — STRIKE THE TRUE CHRONOMANCER TO BREAK [Q] LOCK!", COL_ASTRAL, 4.0)


func _spawn_basalt_pillars_to_target(min_count: int) -> void:
	var used_anchors: Array[int] = []
	for p in _props:
		if p != null and is_instance_valid(p) and p.prop_kind == BossPropScript.PropKind.BASALT_PILLAR:
			used_anchors.append(p.anchor_index)
	for i in range(_pillar_anchors.size()):
		if used_anchors.size() >= min_count:
			break
		if used_anchors.has(i):
			continue
		used_anchors.append(i)
		_create_prop(BossPropScript.PropKind.BASALT_PILLAR, _arena_center + _pillar_anchors[i], 100.0, i)


func _replenish_ice_obelisks(target_count: int) -> void:
	var used_anchors: Array[int] = []
	for p in _props:
		if p != null and is_instance_valid(p) and p.prop_kind == BossPropScript.PropKind.ICE_OBELISK:
			used_anchors.append(p.anchor_index)
	for i in range(_obelisk_anchors.size()):
		if used_anchors.size() >= target_count:
			break
		if used_anchors.has(i):
			continue
		used_anchors.append(i)
		_create_prop(BossPropScript.PropKind.ICE_OBELISK, _arena_center + _obelisk_anchors[i], 100.0, i)


func _spawn_ring_props(kind: int, count: int, radius: float, hp: float) -> void:
	for i in range(count):
		var ang: float = float(i) * (TAU / float(maxi(1, count))) + 0.35
		var pos: Vector3 = _arena_center + Vector3(cos(ang) * radius, 0.0, sin(ang) * radius)
		_create_prop(kind, pos, hp, i)


func _spawn_spore_sac() -> void:
	_spore_angle_cursor = (_spore_angle_cursor + 1) % 6
	var ang: float = float(_spore_angle_cursor) * (TAU / 6.0) + 0.4
	var pos: Vector3 = _arena_center + Vector3(cos(ang) * 7.2, 0.0, sin(ang) * 7.2)
	_create_prop(BossPropScript.PropKind.SPORE_SAC, pos, 70.0 * _prog_mult, _spore_angle_cursor)
	callout_changed.emit("POP SWELLING SPORE SAC BEFORE DETONATION!", COL_EMERALD, 3.2)


func _create_prop(kind: int, pos: Vector3, hp: float, anchor_idx: int) -> BossMechanicProp:
	var prop := BossPropScript.new()
	prop.name = "BossProp_%d_%d" % [kind, _props.size()]
	add_child(prop)
	prop.prop_destroyed.connect(_on_prop_destroyed)
	prop.obelisk_shattered.connect(_on_obelisk_shattered)
	prop.configure(kind, pos, _boss, _players_root, hp, anchor_idx)
	_props.append(prop)
	return prop


func _on_prop_destroyed(prop: BossMechanicProp, was_player_cleared: bool) -> void:
	_props.erase(prop)
	if not _active or _boss == null or not is_instance_valid(_boss) or _boss._is_dying:
		return

	match prop.prop_kind:
		BossPropScript.PropKind.BLIGHT_CONDUIT:
			_conduit_count_remaining = maxi(0, _conduit_count_remaining - 1)
			if _conduit_count_remaining > 0:
				callout_changed.emit("IMPERVIOUS — DESTROY BLIGHT CONDUITS (%d LEFT)" % _conduit_count_remaining, COL_EMERALD, 0.0)
			else:
				if _boss.health_comp:
					_boss.health_comp.set_impervious_locked(false)
				_boss.trigger_boss_stagger(2.2, 1.35, false)
				if _current_phase >= 3:
					_spore_phase_unlocked = true
					_spore_spawn_timer = 2.4
				callout_changed.emit("WARD SHATTERED! STAGGERED & EXPOSED (+35% DMG)", COL_GOLD, 2.8)

		BossPropScript.PropKind.STAR_BEACON:
			if not _rewind_active:
				return
			_beacon_count_remaining = maxi(0, _beacon_count_remaining - 1)
			if _beacon_count_remaining == 0:
				_rewind_active = false
				if _boss.health_comp:
					_boss.health_comp.set_impervious_locked(false)
				_boss.trigger_boss_stagger(2.4, 1.45, false)
				if _players_root != null and is_instance_valid(_players_root):
					for i in range(_players_root.get_child_count()):
						var pl: Node = _players_root.get_child(i)
						if pl != null and pl.has_method("refresh_ability_cooldowns"):
							pl.call("refresh_ability_cooldowns")
				callout_changed.emit("REWIND SHATTERED! EXPOSED (+45% DMG) · ABILITIES REFRESHED", COL_GOLD, 3.2)
				_boss.queue_clock_sector_soon()
				if _pending_p3_mirage:
					_pending_p3_mirage = false
					_activate_astral_mirage()

		BossPropScript.PropKind.SPORE_SAC:
			if was_player_cleared:
				callout_changed.emit("SPORE SAC DEFUSED!", COL_EMERALD, 1.5)


func _on_obelisk_shattered(_prop: BossMechanicProp, world_pos: Vector3) -> void:
	if not _active or _boss == null or not is_instance_valid(_boss) or _boss._is_dying:
		return
	if ProjectilePool and ProjectilePool.has_method("spawn_enemy_ground_hazard") and _players_root != null:
		ProjectilePool.call(
			"spawn_enemy_ground_hazard",
			HazardScript.HazardMode.GROUND_QUAKE,
			world_pos,
			world_pos,
			5.8,
			0.0,
			0.0,
			0.18,
			0.45,
			Color(0.54, 0.96, 1.0),
			0.40,
			_players_root
		)
	var dx: float = _boss.global_position.x - world_pos.x
	var dz: float = _boss.global_position.z - world_pos.z
	if (dx * dx + dz * dz) <= 5.8 * 5.8:
		if _boss.health_comp != null and _boss.health_comp.has_armor():
			var strip_amt: float = _boss.health_comp.max_armor * 0.55
			if _boss.health_comp.current_armor <= strip_amt:
				_boss.health_comp.shatter_armor()
			else:
				_boss.health_comp.current_armor -= strip_amt
				_boss.health_comp.armor_changed.emit(_boss.health_comp.current_armor, _boss.health_comp.max_armor)
		_boss.trigger_boss_stagger(2.0, 1.40, false)
		callout_changed.emit("OBELISK SHATTERED! CRYO-ARCHON STAGGERED (+40% DMG)", COL_GOLD, 2.8)


func _request_minions(arch_list: Array, ring_radius: float, is_clones: bool = false) -> void:
	var specs: Array = []
	for i in range(arch_list.size()):
		var ang: float = float(i) * (TAU / float(maxi(1, arch_list.size()))) + 0.65
		var pos: Vector3 = _arena_center + Vector3(cos(ang) * ring_radius, 0.0, sin(ang) * ring_radius)
		specs.append({
			"arch": int(arch_list[i]),
			"pos": pos,
			"is_clone": is_clones
		})
	reinforcements_requested.emit(specs)


func _prune_invalid_props() -> void:
	for i in range(_props.size() - 1, -1, -1):
		if _props[i] == null or not is_instance_valid(_props[i]):
			_props.remove_at(i)
