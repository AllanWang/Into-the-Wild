class_name ArenaEncounterManager
extends Node3D

## Manages Shape of Dreams-style per-section combat lockdowns:
## - Keeps Spawn Sanctuary (Area 0) unlocked and peaceful.
## - Detects when a player steps inside an unvisited arena, seals its connected bridges
##   with pooled 3D VineBarriers, telegraphs & spawns pooled Sphere Enemies ONLY in that section,
##   and retracts the vines permanently once all enemies in that section are defeated.

const NodePoolScript = preload("res://scripts/node_pool.gd")
const AreaPresetScript = preload("res://world/area_preset.gd")
const PlainsGraphScript = preload("res://world/plains_graph.gd")
const ArchetypeScript = preload("res://enemies/enemy_archetype_data.gd")

const ENEMY_SCENE: PackedScene = preload("res://enemies/enemy_sphere.tscn")
const TELEGRAPH_SCENE: PackedScene = preload("res://world/spawn_telegraph.tscn")
const BARRIER_SCENE: PackedScene = preload("res://world/vine_barrier.tscn")
const PEDESTAL_SCENE: PackedScene = preload("res://world/reward_pedestal.tscn")
const HEALING_WELL_SCENE: PackedScene = preload("res://world/healing_well.tscn")
const StagePortalScript = preload("res://world/stage_portal.gd")
const DroppedItemScript = preload("res://world/dropped_item.gd")

enum RoomState {
	UNVISITED,
	LOCKED_COMBAT,
	CLEARED
}

signal encounter_started(area_idx: int, area_name: String, wave_idx: int, total_waves: int, total_enemies: int)
signal wave_incoming(area_idx: int, area_name: String, next_wave_idx: int, total_waves: int)
signal wave_started(area_idx: int, area_name: String, wave_idx: int, total_waves: int, total_enemies: int)
signal encounter_progress_changed(area_idx: int, wave_idx: int, total_waves: int, remaining_enemies: int, total_enemies: int)
signal encounter_cleared(area_idx: int, area_name: String)
signal encounters_reset()
signal reward_pedestal_interacted(pedestal: Node3D, player_node: Node)
signal dropped_item_interacted(drop_node: Node3D, player_node: Node)
signal stage_portal_entered(player_node: Node)

@export var players_container: Node3D
@export var entry_inset_margin: float = 3.6
@export var waves_per_arena: int = 3
@export var inter_wave_delay: float = 0.65

var _enemy_pool: NodePool = null
var _telegraph_pool: NodePool = null
var _barrier_pool: NodePool = null
var _pedestal_pool: NodePool = null
var _well_pool: NodePool = null
var _stage_portal: Node3D = null
var _dropped_items: Array[Node3D] = []
var _drop_angle_cursor: int = 0

var _graph: PlainsGraph = null
var _room_states: Dictionary = {}          # area_idx -> RoomState
var _area_triggers: Dictionary = {}        # area_idx -> Array[PackedVector2Array]
var _area_trigger_aabbs: Dictionary = {}   # area_idx -> Rect2
var _area_gates: Dictionary = {}           # area_idx -> Array[Dictionary]

var _locked_area_idx: int = -1
var _current_wave_idx: int = 0
var _total_waves_in_room: int = 3
var _waiting_for_next_wave: bool = false
var _next_wave_delay_timer: float = 0.0
var _arenas_cleared_count: int = 0
var _total_wave_enemies: int = 0
var _remaining_enemies: int = 0
var _next_enemy_id: int = 1
var _active_barriers: Array[VineBarrier] = []
var _check_accum: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_setup_pools()


func _setup_pools() -> void:
	if _enemy_pool != null:
		return

	_enemy_pool = NodePoolScript.new()
	_enemy_pool.name = "EnemyPool"
	_enemy_pool.scene = ENEMY_SCENE
	_enemy_pool.initial_size = 18
	_enemy_pool.max_size = 64
	_enemy_pool.can_grow = true
	add_child(_enemy_pool)

	_telegraph_pool = NodePoolScript.new()
	_telegraph_pool.name = "TelegraphPool"
	_telegraph_pool.scene = TELEGRAPH_SCENE
	_telegraph_pool.initial_size = 12
	_telegraph_pool.max_size = 32
	_telegraph_pool.can_grow = true
	add_child(_telegraph_pool)

	_barrier_pool = NodePoolScript.new()
	_barrier_pool.name = "BarrierPool"
	_barrier_pool.scene = BARRIER_SCENE
	_barrier_pool.initial_size = 8
	_barrier_pool.max_size = 24
	_barrier_pool.can_grow = true
	add_child(_barrier_pool)

	_pedestal_pool = NodePoolScript.new()
	_pedestal_pool.name = "PedestalPool"
	_pedestal_pool.scene = PEDESTAL_SCENE
	_pedestal_pool.initial_size = 4
	_pedestal_pool.max_size = 20
	_pedestal_pool.can_grow = true
	add_child(_pedestal_pool)

	_well_pool = NodePoolScript.new()
	_well_pool.name = "HealingWellPool"
	_well_pool.scene = HEALING_WELL_SCENE
	_well_pool.initial_size = 3
	_well_pool.max_size = 8
	_well_pool.can_grow = true
	add_child(_well_pool)

	_stage_portal = StagePortalScript.new()
	_stage_portal.name = "StagePortal"
	add_child(_stage_portal)
	if _stage_portal.has_signal("portal_activated") and not _stage_portal.is_connected("portal_activated", _on_stage_portal_activated):
		_stage_portal.connect("portal_activated", _on_stage_portal_activated)

	for i in range(8):
		_create_pooled_dropped_item(i)


func _create_pooled_dropped_item(idx: int) -> Node3D:
	var d_item: Node3D = DroppedItemScript.new() as Node3D
	d_item.name = "DroppedItem_%d" % idx
	add_child(d_item)
	if d_item.has_signal("dropped_item_interacted") and not d_item.is_connected("dropped_item_interacted", _on_dropped_item_interacted):
		d_item.connect("dropped_item_interacted", _on_dropped_item_interacted)
	if d_item.has_method("deactivate"):
		d_item.call("deactivate")
	_dropped_items.append(d_item)
	return d_item


func _acquire_dropped_item() -> Node3D:
	for d in _dropped_items:
		if d != null and is_instance_valid(d) and d.has_method("is_available") and bool(d.call("is_available")):
			return d
	return _create_pooled_dropped_item(_dropped_items.size())


func _on_dropped_item_interacted(drop_node: Node3D, player_node: Node) -> void:
	dropped_item_interacted.emit(drop_node, player_node)


func spawn_dropped_item(category: String, item_id: int, origin_pos: Vector3) -> Node3D:
	if item_id <= 0 or category.is_empty():
		return null
	_setup_pools()
	var drop_node: Node3D = _acquire_dropped_item()
	if drop_node == null:
		return null
	var target_pos: Vector3 = _find_clear_drop_position(origin_pos)
	if drop_node.has_method("activate_drop"):
		drop_node.call("activate_drop", category, item_id, origin_pos, target_pos, players_container)
	return drop_node


func _find_clear_drop_position(origin_pos: Vector3) -> Vector3:
	var origin_2d := Vector2(origin_pos.x, origin_pos.z)
	var radii: Array[float] = [1.55, 2.25, 2.95]
	var golden_step: float = 2.39996323
	for r in radii:
		for step_i in range(10):
			var ang: float = float(_drop_angle_cursor + step_i) * golden_step
			var dir := Vector2(cos(ang), sin(ang))
			var cand_2d: Vector2 = origin_2d + dir * r
			# Must stay on dry land with shoreline margin (and away from Spawn Sanctuary pond center)
			if _raycast_nearest_shoreline(origin_2d, dir, r + 1.0) != null:
				continue
			if cand_2d.length_squared() < 18.0:
				continue
			if not _is_clear_of_interactables(cand_2d):
				continue
			_drop_angle_cursor = (_drop_angle_cursor + step_i + 1) % 64
			return Vector3(cand_2d.x, 0.0, cand_2d.y)

	# Fallback: step slightly south-east of player
	var fallback_ang: float = float(_drop_angle_cursor) * golden_step
	_drop_angle_cursor = (_drop_angle_cursor + 1) % 64
	return Vector3(origin_2d.x + cos(fallback_ang) * 1.4, 0.0, origin_2d.y + sin(fallback_ang) * 1.4)


func _is_clear_of_interactables(cand_2d: Vector2) -> bool:
	if _pedestal_pool != null:
		for ped_n in _pedestal_pool.get_children():
			var ped3d: Node3D = ped_n as Node3D
			if ped3d != null and ped3d.visible:
				if Vector2(ped3d.global_position.x, ped3d.global_position.z).distance_squared_to(cand_2d) < 4.4:
					return false
	if _stage_portal != null and _stage_portal.visible:
		if Vector2(_stage_portal.global_position.x, _stage_portal.global_position.z).distance_squared_to(cand_2d) < 6.2:
			return false
	if _well_pool != null:
		for well_n in _well_pool.get_children():
			var well3d: Node3D = well_n as Node3D
			if well3d != null and well3d.visible:
				if Vector2(well3d.global_position.x, well3d.global_position.z).distance_squared_to(cand_2d) < 4.4:
					return false
	for d_n in _dropped_items:
		if d_n != null and is_instance_valid(d_n) and d_n.visible:
			if Vector2(d_n.global_position.x, d_n.global_position.z).distance_squared_to(cand_2d) < 2.1:
				return false
	return true


func is_nearest_interactable(candidate: Node3D, player_node: Node3D, max_radius: float) -> bool:
	if candidate == null or player_node == null:
		return false
	var px: float = player_node.global_position.x
	var pz: float = player_node.global_position.z
	var cdx: float = px - candidate.global_position.x
	var cdz: float = pz - candidate.global_position.z
	var cand_d2: float = cdx * cdx + cdz * cdz
	if cand_d2 > max_radius * max_radius:
		return false

	if _pedestal_pool != null:
		for ped_n in _pedestal_pool.get_children():
			var ped3d: Node3D = ped_n as Node3D
			if ped3d == null or ped3d == candidate or not ped3d.visible:
				continue
			var dx: float = px - ped3d.global_position.x
			var dz: float = pz - ped3d.global_position.z
			var d2: float = dx * dx + dz * dz
			if d2 <= 3.1 * 3.1 and d2 + 0.0001 < cand_d2:
				return false

	if _stage_portal != null and _stage_portal != candidate and _stage_portal.visible:
		var pdx: float = px - _stage_portal.global_position.x
		var pdz: float = pz - _stage_portal.global_position.z
		var pd2: float = pdx * pdx + pdz * pdz
		if pd2 <= 3.1 * 3.1 and pd2 + 0.0001 < cand_d2:
			return false

	for d_n in _dropped_items:
		var d3d: Node3D = d_n as Node3D
		if d3d == null or d3d == candidate or not is_instance_valid(d3d) or not d3d.visible:
			continue
		if bool(d3d.get("_consuming")) or float(d3d.get("_pickup_grace")) > 0.0:
			continue
		var ddx: float = px - d3d.global_position.x
		var ddz: float = pz - d3d.global_position.z
		var dd2: float = ddx * ddx + ddz * ddz
		if dd2 <= 2.45 * 2.45 and dd2 + 0.0001 < cand_d2:
			return false

	if _well_pool != null and not is_encounter_active():
		for well_n in _well_pool.get_children():
			var well3d: Node3D = well_n as Node3D
			if well3d == null or well3d == candidate or not well3d.visible:
				continue
			if int(well3d.get("_charges_left")) <= 0:
				continue
			var wdx: float = px - well3d.global_position.x
			var wdz: float = pz - well3d.global_position.z
			var wd2: float = wdx * wdx + wdz * wdz
			if wd2 <= 2.9 * 2.9 and wd2 + 0.0001 < cand_d2:
				return false

	return true


func _on_stage_portal_activated(player_node: Node) -> void:
	stage_portal_entered.emit(player_node)


func _spawn_reward_pedestal_at(world_pos: Vector3, seed_hint: int = 0) -> void:
	if _pedestal_pool == null:
		return
	var ped: Node3D = _pedestal_pool.acquire() as Node3D
	if ped == null:
		return
	if ped.has_signal("pedestal_interacted") and not ped.is_connected("pedestal_interacted", _on_pedestal_interacted):
		ped.connect("pedestal_interacted", _on_pedestal_interacted)
	if ped.has_method("activate_pedestal"):
		ped.call("activate_pedestal", world_pos, players_container, seed_hint)


func _on_pedestal_interacted(pedestal: Node3D, player_node: Node) -> void:
	reward_pedestal_interacted.emit(pedestal, player_node)


## Rebuilds room state tables, inset trigger zones, and bridge gate anchors for a generated graph
func setup_for_graph(graph: PlainsGraph, map_seed: int = 0) -> void:
	_setup_pools()
	reset_active_encounter()
	if _pedestal_pool:
		_pedestal_pool.release_all()
	if _well_pool:
		_well_pool.release_all()
	if _stage_portal and _stage_portal.has_method("deactivate"):
		_stage_portal.call("deactivate")
	for d_item in _dropped_items:
		if d_item != null and is_instance_valid(d_item) and d_item.has_method("deactivate"):
			d_item.call("deactivate")
	_drop_angle_cursor = 0

	_graph = graph
	_arenas_cleared_count = 0
	_room_states.clear()
	_area_triggers.clear()
	_area_trigger_aabbs.clear()
	_area_gates.clear()

	if _graph == null or _graph.areas.is_empty():
		return

	if map_seed > 0:
		_rng.seed = map_seed ^ 0x5A17C3
	else:
		_rng.randomize()

	var outer_is_cw: bool = bool(_graph.get_meta("outer_is_cw", false))
	var unit_sq: PackedVector2Array = PlainsGraphScript._ensure_winding(
		PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 4), Vector2(0, 4)]),
		outer_is_cw
	)
	var test_grow: Array[PackedVector2Array] = Geometry2D.offset_polygon(unit_sq, 1.0, Geometry2D.JOIN_MITER)
	var grow_rect: Rect2 = PlainsGraphScript._poly_aabb(test_grow[0]) if not test_grow.is_empty() else Rect2(0, 0, 4, 4)
	var expand_sign: float = 1.0 if grow_rect.size.x > 4.5 else -1.0

	for area in _graph.areas:
		if area.index == _graph.spawn_index:
			_room_states[area.index] = RoomState.CLEARED
		else:
			_room_states[area.index] = RoomState.UNVISITED

		_area_gates[area.index] = []

		# Erode arena polygon inward by `entry_inset_margin` so lockdown only fires
		# once the player is comfortably inside the room past any bridge throat
		var norm_poly: PackedVector2Array = PlainsGraphScript._ensure_winding(area.polygon, outer_is_cw)
		var inset_polys: Array[PackedVector2Array] = Geometry2D.offset_polygon(
			norm_poly, -expand_sign * entry_inset_margin, Geometry2D.JOIN_ROUND
		)
		var valid_insets: Array[PackedVector2Array] = []
		for ip in inset_polys:
			if ip.size() >= 3 and Geometry2D.is_polygon_clockwise(ip) == outer_is_cw:
				valid_insets.append(ip)
		if valid_insets.is_empty():
			valid_insets.append(norm_poly)

		_area_triggers[area.index] = valid_insets
		_area_trigger_aabbs[area.index] = _combined_aabb(valid_insets)

	# Precompute exact bridge mouth gate transforms for every room's outgoing paths
	for path in _graph.paths:
		_register_gate_for_endpoint(path.from_idx, path.to_idx, path.width)
		_register_gate_for_endpoint(path.to_idx, path.from_idx, path.width)

	# Spawn a Starter Upgrade Pedestal inside Spawn Sanctuary on meadow grass beside player spawn
	if _graph.spawn_index >= 0 and _graph.spawn_index < _graph.areas.size():
		var spawn_area: PlainsGraph.AreaData = _graph.areas[_graph.spawn_index]
		var starter_pos := Vector3(spawn_area.center.x + 2.4, 0.0, spawn_area.center.y + 5.8)
		_spawn_reward_pedestal_at(starter_pos, map_seed ^ 0x101)

	# Spawn infrequent persistent Healing Wells (1 every ~5 rooms, preferring Side Shrines & Hubs)
	_spawn_infrequent_healing_wells()


func _spawn_infrequent_healing_wells() -> void:
	if _graph == null or _well_pool == null:
		return
	var target_count: int = clampi(int(round(float(_graph.areas.size()) / 5.0)), 1, 3)
	var priority_shrines: Array[PlainsGraph.AreaData] = []
	var fallback_rooms: Array[PlainsGraph.AreaData] = []

	for area in _graph.areas:
		if area.index == _graph.spawn_index or area.index == _graph.goal_index:
			continue
		if area.role == AreaPresetScript.RoomRole.DEADEND or area.role == AreaPresetScript.RoomRole.HUB:
			priority_shrines.append(area)
		elif area.tier >= 1:
			fallback_rooms.append(area)

	var used_tiers: Array[int] = []
	var chosen_areas: Array[PlainsGraph.AreaData] = []

	for s_area in priority_shrines:
		if chosen_areas.size() >= target_count:
			break
		if not used_tiers.has(s_area.tier):
			chosen_areas.append(s_area)
			used_tiers.append(s_area.tier)

	for f_area in fallback_rooms:
		if chosen_areas.size() >= target_count:
			break
		if not used_tiers.has(f_area.tier):
			chosen_areas.append(f_area)
			used_tiers.append(f_area.tier)

	for w_area in chosen_areas:
		var well: Node3D = _well_pool.acquire() as Node3D
		if well and well.has_method("activate_well"):
			# Offset 3.4m from room center so cleared Upgrade Pedestals never overlap the Healing Well
			var well_pos := Vector3(w_area.center.x - 3.4, 0.0, w_area.center.y + 2.0)
			well.call("activate_well", w_area.index, well_pos, players_container, self, 2)


## Anchors each VineBarrier right near the arena-side edge of the bridge and raycasts perpendicular
## against the actual filleted landmass shorelines (outer_contours + hole_contours) so every vine
## wall centers dead-on the bridge and seals 100% from water wall to water wall.
func _register_gate_for_endpoint(area_idx: int, neighbor_idx: int, bridge_w: float) -> void:
	if _graph == null:
		return
	var area: PlainsGraph.AreaData = _graph.areas[area_idx]
	var neighbor: PlainsGraph.AreaData = _graph.areas[neighbor_idx]
	var delta: Vector2 = neighbor.center - area.center
	var dist: float = delta.length()
	if dist < 0.1:
		return

	var dir: Vector2 = delta / dist
	var perp := Vector2(-dir.y, dir.x)
	var exit_pt: Vector2 = AreaPresetScript._ray_polygon_exit(area.center, dir, area.polygon, dist * 0.4)
	var neighbor_entry: Vector2 = AreaPresetScript._ray_polygon_exit(neighbor.center, -dir, neighbor.polygon, dist * 0.4)
	var bridge_gap: float = maxf(4.0, (neighbor_entry - exit_pt).dot(dir))
	var max_probe_d: float = minf(12.5, bridge_gap * 0.48)

	var best_center: Vector2 = exit_pt + dir * minf(2.8, max_probe_d)
	var best_span: float = bridge_w + 2.6
	var best_width_found: float = INF

	# Walk from the arena polygon exit onto the bridge (past cruciform alcoves & throat fillets)
	# and lock right onto the first clean bridge-edge cross-section bounded by both shorelines!
	var sample_offsets: Array[float] = [2.4, 3.2, 4.2, 5.4, 6.8, 8.2, 9.6, 11.2, 12.5]
	for raw_off in sample_offsets:
		if raw_off > max_probe_d + 0.25:
			break
		var d: float = minf(raw_off, max_probe_d)
		var probe: Vector2 = exit_pt + dir * d
		var left_hit: Variant = _raycast_nearest_shoreline(probe, perp, 24.0)
		var right_hit: Variant = _raycast_nearest_shoreline(probe, -perp, 24.0)
		if left_hit != null and right_hit != null:
			var l_pt: Vector2 = left_hit as Vector2
			var r_pt: Vector2 = right_hit as Vector2
			var bank_w: float = l_pt.distance_to(r_pt)
			if bank_w >= bridge_w * 0.78 and bank_w < best_width_found:
				best_width_found = bank_w
				best_center = (l_pt + r_pt) * 0.5
				best_span = bank_w + 1.2
				# Stop immediately once we hit the true bridge edge past any arena wing/fillet
				if bank_w <= bridge_w + 1.8:
					break

	var gates_arr: Array = _area_gates[area_idx]
	# Deduplicate if two bridges ever share the same mouth within 3.2m
	for existing_var in gates_arr:
		var eg: Dictionary = existing_var as Dictionary
		var epos: Vector3 = eg["position"] as Vector3
		if Vector2(epos.x, epos.z).distance_to(best_center) < 3.2:
			eg["span"] = maxf(float(eg["span"]), best_span)
			return

	gates_arr.append({
		"position": Vector3(best_center.x, 0.0, best_center.y),
		"dir_2d": dir,
		"span": best_span
	})


func _raycast_nearest_shoreline(origin: Vector2, ray_dir: Vector2, max_dist: float) -> Variant:
	if _graph == null:
		return null
	var ray_end: Vector2 = origin + ray_dir * max_dist
	var best_d2: float = INF
	var best_pt: Vector2 = Vector2.ZERO
	var found: bool = false

	for contour in _graph.merged_polygons:
		var n: int = contour.size()
		if n < 3:
			continue
		for i in range(n):
			var p1: Vector2 = contour[i]
			var p2: Vector2 = contour[(i + 1) % n]
			var hit: Variant = Geometry2D.segment_intersects_segment(origin, ray_end, p1, p2)
			if hit != null:
				var hpt: Vector2 = hit as Vector2
				var d2: float = origin.distance_squared_to(hpt)
				if d2 > 0.001 and d2 < best_d2:
					best_d2 = d2
					best_pt = hpt
					found = true

	if found:
		return best_pt
	return null


## Releases all active enemies, telegraphs, and vine barriers back to their pools
func reset_active_encounter(mark_current_cleared: bool = false) -> void:
	if _locked_area_idx >= 0:
		if mark_current_cleared:
			_room_states[_locked_area_idx] = RoomState.CLEARED
			_arenas_cleared_count += 1
		else:
			_room_states[_locked_area_idx] = RoomState.UNVISITED
	_locked_area_idx = -1
	_current_wave_idx = 0
	_total_waves_in_room = maxi(1, waves_per_arena)
	_waiting_for_next_wave = false
	_next_wave_delay_timer = 0.0
	_remaining_enemies = 0
	_total_wave_enemies = 0
	_active_barriers.clear()

	if _telegraph_pool:
		_telegraph_pool.release_all()
	if _enemy_pool:
		_enemy_pool.release_all()
	if _barrier_pool:
		_barrier_pool.release_all()

	encounters_reset.emit()


func is_encounter_active() -> bool:
	return _locked_area_idx >= 0


func _physics_process(delta: float) -> void:
	if _graph == null:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	if _locked_area_idx >= 0:
		if _waiting_for_next_wave:
			_next_wave_delay_timer -= delta
			if _next_wave_delay_timer <= 0.0:
				_waiting_for_next_wave = false
				_advance_to_next_wave()
		return

	_check_accum += delta
	if _check_accum < 0.08:
		return
	_check_accum = 0.0

	_check_player_arena_entry()


func _check_player_arena_entry() -> void:
	if players_container == null or not is_instance_valid(players_container):
		return

	var p_count: int = players_container.get_child_count()
	for i in range(p_count):
		var p3d: Node3D = players_container.get_child(i) as Node3D
		if p3d == null or not p3d.visible:
			continue
		var pt2d := Vector2(p3d.global_position.x, p3d.global_position.z)

		for area in _graph.areas:
			var idx: int = area.index
			if _room_states.get(idx, RoomState.CLEARED) != RoomState.UNVISITED:
				continue
			var aabb: Rect2 = _area_trigger_aabbs.get(idx, Rect2())
			if not aabb.has_point(pt2d):
				continue
			var trig_polys: Array = _area_triggers.get(idx, [])
			for tp in trig_polys:
				if Geometry2D.is_point_in_polygon(pt2d, tp as PackedVector2Array):
					_trigger_arena_lockdown(idx)
					return


func _trigger_arena_lockdown(area_idx: int) -> void:
	if _graph == null or area_idx < 0 or area_idx >= _graph.areas.size():
		return

	var area: PlainsGraph.AreaData = _graph.areas[area_idx]
	var total_waves: int = maxi(1, waves_per_arena)
	var wave_1_specs: Array[Dictionary] = _build_wave_manifest(area, 1, total_waves)
	if wave_1_specs.is_empty():
		_room_states[area_idx] = RoomState.CLEARED
		return

	# Pull any co-op peer outside the arena safely inside before sealing bridges
	_pull_outside_peers_into_arena(area)

	if multiplayer.has_multiplayer_peer():
		_rpc_start_encounter.rpc(area_idx, total_waves, wave_1_specs)
	else:
		_rpc_start_encounter(area_idx, total_waves, wave_1_specs)


@rpc("authority", "call_local", "reliable")
func _rpc_start_encounter(area_idx: int, total_waves: int, wave_specs: Array) -> void:
	if _graph == null or area_idx < 0 or area_idx >= _graph.areas.size():
		return

	_room_states[area_idx] = RoomState.LOCKED_COMBAT
	_locked_area_idx = area_idx
	_current_wave_idx = 1
	_total_waves_in_room = maxi(1, total_waves)
	_waiting_for_next_wave = false
	_next_wave_delay_timer = 0.0
	_active_barriers.clear()

	# 1. Seal all connected bridges on this arena with pooled VineBarriers
	var gates: Array = _area_gates.get(area_idx, [])
	for g_var in gates:
		var g: Dictionary = g_var as Dictionary
		var barrier: VineBarrier = _barrier_pool.acquire() as VineBarrier
		if barrier:
			barrier.activate_barrier(
				area_idx,
				g["position"] as Vector3,
				g["dir_2d"] as Vector2,
				float(g["span"])
			)
			_active_barriers.append(barrier)

	# 2. Spawn Wave 1 ground telegraph rings ONLY inside this section
	_begin_wave_telegraphs(area_idx, wave_specs)

	var label: String = _role_title(_graph.areas[area_idx].role)
	encounter_started.emit(area_idx, label, _current_wave_idx, _total_waves_in_room, _total_wave_enemies)
	encounter_progress_changed.emit(area_idx, _current_wave_idx, _total_waves_in_room, _remaining_enemies, _total_wave_enemies)


func _advance_to_next_wave() -> void:
	if _graph == null or _locked_area_idx < 0 or _locked_area_idx >= _graph.areas.size():
		return
	var next_wave: int = _current_wave_idx + 1
	var area: PlainsGraph.AreaData = _graph.areas[_locked_area_idx]
	var next_specs: Array[Dictionary] = _build_wave_manifest(area, next_wave, _total_waves_in_room)
	if next_specs.is_empty():
		_arenas_cleared_count += 1
		if multiplayer.has_multiplayer_peer():
			_rpc_clear_encounter.rpc(_locked_area_idx)
		else:
			_rpc_clear_encounter(_locked_area_idx)
		return

	if multiplayer.has_multiplayer_peer():
		_rpc_spawn_wave.rpc(_locked_area_idx, next_wave, _total_waves_in_room, next_specs)
	else:
		_rpc_spawn_wave(_locked_area_idx, next_wave, _total_waves_in_room, next_specs)


@rpc("authority", "call_local", "reliable")
func _rpc_notify_wave_incoming(area_idx: int, next_wave_idx: int, total_waves: int) -> void:
	if area_idx != _locked_area_idx:
		return
	var label: String = _role_title(_graph.areas[area_idx].role) if (_graph and area_idx < _graph.areas.size()) else "Combat Arena"
	wave_incoming.emit(area_idx, label, next_wave_idx, total_waves)


@rpc("authority", "call_local", "reliable")
func _rpc_spawn_wave(area_idx: int, wave_idx: int, total_waves: int, wave_specs: Array) -> void:
	if _graph == null or area_idx != _locked_area_idx:
		return

	_current_wave_idx = wave_idx
	_total_waves_in_room = maxi(1, total_waves)
	_waiting_for_next_wave = false
	_next_wave_delay_timer = 0.0

	_begin_wave_telegraphs(area_idx, wave_specs)

	var label: String = _role_title(_graph.areas[area_idx].role)
	wave_started.emit(area_idx, label, _current_wave_idx, _total_waves_in_room, _total_wave_enemies)
	encounter_progress_changed.emit(area_idx, _current_wave_idx, _total_waves_in_room, _remaining_enemies, _total_wave_enemies)


func _begin_wave_telegraphs(area_idx: int, wave_specs: Array) -> void:
	_total_wave_enemies = wave_specs.size()
	_remaining_enemies = _total_wave_enemies

	for spec_var in wave_specs:
		var spec: Dictionary = spec_var as Dictionary
		var eid: int = int(spec["id"])
		var arch_id: int = int(spec["arch"])
		var spos: Vector3 = spec["pos"] as Vector3
		var arch_data: EnemyArchetypeData = ArchetypeScript.get_archetype(arch_id)

		var telegraph: SpawnTelegraph = _telegraph_pool.acquire() as SpawnTelegraph
		if telegraph:
			if not telegraph.telegraph_completed.is_connected(_on_telegraph_completed):
				telegraph.telegraph_completed.connect(_on_telegraph_completed)
			telegraph.activate(eid, area_idx, arch_id, spos, arch_data.radius, 0.55)
		else:
			_spawn_pooled_enemy(eid, area_idx, arch_id, spos)


func _on_telegraph_completed(
	p_enemy_id: int,
	p_area_idx: int,
	p_arch_id: int,
	p_spawn_pos: Vector3
) -> void:
	if p_area_idx != _locked_area_idx:
		return
	_spawn_pooled_enemy(p_enemy_id, p_area_idx, p_arch_id, p_spawn_pos)


func _spawn_pooled_enemy(
	p_enemy_id: int,
	p_area_idx: int,
	p_arch_id: int,
	p_spawn_pos: Vector3
) -> void:
	var enemy: EnemySphere = _enemy_pool.acquire() as EnemySphere
	if enemy == null:
		return
	if not enemy.defeated.is_connected(_on_enemy_defeated):
		enemy.defeated.connect(_on_enemy_defeated)
	enemy.activate(p_enemy_id, p_area_idx, p_arch_id, p_spawn_pos, players_container)


func _on_enemy_defeated(_enemy_id: int, p_area_idx: int) -> void:
	if p_area_idx != _locked_area_idx:
		return

	_remaining_enemies = maxi(0, _remaining_enemies - 1)
	encounter_progress_changed.emit(p_area_idx, _current_wave_idx, _total_waves_in_room, _remaining_enemies, _total_wave_enemies)

	if _remaining_enemies <= 0 and not _waiting_for_next_wave:
		if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
			return

		if _current_wave_idx < _total_waves_in_room:
			_waiting_for_next_wave = true
			_next_wave_delay_timer = maxf(0.15, inter_wave_delay)
			if multiplayer.has_multiplayer_peer():
				_rpc_notify_wave_incoming.rpc(p_area_idx, _current_wave_idx + 1, _total_waves_in_room)
			else:
				_rpc_notify_wave_incoming(p_area_idx, _current_wave_idx + 1, _total_waves_in_room)
		else:
			_arenas_cleared_count += 1
			if multiplayer.has_multiplayer_peer():
				_rpc_clear_encounter.rpc(p_area_idx)
			else:
				_rpc_clear_encounter(p_area_idx)


@rpc("authority", "call_local", "reliable")
func _rpc_clear_encounter(area_idx: int) -> void:
	if _locked_area_idx != area_idx and _room_states.get(area_idx, -1) == RoomState.CLEARED:
		return

	_room_states[area_idx] = RoomState.CLEARED
	_locked_area_idx = -1
	_current_wave_idx = 0
	_waiting_for_next_wave = false
	_next_wave_delay_timer = 0.0
	_remaining_enemies = 0

	for barrier in _active_barriers:
		if barrier and is_instance_valid(barrier):
			barrier.retract_barrier()
	_active_barriers.clear()

	if _graph and area_idx >= 0 and area_idx < _graph.areas.size():
		var c_area: PlainsGraph.AreaData = _graph.areas[area_idx]
		var is_final_stage: bool = (area_idx == _graph.goal_index) or (c_area.role == AreaPresetScript.RoomRole.BOSS)
		if is_final_stage:
			# Final Stage (Boss Citadel): drop 3 Upgrade Pedestals in an arc + unlock the Rift Portal to the next map
			_spawn_reward_pedestal_at(Vector3(c_area.center.x - 4.2, 0.0, c_area.center.y + 2.4), area_idx * 7919 + 11)
			_spawn_reward_pedestal_at(Vector3(c_area.center.x, 0.0, c_area.center.y + 3.8), area_idx * 7919 + 29)
			_spawn_reward_pedestal_at(Vector3(c_area.center.x + 4.2, 0.0, c_area.center.y + 2.4), area_idx * 7919 + 47)
			if _stage_portal and _stage_portal.has_method("activate_portal"):
				_stage_portal.call("activate_portal", Vector3(c_area.center.x, 0.0, c_area.center.y - 3.2), players_container)
		else:
			_spawn_reward_pedestal_at(Vector3(c_area.center.x, 0.0, c_area.center.y), area_idx * 7919)

	var label: String = _role_title(_graph.areas[area_idx].role) if (_graph and area_idx < _graph.areas.size()) else "Arena"
	encounter_cleared.emit(area_idx, label)


func _build_wave_manifest(area: PlainsGraph.AreaData, wave_idx: int, total_waves: int) -> Array[Dictionary]:
	# Escalate second & third waves as players advance into deeper tiers / additional cleared areas
	var progression_stage: int = maxi(1, maxi(area.tier, _arenas_cleared_count + 1))
	var stage_bonus: int = mini(2, maxi(0, progression_stage - 1))
	var is_final_wave: bool = (wave_idx >= total_waves)

	var archetypes: Array[int] = []
	match area.role:
		AreaPresetScript.RoomRole.DEADEND:
			if wave_idx == 1:
				for _i in range(2 + mini(1, stage_bonus)):
					archetypes.append(ArchetypeScript.ArchetypeId.CHASER)
			elif not is_final_wave:
				for _i in range(3):
					archetypes.append(ArchetypeScript.ArchetypeId.CHASER)
				if stage_bonus >= 1:
					archetypes.append(ArchetypeScript.ArchetypeId.BRUISER)
			else:
				for _i in range(3 + mini(1, stage_bonus)):
					archetypes.append(ArchetypeScript.ArchetypeId.CHASER)
				archetypes.append(ArchetypeScript.ArchetypeId.BRUISER)

		AreaPresetScript.RoomRole.ELITE:
			if wave_idx == 1:
				for _i in range(4):
					archetypes.append(ArchetypeScript.ArchetypeId.CHASER)
				archetypes.append(ArchetypeScript.ArchetypeId.BRUISER)
			elif not is_final_wave:
				for _i in range(4 + stage_bonus):
					archetypes.append(ArchetypeScript.ArchetypeId.CHASER)
				for _i in range(2):
					archetypes.append(ArchetypeScript.ArchetypeId.BRUISER)
			else:
				for _i in range(5 + stage_bonus):
					archetypes.append(ArchetypeScript.ArchetypeId.CHASER)
				for _i in range(2 + (1 if stage_bonus >= 2 else 0)):
					archetypes.append(ArchetypeScript.ArchetypeId.BRUISER)

		AreaPresetScript.RoomRole.HUB:
			if wave_idx == 1:
				for _i in range(4):
					archetypes.append(ArchetypeScript.ArchetypeId.CHASER)
			elif not is_final_wave:
				for _i in range(3 + stage_bonus):
					archetypes.append(ArchetypeScript.ArchetypeId.CHASER)
				archetypes.append(ArchetypeScript.ArchetypeId.BRUISER)
			else:
				for _i in range(4 + stage_bonus):
					archetypes.append(ArchetypeScript.ArchetypeId.CHASER)
				for _i in range(2):
					archetypes.append(ArchetypeScript.ArchetypeId.BRUISER)

		AreaPresetScript.RoomRole.BOSS:
			if wave_idx == 1:
				for _i in range(4):
					archetypes.append(ArchetypeScript.ArchetypeId.CHASER)
				archetypes.append(ArchetypeScript.ArchetypeId.BRUISER)
			elif not is_final_wave:
				for _i in range(5):
					archetypes.append(ArchetypeScript.ArchetypeId.CHASER)
				for _i in range(2):
					archetypes.append(ArchetypeScript.ArchetypeId.BRUISER)
			else:
				archetypes.append(ArchetypeScript.ArchetypeId.BOSS)
				for _i in range(2):
					archetypes.append(ArchetypeScript.ArchetypeId.BRUISER)
				for _i in range(4):
					archetypes.append(ArchetypeScript.ArchetypeId.CHASER)

		_:
			# Standard COMBAT arena: 3 waves escalating across both wave index and map progression
			if wave_idx == 1:
				for _i in range(3 + mini(1, stage_bonus)):
					archetypes.append(ArchetypeScript.ArchetypeId.CHASER)
			elif not is_final_wave:
				for _i in range(3 + stage_bonus):
					archetypes.append(ArchetypeScript.ArchetypeId.CHASER)
				if stage_bonus >= 1:
					archetypes.append(ArchetypeScript.ArchetypeId.BRUISER)
			else:
				for _i in range(3 + stage_bonus):
					archetypes.append(ArchetypeScript.ArchetypeId.CHASER)
				for _i in range(1 + mini(1, stage_bonus)):
					archetypes.append(ArchetypeScript.ArchetypeId.BRUISER)

	var chosen_pts: Array[Vector2] = []
	var manifest: Array[Dictionary] = []

	for arch_id in archetypes:
		var pt2d: Vector2 = _sample_safe_spawn_point(area, chosen_pts, arch_id == ArchetypeScript.ArchetypeId.BOSS)
		chosen_pts.append(pt2d)
		var eid: int = _next_enemy_id
		_next_enemy_id += 1
		manifest.append({
			"id": eid,
			"arch": arch_id,
			"pos": Vector3(pt2d.x, 0.0, pt2d.y)
		})

	return manifest


func _sample_safe_spawn_point(
	area: PlainsGraph.AreaData,
	existing_pts: Array[Vector2],
	prefer_center: bool
) -> Vector2:
	if prefer_center and _is_far_from_players(area.center, 4.0):
		return area.center

	var trig_polys: Array = _area_triggers.get(area.index, [])
	var bounds: Rect2 = _area_trigger_aabbs.get(area.index, Rect2(area.center - area.size * 0.35, area.size * 0.7))

	for _attempt in range(40):
		var cand := Vector2(
			_rng.randf_range(bounds.position.x, bounds.position.x + bounds.size.x),
			_rng.randf_range(bounds.position.y, bounds.position.y + bounds.size.y)
		)
		var inside: bool = false
		for tp in trig_polys:
			if Geometry2D.is_point_in_polygon(cand, tp as PackedVector2Array):
				inside = true
				break
		if not inside:
			continue
		if not _is_far_from_players(cand, 4.6):
			continue
		var too_close: bool = false
		for ep in existing_pts:
			if cand.distance_squared_to(ep) < 4.4:
				too_close = true
				break
		if not too_close:
			return cand

	# Fallback along a ring around arena center
	var angle: float = float(existing_pts.size()) * 1.15
	return area.center + Vector2(cos(angle), sin(angle)) * 5.0


func _is_far_from_players(pt2d: Vector2, min_dist: float) -> bool:
	if players_container == null or not is_instance_valid(players_container):
		return true
	var min_sq: float = min_dist * min_dist
	var p_count: int = players_container.get_child_count()
	for i in range(p_count):
		var p3d: Node3D = players_container.get_child(i) as Node3D
		if p3d == null:
			continue
		var pp := Vector2(p3d.global_position.x, p3d.global_position.z)
		if pp.distance_squared_to(pt2d) < min_sq:
			return false
	return true


func _pull_outside_peers_into_arena(area: PlainsGraph.AreaData) -> void:
	if players_container == null or not is_instance_valid(players_container):
		return
	var p_count: int = players_container.get_child_count()
	if p_count < 1:
		return

	for i in range(p_count):
		var p_body: CharacterBody3D = players_container.get_child(i) as CharacterBody3D
		if p_body == null:
			continue
		var pt := Vector2(p_body.global_position.x, p_body.global_position.z)
		if not Geometry2D.is_point_in_polygon(pt, area.polygon):
			p_body.velocity = Vector3.ZERO
			p_body.global_position = Vector3(area.center.x, 0.0, area.center.y)


func _combined_aabb(polys: Array[PackedVector2Array]) -> Rect2:
	if polys.is_empty():
		return Rect2()
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for poly in polys:
		for pt in poly:
			min_p.x = minf(min_p.x, pt.x)
			min_p.y = minf(min_p.y, pt.y)
			max_p.x = maxf(max_p.x, pt.x)
			max_p.y = maxf(max_p.y, pt.y)
	return Rect2(min_p, max_p - min_p)


func _role_title(role: int) -> String:
	match role:
		AreaPresetScript.RoomRole.DEADEND:
			return "Memory Shrine"
		AreaPresetScript.RoomRole.ELITE:
			return "Elite Arena"
		AreaPresetScript.RoomRole.HUB:
			return "Crossroads Arena"
		AreaPresetScript.RoomRole.BOSS:
			return "Boss Citadel"
	return "Combat Arena"
