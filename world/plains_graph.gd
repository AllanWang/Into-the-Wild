class_name PlainsGraph
extends RefCounted

## Graph and geometry data structures for procedural plains generation.
## Implements Poisson disk placement, Delaunay triangulation, MST + loop edge injection,
## and organic polygon synthesis.

class AreaData:
	extends RefCounted
	var index: int = 0
	var center: Vector2 = Vector2.ZERO
	var radius: float = 10.0
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

class DisjointSet:
	var parent: Dictionary = {}
	func _init(n: int) -> void:
		for i in range(n):
			parent[i] = i
	func find(i: int) -> int:
		var root: int = i
		while parent[root] != root:
			root = parent[root]
		var curr: int = i
		while curr != root:
			var nxt: int = parent[curr]
			parent[curr] = root
			curr = nxt
		return root
	func union(i: int, j: int) -> bool:
		var root_i := find(i)
		var root_j := find(j)
		if root_i != root_j:
			parent[root_i] = root_j
			return true
		return false

## Generates the complete plains topology and organic polygons
static func generate(
	rng: RandomNumberGenerator,
	num_layers: int = 5,
	min_area_radius: float = 9.0,
	max_area_radius: float = 14.0,
	path_width_min: float = 3.2,
	path_width_max: float = 4.8,
	loop_ratio: float = 0.25
) -> PlainsGraph:
	var graph := PlainsGraph.new()

	# FastNoiseLite setup for organic shape distortion
	var shape_noise := FastNoiseLite.new()
	shape_noise.seed = rng.randi()
	shape_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	shape_noise.frequency = 0.08
	shape_noise.fractal_octaves = 2

	# 1. Place areas in sequential progression layers
	# Layout progresses primarily along the Z/Y axis (e.g. from -50 to +50)
	var area_centers: PackedVector2Array = []
	var layer_spacing: float = 24.0
	var start_y: float = - float(num_layers - 1) * layer_spacing * 0.5

	for layer in range(num_layers):
		var y_pos: float = start_y + layer * layer_spacing
		var nodes_in_layer: int = 1
		if layer == 0 or layer == num_layers - 1:
			# Single spawn area and single goal/boss area
			nodes_in_layer = 1
		else:
			# Middle layers can split into 1 or 2 clumps
			nodes_in_layer = rng.randi_range(1, 2)

		var x_spread: float = 20.0
		for i in range(nodes_in_layer):
			var x_pos: float = 0.0
			if nodes_in_layer == 1:
				x_pos = rng.randf_range(-6.0, 6.0)
			else:
				var sign_val: float = -1.0 if i == 0 else 1.0
				x_pos = sign_val * rng.randf_range(12.0, x_spread) + rng.randf_range(-3.0, 3.0)

			# Add subtle random offset
			var pos := Vector2(x_pos, y_pos + rng.randf_range(-3.5, 3.5))
			area_centers.append(pos)

			var area := AreaData.new()
			area.index = graph.areas.size()
			area.center = pos
			area.radius = rng.randf_range(min_area_radius, max_area_radius)
			graph.areas.append(area)

	graph.spawn_index = 0
	graph.goal_index = graph.areas.size() - 1

	# 2. Delaunay Triangulation to find candidate connections
	var tri_indices := Geometry2D.triangulate_delaunay(area_centers)
	var edge_map: Dictionary = {}
	for i in range(0, tri_indices.size(), 3):
		var a: int = tri_indices[i]
		var b: int = tri_indices[i + 1]
		var c: int = tri_indices[i + 2]
		edge_map[Vector2i(mini(a, b), maxi(a, b))] = true
		edge_map[Vector2i(mini(b, c), maxi(b, c))] = true
		edge_map[Vector2i(mini(c, a), maxi(c, a))] = true

	var all_edges: Array = edge_map.keys()
	# Sort edges by distance between area centers
	all_edges.sort_custom(func(e1: Vector2i, e2: Vector2i) -> bool:
		return area_centers[e1.x].distance_squared_to(area_centers[e1.y]) < area_centers[e2.x].distance_squared_to(area_centers[e2.y])
	)

	# 3. Minimum Spanning Tree (MST) using Kruskal's algorithm
	var dsu := DisjointSet.new(graph.areas.size())
	var active_edges: Array[Vector2i] = []
	var unused_edges: Array[Vector2i] = []

	for edge_variant in all_edges:
		var edge: Vector2i = edge_variant
		if dsu.union(edge.x, edge.y):
			active_edges.append(edge)
		else:
			unused_edges.append(edge)

	# 4. Add back 20-30% of unused edges to introduce loops & alternative paths
	var num_loops: int = maxi(1, int(unused_edges.size() * loop_ratio))
	# Shuffle unused edges using our deterministic RNG
	for i in range(unused_edges.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = unused_edges[i]
		unused_edges[i] = unused_edges[j]
		unused_edges[j] = tmp

	var loop_edges_added: Dictionary = {}
	for i in range(mini(num_loops, unused_edges.size())):
		var loop_edge: Vector2i = unused_edges[i]
		# Avoid excessively long edges that cross the entire map
		var dist: float = area_centers[loop_edge.x].distance_to(area_centers[loop_edge.y])
		if dist <= layer_spacing * 2.2:
			active_edges.append(loop_edge)
			loop_edges_added[loop_edge] = true

	# 5. Generate organic polygons for each area
	var all_polygons_to_merge: Array[PackedVector2Array] = []
	for area in graph.areas:
		area.polygon = _generate_area_polygon(area.center, area.radius, shape_noise)
		all_polygons_to_merge.append(area.polygon)

	# 6. Generate connecting path polygons for each edge
	for edge in active_edges:
		var from_area := graph.areas[edge.x]
		var to_area := graph.areas[edge.y]
		var path := PathData.new()
		path.from_idx = edge.x
		path.to_idx = edge.y
		path.is_loop = loop_edges_added.has(edge)

		var path_w: float = rng.randf_range(path_width_min, path_width_max)
		path.polygon = _generate_path_polygon(from_area.center, to_area.center, path_w, shape_noise, rng)
		graph.paths.append(path)
		all_polygons_to_merge.append(path.polygon)

	# 7. Merge all polygons into a unified archipelago / terrain boundary
	var merged: Array[PackedVector2Array] = []
	for poly in all_polygons_to_merge:
		if merged.is_empty():
			merged.append(poly)
		else:
			var new_merged: Array[PackedVector2Array] = []
			var merged_any: bool = false
			for existing in merged:
				var res := Geometry2D.merge_polygons(existing, poly)
				if res.size() == 1:
					# Overlapped and merged into single polygon
					new_merged.append(res[0])
					merged_any = true
				else:
					# Kept separate or complex
					for r in res:
						new_merged.append(r)
			if merged_any:
				merged = new_merged
			else:
				merged.append(poly)

	# Final pass to merge any overlapping polygons remaining
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

## Creates a natural organic clearing polygon with radial harmonic & noise distortion
static func _generate_area_polygon(
	center: Vector2,
	base_radius: float,
	noise: FastNoiseLite,
	point_count: int = 36
) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	for i in range(point_count):
		var angle: float = float(i) / float(point_count) * TAU
		var dir := Vector2(cos(angle), sin(angle))

		# Multi-harmonic organic contour (matches toon shader style)
		var harmonic: float = (
			sin(angle * 2.0) * 0.12 +
			cos(angle * 3.0 + 0.8) * 0.09 +
			sin(angle * 5.0) * 0.05
		)
		var sample_point := center + dir * base_radius
		var noise_val: float = noise.get_noise_2d(sample_point.x, sample_point.y)

		var r: float = base_radius * (1.0 + harmonic + noise_val * 0.18)
		polygon.append(center + dir * r)

	return polygon

## Creates a curving corridor polygon connecting two area centers
static func _generate_path_polygon(
	start: Vector2,
	end: Vector2,
	width: float,
	noise: FastNoiseLite,
	rng: RandomNumberGenerator,
	segments: int = 24
) -> PackedVector2Array:
	var left_side := PackedVector2Array()
	var right_side := PackedVector2Array()

	var diff := end - start
	var length := diff.length()
	var dir := diff.normalized()
	var normal := Vector2(-dir.y, dir.x)

	# Midpoint lateral curvature offset (natural bend)
	var curve_offset: float = rng.randf_range(-0.15, 0.15) * length

	for i in range(segments + 1):
		var t: float = float(i) / float(segments)
		# Quadratic bezier curve
		var lateral: float = 4.0 * t * (1.0 - t) * curve_offset
		var center_pt: Vector2 = start.lerp(end, t) + normal * lateral

		# Flare width at junctions (wider where it connects to areas), narrower in choke point
		var junction_flare: float = 1.0 + 1.2 * (4.0 * (t - 0.5) * (t - 0.5))
		var n_val: float = noise.get_noise_2d(center_pt.x, center_pt.y) * 0.2
		var half_w: float = (width * 0.5) * (junction_flare + n_val)

		left_side.append(center_pt + normal * half_w)
		right_side.append(center_pt - normal * half_w)

	right_side.reverse()
	var full_poly := PackedVector2Array()
	full_poly.append_array(left_side)
	full_poly.append_array(right_side)
	return full_poly
