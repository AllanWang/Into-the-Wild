class_name HealthComponent
extends Node

## Reusable health and shield/barrier component.
## Emits upward signals; never references parent gameplay classes directly.

signal health_changed(current_hp: float, max_hp: float)
signal shield_changed(current_shield: float, max_hp: float)
signal damaged(amount: float, hit_dir: Vector3)
signal healed(amount: float)
signal died()

@export var max_health: float = 3.0
@export var starting_shield: float = 0.0

var current_health: float = 3.0
var current_shield: float = 0.0
var is_dead: bool = false


func _ready() -> void:
	current_health = max_health
	current_shield = maxf(0.0, starting_shield)
	is_dead = false


func setup_max_health(p_max: float, p_shield: float = 0.0) -> void:
	max_health = maxf(1.0, p_max)
	starting_shield = maxf(0.0, p_shield)
	reset_health()


func reset_health() -> void:
	current_health = max_health
	current_shield = maxf(0.0, starting_shield)
	is_dead = false
	health_changed.emit(current_health, max_health)
	shield_changed.emit(current_shield, max_health)


func set_shield(amount: float) -> void:
	if is_dead:
		return
	current_shield = maxf(0.0, amount)
	shield_changed.emit(current_shield, max_health)


func add_shield(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	current_shield += amount
	shield_changed.emit(current_shield, max_health)


func heal(amount: float) -> float:
	if is_dead or amount <= 0.0:
		return 0.0
	var before: float = current_health
	current_health = minf(max_health, current_health + amount)
	var gained: float = current_health - before
	if gained > 0.01:
		health_changed.emit(current_health, max_health)
		healed.emit(gained)
	return gained


func take_damage(amount: float, hit_dir: Vector3 = Vector3.ZERO) -> bool:
	if is_dead or amount <= 0.0:
		return false

	var remaining: float = amount
	if current_shield > 0.0:
		var absorbed: float = minf(current_shield, remaining)
		current_shield = maxf(0.0, current_shield - absorbed)
		remaining -= absorbed
		shield_changed.emit(current_shield, max_health)

	if remaining > 0.0:
		current_health = maxf(0.0, current_health - remaining)
		health_changed.emit(current_health, max_health)

	damaged.emit(amount, hit_dir)

	if current_health <= 0.0:
		is_dead = true
		died.emit()

	return true
