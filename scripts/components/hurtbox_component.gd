class_name HurtboxComponent
extends Area3D

## Reusable hurtbox Area3D on Layer 3 (bitmask 4) that routes projectile/attack hits
## into an attached HealthComponent using deferred collision state toggles.

@export var health_component: HealthComponent

@onready var collision_shape: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D


func _ready() -> void:
	collision_layer = 4
	collision_mask = 0
	monitoring = false


func apply_hit(damage: float, hit_dir: Vector3 = Vector3.ZERO) -> bool:
	if health_component == null or health_component.is_dead:
		return false
	return health_component.take_damage(damage, hit_dir)


func set_active_deferred(active: bool) -> void:
	set_deferred("monitorable", active)
	if collision_shape == null:
		collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape:
		collision_shape.set_deferred("disabled", not active)
