# MIT License. 
# Made by Dylearn

# Pass light direction to global shaders
# Auto-registered and cached to eliminate redundant per-frame updates

@tool
extends DirectionalLight3D

var _last_direction: Vector3 = Vector3.ZERO
var _registered: bool = false

func _ready() -> void:
	_update_light_direction(true)

func _process(_delta: float) -> void:
	_update_light_direction(false)

func _update_light_direction(force: bool) -> void:
	var current_direction: Vector3 = global_transform.basis.z.normalized()
	if not force and current_direction.is_equal_approx(_last_direction):
		return
	_last_direction = current_direction
	
	_ensure_global_param(current_direction)
	RenderingServer.global_shader_parameter_set("light_direction", current_direction)

func _ensure_global_param(default_val: Vector3) -> void:
	if _registered:
		return
	_registered = true
	if RenderingServer.global_shader_parameter_get_type("light_direction") == RenderingServer.GLOBAL_VAR_TYPE_MAX:
		RenderingServer.global_shader_parameter_add("light_direction", RenderingServer.GLOBAL_VAR_TYPE_VEC3, default_val)
