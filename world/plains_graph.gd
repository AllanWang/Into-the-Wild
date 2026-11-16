class_name PlainsGraph
extends RefCounted

## Shape of Dreams-style planar node-web synthesizer.
## Generates large multi-shape combat arenas arranged across branching & converging tiers,
## connected by narrow grassy causeways, lateral loop bridges, and 1-hop side shrines.

const AreaPresetScript = preload("res://world/area_preset.gd")
const MapPresetConfigScript = preload("res://world/map_preset_config.gd")

class AreaData:
	extends RefCounted
	var index: int = 0
	var tier: int = 0
	var lane: int = 0
	var grid_coord: Vector2i = Vector2i.ZERO
	var center: Vector2 = Vector2.ZERO
	var size: Vector2 = Vector2(30.0, 26.0)
	var role: int = AreaPresetScript.RoomRole.COMBAT
	var shape: int = AreaPresetScript.ArenaShape.ROUNDED_RECT
	var polygon: PackedVector2Array = PackedVector2Array()
	var inner_safe_rect: Rect2 = Rect2()

class PathData:
	extends RefCounted
	var from_idx: int = 0
	var to_idx: int = 0
	var width: float = 5.2
	var is_loop: bool = false
	var polygon: PackedVector2Array = PackedVector2Array()
	var clipped_segments: Array[PackedVector2Array] = []

var preset_name: String = "Standard Web"
var areas: Array[AreaData] = []
var paths: Array[PathData] = []
var spawn_index: int = 0
var goal_index: int = 0

## All merged landmass contours (outer CCW coasts + inner CW water-courtyard holes)
var merged_polygons: Array[PackedVector2Array] = []
var outer_contours: Array[PackedVector2Array] = []
var hole_contours: Array[PackedVector2Array] = []


## Primary entry point using a MapPresetConfig Resource
static func generate_from_preset(
	rng: RandomNumberGenerator,
	preset: MapPresetConfig
) -> PlainsGraph:
	var cfg: MapPresetConfig = preset if preset != null else MapPresetConfigScript.create_preset(
		MapPresetConfigScript.TopologyMode.DREAMSCAPE_WEB
	)
	var graph := PlainsGraph.new()
	graph.preset_name = cfg.preset_name

	var num_tiers: int = maxi(4, cfg.progression_tiers)
	var max_lanes: int = clampi(cfg.max_lanes, 2, 3)
	var lane_step: float = maxf(46.0, cfg.lane_spacing)
	var tier_step: float = maxf(46.0, cfg.tier_spacing)

	# Track area indices per progression tier (ordered left-to-right by X)
	var tier_nodes: Array[Array] = []
	for _t in range(num_tiers):
		tier_nodes.append([])

	# 1. Tier 0: Spawn Sanctuary anchored at world origin (0, 0) for SpawnPond alignment
	var spawn_area: AreaData = _make_area(
		0, 0, 0, Vector2.ZERO,
		AreaPresetScript.RoomRole.SPAWN,
		rng, cfg.arena_scale
	)
	if cfg.enable_spawn_pond:
		spawn_area.size.x = maxf(spawn_area.size.x, 26.0)
		spawn_area.size.y = maxf(spawn_area.size.y, 26.0)
		spawn_area.polygon = AreaPresetScript.build_arena_polygon(spawn_area.center, spawn_area.size, spawn_area.shape)
		spawn_area.inner_safe_rect = AreaPresetScript.get_inner_safe_rect(spawn_area.center, spawn_area.size, spawn_area.shape)
	graph.areas.append(spawn_area)
	tier_nodes[0].append(spawn_area.index)

	# 2. Intermediate Web Tiers (t = 1 .. num_tiers - 2)
	var has_three_lane_tier: bool = false
	for t in range(1, num_tiers - 1):
		var is_pre_boss: bool = (t == num_tiers - 2)
		var lanes_in_tier: Array[float] = []

		if is_pre_boss:
			# Pre-boss convergence: either a single central Hub or twin flanking Gatekeepers
			if rng.randf() < 0.55:
				lanes_in_tier = [0.0]
			else:
				lanes_in_tier = [-0.65, 0.65]
		else:
			var force_three: bool = (max_lanes >= 3 and not has_three_lane_tier and t == maxi(1, floori(float(num_tiers) * 0.5) - 1))
			if force_three or (max_lanes >= 3 and rng.randf() < 0.62):
				lanes_in_tier = [-1.0, 0.0, 1.0]
				has_three_lane_tier = true
			else:
				var pattern_roll: float = rng.randf()
				if pattern_roll < 0.55:
					lanes_in_tier = [-0.85, 0.85]
				elif pattern_roll < 0.78:
					lanes_in_tier = [-1.0, 0.15]
				else:
					lanes_in_tier = [-0.15, 1.0]

		# Pick at most one Elite node in deeper tiers for risk/reward routing
		var elite_slot: int = -1
		if t >= 2 and lanes_in_tier.size() >= 2:
			elite_slot = rng.randi_range(0, lanes_in_tier.size() - 1)

		for l_idx in range(lanes_in_tier.size()):
			var lane_val: float = lanes_in_tier[l_idx]
			var jitter_x: float = rng.randf_range(-cfg.position_jitter, cfg.position_jitter)
			var jitter_z: float = rng.randf_range(-cfg.position_jitter * 0.7, cfg.position_jitter * 0.7)
			var pos := Vector2(lane_val * lane_step + jitter_x, -float(t) * tier_step + jitter_z)

			var role: int = AreaPresetScript.RoomRole.COMBAT
			if is_pre_boss and lanes_in_tier.size() == 1:
				role = AreaPresetScript.RoomRole.HUB
			elif l_idx == elite_slot:
				role = AreaPresetScript.RoomRole.ELITE

			var node_area: AreaData = _make_area(
				graph.areas.size(), t, int(round(lane_val)), pos,
				role, rng, cfg.arena_scale
			)
			graph.areas.append(node_area)
			tier_nodes[t].append(node_area.index)

	# 3. Final Tier (t = num_tiers - 1): Colossal Boss Arena
	var boss_t: int = num_tiers - 1
	var boss_pos := Vector2(
		rng.randf_range(-3.0, 3.0),
		-float(boss_t) * tier_step - 8.0
	)
	var boss_area: AreaData = _make_area(
		graph.areas.size(), boss_t, 0, boss_pos,
		AreaPresetScript.RoomRole.BOSS, rng, cfg.arena_scale
	)
	graph.areas.append(boss_area)
	tier_nodes[boss_t].append(boss_area.index)

	graph.spawn_index = 0
	graph.goal_index = boss_area.index

	# Settle base room positions before evaluating web edge angles & clearances
	_enforce_room_clearance(graph.areas, 14.0)

	# Edge set: Vector2i(min_idx, max_idx) -> is_loop (bool)
	var active_edges: Dictionary = {}
	var optional_loop_candidates: Array[Vector2i] = []

	# 4. Planar Nearest-Lane Web Connections between consecutive tiers
	# Guarantees 100% reachability, 0 crossings, and 0 cross-map 2-lane diagonal highways
	for t in range(num_tiers - 1):
		var curr_tier: Array = tier_nodes[t]
		var next_tier: Array = tier_nodes[t + 1]
		var p: int = curr_tier.size()
		var q: int = next_tier.size()
		if p == 0 or q == 0:
			continue

		for i in range(p):
			var u_idx: int = int(curr_tier[i])
			var ux: float = graph.areas[u_idx].center.x
			var best_j: int = 0
			var best_dx: float = INF
			for j in range(q):
				var vx: float = graph.areas[int(next_tier[j])].center.x
				var dx_abs: float = absf(vx - ux)
				if dx_abs < best_dx:
					best_dx = dx_abs
					best_j = j
			_add_edge(active_edges, u_idx, int(next_tier[best_j]), false)
			if best_j + 1 < q and rng.randf() < 0.45:
				optional_loop_candidates.append(Vector2i(u_idx, int(next_tier[best_j + 1])))

		for j in range(q):
			var v_idx: int = int(next_tier[j])
			var vx: float = graph.areas[v_idx].center.x
			var best_i: int = 0
			var best_dx_b: float = INF
			for i in range(p):
				var ux: float = graph.areas[int(curr_tier[i])].center.x
				var dx_abs_b: float = absf(ux - vx)
				if dx_abs_b < best_dx_b:
					best_dx_b = dx_abs_b
					best_i = i
			_add_edge(active_edges, int(curr_tier[best_i]), v_idx, false)

	# 5. Lateral Cross-Lane & Diagonal Loop Causeways (only accepted when cleanly separated in angle & clearance)
	for t in range(1, num_tiers - 1):
		var row: Array = tier_nodes[t]
		for k in range(row.size() - 1):
			if rng.randf() <= cfg.cross_link_chance:
				optional_loop_candidates.append(Vector2i(row[k], row[k + 1]))

	for cand_edge in optional_loop_candidates:
		if _can_add_clean_web_edge(graph.areas, active_edges, cand_edge.x, cand_edge.y, 0.52):
			_add_edge(active_edges, cand_edge.x, cand_edge.y, true)

	# 6. 1-Hop Side Shrines / Memory Wells sprouting outward from outer web nodes
	var shrines_added: int = 0
	for t in range(1, num_tiers - 1):
		var row: Array = tier_nodes[t]
		if row.is_empty():
			continue

		# Candidate left wing (-X) and right wing (+X)
		var sides: Array[int] = [-1, 1]
		if rng.randf() < 0.5:
			sides = [1, -1]

		for side_sign in sides:
			var force_one: bool = (shrines_added == 0 and t == num_tiers - 2 and cfg.side_shrine_chance > 0.0)
			if not force_one and rng.randf() > cfg.side_shrine_chance:
				continue
			if shrines_added >= 3 and cfg.topology_mode != MapPresetConfigScript.TopologyMode.GRAND_DREAMSCAPE:
				break

			var anchor_idx: int = row[0] if side_sign < 0 else row[row.size() - 1]
			var anchor_area: AreaData = graph.areas[anchor_idx]

			var shrine_size: Vector2 = AreaPresetScript.get_room_size(
				AreaPresetScript.RoomRole.DEADEND, rng, cfg.arena_scale
			)
			var gap: float = rng.randf_range(13.0, 17.0)
			var offset_x: float = float(side_sign) * (anchor_area.size.x * 0.5 + gap + shrine_size.x * 0.5)
			var offset_z: float = rng.randf_range(-8.0, 8.0)
			var candidate_pos: Vector2 = anchor_area.center + Vector2(offset_x, offset_z)

			if _has_clearance(candidate_pos, shrine_size, graph.areas, 14.0):
				var shrine_area := AreaData.new()
				shrine_area.index = graph.areas.size()
				shrine_area.tier = t
				shrine_area.lane = side_sign * 2
				shrine_area.grid_coord = Vector2i(shrine_area.lane, -t)
				shrine_area.center = candidate_pos
				shrine_area.role = AreaPresetScript.RoomRole.DEADEND
				shrine_area.size = shrine_size
				shrine_area.shape = AreaPresetScript.pick_arena_shape(shrine_area.role, rng)
				shrine_area.polygon = AreaPresetScript.build_arena_polygon(
					shrine_area.center, shrine_area.size, shrine_area.shape
				)
				shrine_area.inner_safe_rect = AreaPresetScript.get_inner_safe_rect(
					shrine_area.center, shrine_area.size, shrine_area.shape
				)
				if _can_add_clean_shrine(graph.areas, active_edges, anchor_idx, candidate_pos, 0.45):
					graph.areas.append(shrine_area)
					_add_edge(active_edges, anchor_idx, shrine_area.index, false)
					shrines_added += 1
					break # Max 1 shrine per tier keeps silhouette balanced

	# 7. Guarantee generous water gaps between all rooms before building bridges
	_enforce_room_clearance(graph.areas, 14.0)

	# Determine canonical Clipper2 outer winding & offset sign in Godot's Geometry2D once
	var unit_sq := PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 4), Vector2(0, 4)])
	var unit_merged: Array[PackedVector2Array] = Geometry2D.merge_polygons(unit_sq, unit_sq)
	var outer_is_cw: bool = Geometry2D.is_polygon_clockwise(unit_merged[0]) if not unit_merged.is_empty() else false
	var unit_norm: PackedVector2Array = _ensure_winding(unit_sq, outer_is_cw)
	var test_grow: Array[PackedVector2Array] = Geometry2D.offset_polygon(unit_norm, 1.0, Geometry2D.JOIN_MITER)
	var grow_aabb: Rect2 = _poly_aabb(test_grow[0]) if not test_grow.is_empty() else Rect2(0, 0, 4, 4)
	var expand_sign: float = 1.0 if grow_aabb.size.x > 4.5 else -1.0
	graph.set_meta("outer_is_cw", outer_is_cw)

	# 8. Build Connecting Bridge Ribbons & Exact Disjoint Clipped Bridge Segments
	var all_polys_to_merge: Array[PackedVector2Array] = []
	for area in graph.areas:
		area.polygon = _ensure_winding(area.polygon, outer_is_cw)
		all_polys_to_merge.append(area.polygon)

	for edge_key in active_edges.keys():
		var edge: Vector2i = edge_key as Vector2i
		var is_loop_edge: bool = active_edges[edge]
		var from_area: AreaData = graph.areas[edge.x]
		var to_area: AreaData = graph.areas[edge.y]

		var w: float = cfg.bridge_width
		if from_area.role == AreaPresetScript.RoomRole.DEADEND or to_area.role == AreaPresetScript.RoomRole.DEADEND:
			w = maxf(4.4, cfg.bridge_width - 0.6)

		var path := PathData.new()
		path.from_idx = edge.x
		path.to_idx = edge.y
		path.width = w
		path.is_loop = is_loop_edge
		path.polygon = AreaPresetScript.build_connecting_bridge(
			from_area.center, from_area.polygon,
			to_area.center, to_area.polygon,
			w
		)
		if path.polygon.size() < 3:
			continue

		# Subtract room polygons via Geometry2D.clip_polygons (A - B, NOT symmetric XOR!)
		# so bridge floor & grass form a strictly disjoint partition with rooms
		var fragments: Array[PackedVector2Array] = [_ensure_winding(path.polygon, outer_is_cw)]
		var path_rect: Rect2 = _poly_aabb(path.polygon)
		for area in graph.areas:
			var area_rect: Rect2 = Rect2(area.center - area.size * 0.5, area.size)
			if not path_rect.intersects(area_rect):
				continue
			var clip_poly: PackedVector2Array = _ensure_winding(area.polygon, outer_is_cw)
			var next_frags: Array[PackedVector2Array] = []
			for frag in fragments:
				var diff_polys: Array[PackedVector2Array] = Geometry2D.clip_polygons(frag, clip_poly)
				for dp in diff_polys:
					if dp.size() >= 3 and Geometry2D.is_polygon_clockwise(dp) == outer_is_cw:
						next_frags.append(dp)
			fragments = next_frags

		path.clipped_segments = fragments
		graph.paths.append(path)
		all_polys_to_merge.append(_ensure_winding(path.polygon, outer_is_cw))

	# 9. Boolean Union + Morphological Corner Filleting (flushes all bridge throats & sharp steps)
	var raw_merged: Array[PackedVector2Array] = _merge_polygon_soup(all_polys_to_merge, outer_is_cw)
	var r_throat: float = clampf(cfg.throat_fillet_radius, 0.8, 3.0)
	var r_convex: float = 0.85

	for poly in raw_merged:
		if Geometry2D.is_polygon_clockwise(poly) == outer_is_cw:
			var filleted_outers: Array[PackedVector2Array] = _fillet_outer_polygon(
				poly, r_throat, r_convex, outer_is_cw, expand_sign
			)
			for fo in filleted_outers:
				var cleaned_o: PackedVector2Array = _clean_contour(fo, 0.28)
				if cleaned_o.size() >= 3:
					graph.outer_contours.append(_ensure_winding(cleaned_o, outer_is_cw))
		else:
			var filleted_holes: Array[PackedVector2Array] = _fillet_hole_polygon(
				poly, r_throat, r_convex, outer_is_cw, expand_sign
			)
			for fh in filleted_holes:
				var cleaned_h: PackedVector2Array = _clean_contour(fh, 0.28)
				if cleaned_h.size() >= 3:
					graph.hole_contours.append(_ensure_winding(cleaned_h, not outer_is_cw))

	graph.merged_polygons.clear()
	graph.merged_polygons.append_array(graph.outer_contours)
	graph.merged_polygons.append_array(graph.hole_contours)

	return graph


## Legacy static signature preserved for existing callers
static func generate(
	rng: RandomNumberGenerator,
	spine_length: int = 5,
	bridge_width: float = 5.2,
	deadend_chance: float = 0.50,
	loop_chance: float = 0.55
) -> PlainsGraph:
	var cfg := MapPresetConfigScript.create_preset(MapPresetConfigScript.TopologyMode.DREAMSCAPE_WEB)
	cfg.progression_tiers = maxi(4, spine_length)
	cfg.bridge_width = bridge_width
	cfg.side_shrine_chance = deadend_chance
	cfg.cross_link_chance = loop_chance
	return generate_from_preset(rng, cfg)


static func _make_area(
	idx: int,
	tier: int,
	lane: int,
	center: Vector2,
	role: int,
	rng: RandomNumberGenerator,
	scale_mult: float
) -> AreaData:
	var area := AreaData.new()
	area.index = idx
	area.tier = tier
	area.lane = lane
	area.grid_coord = Vector2i(lane, -tier)
	area.center = center
	area.role = role
	area.size = AreaPresetScript.get_room_size(role as AreaPresetScript.RoomRole, rng, scale_mult)
	area.shape = AreaPresetScript.pick_arena_shape(role as AreaPresetScript.RoomRole, rng)
	area.polygon = AreaPresetScript.build_arena_polygon(area.center, area.size, area.shape as AreaPresetScript.ArenaShape)
	area.inner_safe_rect = AreaPresetScript.get_inner_safe_rect(area.center, area.size, area.shape as AreaPresetScript.ArenaShape)
	return area


static func _add_edge(edge_dict: Dictionary, a: int, b: int, is_loop: bool) -> void:
	if a == b:
		return
	var key := Vector2i(mini(a, b), maxi(a, b))
	if not edge_dict.has(key):
		edge_dict[key] = is_loop


## Prevents two bridges from leaving the same arena at a shallow angle (fusing into a double-wide field)
## or grazing a third unrelated arena along their span.
static func _can_add_clean_web_edge(
	areas_list: Array[AreaData],
	edge_dict: Dictionary,
	a: int,
	b: int,
	min_angle_rad: float
) -> bool:
	if a == b or a < 0 or b < 0 or a >= areas_list.size() or b >= areas_list.size():
		return false
	var key := Vector2i(mini(a, b), maxi(a, b))
	if edge_dict.has(key):
		return false

	var ca: Vector2 = areas_list[a].center
	var cb: Vector2 = areas_list[b].center
	var dir_ab: Vector2 = (cb - ca).normalized()
	var dir_ba: Vector2 = -dir_ab
	var max_cos: float = cos(min_angle_rad)

	for existing_var in edge_dict.keys():
		var ex: Vector2i = existing_var as Vector2i
		if ex.x == a or ex.y == a:
			var other_a: int = ex.y if ex.x == a else ex.x
			var d_a: Vector2 = (areas_list[other_a].center - ca).normalized()
			if dir_ab.dot(d_a) > max_cos:
				return false
		if ex.x == b or ex.y == b:
			var other_b: int = ex.y if ex.x == b else ex.x
			var d_b: Vector2 = (areas_list[other_b].center - cb).normalized()
			if dir_ba.dot(d_b) > max_cos:
				return false

	# Ensure segment (ca, cb) doesn't cut across or graze a third arena's boundary
	for idx in range(areas_list.size()):
		if idx == a or idx == b:
			continue
		var third: AreaData = areas_list[idx]
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(third.center, ca, cb)
		var dx: float = absf(closest.x - third.center.x)
		var dz: float = absf(closest.y - third.center.y)
		if dx < (third.size.x * 0.5 + 7.5) and dz < (third.size.y * 0.5 + 7.5):
			return false

	return true


static func _can_add_clean_shrine(
	areas_list: Array[AreaData],
	edge_dict: Dictionary,
	anchor_idx: int,
	shrine_pos: Vector2,
	min_angle_rad: float
) -> bool:
	var ca: Vector2 = areas_list[anchor_idx].center
	var dir_as: Vector2 = (shrine_pos - ca).normalized()
	var max_cos: float = cos(min_angle_rad)
	for existing_var in edge_dict.keys():
		var ex: Vector2i = existing_var as Vector2i
		if ex.x == anchor_idx or ex.y == anchor_idx:
			var other_idx: int = ex.y if ex.x == anchor_idx else ex.x
			var d_other: Vector2 = (areas_list[other_idx].center - ca).normalized()
			if dir_as.dot(d_other) > max_cos:
				return false
	return true


static func _has_clearance(
	pos: Vector2,
	size: Vector2,
	existing_areas: Array[AreaData],
	min_gap: float
) -> bool:
	var candidate_rect := Rect2(
		pos.x - size.x * 0.5 - min_gap,
		pos.y - size.y * 0.5 - min_gap,
		size.x + min_gap * 2.0,
		size.y + min_gap * 2.0
	)
	for other in existing_areas:
		var other_rect := Rect2(
			other.center.x - other.size.x * 0.5,
			other.center.y - other.size.y * 0.5,
			other.size.x,
			other.size.y
		)
		if candidate_rect.intersects(other_rect):
			return false
	return true


static func _enforce_room_clearance(areas_list: Array[AreaData], min_gap: float) -> void:
	# Keep Spawn (index 0) pinned at (0, 0); gently nudge any pair closer than min_gap apart
	for _iter in range(6):
		var moved: bool = false
		for i in range(areas_list.size()):
			for j in range(i + 1, areas_list.size()):
				var a: AreaData = areas_list[i]
				var b: AreaData = areas_list[j]
				var req_x: float = (a.size.x + b.size.x) * 0.5 + min_gap
				var req_y: float = (a.size.y + b.size.y) * 0.5 + min_gap
				var dx: float = b.center.x - a.center.x
				var dy: float = b.center.y - a.center.y
				var overlap_x: float = req_x - absf(dx)
				var overlap_y: float = req_y - absf(dy)

				if overlap_x > 0.0 and overlap_y > 0.0:
					moved = true
					if overlap_x < overlap_y:
						var push_x: float = (overlap_x + 0.5) * (1.0 if dx >= 0.0 else -1.0)
						if i == 0:
							b.center.x += push_x
						else:
							a.center.x -= push_x * 0.5
							b.center.x += push_x * 0.5
					else:
						var push_y: float = (overlap_y + 0.5) * (1.0 if dy >= 0.0 else -1.0)
						if i == 0:
							b.center.y += push_y
						else:
							a.center.y -= push_y * 0.5
							b.center.y += push_y * 0.5

		if not moved:
			break

	for area in areas_list:
		area.polygon = AreaPresetScript.build_arena_polygon(
			area.center, area.size, area.shape as AreaPresetScript.ArenaShape
		)
		area.inner_safe_rect = AreaPresetScript.get_inner_safe_rect(
			area.center, area.size, area.shape as AreaPresetScript.ArenaShape
		)


static func _merge_polygon_soup(polys: Array[PackedVector2Array], outer_is_cw: bool) -> Array[PackedVector2Array]:
	# Iteratively merge overlapping outer polygons while preserving interior hole contours
	var outer_list: Array[PackedVector2Array] = []
	var holes_list: Array[PackedVector2Array] = []

	for poly in polys:
		if poly.size() < 3:
			continue
		outer_list.append(poly)

	var changed: bool = true
	var passes: int = 0
	while changed and passes < 16:
		changed = false
		passes += 1
		var i: int = 0
		while i < outer_list.size():
			var j: int = i + 1
			var merged_i: bool = false
			while j < outer_list.size():
				var combined: Array[PackedVector2Array] = Geometry2D.merge_polygons(outer_list[i], outer_list[j])
				var out_contours: Array[PackedVector2Array] = []
				var hole_contours_local: Array[PackedVector2Array] = []
				for cp in combined:
					if Geometry2D.is_polygon_clockwise(cp) == outer_is_cw:
						out_contours.append(cp)
					else:
						hole_contours_local.append(cp)

				# If two outer polygons fused into a single outer contour, accept the union
				if out_contours.size() == 1:
					outer_list[i] = out_contours[0]
					outer_list.remove_at(j)
					for h in hole_contours_local:
						holes_list.append(h)
					changed = true
					merged_i = true
				else:
					j += 1
			if not merged_i:
				i += 1

	var result: Array[PackedVector2Array] = []
	result.append_array(outer_list)
	result.append_array(holes_list)
	return result


static func _ensure_winding(poly: PackedVector2Array, target_cw: bool) -> PackedVector2Array:
	if poly.size() < 3:
		return poly
	if Geometry2D.is_polygon_clockwise(poly) == target_cw:
		return poly
	var rev := PackedVector2Array()
	rev.resize(poly.size())
	var n: int = poly.size()
	for i in range(n):
		rev[i] = poly[n - 1 - i]
	return rev


static func _poly_aabb(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()
	var min_p: Vector2 = poly[0]
	var max_p: Vector2 = poly[0]
	for pt in poly:
		min_p.x = minf(min_p.x, pt.x)
		min_p.y = minf(min_p.y, pt.y)
		max_p.x = maxf(max_p.x, pt.x)
		max_p.y = maxf(max_p.y, pt.y)
	return Rect2(min_p, max_p - min_p)


## Smooths all concave bridge-to-arena throats (Morphological Closing) and sharp convex corners (Opening)
static func _fillet_outer_polygon(
	poly: PackedVector2Array,
	r_throat: float,
	r_convex: float,
	outer_is_cw: bool,
	expand_sign: float
) -> Array[PackedVector2Array]:
	var base: PackedVector2Array = _ensure_winding(poly, outer_is_cw)
	# 1. Closing: Dilate +r_throat then Erode -r_throat to round all concave corners / bridge throats
	var dilated: Array[PackedVector2Array] = Geometry2D.offset_polygon(base, expand_sign * r_throat, Geometry2D.JOIN_ROUND)
	var closed_list: Array[PackedVector2Array] = []
	for d in dilated:
		if Geometry2D.is_polygon_clockwise(d) == outer_is_cw:
			var eroded: Array[PackedVector2Array] = Geometry2D.offset_polygon(d, -expand_sign * r_throat, Geometry2D.JOIN_ROUND)
			for e in eroded:
				if Geometry2D.is_polygon_clockwise(e) == outer_is_cw:
					closed_list.append(e)
	if closed_list.is_empty():
		closed_list.append(base)

	# 2. Opening: Erode -r_convex then Dilate +r_convex to flush any sharp convex steps/notches
	var final_list: Array[PackedVector2Array] = []
	for c in closed_list:
		var shrunk: Array[PackedVector2Array] = Geometry2D.offset_polygon(c, -expand_sign * r_convex, Geometry2D.JOIN_ROUND)
		for s in shrunk:
			if Geometry2D.is_polygon_clockwise(s) == outer_is_cw:
				var regrown: Array[PackedVector2Array] = Geometry2D.offset_polygon(s, expand_sign * r_convex, Geometry2D.JOIN_ROUND)
				for rg in regrown:
					if Geometry2D.is_polygon_clockwise(rg) == outer_is_cw:
						final_list.append(rg)
	if final_list.is_empty():
		return closed_list
	return final_list


## Smooths bridge throats & corners along enclosed loop water courtyards
static func _fillet_hole_polygon(
	hole_poly: PackedVector2Array,
	r_throat: float,
	_r_convex: float,
	outer_is_cw: bool,
	expand_sign: float
) -> Array[PackedVector2Array]:
	var water_shape: PackedVector2Array = _ensure_winding(hole_poly, outer_is_cw)
	# Shrinking then regrowing the water hole rounds its corners (which are the land's bridge throats!)
	var shrunk: Array[PackedVector2Array] = Geometry2D.offset_polygon(water_shape, -expand_sign * r_throat, Geometry2D.JOIN_ROUND)
	var out_holes: Array[PackedVector2Array] = []
	for s in shrunk:
		if Geometry2D.is_polygon_clockwise(s) == outer_is_cw:
			var regrown: Array[PackedVector2Array] = Geometry2D.offset_polygon(s, expand_sign * r_throat, Geometry2D.JOIN_ROUND)
			for rg in regrown:
				if Geometry2D.is_polygon_clockwise(rg) == outer_is_cw:
					out_holes.append(rg)
	return out_holes


## Removes micro-edges shorter than `min_dist` so shoreline meshes & collision prisms stay clean
static func _clean_contour(poly: PackedVector2Array, min_dist: float) -> PackedVector2Array:
	var n: int = poly.size()
	if n < 3:
		return poly
	var min_sq: float = min_dist * min_dist
	var cleaned := PackedVector2Array()
	for i in range(n):
		var pt: Vector2 = poly[i]
		if cleaned.is_empty() or cleaned[cleaned.size() - 1].distance_squared_to(pt) >= min_sq:
			cleaned.append(pt)
	if cleaned.size() >= 3 and cleaned[0].distance_squared_to(cleaned[cleaned.size() - 1]) < min_sq:
		cleaned.resize(cleaned.size() - 1)
	return cleaned
