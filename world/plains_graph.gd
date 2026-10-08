class_name PlainsGraph
extends RefCounted

## Grid-based room and cardinal bridge synthesizer (Cult of the Lamb style).
## Generates large rectangular sections connected by Left/Right/Up/Down bridges,
## with a primary progression spine, optional loops, and strictly 1-room-deep deadends.

const AreaPresetScript = preload("res://world/area_preset.gd")

class AreaData:
	extends RefCounted
	var index: int = 0
	var grid_coord: Vector2i = Vector2i.ZERO
	var center: Vector2 = Vector2.ZERO
	var size: Vector2 = Vector2(26.0, 20.0)
	var role: int = 0 # AreaPreset.RoomRole
	var polygon: PackedVector2Array = PackedVector2Array()

class PathData:
	extends RefCounted
	var from_idx: int = 0
	var to_idx: int = 0
	var polygon: PackedVector2Array = PackedVector2Array()
	var is_loop: bool = false

var areas: Array[AreaData] = []
var paths: Array[PathData] = []
var spawn_index: int = 0
var goal_index: int = 0
var merged_polygons: Array[PackedVector2Array] = []

# Cardinal direction offsets: Right, Left, Down, Up
const CARDINALS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1)
]

## Generates Cult of the Lamb style rectangular layout with cardinal bridges
static func generate(
	rng: RandomNumberGenerator,
	spine_length: int = 6,
	bridge_width: float = 4.8,
	deadend_chance: float = 0.45,
	loop_chance: float = 0.25
) -> PlainsGraph:
	var graph := PlainsGraph.new()

	# Grid spacing between room centers
	var step_x: float = 46.0
	var step_y: float = 38.0

	# Map tracking: grid_coord -> area_index
	var grid_map: Dictionary = {}
	# Edges tracking: Vector2i(min_idx, max_idx) -> bool
	var active_edges: Dictionary = {}

	# 1. Generate Main Path (Spine)
	var current_coord := Vector2i.ZERO
	var main_spine_coords: Array[Vector2i] = [current_coord]

	var spawn_area := AreaData.new()
	spawn_area.index = 0
	spawn_area.grid_coord = current_coord
	spawn_area.center = Vector2(current_coord.x * step_x, current_coord.y * step_y)
	spawn_area.role = AreaPresetScript.RoomRole.SPAWN
	spawn_area.size = AreaPresetScript.get_room_size(spawn_area.role, rng)
	spawn_area.polygon = AreaPresetScript.build_rounded_rectangle(spawn_area.center, spawn_area.size)
	graph.areas.append(spawn_area)
	grid_map[current_coord] = spawn_area.index

	var prev_idx: int = 0

	# Directional walk with forward progression bias
	var last_dir := Vector2i.ZERO

	for step in range(1, spine_length):
		var valid_dirs: Array[Vector2i] = []
		for dir in CARDINALS:
			var next_c: Vector2i = current_coord + dir
			if not grid_map.has(next_c):
				valid_dirs.append(dir)

		if valid_dirs.is_empty():
			break

		# Bias against immediately reversing direction
		var chosen_dir: Vector2i = valid_dirs[rng.randi_range(0, valid_dirs.size() - 1)]
		if valid_dirs.size() > 1 and chosen_dir == -last_dir:
			valid_dirs.erase(chosen_dir)
			chosen_dir = valid_dirs[rng.randi_range(0, valid_dirs.size() - 1)]

		last_dir = chosen_dir
		current_coord += chosen_dir
		main_spine_coords.append(current_coord)

		var role = AreaPresetScript.RoomRole.BOSS if step == spine_length - 1 else (
			AreaPresetScript.RoomRole.LARGE if rng.randf() < 0.3 else AreaPresetScript.RoomRole.COMBAT
		)

		var area := AreaData.new()
		area.index = graph.areas.size()
		area.grid_coord = current_coord
		area.center = Vector2(current_coord.x * step_x, current_coord.y * step_y)
		area.role = role
		area.size = AreaPresetScript.get_room_size(role, rng)
		area.polygon = AreaPresetScript.build_rounded_rectangle(area.center, area.size)
		graph.areas.append(area)
		grid_map[current_coord] = area.index

		# Connect spine edge
		active_edges[Vector2i(mini(prev_idx, area.index), maxi(prev_idx, area.index))] = false
		prev_idx = area.index

	graph.spawn_index = 0
	graph.goal_index = prev_idx

	# 2. Add Strictly 1-Room-Deep Dead-End Branches off the main spine
	# Rooms on the main spine can sprout deadends, but deadends NEVER sprout extra rooms!
	for spine_coord in main_spine_coords:
		var parent_idx: int = grid_map[spine_coord]
		if parent_idx == graph.spawn_index or parent_idx == graph.goal_index:
			# Keep spawn and boss room entries clean
			continue

		if rng.randf() <= deadend_chance:
			# Find an available cardinal neighbor
			var free_neighbors: Array[Vector2i] = []
			for dir in CARDINALS:
				var neighbor_coord: Vector2i = spine_coord + dir
				if not grid_map.has(neighbor_coord):
					free_neighbors.append(neighbor_coord)

			if not free_neighbors.is_empty():
				var branch_coord: Vector2i = free_neighbors[rng.randi_range(0, free_neighbors.size() - 1)]

				var deadend_area := AreaData.new()
				deadend_area.index = graph.areas.size()
				deadend_area.grid_coord = branch_coord
				deadend_area.center = Vector2(branch_coord.x * step_x, branch_coord.y * step_y)
				deadend_area.role = AreaPresetScript.RoomRole.DEADEND
				deadend_area.size = AreaPresetScript.get_room_size(deadend_area.role, rng)
				deadend_area.polygon = AreaPresetScript.build_rounded_rectangle(deadend_area.center, deadend_area.size)
				graph.areas.append(deadend_area)
				grid_map[branch_coord] = deadend_area.index

				# Connect 1-room branch to parent main-spine room
				active_edges[Vector2i(mini(parent_idx, deadend_area.index), maxi(parent_idx, deadend_area.index))] = false

	# 3. Optional Loops: check adjacent main-path rooms that are not connected
	for i in range(main_spine_coords.size()):
		var c1: Vector2i = main_spine_coords[i]
		var idx1: int = grid_map[c1]
		for dir in CARDINALS:
			var c2: Vector2i = c1 + dir
			if grid_map.has(c2):
				var idx2: int = grid_map[c2]
				var edge_pair := Vector2i(mini(idx1, idx2), maxi(idx1, idx2))
				if not active_edges.has(edge_pair):
					# If both are main path rooms and not deadends, allow a loop with loop_chance
					var area2 := graph.areas[idx2]
					if area2.role != AreaPresetScript.RoomRole.DEADEND:
						if rng.randf() <= loop_chance:
							active_edges[edge_pair] = true # marked as loop

	# 4. Generate Cardinal Bridges
	var all_polys_to_merge: Array[PackedVector2Array] = []
	for area in graph.areas:
		all_polys_to_merge.append(area.polygon)

	for edge in active_edges.keys():
		var is_loop: bool = active_edges[edge]
		var from_area := graph.areas[edge.x]
		var to_area := graph.areas[edge.y]

		var path := PathData.new()
		path.from_idx = edge.x
		path.to_idx = edge.y
		path.is_loop = is_loop

		path.polygon = AreaPresetScript.build_cardinal_bridge(
			from_area.center,
			from_area.size,
			to_area.center,
			to_area.size,
			bridge_width
		)
		graph.paths.append(path)
		all_polys_to_merge.append(path.polygon)

	# 5. Merge all rectangular rooms and cardinal bridges into seamless archipelago landmasses
	var merged: Array[PackedVector2Array] = []
	for poly in all_polys_to_merge:
		if merged.is_empty():
			merged.append(poly)
		else:
			var new_merged: Array[PackedVector2Array] = []
			var merged_any: bool = false
			for existing in merged:
				var res := Geometry2D.merge_polygons(existing, poly)
				if res.size() == 1:
					new_merged.append(res[0])
					merged_any = true
				else:
					for r in res:
						new_merged.append(r)
			if merged_any:
				merged = new_merged
			else:
				merged.append(poly)

	# Stabilization pass
	var stabilized: bool = false
	var passes: int = 0
	while not stabilized and passes < 5:
		stabilized = true
		passes += 1
		var next_pass: Array[PackedVector2Array] = []
		var skip_idx: Dictionary = {}
		for i in range(merged.size()):
			if skip_idx.has(i):
				continue
			var current := merged[i]
			for j in range(i + 1, merged.size()):
				if skip_idx.has(j):
					continue
				var combined := Geometry2D.merge_polygons(current, merged[j])
				if combined.size() == 1:
					current = combined[0]
					skip_idx[j] = true
					stabilized = false
			next_pass.append(current)
		merged = next_pass

	graph.merged_polygons = merged
	return graph
