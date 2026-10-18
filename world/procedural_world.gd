class_name ProceduralWorld
extends Node3D

## Procedural World Generator for Plains / Meadows
## Generates connected rectangular sections, cardinal bridges,
## surrounding stylized water, and MultiMesh foliage.

signal world_generated(spawn_pos: Vector3, goal_pos: Vector3)

@export_group("Areas & Layout")
@export var area_count: int = 2
@export var area_1_size: Vector2 = Vector2(25.0, 25.0)
@export var area_2_size: Vector2 = Vector2(25.0, 25.0)
@export var bridge_width: float = 6.0
@export var bridge_length: float = 11.0
@export var bridge_direction: Vector3 = Vector3(0, 0, -1) # North along -Z

@export_group("Materials & Meshes")
@export var floor_material: Material = preload("res://assets/floor_material.tres")
@export var grass_material: Material = preload("res://assets/grass_material.tres")
@export var grass_multimesh: MultiMesh = preload("res://assets/grass_multimesh.tres")
@export var water_material: Material = preload("res://assets/plains_water_material.tres")
@export var pond_material: Material = preload("res://assets/water_pond_material.tres")

# Generated nodes container
var areas_root: Node3D = null
var bridges_root: Node3D = null
var water_instance: MeshInstance3D = null
var pond_instance: MeshInstance3D = null

# Cached positions
var area_1_center: Vector3 = Vector3.ZERO
var area_2_center: Vector3 = Vector3.ZERO
var bridge_center: Vector3 = Vector3.ZERO

func _ready() -> void:
	generate_world()

## Cleans up existing geometry and generates the procedural world
func generate_world() -> void:
	_cleanup()
	
	areas_root = Node3D.new()
	areas_root.name = "Areas"
	add_child(areas_root)
	
	bridges_root = Node3D.new()
	bridges_root.name = "Bridges"
	add_child(bridges_root)
	
	# 1. Compute Centers
	area_1_center = Vector3.ZERO
	# Bridge offset along -Z
	var gap_center_z: float = -(area_1_size.y * 0.5 + bridge_length * 0.5)
	bridge_center = Vector3(0.0, 0.0, gap_center_z)
	
	var area_2_z: float = -(area_1_size.y * 0.5 + bridge_length + area_2_size.y * 0.5)
	area_2_center = Vector3(0.0, 0.0, area_2_z)
	
	# 2. Build Area 1 (Spawn Area)
	_build_area("Area_1_Spawn", area_1_center, area_1_size, true)
	
	# 3. Build Area 2 (Second Area / Arena)
	if area_count >= 2:
		_build_area("Area_2_Arena", area_2_center, area_2_size, false)
		_build_bridge("Bridge_1_to_2", bridge_center, Vector2(bridge_width, bridge_length))
	
	# 4. Build Surrounding Water Boundary
	_build_surrounding_water()
	
	# 5. Build Optional Spawn Pond
	_build_spawn_pond()
	
	world_generated.emit(area_1_center, area_2_center)

func _cleanup() -> void:
	if areas_root and is_instance_valid(areas_root):
		areas_root.queue_free()
		areas_root = null
	if bridges_root and is_instance_valid(bridges_root):
		bridges_root.queue_free()
		bridges_root = null
	if water_instance and is_instance_valid(water_instance):
		water_instance.queue_free()
		water_instance = null
	if pond_instance and is_instance_valid(pond_instance):
		pond_instance.queue_free()
		pond_instance = null

func _build_area(p_name: String, p_center: Vector3, p_size: Vector2, has_pond: bool) -> void:
	var area_node := Node3D.new()
	area_node.name = p_name
	area_node.position = p_center
	areas_root.add_child(area_node)
	
	# Floor PlaneMesh
	var floor_mesh_inst := MeshInstance3D.new()
	floor_mesh_inst.name = "FloorMesh"
	var pmesh := PlaneMesh.new()
	pmesh.size = p_size
	floor_mesh_inst.mesh = pmesh
	floor_mesh_inst.material_override = floor_material
	area_node.add_child(floor_mesh_inst)
	
	# StaticBody3D Collision
	var sb := StaticBody3D.new()
	sb.name = "StaticBody3D"
	var col_shape := CollisionShape3D.new()
	col_shape.name = "CollisionShape3D"
	col_shape.position = Vector3(0.0, -0.1, 0.0)
	var box := BoxShape3D.new()
	box.size = Vector3(p_size.x, 0.2, p_size.y)
	col_shape.shape = box
	sb.add_child(col_shape)
	
	# Perimeter boundary walls (1.8m tall invisible walls along shores)
	var half_w: float = p_size.x * 0.5
	var half_h: float = p_size.y * 0.5
	var wall_h: float = 2.0
	var wall_t: float = 0.5
	
	# Side walls: West & East
	_add_wall_barrier(sb, Vector3(wall_t, wall_h, p_size.y), Vector3(-half_w, wall_h * 0.5, 0.0))
	_add_wall_barrier(sb, Vector3(wall_t, wall_h, p_size.y), Vector3(half_w, wall_h * 0.5, 0.0))
	
	if has_pond:
		# Area 1 (Spawn): South wall is solid, North wall has opening for bridge
		_add_wall_barrier(sb, Vector3(p_size.x, wall_h, wall_t), Vector3(0.0, wall_h * 0.5, half_h))
		var wing_w: float = (p_size.x - bridge_width) * 0.5
		var wing_center: float = bridge_width * 0.5 + wing_w * 0.5
		_add_wall_barrier(sb, Vector3(wing_w, wall_h, wall_t), Vector3(-wing_center, wall_h * 0.5, -half_h))
		_add_wall_barrier(sb, Vector3(wing_w, wall_h, wall_t), Vector3(wing_center, wall_h * 0.5, -half_h))
	else:
		# Area 2 (Arena): North wall is solid, South wall has opening for bridge
		_add_wall_barrier(sb, Vector3(p_size.x, wall_h, wall_t), Vector3(0.0, wall_h * 0.5, -half_h))
		var wing_w: float = (p_size.x - bridge_width) * 0.5
		var wing_center: float = bridge_width * 0.5 + wing_w * 0.5
		_add_wall_barrier(sb, Vector3(wing_w, wall_h, wall_t), Vector3(-wing_center, wall_h * 0.5, half_h))
		_add_wall_barrier(sb, Vector3(wing_w, wall_h, wall_t), Vector3(wing_center, wall_h * 0.5, half_h))
	
	floor_mesh_inst.add_child(sb)
	
	# Grass MultiMesh
	var grass_inst := MultiMeshInstance3D.new()
	grass_inst.name = "Grass"
	grass_inst.add_to_group("grass")
	grass_inst.material_override = grass_material
	grass_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	grass_inst.multimesh = grass_multimesh
	area_node.add_child(grass_inst)

func _add_wall_barrier(parent_sb: StaticBody3D, size: Vector3, pos: Vector3) -> void:
	var barrier := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	barrier.shape = box
	barrier.position = pos
	parent_sb.add_child(barrier)

func _build_bridge(p_name: String, p_center: Vector3, p_size: Vector2) -> void:
	var bridge_node := Node3D.new()
	bridge_node.name = p_name
	bridge_node.position = p_center
	bridges_root.add_child(bridge_node)
	
	# Bridge Floor Mesh
	var bridge_mesh_inst := MeshInstance3D.new()
	bridge_mesh_inst.name = "BridgeFloor"
	var pmesh := PlaneMesh.new()
	pmesh.size = p_size
	bridge_mesh_inst.mesh = pmesh
	
	bridge_mesh_inst.material_override = floor_material
	bridge_node.add_child(bridge_mesh_inst)
	
	# StaticBody3D Collision
	var sb := StaticBody3D.new()
	sb.name = "StaticBody3D"
	var col_shape := CollisionShape3D.new()
	col_shape.name = "CollisionShape3D"
	col_shape.position = Vector3(0.0, -0.1, 0.0)
	var box := BoxShape3D.new()
	box.size = Vector3(p_size.x, 0.2, p_size.y)
	col_shape.shape = box
	sb.add_child(col_shape)
	
	# Side collision barriers along left & right bridge edges to prevent falling into water
	var left_barrier := CollisionShape3D.new()
	var right_barrier := CollisionShape3D.new()
	var barrier_box := BoxShape3D.new()
	barrier_box.size = Vector3(0.4, 2.0, p_size.y)
	left_barrier.shape = barrier_box
	right_barrier.shape = barrier_box
	left_barrier.position = Vector3(-p_size.x * 0.5, 0.9, 0.0)
	right_barrier.position = Vector3(p_size.x * 0.5, 0.9, 0.0)
	sb.add_child(left_barrier)
	sb.add_child(right_barrier)
	bridge_mesh_inst.add_child(sb)
	
	# Bridge Grass MultiMesh cropped directly from the original terrain grass_multimesh
	var grass_inst := MultiMeshInstance3D.new()
	grass_inst.name = "BridgeGrass"
	grass_inst.add_to_group("grass")
	grass_inst.material_override = grass_material
	grass_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	var crop_box := Rect2(-p_size.x * 0.5, -(p_size.y + 0.4) * 0.5, p_size.x, p_size.y + 0.4)
	grass_inst.multimesh = _crop_multimesh(grass_multimesh, crop_box)
	bridge_node.add_child(grass_inst)

func _crop_multimesh(source_mm: MultiMesh, crop_rect: Rect2) -> MultiMesh:
	var count: int = source_mm.instance_count
	var kept: Array[Transform3D] = []
	for i in range(count):
		var t: Transform3D = source_mm.get_instance_transform(i)
		if crop_rect.has_point(Vector2(t.origin.x, t.origin.z)):
			kept.append(t)
			
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = source_mm.mesh
	mm.instance_count = kept.size()
	mm.visible_instance_count = kept.size()
	for i in range(kept.size()):
		mm.set_instance_transform(i, kept[i])
	return mm

func _build_surrounding_water() -> void:
	water_instance = MeshInstance3D.new()
	water_instance.name = "SurroundingWater"
	
	var water_pmesh := PlaneMesh.new()
	water_pmesh.size = Vector2(250.0, 250.0)
	water_pmesh.subdivide_width = 64
	water_pmesh.subdivide_depth = 64
	
	water_instance.mesh = water_pmesh
	water_instance.material_override = water_material
	water_instance.position = Vector3(0.0, -0.05, bridge_center.z)
	add_child(water_instance)

func _build_spawn_pond() -> void:
	pond_instance = MeshInstance3D.new()
	pond_instance.name = "SpawnPond"
	
	var pond_pmesh := PlaneMesh.new()
	pond_pmesh.size = Vector2(6.0, 6.0)
	pond_pmesh.subdivide_width = 16
	pond_pmesh.subdivide_depth = 16
	
	pond_instance.mesh = pond_pmesh
	pond_instance.material_override = pond_material
	# Placed in Area 1 at original position (0, 0.05, 0)
	pond_instance.position = Vector3(0.0, 0.05, 0.0)
	add_child(pond_instance)
