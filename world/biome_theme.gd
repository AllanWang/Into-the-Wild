class_name BiomeTheme
extends Resource

## Data Resource defining the visual environment, shaders, materials,
## and foliage for procedurally generated levels.
## Decouples the procedural layout generator from any specific shader/biome.

@export var theme_name: String = "Default"

@export_group("Surfaces & Shaders")
@export var ground_material: Material
@export var boundary_material: Material
@export var boundary_depth: float = -0.15 ## Y-position of the surrounding liquid/void plane
@export var skirt_depth: float = 0.35    ## Vertical depth of the shoreline/cliff skirt mesh

@export_group("Foliage & Props")
@export var enable_foliage: bool = true
@export var foliage_mesh: Mesh
@export var foliage_material: Material
@export var foliage_density: float = 5.5  ## Instances per square meter of land
@export var max_foliage_instances: int = 25000
