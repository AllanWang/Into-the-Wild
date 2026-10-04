# MIT License. 
# Made by Dylearn

# Node for ease of editing shader globals

@tool
extends Node

@export var cloud_contrast : float:
	set(value):
		cloud_contrast = value
		RenderingServer.global_shader_parameter_set("cloud_contrast", value)

@export var cloud_direction : Vector2:
	set(value):
		cloud_direction = value
		RenderingServer.global_shader_parameter_set("cloud_direction", value)

@export var cloud_diverge_angle : float:
	set(value):
		cloud_diverge_angle = value
		RenderingServer.global_shader_parameter_set("cloud_diverge_angle", value)

@export var cloud_scale : float:
	set(value):
		cloud_scale = value
		RenderingServer.global_shader_parameter_set("cloud_scale", value)

@export var cloud_speed : float:
	set(value):
		cloud_speed = value
		RenderingServer.global_shader_parameter_set("cloud_speed", value)

@export var cloud_threshold : float:
	set(value):
		cloud_threshold = value
		RenderingServer.global_shader_parameter_set("cloud_threshold", value)

@export var cloud_shadow_min : float:
	set(value):
		cloud_shadow_min = value
		RenderingServer.global_shader_parameter_set("cloud_shadow_min", value)

@export var cloud_world_y : float:
	set(value):
		cloud_world_y = value
		RenderingServer.global_shader_parameter_set("cloud_world_y", value)


func _ready():
	if Engine.is_editor_hint():
		var val = RenderingServer.global_shader_parameter_get("cloud_contrast")
		if val != null: cloud_contrast = val
		val = RenderingServer.global_shader_parameter_get("cloud_direction")
		if val != null: cloud_direction = val
		val = RenderingServer.global_shader_parameter_get("cloud_diverge_angle")
		if val != null: cloud_diverge_angle = val
		val = RenderingServer.global_shader_parameter_get("cloud_scale")
		if val != null: cloud_scale = val
		val = RenderingServer.global_shader_parameter_get("cloud_speed")
		if val != null: cloud_speed = val
		val = RenderingServer.global_shader_parameter_get("cloud_threshold")
		if val != null: cloud_threshold = val
		val = RenderingServer.global_shader_parameter_get("cloud_shadow_min")
		if val != null: cloud_shadow_min = val
		val = RenderingServer.global_shader_parameter_get("cloud_world_y")
		if val != null: cloud_world_y = val
	else:
		RenderingServer.global_shader_parameter_set("cloud_contrast", cloud_contrast)
		RenderingServer.global_shader_parameter_set("cloud_direction", cloud_direction)
		RenderingServer.global_shader_parameter_set("cloud_diverge_angle", cloud_diverge_angle)
		RenderingServer.global_shader_parameter_set("cloud_scale", cloud_scale)
		RenderingServer.global_shader_parameter_set("cloud_speed", cloud_speed)
		RenderingServer.global_shader_parameter_set("cloud_threshold", cloud_threshold)
		RenderingServer.global_shader_parameter_set("cloud_shadow_min", cloud_shadow_min)
		RenderingServer.global_shader_parameter_set("cloud_world_y", cloud_world_y)
