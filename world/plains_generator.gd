class_name PlainsGenerator
extends Node3D

## Procedural level generator.
## Builds smooth, rounded clearings attached by clean bridges,
## an ArrayMesh terrain with a shoreline skirt, impassable perimeter boundaries,
## and modular BiomeTheme environment rendering.

const PlainsGraphScript = preload("res://world/plains_graph.gd")
const BiomeThemeScript = preload("res://world/biome_theme.gd")

signal map_generated(spawn_pos: Vector3, goal_pos: Vector3)
signal graph_ready(graph: RefCounted)

@export_group("Layout & Topology")
@export var map_seed: int = 0
@export var spine_length: int = 6
@export var bridge_width: float = 4.8
@export var deadend_chance: float = 0.45
@export var loop_ratio: float = 0.25
@export var auto_generate_on_ready: bool = false

@export_group("Environment & Theme")
@export var biome_theme: BiomeTheme = preload("res://assets/plains_biome_theme.tres")

# Cached node references
var terrain_mesh_instance: MeshInstance3D = null
var static_body: StaticBody3D = null
var foliage_multimesh_instance: MultiMeshInstance3D = null
var boundary_liquid_instance: MeshInstance3D = null

var current_graph: RefCounted = null
var current_seed: int = 0

func _ready() -> void:
	if auto_generate_on_ready:
		generate_map(map_seed)

## Generates or regenerates the entire procedural map
func generate_map(p_seed: int = 0) -> void:
	_cleanup_existing()

	var rng := RandomNumberGenerator.new()
	if p_seed != 0:
		rng.seed = p_seed
		current_seed = p_seed
	else:
		rng.randomize()
		current_seed = rng.seed

	# 1. Generate rectangular graph & cardinal bridge geometry
	current_graph = PlainsGraphScript.generate(
		rng,
		spine_length,
		bridge_width,
		deadend_chance,
		loop_ratio
	)

	# 2. Build Terrain Mesh (top cap + shoreline skirt)
	_build_terrain_mesh()

	# 3. Build Static Collision (ground plane + impassable perimeter wall)
	_build_terrain_collision()

	# 4. Build Foliage / Surface Props
	if biome_theme and biome_theme.enable_foliage:
		_build_foliage(rng)

	# 5. Build Boundary Plane (water, void, lava, etc.)
	_build_boundary_plane()

	# 6. Emit completion signals with world spawn & goal positions
	var spawn_pos2d: Vector2 = current_graph.areas[current_graph.spawn_index].center
	var goal_pos2d: Vector2 = current_graph.areas[current_graph.goal_index].center

	var spawn_pos3d := Vector3(spawn_pos2d.x, 0.0, spawn_pos2d.y)
	var goal_pos3d := Vector3(goal_pos2d.x, 0.0, goal_pos2d.y)

	graph_ready.emit(current_graph)
	map_generated.emit(spawn_pos3d, goal_pos3d)

func _cleanup_existing() -> void:
	if terrain_mesh_instance and is_instance_valid(terrain_mesh_instance):
		terrain_mesh_instance.queue_free()
		terrain_mesh_instance = null
	if static_body and is_instance_valid(static_body):
		static_body.queue_free()
		static_body = null
	if foliage_multimesh_instance and is_instance_valid(foliage_multimesh_instance):
		foliage_multimesh_instance.queue_free()
		foliage_multimesh_instance = null
	if boundary_liquid_instance and is_instance_valid(boundary_liquid_instance):
		boundary_liquid_instance.queue_free()
		boundary_liquid_instance = null

## Constructs the ArrayMesh terrain with smooth rounded top cap & beveled shoreline skirt
func _build_terrain_mesh() -> void:
	terrain_mesh_instance = MeshInstance3D.new()
	terrain_mesh_instance.name = "TerrainMesh"
	add_child(terrain_mesh_instance)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var skirt_d: float = biome_theme.skirt_depth if biome_theme else 0.35

	for poly in current_graph.merged_polygons:
		var n: int = poly.size()
		if n < 3:
			continue

		# Top Cap Triangulation
		var tri_indices := Geometry2D.triangulate_polygon(poly)
		for idx in tri_indices:
			var pt: Vector2 = poly[idx]
			st.set_uv(Vector2(pt.x * 0.05, pt.y * 0.05))
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(pt.x, 0.0, pt.y))

		# Shoreline Bevel / Skirt
		for i in range(n):
			var p1: Vector2 = poly[i]
			var p2: Vector2 = poly[(i + 1) % n]
			var edge_dir := (p2 - p1).normalized()
			var out_norm := Vector3(-edge_dir.y, -0.4, edge_dir.x).normalized()

			var t1 := Vector3(p1.x, 0.0, p1.y)
			var t2 := Vector3(p2.x, 0.0, p2.y)
			var b1 := Vector3(p1.x, -skirt_d, p1.y)
			var b2 := Vector3(p2.x, -skirt_d, p2.y)

			st.set_normal(out_norm)
			st.set_uv(Vector2(p1.x * 0.05, p1.y * 0.05))
			st.add_vertex(t1)
			st.add_vertex(t2)
			st.add_vertex(b2)

			st.add_vertex(t1)
			st.add_vertex(b2)
			st.add_vertex(b1)

	st.generate_tangents()
	var array_mesh := st.commit()

	terrain_mesh_instance.mesh = array_mesh
	if biome_theme and biome_theme.ground_material:
		terrain_mesh_instance.material_override = biome_theme.ground_material

## Generates static physics collision shape matching terrain and boundary walls
func _build_terrain_collision() -> void:
	if not terrain_mesh_instance or not terrain_mesh_instance.mesh:
		return

	static_body = StaticBody3D.new()
	static_body.name = "TerrainCollision"
	terrain_mesh_instance.add_child(static_body)

	# 1. Ground collision
	var ground_shape := CollisionShape3D.new()
	ground_shape.name = "GroundCollisionShape"
	ground_shape.shape = terrain_mesh_instance.mesh.create_trimesh_shape()
	static_body.add_child(ground_shape)

	# 2. Impassable boundary wall along the outer shore contours
	var wall_faces: PackedVector3Array = []
	for poly in current_graph.merged_polygons:
		var n: int = poly.size()
		for i in range(n):
			var p1: Vector2 = poly[i]
			var p2: Vector2 = poly[(i + 1) % n]
			var v1_low := Vector3(p1.x, -1.0, p1.y)
			var v1_high := Vector3(p1.x, 2.5, p1.y)
			var v2_low := Vector3(p2.x, -1.0, p2.y)
			var v2_high := Vector3(p2.x, 2.5, p2.y)

			wall_faces.append_array([v1_low, v1_high, v2_high, v1_low, v2_high, v2_low])
			wall_faces.append_array([v1_low, v2_high, v1_high, v1_low, v2_low, v2_high])

	if not wall_faces.is_empty():
		var wall_shape := CollisionShape3D.new()
		wall_shape.name = "ShoreBoundaryShape"
		var concave := ConcavePolygonShape3D.new()
		concave.set_faces(wall_faces)
		wall_shape.shape = concave
		static_body.add_child(wall_shape)

## Populates foliage / surface props from the BiomeTheme definition
func _build_foliage(rng: RandomNumberGenerator) -> void:
	if not biome_theme or not biome_theme.foliage_mesh:
		return

	foliage_multimesh_instance = MultiMeshInstance3D.new()
	foliage_multimesh_instance.name = "Foliage"
	foliage_multimesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(foliage_multimesh_instance)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = biome_theme.foliage_mesh

	var valid_transforms: Array[Transform3D] = []

	# 1. Sample directly inside each room's bounding box and test against area polygon
	for area in current_graph.areas:
		var half_sz: Vector2 = area.size * 0.5
		var room_area: float = area.size.x * area.size.y
		var room_count: int = int(room_area * biome_theme.foliage_density)
		for _i in range(room_count):
			var test_pt := Vector2(
				rng.randf_range(area.center.x - half_sz.x, area.center.x + half_sz.x),
				rng.randf_range(area.center.y - half_sz.y, area.center.y + half_sz.y)
			)
			if Geometry2D.is_point_in_polygon(test_pt, area.polygon):
				var yaw: float = rng.randf_range(0.0, TAU)
				var t := Transform3D()
				t = t.rotated(Vector3.UP, yaw)
				t.origin = Vector3(test_pt.x, 0.0, test_pt.y)
				valid_transforms.append(t)
				if valid_transforms.size() >= biome_theme.max_foliage_instances:
					break
		if valid_transforms.size() >= biome_theme.max_foliage_instances:
			break

	# 2. Sample along each bridge
	if valid_transforms.size() < biome_theme.max_foliage_instances:
		for path in current_graph.paths:
			var p_min := Vector2(INF, INF)
			var p_max := Vector2(-INF, -INF)
			for pt in path.polygon:
				p_min.x = minf(p_min.x, pt.x)
				p_min.y = minf(p_min.y, pt.y)
				p_max.x = maxf(p_max.x, pt.x)
				p_max.y = maxf(p_max.y, pt.y)
			var bridge_area: float = (p_max.x - p_min.x) * (p_max.y - p_min.y)
			var bridge_count: int = int(bridge_area * biome_theme.foliage_density)
			for _i in range(bridge_count):
				var test_pt := Vector2(
					rng.randf_range(p_min.x, p_max.x),
					rng.randf_range(p_min.y, p_max.y)
				)
				if Geometry2D.is_point_in_polygon(test_pt, path.polygon):
					var yaw: float = rng.randf_range(0.0, TAU)
					var t := Transform3D()
					t = t.rotated(Vector3.UP, yaw)
					t.origin = Vector3(test_pt.x, 0.0, test_pt.y)
					valid_transforms.append(t)
					if valid_transforms.size() >= biome_theme.max_foliage_instances:
						break
			if valid_transforms.size() >= biome_theme.max_foliage_instances:
				break

	mm.instance_count = valid_transforms.size()
	for i in range(valid_transforms.size()):
		mm.set_instance_transform(i, valid_transforms[i])

	foliage_multimesh_instance.multimesh = mm
	if biome_theme.foliage_material:
		foliage_multimesh_instance.material_override = biome_theme.foliage_material


## Builds surrounding liquid/void plane
func _build_boundary_plane() -> void:
	if not biome_theme or not biome_theme.boundary_material:
		return

	boundary_liquid_instance = MeshInstance3D.new()
	boundary_liquid_instance.name = "BoundaryPlane"
	add_child(boundary_liquid_instance)

	var min_pt := Vector2(INF, INF)
	var max_pt := Vector2(-INF, -INF)
	if current_graph and not current_graph.areas.is_empty():
		for area in current_graph.areas:
			var half_sz: Vector2 = area.size * 0.5
			min_pt.x = minf(min_pt.x, area.center.x - half_sz.x)
			min_pt.y = minf(min_pt.y, area.center.y - half_sz.y)
			max_pt.x = maxf(max_pt.x, area.center.x + half_sz.x)
			max_pt.y = maxf(max_pt.y, area.center.y + half_sz.y)

	var center_2d: Vector2 = (min_pt + max_pt) * 0.5 if not current_graph.areas.is_empty() else Vector2.ZERO
	var span_2d: Vector2 = (max_pt - min_pt) if not current_graph.areas.is_empty() else Vector2(200.0, 200.0)
	var water_size: float = maxf(2000.0, maxf(span_2d.x, span_2d.y) * 4.0)

	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(water_size, water_size)
	plane_mesh.subdivide_width = 128
	plane_mesh.subdivide_depth = 128

	boundary_liquid_instance.mesh = plane_mesh
	boundary_liquid_instance.position = Vector3(center_2d.x, biome_theme.boundary_depth, center_2d.y)
	boundary_liquid_instance.material_override = biome_theme.boundary_material
