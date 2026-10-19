class_name NodePool
extends Node

## Generic object pool for any PackedScene (projectiles, enemies, particles, UI items).
## Minimizes SceneTree churn and memory allocation spikes by recycling inactive nodes.

@export var scene: PackedScene
@export var initial_size: int = 32
@export var max_size: int = 128
@export var can_grow: bool = true

## Optional custom container node where pooled instances will be added as children.
## If null, pooled instances are added as children of this NodePool node.
@export var container: Node = null

var _available: Array[Node] = []
var _active: Array[Node] = []

func _ready() -> void:
	if scene and initial_size > 0:
		prewarm(initial_size)

## Pre-allocates a specific number of scene instances into the pool.
func prewarm(count: int) -> void:
	if not scene:
		push_warning("[NodePool] Cannot prewarm without a valid scene assigned.")
		return
	for i in range(count):
		if max_size > 0 and get_total_count() >= max_size:
			break
		var inst := _create_instance()
		_available.append(inst)

## Acquires an instance from the pool. Creates a new one if available pool is empty and can_grow is true.
func acquire() -> Node:
	var inst: Node = null
	
	while not _available.is_empty():
		var candidate: Node = _available.pop_back()
		if is_instance_valid(candidate):
			inst = candidate
			break
			
	if not inst:
		if can_grow and (max_size <= 0 or get_total_count() < max_size):
			inst = _create_instance()
		else:
			push_warning("[NodePool] Exhausted pool for %s (active: %d, max: %d)" % [
				scene.resource_path if scene else "unknown", _active.size(), max_size
			])
			return null
			
	_active.append(inst)
	
	# Lifecycle callback on target instance if implemented
	if inst.has_method("on_pool_acquire"):
		inst.on_pool_acquire()
		
	return inst

## Returns an active node back to the pool.
func release(inst: Node) -> void:
	if not is_instance_valid(inst):
		return
		
	var idx := _active.find(inst)
	if idx != -1:
		_active.remove_at(idx)
	elif _available.has(inst):
		# Already in available pool
		return
		
	_available.append(inst)
	
	# Lifecycle callback on target instance if implemented
	if inst.has_method("on_pool_release"):
		inst.on_pool_release()
	else:
		# Default fallback deactivation for general nodes
		inst.set_process(false)
		inst.set_physics_process(false)
		if inst is Node3D:
			(inst as Node3D).visible = false
		elif inst is CanvasItem:
			(inst as CanvasItem).visible = false
		if inst is CollisionObject3D:
			(inst as CollisionObject3D).set_deferred("collision_layer", 0)

## Recycles all currently active instances back into the pool.
func release_all() -> void:
	var active_copy := _active.duplicate()
	for inst in active_copy:
		release(inst)

## Destroys all pooled instances (e.g. on full cleanup).
func clear_pool() -> void:
	for inst in _active:
		if is_instance_valid(inst):
			inst.queue_free()
	for inst in _available:
		if is_instance_valid(inst):
			inst.queue_free()
	_active.clear()
	_available.clear()

func get_active_count() -> int:
	return _active.size()

func get_available_count() -> int:
	return _available.size()

func get_total_count() -> int:
	return _active.size() + _available.size()

func _create_instance() -> Node:
	var inst := scene.instantiate()
	
	# Set pool reference on instance if property exists
	if "pool" in inst:
		inst.pool = self
		
	var target_parent: Node = container if container and is_instance_valid(container) else self
	target_parent.add_child(inst)
	
	# Immediately deactivate new instance
	if inst.has_method("on_pool_release"):
		inst.on_pool_release()
	elif inst.has_method("deactivate"):
		inst.deactivate()
	else:
		inst.set_process(false)
		inst.set_physics_process(false)
		if inst is Node3D:
			(inst as Node3D).visible = false
		elif inst is CanvasItem:
			(inst as CanvasItem).visible = false
			
	return inst
