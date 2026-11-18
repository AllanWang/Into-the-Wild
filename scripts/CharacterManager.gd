# MIT License. 
# Made by Dylearn
# Extended for Water Ripples and Multi-Surface interaction

@tool
extends Node

@export var grass: MultiMeshInstance3D
@export var water_material: ShaderMaterial = preload("res://assets/water_pond_material.tres")

const MAX_CHARACTERS = 64
const WEB_MAX_GRASS_CHARACTERS: int = 12
var character_positions: Array[Vector4] = []
@export var grass_framerate: float = 60.0
var grass_timer: float = 0.0

const MAX_RIPPLES = 8
# Each ripple is a Dictionary: { "x": pos.x, "z": pos.z, "time": 0.0, "max_time": 2.5, "max_radius": 1.4 }
var active_ripples: Array[Dictionary] = []
var ripple_uniform_data: Array[Vector4] = []
var _had_active_ripples: bool = false
var _web_best_dist2: PackedFloat32Array = PackedFloat32Array()

# Track previous inside-water state and movement of characters
var character_in_water: Dictionary = {}
var character_last_pos: Dictionary = {}

func _ready() -> void:
	character_positions.resize(MAX_CHARACTERS)
	character_positions.fill(Vector4.ZERO)
	ripple_uniform_data.resize(MAX_RIPPLES)
	ripple_uniform_data.fill(Vector4.ZERO)
	_web_best_dist2.resize(WEB_MAX_GRASS_CHARACTERS)

func _process(delta: float) -> void:
	if not is_inside_tree():
		return
	
	_update_water_ripples(delta)
	
	var grass_frametime = 1.0 / maxf(grass_framerate, 0.1)
	grass_timer += delta
	if grass_timer >= grass_frametime:
		grass_timer -= grass_frametime
		_update_grass()

func _update_grass() -> void:
	if character_positions.size() != MAX_CHARACTERS:
		character_positions.resize(MAX_CHARACTERS)
	character_positions.fill(Vector4.ZERO)

	var characters: Array[Node] = get_tree().get_nodes_in_group("characters")
	var is_web: bool = OS.has_feature("web")
	var use_editor_pos: bool = Engine.is_editor_hint()
	var active_count: int = 0

	if is_web and characters.size() > WEB_MAX_GRASS_CHARACTERS:
		if _web_best_dist2.size() != WEB_MAX_GRASS_CHARACTERS:
			_web_best_dist2.resize(WEB_MAX_GRASS_CHARACTERS)
		var focus_pt: Vector3 = Vector3.ZERO
		var cam: Camera3D = get_viewport().get_camera_3d()
		if cam != null:
			focus_pt = cam.global_position - Vector3(-18.0, 18.0, 18.0)

		for character in characters:
			if not (character is Node3D):
				continue
			var c3d: Node3D = character as Node3D
			if not c3d.is_visible_in_tree():
				continue
			var size: float = float(character.grass_displacement_size) if ("grass_displacement_size" in character) else 0.6
			var pos: Vector3 = c3d.global_transform.origin if use_editor_pos else c3d.get_global_transform_interpolated().origin
			var dx: float = pos.x - focus_pt.x
			var dz: float = pos.z - focus_pt.z
			var d2: float = dx * dx + dz * dz

			if active_count < WEB_MAX_GRASS_CHARACTERS:
				character_positions[active_count] = Vector4(pos.x, pos.y, pos.z, size)
				_web_best_dist2[active_count] = d2
				active_count += 1
			else:
				var worst_idx: int = 0
				var worst_d2: float = _web_best_dist2[0]
				for k in range(1, WEB_MAX_GRASS_CHARACTERS):
					if _web_best_dist2[k] > worst_d2:
						worst_d2 = _web_best_dist2[k]
						worst_idx = k
				if d2 < worst_d2:
					character_positions[worst_idx] = Vector4(pos.x, pos.y, pos.z, size)
					_web_best_dist2[worst_idx] = d2
	else:
		var cap: int = WEB_MAX_GRASS_CHARACTERS if is_web else MAX_CHARACTERS
		for character in characters:
			if active_count >= cap:
				break
			if character is Node3D and (character as Node3D).is_visible_in_tree():
				var c3d: Node3D = character as Node3D
				var size: float = float(character.grass_displacement_size) if ("grass_displacement_size" in character) else 0.6
				var pos: Vector3 = c3d.global_transform.origin if use_editor_pos else c3d.get_global_transform_interpolated().origin
				character_positions[active_count] = Vector4(pos.x, pos.y, pos.z, size)
				active_count += 1

	var mat: ShaderMaterial = null
	if grass and grass.material_override is ShaderMaterial:
		mat = grass.material_override as ShaderMaterial
	elif grass and grass.material_override:
		grass.material_override.set("shader_parameter/active_character_count", active_count)
		grass.material_override.set("shader_parameter/character_positions", character_positions)
		return
	else:
		var grass_nodes = get_tree().get_nodes_in_group("grass")
		for g in grass_nodes:
			if g is GeometryInstance3D and g.material_override is ShaderMaterial:
				mat = g.material_override as ShaderMaterial
				break

	if mat:
		mat.set_shader_parameter("active_character_count", active_count)
		mat.set_shader_parameter("character_positions", character_positions)

func _is_pos_in_pond(pos: Vector3) -> bool:
	if absf(pos.x) > 4.0 or absf(pos.z) > 4.0:
		return false
	# Organic pond equation matching ToonWater.gdshader
	var angle: float = atan2(pos.z, pos.x)
	var distort: float = sin(angle * 2.0) * 0.45 + cos(angle * 3.0 + 0.8) * 0.3 + sin(angle * 5.0) * 0.15
	var pond_radius: float = 2.3 + distort
	return Vector2(pos.x, pos.z).length() <= pond_radius

func spawn_ripple(world_pos: Vector3) -> void:
	# If we have reached capacity, remove the oldest ripple
	if active_ripples.size() >= MAX_RIPPLES:
		active_ripples.pop_front()
	active_ripples.append({
		"x": world_pos.x,
		"z": world_pos.z,
		"time": 0.0,
		"max_time": 2.2, # Slow, graceful lifetime
		"max_radius": 1.5
	})

func _update_water_ripples(delta: float) -> void:
	var characters: Array[Node] = get_tree().get_nodes_in_group("characters")
	var use_editor_pos: bool = Engine.is_editor_hint()

	for character in characters:
		if not (character is Node3D):
			continue
		var c3d: Node3D = character as Node3D
		var c_id: int = character.get_instance_id()
		var pos: Vector3 = c3d.global_transform.origin if use_editor_pos else c3d.get_global_transform_interpolated().origin
		var in_water: bool = _is_pos_in_pond(pos)
		var was_in_water: bool = bool(character_in_water.get(c_id, false))
		var last_pos: Vector3 = character_last_pos.get(c_id, pos) as Vector3

		# Trigger ripples only upon entering the water or when moving in water
		if in_water and not was_in_water:
			# Player entered the water! Spawn entry ripples
			spawn_ripple(pos)
		elif in_water and was_in_water:
			# If moving significantly in the water, periodically spawn gentle step ripples
			var dist_moved: float = Vector2(pos.x - last_pos.x, pos.z - last_pos.z).length()
			if dist_moved > 0.65:
				spawn_ripple(pos)
				character_last_pos[c_id] = pos

		character_in_water[c_id] = in_water
		if not was_in_water:
			character_last_pos[c_id] = pos

	# Advance active ripples
	var i: int = active_ripples.size() - 1
	while i >= 0:
		active_ripples[i]["time"] += delta
		if active_ripples[i]["time"] >= active_ripples[i]["max_time"]:
			active_ripples.remove_at(i)
		i -= 1

	var has_ripples: bool = not active_ripples.is_empty()
	if not has_ripples and not _had_active_ripples:
		return

	# Pack into ripple_uniform_data for the shader
	# x = world.x, y = world.z, z = current progress (0..1), w = current radius (>0 means active)
	ripple_uniform_data.fill(Vector4.ZERO)
	for idx in range(min(active_ripples.size(), MAX_RIPPLES)):
		var rip: Dictionary = active_ripples[idx]
		var progress: float = clampf(float(rip["time"]) / float(rip["max_time"]), 0.0, 1.0)
		var radius: float = float(rip["max_radius"]) * progress
		ripple_uniform_data[idx] = Vector4(float(rip["x"]), float(rip["z"]), progress, radius)

	if water_material:
		water_material.set_shader_parameter("ripple_positions", ripple_uniform_data)
	_had_active_ripples = has_ripples
