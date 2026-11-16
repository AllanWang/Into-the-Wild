class_name PlainsGenerator
extends ProceduralWorld

## Compatibility adapter for world/plains_level.tscn so both Main.tscn and
## plains_level.tscn share the exact same Shape of Dreams web layout, volumetric
## coastline walls, and 100% authentic grass_multimesh.tres tile-cropped texture.

signal map_generated(spawn_pos: Vector3, goal_pos: Vector3)


func _ready() -> void:
	auto_generate_on_ready = false
	super._ready()


## Generates or regenerates the procedural Dreamscape Web map (legacy signature)
func generate_map(p_seed: int = 0, p_mode: int = -1) -> void:
	var target_seed: int = p_seed if p_seed > 0 else -1
	generate_world(target_seed, p_mode)
	map_generated.emit(spawn_world_pos, goal_world_pos)
