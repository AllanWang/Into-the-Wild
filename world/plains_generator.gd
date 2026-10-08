class_name PlainsGenerator
extends Node3D

## Procedural plains generator for 2.5D roguelike levels.
## Builds connected organic clearings, winding path corridors,
## ArrayMesh terrain with toon floor shader, MultiMesh grass, and boundary water.

const PlainsGraphScript = preload("res://world/plains_graph.gd")

signal map_generated(spawn_pos: Vector3, goal_pos: Vector3)
signal graph_ready(graph: RefCounted)

@export_group("Map Generation")
@export var map_seed: int = 0
@export var num_layers: int = 5
@export var min_area_radius: float = 8.5
@export var max_area_radius: float = 13.5
@export var path_width_min: float = 3.2
@export var path_width_max: float = 4.8
@export var loop_ratio: float = 0.25
@export var auto_generate_on_ready: bool = false

@export_group("Foliage & Grass")
@export var enable_grass: bool = true
@export var grass_density: float = 5.5 ## Blades per square meter
@export var max_grass_instances: int = 25000

@export_group("Materials")
@export var floor_material: Material = preload("res://assets/plains_floor_material.tres")
@export var grass_material: Material = preload("res://assets/plains_grass_material.tres")
@export var water_material: Material = preload("res://assets/plains_water_material.tres")

# Cached node references
var terrain_mesh_instance: MeshInstance3D = null
var static_body: StaticBody3D = null
var grass_multimesh_instance: MultiMeshInstance3D = null
var water_mesh_instance: MeshInstance3D = null

var current_graph: RefCounted = null
var current_seed: int = 0

func _ready() -> void:
	if auto_generate_on_ready:
		generate_map(map_seed)

## Generates or regenerates the entire procedural plains map
func generate_map(p_seed: int = 0) -> void:
	_cleanup_existing()

	var rng := RandomNumberGenerator.new()
	if p_seed != 0:
		rng.seed = p_seed
		current_seed = p_seed
	else:
		rng.randomize()
		current_seed = rng.seed

	# 1. Generate abstract graph & organic polygons
	current_graph = PlainsGraphScript.generate(
		rng,
		num_layers,
		min_area_radius,
		max_area_radius,
		path_width_min,
		path_width_max,
		loop_ratio
	)

	# 2. Build Terrain Mesh
	_build_terrain_mesh()

	# 3. Build Static Collision
	_build_terrain_collision()

	# 4. Build MultiMesh Grass
	if enable_grass:
		_build_grass_foliage(rng)

	# 5. Build Water Boundary Plane
	_build_water_plane()

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
	if grass_multimesh_instance and is_instance_valid(grass_multimesh_instance):
		grass_multimesh_instance.queue_free()
		grass_multimesh_instance = null
	if water_mesh_instance and is_instance_valid(water_mesh_instance):
		water_mesh_instance.queue_free()
		water_mesh_instance = null

## Constructs the ArrayMesh terrain from merged land polygons
func _build_terrain_mesh() -> void:
	terrain_mesh_instance = MeshInstance3D.new()
	terrain_mesh_instance.name = "TerrainMesh"
	add_child(terrain_mesh_instance)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Triangulate each merged island / polygon (top cap + shoreline skirt)
	for poly in current_graph.merged_polygons:
		var n: int = poly.size()
		if n < 3:
			continue

		# Top Cap
		var tri_indices := Geometry2D.triangulate_polygon(poly)
		for idx in tri_indices:
			var pt: Vector2 = poly[idx]
			st.set_uv(Vector2(pt.x * 0.05, pt.y * 0.05))
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(pt.x, 0.0, pt.y))

		# Shoreline Skirt: extrude outer edge down into water (-0.35)
		for i in range(n):
			var p1: Vector2 = poly[i]
			var p2: Vector2 = poly[(i + 1) % n]
			var edge_dir := (p2 - p1).normalized()
			var out_norm := Vector3(-edge_dir.y, -0.4, edge_dir.x).normalized()

			var t1 := Vector3(p1.x, 0.0, p1.y)
			var t2 := Vector3(p2.x, 0.0, p2.y)
			var b1 := Vector3(p1.x, -0.35, p1.y)
			var b2 := Vector3(p2.x, -0.35, p2.y)

			# Quad: two triangles facing outward
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
	if floor_material:
		terrain_mesh_instance.material_override = floor_material

## Generates static physics collision shape matching the terrain and boundary walls
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

	# 2. Impassable shoreline boundary wall collision (stops player from falling into water)
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

			# Both face sides for robust blocking
			wall_faces.append_array([v1_low, v1_high, v2_high, v1_low, v2_high, v2_low])
			wall_faces.append_array([v1_low, v2_high, v1_high, v1_low, v2_low, v2_high])

	if not wall_faces.is_empty():
		var wall_shape := CollisionShape3D.new()
		wall_shape.name = "ShoreBoundaryShape"
		var concave := ConcavePolygonShape3D.new()
		concave.set_faces(wall_faces)
		wall_shape.shape = concave
		static_body.add_child(wall_shape)

## Populates grass MultiMesh blades restricted to land polygons
func _build_grass_foliage(rng: RandomNumberGenerator) -> void:
	grass_multimesh_instance = MultiMeshInstance3D.new()
	grass_multimesh_instance.name = "Grass"
	add_child(grass_multimesh_instance)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	quad.size = Vector2(0.2, 0.3)
	mm.mesh = quad

	# Calculate bounding rect for all land polygons
	var min_pt := Vector2(INF, INF)
	var max_pt := Vector2(-INF, -INF)
	for poly in current_graph.merged_polygons:
		for pt in poly:
			min_pt.x = minf(min_pt.x, pt.x)
			min_pt.y = minf(min_pt.y, pt.y)
			max_pt.x = maxf(max_pt.x, pt.x)
			max_pt.y = maxf(max_pt.y, pt.y)

	var width := max_pt.x - min_pt.x
	var height := max_pt.y - min_pt.y
	var bounding_area := width * height

	# Sample random points and reject those outside land
	var target_samples := mini(max_grass_instances, int(bounding_area * grass_density * 0.5))
	var valid_transforms: Array[Transform3D] = []

	for _i in range(target_samples):
		var test_pt := Vector2(
			rng.randf_range(min_pt.x, max_pt.x),
			rng.randf_range(min_pt.y, max_pt.y)
		)

		# Check if point is inside any land polygon
		var is_on_land: bool = false
		for poly in current_graph.merged_polygons:
			if Geometry2D.is_point_in_polygon(test_pt, poly):
				is_on_land = true
				break

		if is_on_land:
			var yaw: float = rng.randf_range(0.0, TAU)
			var scale_var: float = rng.randf_range(0.85, 1.25)
			var t := Transform3D()
			t = t.scaled(Vector3(scale_var, scale_var, scale_var))
			t = t.rotated(Vector3.UP, yaw)
			t.origin = Vector3(test_pt.x, 0.0, test_pt.y)
			valid_transforms.append(t)

			if valid_transforms.size() >= max_grass_instances:
				break

	mm.instance_count = valid_transforms.size()
	for i in range(valid_transforms.size()):
		mm.set_instance_transform(i, valid_transforms[i])

	grass_multimesh_instance.multimesh = mm
	if grass_material:
		grass_multimesh_instance.material_override = grass_material

## Creates surrounding boundary water plane
func _build_water_plane() -> void:
	water_mesh_instance = MeshInstance3D.new()
	water_mesh_instance.name = "WaterPlane"
	add_child(water_mesh_instance)

	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(400.0, 400.0)
	plane_mesh.subdivide_width = 64
	plane_mesh.subdivide_depth = 64

	water_mesh_instance.mesh = plane_mesh

	# Center water on archipelago bounds
	var center_2d := Vector2.ZERO
	if current_graph and not current_graph.areas.is_empty():
		for area in current_graph.areas:
			center_2d += area.center
		center_2d /= float(current_graph.areas.size())

	# Position slightly below floor level (-0.15)
	water_mesh_instance.position = Vector3(center_2d.x, -0.15, center_2d.y)

	if water_material:
		water_mesh_instance.material_override = water_material
