class_name HealthComponent
extends Node

## Reusable health, shield, Hades-style yellow armor, and multi-bar phase-gate component.
## Emits upward signals; never references parent gameplay classes directly.

signal health_changed(current_hp: float, max_hp: float)
signal shield_changed(current_shield: float, max_hp: float)
signal armor_changed(current_armor: float, max_armor: float)
signal armor_broken()
signal bar_broken(remaining_bars: int, total_bars: int, bar_max_hp: float)
signal phase_gate_changed(is_impervious: bool, remaining_bars: int)
signal damaged(amount: float, hit_dir: Vector3)
signal healed(amount: float)
signal died()

@export var max_health: float = 3.0
@export var starting_shield: float = 0.0

var current_health: float = 3.0
var current_shield: float = 0.0
var max_armor: float = 0.0
var current_armor: float = 0.0
var total_bars: int = 1
var current_bar_index: int = 1
var phase_gate_duration: float = 0.0
var phase_gate_timer: float = 0.0
var is_dead: bool = false


func _ready() -> void:
	current_health = max_health
	current_shield = maxf(0.0, starting_shield)
	current_bar_index = maxi(1, total_bars)
	current_armor = maxf(0.0, max_armor)
	phase_gate_timer = 0.0
	is_dead = false
	set_process(false)


func _process(delta: float) -> void:
	if phase_gate_timer <= 0.0:
		set_process(false)
		return
	phase_gate_timer -= delta
	if phase_gate_timer <= 0.0:
		phase_gate_timer = 0.0
		set_process(false)
		phase_gate_changed.emit(false, current_bar_index)


func setup_max_health(p_max: float, p_shield: float = 0.0) -> void:
	setup_combat_bars(p_max, 1, 0.0, 0.0, p_shield)


## Configures multi-stock health bars, yellow Hades-style armor buffer, and phase-gate imperviousness.
func setup_combat_bars(
	p_bar_hp: float,
	p_total_bars: int,
	p_armor: float = 0.0,
	p_phase_gate_s: float = 0.0,
	p_shield: float = 0.0
) -> void:
	max_health = maxf(1.0, p_bar_hp)
	total_bars = maxi(1, p_total_bars)
	max_armor = maxf(0.0, p_armor)
	phase_gate_duration = maxf(0.0, p_phase_gate_s)
	starting_shield = maxf(0.0, p_shield)
	reset_health()


func reset_health() -> void:
	current_health = max_health
	current_bar_index = maxi(1, total_bars)
	current_armor = max_armor
	current_shield = maxf(0.0, starting_shield)
	phase_gate_timer = 0.0
	is_dead = false
	set_process(false)
	health_changed.emit(current_health, max_health)
	shield_changed.emit(current_shield, max_health)
	armor_changed.emit(current_armor, max_armor)
	phase_gate_changed.emit(false, current_bar_index)


func grant_armor(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	current_armor += amount
	max_armor = maxf(max_armor, current_armor)
	armor_changed.emit(current_armor, max_armor)


func has_armor() -> bool:
	return current_armor > 0.01


func is_impervious() -> bool:
	return phase_gate_timer > 0.0


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
	if is_dead or amount <= 0.0 or phase_gate_timer > 0.0:
		return false

	var remaining: float = amount
	if current_shield > 0.0:
		var absorbed_shield: float = minf(current_shield, remaining)
		current_shield = maxf(0.0, current_shield - absorbed_shield)
		remaining -= absorbed_shield
		shield_changed.emit(current_shield, max_health)

	if remaining > 0.0 and current_armor > 0.0:
		var absorbed_armor: float = minf(current_armor, remaining)
		current_armor = maxf(0.0, current_armor - absorbed_armor)
		remaining -= absorbed_armor
		armor_changed.emit(current_armor, max_armor)
		if current_armor <= 0.001:
			current_armor = 0.0
			armor_broken.emit()

	if remaining > 0.0:
		current_health = maxf(0.0, current_health - remaining)
		if current_health <= 0.001 and current_bar_index > 1:
			# Hades-style phase gate: clamp overflow at the bar boundary so next phase always plays out.
			current_bar_index -= 1
			current_health = max_health
			bar_broken.emit(current_bar_index, total_bars, max_health)
			health_changed.emit(current_health, max_health)
			if phase_gate_duration > 0.0:
				phase_gate_timer = phase_gate_duration
				set_process(true)
				phase_gate_changed.emit(true, current_bar_index)
			damaged.emit(amount, hit_dir)
			return true
		health_changed.emit(current_health, max_health)

	damaged.emit(amount, hit_dir)

	if current_health <= 0.0:
		current_health = 0.0
		is_dead = true
		died.emit()

	return true
