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

# Briarbloom Matriarch state (plant vine-spawners + swarmer hordes)
var _overgrowth_locked: bool = false
var _overgrowth_grace_timer: float = 0.0
var _p1_overgrowth_triggered: bool = false
var _p1_elapsed_timer: float = 0.0
var _live_vine_swarmers: Array[EnemySphere] = []
var _max_vine_swarm_cap: int = 8
var _vine_spawn_cursor: int = 0
var _last_overgrowth_callout: String = ""
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

# Chronomancer state (full-field time-ticking shifting safe zones + Mirage)
var _horology_active: bool = false
var _horology_steps: Array = []
var _horology_step_idx: int = 0
var _horology_step_timer: float = 0.0
var _horology_gap_timer: float = 0.0
var _horology_last_angle: float = 0.0
var _horology_last_pos: Vector3 = Vector3.ZERO
var _p1_horology_triggered: bool = false
var _horology_recast_cd: float = 17.0
var _mirage_delay_timer: float = 0.0
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


func get_arena_center() -> Vector3:
	return _arena_center


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

	_overgrowth_locked = false
	_overgrowth_grace_timer = 0.0
	_p1_overgrowth_triggered = false
	_p1_elapsed_timer = 0.0
	_live_vine_swarmers.clear()
	_max_vine_swarm_cap = 8
	_vine_spawn_cursor = 0
	_last_overgrowth_callout = ""
	_spore_phase_unlocked = false
	_spore_spawn_timer = 0.0
	_spore_angle_cursor = 0
	_aegis_cd_timer = 2.4
	_whiteout_cd_timer = 999.0
	_whiteout_active = false
	_whiteout_timer = 0.0
	_horology_active = false
	_horology_steps.clear()
	_horology_step_idx = 0
	_horology_step_timer = 0.0
	_horology_gap_timer = 0.0
	_horology_last_angle = 0.35
	_horology_last_pos = Vector3.ZERO
	_p1_horology_triggered = false
	_horology_recast_cd = 17.0
	_mirage_delay_timer = 0.0
	_mirage_active = false
	_mirage_hits_left = 0
	_pending_p3_mirage = false

	match _boss_arch_id:
		ArchetypeScript.ArchetypeId.BOSS_BLIGHTWEAVER:
			callout_changed.emit("BRIARBLOOM MATRIARCH — DESTROY VINE STALKS & SWARMERS TO EXPOSE THE CORE!", COL_EMERALD, 3.6)

		ArchetypeScript.ArchetypeId.BOSS_CRYO_ARCHON:
			if _boss.health_comp:
				_boss.health_comp.set_armor_dr(0.25)
			callout_changed.emit("RIMEBLADE SOVEREIGN — WATCH FOR GLACIAL AEGIS DOME", COL_CYAN, 3.2)

		ArchetypeScript.ArchetypeId.BOSS_CHRONOMANCER:
			callout_changed.emit("COSMIC TIMEWEAVER — READ TICKING CLOCK ZONES & SHIFTING SAFE ZONES!", COL_ASTRAL, 3.6)

		ArchetypeScript.ArchetypeId.BOSS:
			if _boss.health_comp:
				_boss.health_comp.set_armor_dr(0.55)
			_spawn_basalt_pillars_to_target(4)
			callout_changed.emit("MONOLITH ARMOR (55% DR) — BAIT BULL-RUSH INTO A BASALT PILLAR!", COL_MAGMA, 4.5)

	set_process(true)


func clear_boss_encounter() -> void:
	_active = false
	_whiteout_active = false
	_overgrowth_locked = false
	_live_vine_swarmers.clear()
	_horology_active = false
	_horology_steps.clear()
	_mirage_delay_timer = 0.0
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
			_step_blightweaver(delta)

		ArchetypeScript.ArchetypeId.BOSS_CRYO_ARCHON:
			_step_cryo_archon(delta)

		ArchetypeScript.ArchetypeId.BOSS_CHRONOMANCER:
			_step_chronomancer(delta)


func register_vine_swarmer(enemy: EnemySphere) -> void:
	if enemy != null and is_instance_valid(enemy) and not _live_vine_swarmers.has(enemy):
		_live_vine_swarmers.append(enemy)


func on_reinforcement_defeated(enemy: EnemySphere) -> void:
	if enemy != null:
		_live_vine_swarmers.erase(enemy)


func _prune_vine_swarmers() -> void:
	for i in range(_live_vine_swarmers.size() - 1, -1, -1):
		var es: EnemySphere = _live_vine_swarmers[i]
		if es == null or not is_instance_valid(es) or es._is_dying or not es._is_active_unit or not es.visible:
			_live_vine_swarmers.remove_at(i)


func _count_props_of_kind(kind: int) -> int:
	var n: int = 0
	for p in _props:
		if p != null and is_instance_valid(p) and p.prop_kind == kind:
			n += 1
	return n


func _step_blightweaver(delta: float) -> void:
	_prune_vine_swarmers()

	if _current_phase == 1 and not _p1_overgrowth_triggered and not _overgrowth_locked and _boss._stagger_timer <= 0.0:
		_p1_elapsed_timer += delta
		var hp_trigger: bool = (_boss.health_comp != null and _boss.health_comp.current_health <= _boss.health_comp.max_health * 0.72)
		if hp_trigger or _p1_elapsed_timer >= 5.5:
			_p1_overgrowth_triggered = true
			_start_overgrowth_phase(2, 2, 7, 85.0 * _prog_mult)
			return

	if _overgrowth_locked:
		_overgrowth_grace_timer = maxf(0.0, _overgrowth_grace_timer - delta)
		var alive_vines: int = _count_props_of_kind(BossPropScript.PropKind.VINE_SPAWNER)
		var alive_swarm: int = _live_vine_swarmers.size()
		var vine_w: String = "VINE" if alive_vines == 1 else "VINES"
		var swarm_w: String = "SWARMER" if alive_swarm == 1 else "SWARMERS"
		var msg: String = ""
		if alive_vines > 0 and alive_swarm > 0:
			msg = "THORN SHELL IMPERVIOUS — KILL %d %s & %d %s" % [alive_vines, vine_w, alive_swarm, swarm_w]
		elif alive_vines > 0:
			msg = "THORN SHELL IMPERVIOUS — DESTROY %d REMAINING %s" % [alive_vines, vine_w]
		elif alive_swarm > 0:
			msg = "VINES CLEARED — KILL %d %s TO EXPOSE CORE!" % [alive_swarm, swarm_w]
		if not msg.is_empty() and msg != _last_overgrowth_callout:
			_last_overgrowth_callout = msg
			callout_changed.emit(msg, COL_EMERALD, 0.0)
		if _overgrowth_grace_timer <= 0.0 and alive_vines == 0 and alive_swarm == 0:
			_overgrowth_locked = false
			_last_overgrowth_callout = ""
			if _boss.health_comp:
				_boss.health_comp.set_impervious_locked(false)
			_boss.trigger_boss_stagger(2.5, 1.40, false)
			if _current_phase >= 3:
				_spore_phase_unlocked = true
				_spore_spawn_timer = 2.6
			callout_changed.emit("OVERGROWTH SHATTERED! CORE EXPOSED (+40% DMG)", COL_GOLD, 2.8)
	elif _spore_phase_unlocked and _boss.health_comp != null and not _boss.health_comp.is_impervious():
		_spore_spawn_timer -= delta
		if _spore_spawn_timer <= 0.0:
			_spore_spawn_timer = 7.5
			_spawn_spore_sac()


func _start_overgrowth_phase(vine_count: int, initial_per_vine: int, cap: int, vine_hp: float) -> void:
	_boss.force_return_to_point(_arena_center)
	if _boss.health_comp:
		_boss.health_comp.set_impervious_locked(true)
	_overgrowth_locked = true
	_overgrowth_grace_timer = 0.25
	_max_vine_swarm_cap = cap
	_last_overgrowth_callout = ""

	var specs: Array = []
	for i in range(vine_count):
		var ang: float = float(i) * (TAU / float(maxi(1, vine_count))) + 0.45
		var v_pos: Vector3 = _arena_center + Vector3(cos(ang) * 9.2, 0.0, sin(ang) * 9.2)
		_create_prop(BossPropScript.PropKind.VINE_SPAWNER, v_pos, vine_hp, i)
		for j in range(initial_per_vine):
			var s_ang: float = ang + (float(j) - 0.5) * 1.15
			var s_pos: Vector3 = v_pos + Vector3(cos(s_ang) * 1.85, 0.0, sin(s_ang) * 1.85)
			var arch: int = ArchetypeScript.ArchetypeId.CHASER if ((i + j) % 2 == 0) else ArchetypeScript.ArchetypeId.DASHER
			if _current_phase >= 3 and ((i + j) % 3 == 2):
				arch = ArchetypeScript.ArchetypeId.LUNGER
			specs.append({
				"arch": arch,
				"pos": s_pos,
				"vine_swarm": true,
				"hp_mult": 0.55
			})
	if not specs.is_empty():
		reinforcements_requested.emit(specs)


func _on_vine_spawn_requested(_prop: BossMechanicProp, world_pos: Vector3) -> void:
	if not _active or _boss == null or not is_instance_valid(_boss) or _boss._is_dying or not _overgrowth_locked:
		return
	_prune_vine_swarmers()
	if _live_vine_swarmers.size() >= _max_vine_swarm_cap:
		return
	var room_left: int = _max_vine_swarm_cap - _live_vine_swarmers.size()
	var batch: int = 2 if (_current_phase >= 3 and room_left >= 2) else 1
	var specs: Array = []
	for i in range(batch):
		_vine_spawn_cursor += 1
		var ang: float = float(_vine_spawn_cursor) * 1.65
		var s_pos: Vector3 = world_pos + Vector3(cos(ang) * 1.65, 0.0, sin(ang) * 1.65)
		var arch: int = ArchetypeScript.ArchetypeId.CHASER if (_vine_spawn_cursor % 2 == 0) else ArchetypeScript.ArchetypeId.DASHER
		if _current_phase >= 3 and (_vine_spawn_cursor % 3 == 0):
			arch = ArchetypeScript.ArchetypeId.LUNGER
		specs.append({
			"arch": arch,
			"pos": s_pos,
			"vine_swarm": true,
			"hp_mult": 0.55
		})
	reinforcements_requested.emit(specs)


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
	if _mirage_delay_timer > 0.0:
		_mirage_delay_timer -= delta
		if _mirage_delay_timer <= 0.0:
			_mirage_delay_timer = 0.0
			if not _horology_active:
				_activate_astral_mirage()

	if _horology_active:
		if _horology_gap_timer > 0.0:
			_horology_gap_timer -= delta
			if _horology_gap_timer <= 0.0:
				_horology_gap_timer = 0.0
				_launch_horology_step(_horology_step_idx)
		elif _horology_step_timer > 0.0:
			_horology_step_timer -= delta
			if _horology_step_timer <= 0.0:
				_horology_step_idx += 1
				if _horology_step_idx < _horology_steps.size():
					_horology_gap_timer = 0.22
				else:
					_finish_horology_sequence()
		return

	if _horology_recast_cd > 0.0:
		_horology_recast_cd -= delta

	if _current_phase == 1 and not _p1_horology_triggered and _boss._stagger_timer <= 0.0:
		_p1_elapsed_timer += delta
		var hp_trigger: bool = (_boss.health_comp != null and _boss.health_comp.current_health <= _boss.health_comp.max_health * 0.62)
		if hp_trigger or _p1_elapsed_timer >= 7.0:
			_p1_horology_triggered = true
			_start_horology_sequence([
				_make_wedge_step(2.4, 22.0, 33.0),
				_make_wedge_step(2.15, 22.0, 32.0)
			], false)


func try_trigger_mid_combat_horology() -> bool:
	if (
		not _active
		or _boss == null
		or _boss_arch_id != ArchetypeScript.ArchetypeId.BOSS_CHRONOMANCER
		or _current_phase < 2
		or _horology_active
		or _mirage_active
		or _mirage_delay_timer > 0.0
		or _horology_recast_cd > 0.0
		or _boss._stagger_timer > 0.0
	):
		return false
	_start_horology_sequence([
		_make_wedge_step(2.15, 24.0, 31.0),
		_make_circle_step(2.25, 24.0, 4.2)
	], false)
	return true


func _make_wedge_step(dur: float, dmg: float, half_deg: float) -> Dictionary:
	var shift_mag: float = deg_to_rad(randf_range(115.0, 165.0))
	var sign_f: float = 1.0 if ((_horology_step_idx + _boss._boss_pattern_idx) % 2 == 0) else -1.0
	var next_ang: float = wrapf(_horology_last_angle + shift_mag * sign_f, -PI, PI)
	_horology_last_angle = next_ang
	return {
		"kind": "wedge",
		"duration": dur,
		"damage": dmg,
		"safe_angle": next_ang,
		"safe_half_width": deg_to_rad(half_deg)
	}


func _make_circle_step(dur: float, dmg: float, safe_r: float) -> Dictionary:
	var base_ang: float = randf_range(0.0, TAU)
	if _horology_last_pos != Vector3.ZERO:
		var prev_ang: float = atan2(_horology_last_pos.z - _arena_center.z, _horology_last_pos.x - _arena_center.x)
		base_ang = prev_ang + deg_to_rad(randf_range(125.0, 235.0))
	var chosen := _arena_center + Vector3(cos(base_ang) * 9.4, 0.0, sin(base_ang) * 9.4)
	for attempt in range(4):
		var rad: float = randf_range(8.2, 10.6)
		var ang: float = base_ang + float(attempt) * 0.65
		var cand: Vector3 = _arena_center + Vector3(cos(ang) * rad, 0.0, sin(ang) * rad)
		if _horology_last_pos == Vector3.ZERO or cand.distance_to(_horology_last_pos) >= 9.5:
			chosen = cand
			break
	_horology_last_pos = chosen
	return {
		"kind": "circle",
		"duration": dur,
		"damage": dmg,
		"safe_pos": chosen,
		"safe_radius": safe_r
	}


func _start_horology_sequence(steps: Array, trigger_mirage_after: bool = false) -> void:
	_horology_steps = steps
	_horology_step_idx = 0
	_horology_gap_timer = 0.35
	_horology_step_timer = 0.0
	_horology_active = true
	_pending_p3_mirage = trigger_mirage_after
	_boss.force_return_to_point(_arena_center)
	if _boss.health_comp:
		_boss.health_comp.set_impervious_locked(true)
	callout_changed.emit("CHRONOS OVERDRIVE — FULL-FIELD JUDGMENT INCOMING!", COL_ASTRAL, 0.0)


func _launch_horology_step(idx: int) -> void:
	if idx < 0 or idx >= _horology_steps.size() or _players_root == null:
		return
	var step: Dictionary = _horology_steps[idx]
	var dur: float = float(step.get("duration", 2.4))
	var dmg: float = float(step.get("damage", 24.0))
	var total_beats: int = _horology_steps.size()
	_horology_step_timer = dur + 0.32

	if str(step.get("kind", "wedge")) == "circle":
		var safe_pos: Vector3 = step.get("safe_pos", _arena_center) as Vector3
		var safe_r: float = float(step.get("safe_radius", 4.2))
		if ProjectilePool and ProjectilePool.has_method("spawn_enemy_clock_safe_circle"):
			ProjectilePool.call(
				"spawn_enemy_clock_safe_circle",
				_arena_center,
				26.0,
				safe_pos,
				safe_r,
				dmg,
				dur,
				Color(0.56, 0.28, 0.96),
				0.58,
				_players_root
			)
		var msg: String = "CHRONOS ECLIPSE (%d/%d) — REACH THE GOLDEN SAFE CIRCLE!" % [idx + 1, total_beats]
		if idx > 0:
			msg = "SAFE CIRCLE SHIFTED (%d/%d) — FOLLOW THE COMPASS RAY!" % [idx + 1, total_beats]
		callout_changed.emit(msg, COL_GOLD, 0.0)
	else:
		var safe_ang: float = float(step.get("safe_angle", 0.0))
		var safe_hw: float = float(step.get("safe_half_width", 0.56))
		if ProjectilePool and ProjectilePool.has_method("spawn_enemy_clock_sector"):
			ProjectilePool.call(
				"spawn_enemy_clock_sector",
				_arena_center,
				26.0,
				safe_ang,
				safe_hw,
				dmg,
				dur,
				Color(0.56, 0.28, 0.96),
				0.58,
				_players_root
			)
		var w_msg: String = "CHRONOS JUDGMENT (%d/%d) — STEP INTO THE GOLDEN SAFE WEDGE!" % [idx + 1, total_beats]
		if idx > 0:
			w_msg = "SAFE ZONE SHIFTED (%d/%d) — MOVE TO THE NEW GOLDEN WEDGE!" % [idx + 1, total_beats]
		callout_changed.emit(w_msg, COL_GOLD, 0.0)


func _finish_horology_sequence() -> void:
	_horology_active = false
	_horology_recast_cd = 16.0 if _current_phase >= 3 else 18.0
	if _boss.health_comp:
		_boss.health_comp.set_impervious_locked(false)
	_boss.trigger_boss_stagger(2.6, 1.45, false)
	if _players_root != null and is_instance_valid(_players_root):
		for i in range(_players_root.get_child_count()):
			var pl: Node = _players_root.get_child(i)
			if pl != null and pl.has_method("refresh_ability_cooldowns"):
				pl.call("refresh_ability_cooldowns")
	callout_changed.emit("TEMPORAL OVERLOAD! EXPOSED (+45% DMG) · ABILITIES REFRESHED", COL_GOLD, 3.2)
	if _pending_p3_mirage:
		_pending_p3_mirage = false
		_mirage_delay_timer = 3.0


func on_boss_phase_changed(boss: EnemySphere, new_phase: int) -> void:
	if not _active or boss != _boss:
		return
	_current_phase = new_phase

	match _boss_arch_id:
		ArchetypeScript.ArchetypeId.BOSS_BLIGHTWEAVER:
			_p1_overgrowth_triggered = true
			if new_phase == 2:
				_start_overgrowth_phase(3, 2, 10, 100.0 * _prog_mult)
			else:
				_start_overgrowth_phase(4, 2, 12, 110.0 * _prog_mult)

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
			_p1_horology_triggered = true
			if new_phase == 2:
				_start_horology_sequence([
					_make_circle_step(2.6, 26.0, 4.4),
					_make_circle_step(2.35, 26.0, 4.2)
				], false)
			else:
				_start_horology_sequence([
					_make_wedge_step(2.2, 28.0, 29.0),
					_make_circle_step(2.35, 28.0, 4.2),
					_make_circle_step(2.15, 28.0, 4.0)
				], true)

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


func notify_multi_clock_cast(telegraph_s: float) -> void:
	if _active and _boss_arch_id == ArchetypeScript.ArchetypeId.BOSS_CHRONOMANCER:
		callout_changed.emit("TEMPORAL ZONES — STEP INTO A GOLDEN SAFE WEDGE OR CLEAR OUT!", COL_GOLD, telegraph_s)


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
	prop.vine_spawn_requested.connect(_on_vine_spawn_requested)
	prop.configure(kind, pos, _boss, _players_root, hp, anchor_idx)
	_props.append(prop)
	return prop


func _on_prop_destroyed(prop: BossMechanicProp, was_player_cleared: bool) -> void:
	_props.erase(prop)
	if not _active or _boss == null or not is_instance_valid(_boss) or _boss._is_dying:
		return

	match prop.prop_kind:
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
