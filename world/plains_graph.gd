class_name PlainsGraph
extends RefCounted

## Graph topology and geometry synthesizer for procedural maps.
## Generates smooth, rounded clearings/arenas connected by clean bridges,
## with a sequential progression spine, forks, and loops.

const AreaPresetScript = preload("res://world/area_preset.gd")

class AreaData:
	extends RefCounted
	var index: int = 0
	var center: Vector2 = Vector2.ZERO
	var radius: float = 12.0
	var size_category: int = 1 # AreaPreset.SizeCategory.MEDIUM
	var shape_format: int = 0  # AreaPreset.ShapeFormat.CIRCLE
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

## Generates the complete procedural map graph and smooth rounded geometry
static func generate(
	rng: RandomNumberGenerator,
	num_layers: int = 5,
	bridge_width_min: float = 3.6,
	bridge_width_max: float = 4.8,
	loop_ratio: float = 0.25
) -> PlainsGraph:
	var graph := PlainsGraph.new()

	# 1. Place rounded areas in sequential progression layers
	var area_centers: PackedVector2Array = []
	var layer_spacing: float = 28.0
	var start_y: float = - float(num_layers - 1) * layer_spacing * 0.5

	for layer in range(num_layers):
		var y_pos: float = start_y + layer * layer_spacing
		var nodes_in_layer: int = 1
		if layer == 0 or layer == num_layers - 1:
			nodes_in_layer = 1
		else:
			nodes_in_layer = rng.randi_range(1, 2)

		var x_spread: float = 24.0
		for i in range(nodes_in_layer):
			var x_pos: float = 0.0
			if nodes_in_layer == 1:
				x_pos = rng.randf_range(-6.0, 6.0)
			else:
				var sign_val: float = -1.0 if i == 0 else 1.0
				x_pos = sign_val * rng.randf_range(13.0, x_spread) + rng.randf_range(-3.0, 3.0)

			var pos := Vector2(x_pos, y_pos + rng.randf_range(-3.0, 3.0))
			area_centers.append(pos)

			var area := AreaData.new()
			area.index = graph.areas.size()
			area.center = pos

			# Use size and format presets
			var cat = AreaPresetScript.pick_size_category(layer, num_layers, rng)
			area.size_category = cat
			area.radius = AreaPresetScript.get_radius_for_category(cat, rng)
			area.shape_format = AreaPresetScript.pick_format(rng)

			# Generate smooth rounded polygon
			area.polygon = AreaPresetScript.build_smooth_area_polygon(
				area.center,
				area.radius,
				area.shape_format,
				rng,
				48
			)
			graph.areas.append(area)

	graph.spawn_index = 0
	graph.goal_index = graph.areas.size() - 1

	# 2. Delaunay Triangulation to discover neighbor proximity
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

	# 4. Controlled loop edge injection (add back 20-25% of candidates within range)
	var num_loops: int = maxi(1, int(unused_edges.size() * loop_ratio))
	for i in range(unused_edges.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = unused_edges[i]
		unused_edges[i] = unused_edges[j]
		unused_edges[j] = tmp

	var loop_edges_added: Dictionary = {}
	for i in range(mini(num_loops, unused_edges.size())):
		var loop_edge: Vector2i = unused_edges[i]
		var dist: float = area_centers[loop_edge.x].distance_to(area_centers[loop_edge.y])
		if dist <= layer_spacing * 2.3:
			active_edges.append(loop_edge)
			loop_edges_added[loop_edge] = true

	# 5. Build clean bridge polygons attaching the rounded areas
	var all_polys_to_merge: Array[PackedVector2Array] = []
	for area in graph.areas:
		all_polys_to_merge.append(area.polygon)

	for edge in active_edges:
		var from_area := graph.areas[edge.x]
		var to_area := graph.areas[edge.y]
		var path := PathData.new()
		path.from_idx = edge.x
		path.to_idx = edge.y
		path.is_loop = loop_edges_added.has(edge)

		var bridge_w: float = rng.randf_range(bridge_width_min, bridge_width_max)
		path.polygon = AreaPresetScript.build_bridge_polygon(
			from_area.center,
			to_area.center,
			bridge_w,
			16
		)
		graph.paths.append(path)
		all_polys_to_merge.append(path.polygon)

	# 6. Merge all smooth rounded areas and bridges into archipelago polygons
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
