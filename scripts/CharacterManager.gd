# MIT License. 
# Made by Dylearn
# Extended for Water Ripples and Multi-Surface interaction

@tool
extends Node

@export var grass: MultiMeshInstance3D
@export var water_material: ShaderMaterial = preload("res://assets/water_pond_material.tres")

const MAX_CHARACTERS = 64
var character_positions: Array[Vector4] = []
@export var grass_framerate = 10.0
var grass_timer = 0.0

const MAX_RIPPLES = 8
# Each ripple is a Dictionary: { "x": pos.x, "z": pos.z, "time": 0.0, "max_time": 2.5, "max_radius": 1.4 }
var active_ripples: Array[Dictionary] = []
var ripple_uniform_data: Array[Vector4] = []

# Track previous inside-water state and movement of characters
var character_in_water: Dictionary = {}
var character_last_pos: Dictionary = {}

func _ready() -> void:
	character_positions.resize(MAX_CHARACTERS)
	character_positions.fill(Vector4.ZERO)
	ripple_uniform_data.resize(MAX_RIPPLES)
	ripple_uniform_data.fill(Vector4.ZERO)

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
	
	var characters = get_tree().get_nodes_in_group("characters")
	for i in range(min(characters.size(), MAX_CHARACTERS)):
		var character = characters[i]
		var size: float = character.grass_displacement_size if "grass_displacement_size" in character else 0.6
		var pos: Vector3 = character.global_transform.origin
		character_positions[i] = Vector4(pos.x, pos.y, pos.z, size)
	
	if grass and grass.material_override is ShaderMaterial:
		grass.material_override.set_shader_parameter("character_positions", character_positions)
	elif grass and grass.material_override:
		grass.material_override.set("shader_parameter/character_positions", character_positions)

func _is_pos_in_pond(pos: Vector3) -> bool:
	# Organic pond equation matching ToonWater.gdshader
	var angle = atan2(pos.z, pos.x)
	var distort = sin(angle * 2.0) * 0.45 + cos(angle * 3.0 + 0.8) * 0.3 + sin(angle * 5.0) * 0.15
	var pond_radius = 2.3 + distort
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
	var characters = get_tree().get_nodes_in_group("characters")
	
	for character in characters:
		var c_id = character.get_instance_id()
		var pos = character.global_transform.origin
		var in_water = _is_pos_in_pond(pos)
		var was_in_water = character_in_water.get(c_id, false)
		var last_pos = character_last_pos.get(c_id, pos)
		
		# Trigger ripples only upon entering the water or when moving in water
		if in_water and not was_in_water:
			# Player entered the water! Spawn entry ripples
			spawn_ripple(pos)
		elif in_water and was_in_water:
			# If moving significantly in the water, periodically spawn gentle step ripples
			var dist_moved = Vector2(pos.x - last_pos.x, pos.z - last_pos.z).length()
			if dist_moved > 0.65:
				spawn_ripple(pos)
				character_last_pos[c_id] = pos
		
		character_in_water[c_id] = in_water
		if not was_in_water:
			character_last_pos[c_id] = pos

	# Advance active ripples
	var i = active_ripples.size() - 1
	while i >= 0:
		active_ripples[i]["time"] += delta
		if active_ripples[i]["time"] >= active_ripples[i]["max_time"]:
			active_ripples.remove_at(i)
		i -= 1

	# Pack into ripple_uniform_data for the shader
	# x = world.x, y = world.z, z = current progress (0..1), w = current radius (>0 means active)
	ripple_uniform_data.fill(Vector4.ZERO)
	for idx in range(min(active_ripples.size(), MAX_RIPPLES)):
		var rip = active_ripples[idx]
		var progress = clampf(rip["time"] / rip["max_time"], 0.0, 1.0)
		var radius = rip["max_radius"] * progress
		ripple_uniform_data[idx] = Vector4(rip["x"], rip["z"], progress, radius)

	if water_material:
		water_material.set_shader_parameter("ripple_positions", ripple_uniform_data)
