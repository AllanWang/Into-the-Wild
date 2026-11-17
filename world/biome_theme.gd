class_name BiomeTheme
extends Resource

## Painterly Toon Biome Catalog (Shape of Dreams x Arcane aesthetic).
## Defines coordinated Floor, Grass, Water/Lava/Void, Shoreline Skirt, VineBarrier,
## DirectionalLight, Ambient Environment, and 3D Landmark palettes for all 5 biomes.

enum BiomeId {
	VERDANT_MEADOW = 0,
	GLACIAL_FROSTFIELD = 1,
	ASTRAL_CONSTELLATION = 2,
	VOLCANIC_CALDERA = 3,
	ARCANE_ANOMALY = 4
}

const BIOME_COUNT: int = 5

@export var theme_name: String = "Verdant Meadow"
@export var ground_material: Material
@export var boundary_material: Material
@export var boundary_depth: float = -0.15
@export var skirt_depth: float = 0.35
@export var enable_foliage: bool = true
@export var foliage_mesh: Mesh
@export var foliage_material: Material
@export var foliage_density: float = 5.5
@export var max_foliage_instances: int = 25000

static var _presets: Dictionary = {}


static func get_biome_count() -> int:
	return BIOME_COUNT


static func get_biome_name(biome_id: int) -> String:
	var d: Dictionary = get_biome_data(biome_id)
	return str(d.get("name", "Verdant Meadow"))


static func get_biome_data(biome_id: int) -> Dictionary:
	_ensure_presets()
	var idx: int = posmod(biome_id, BIOME_COUNT)
	return _presets[idx] as Dictionary


static func _ensure_presets() -> void:
	if not _presets.is_empty():
		return

	# 0. Verdant Meadow (Classic Studio Ghibli / Shape of Dreams sunlit meadow)
	_presets[BiomeId.VERDANT_MEADOW] = {
		"id": BiomeId.VERDANT_MEADOW,
		"name": "Verdant Meadow",
		"floor_a1": Color(0.443, 0.635, 0.0, 1.0),
		"floor_a2": Color(0.557, 0.678, 0.212, 1.0),
		"floor_a3": Color(0.502, 0.655, 0.224, 1.0),
		"bank_col": Color(0.55, 0.62, 0.35, 1.0),
		"skirt_col": Color(0.36, 0.54, 0.08, 1.0),
		"fx_mode": 0,
		"fx_c1": Color(0.6, 0.9, 0.4, 1.0),
		"fx_c2": Color(0.4, 0.8, 0.3, 1.0),
		"fx_c3": Color(0.9, 1.0, 0.6, 1.0),
		"fx_emit": 0.0,
		"blade_density": 1.0,
		"blade_scale": 1.0,
		"grass_acc1": Color(0.604, 0.718, 0.0, 1.0),
		"grass_acc2": Color(0.424, 0.604, 0.0, 1.0),
		"tip_col": Color(0.0, 0.0, 0.0, 1.0),
		"tip_emit": 0.0,
		"anomaly_iri": false,
		"water_shallow": Color(0.38, 0.82, 0.90, 0.90),
		"water_deep": Color(0.18, 0.52, 0.78, 0.95),
		"water_foam": Color(1.0, 1.0, 1.0, 1.0),
		"water_foam2": Color(1.0, 1.0, 1.0, 1.0),
		"water_cutoff": 0.78,
		"water_chromatic": false,
		"water_emit": 0.0,
		"ambient_col": Color(0.651, 0.749, 0.851, 1.0),
		"ambient_energy": 0.82,
		"light_col": Color(1.0, 0.98, 0.94, 1.0),
		"light_energy": 1.0,
		"vine_dark": Color(0.13, 0.33, 0.11, 1.0),
		"vine_moss": Color(0.24, 0.53, 0.16, 1.0),
		"vine_bud": Color(1.0, 0.34, 0.48, 1.0),
		"prop_primary": Color(0.88, 0.94, 0.72, 1.0),
		"prop_secondary": Color(0.46, 0.74, 0.32, 1.0)
	}

	# 1. Glacial Frostfield (Rich glacier-cerulean ice sheet, frost fracture veins & clustered rime tufts)
	_presets[BiomeId.GLACIAL_FROSTFIELD] = {
		"id": BiomeId.GLACIAL_FROSTFIELD,
		"name": "Glacial Frostfield",
		"floor_a1": Color(0.36, 0.62, 0.86, 1.0),
		"floor_a2": Color(0.52, 0.76, 0.95, 1.0),
		"floor_a3": Color(0.28, 0.50, 0.78, 1.0),
		"bank_col": Color(0.76, 0.92, 1.0, 1.0),
		"skirt_col": Color(0.16, 0.34, 0.62, 1.0),
		"fx_mode": 1,
		"fx_c1": Color(0.90, 0.98, 1.0, 1.0),
		"fx_c2": Color(0.46, 0.88, 1.0, 1.0),
		"fx_c3": Color(0.76, 0.94, 1.0, 1.0),
		"fx_emit": 0.34,
		"blade_density": 0.32,
		"blade_scale": 0.86,
		"grass_acc1": Color(0.92, 0.98, 1.0, 1.0),
		"grass_acc2": Color(0.58, 0.88, 1.0, 1.0),
		"tip_col": Color(0.88, 0.98, 1.0, 1.0),
		"tip_emit": 0.36,
		"anomaly_iri": false,
		"water_shallow": Color(0.14, 0.44, 0.72, 0.94),
		"water_deep": Color(0.05, 0.18, 0.38, 0.98),
		"water_foam": Color(0.88, 0.98, 1.0, 1.0),
		"water_foam2": Color(0.62, 0.90, 1.0, 1.0),
		"water_cutoff": 0.62,
		"water_chromatic": false,
		"water_emit": 0.24,
		"ambient_col": Color(0.62, 0.80, 0.96, 1.0),
		"ambient_energy": 0.84,
		"light_col": Color(0.90, 0.96, 1.0, 1.0),
		"light_energy": 0.98,
		"vine_dark": Color(0.16, 0.38, 0.64, 1.0),
		"vine_moss": Color(0.48, 0.82, 0.98, 1.0),
		"vine_bud": Color(0.86, 0.98, 1.0, 1.0),
		"prop_primary": Color(0.52, 0.88, 1.0, 1.0),
		"prop_secondary": Color(0.90, 0.98, 1.0, 1.0)
	}

	# 2. Astral Constellation (Shape of Dreams velvet cosmos, starfield & golden/cyan constellation threads)
	_presets[BiomeId.ASTRAL_CONSTELLATION] = {
		"id": BiomeId.ASTRAL_CONSTELLATION,
		"name": "Astral Constellation",
		"floor_a1": Color(0.09, 0.08, 0.22, 1.0),
		"floor_a2": Color(0.16, 0.12, 0.36, 1.0),
		"floor_a3": Color(0.11, 0.18, 0.40, 1.0),
		"bank_col": Color(0.38, 0.64, 0.96, 1.0),
		"skirt_col": Color(0.06, 0.05, 0.16, 1.0),
		"fx_mode": 2,
		"fx_c1": Color(0.46, 0.90, 1.0, 1.0),
		"fx_c2": Color(0.70, 0.46, 1.0, 1.0),
		"fx_c3": Color(1.0, 0.88, 0.46, 1.0),
		"fx_emit": 1.15,
		"blade_density": 0.26,
		"blade_scale": 0.88,
		"grass_acc1": Color(0.56, 0.90, 1.0, 1.0),
		"grass_acc2": Color(1.0, 0.86, 0.46, 1.0),
		"tip_col": Color(0.58, 0.88, 1.0, 1.0),
		"tip_emit": 0.72,
		"anomaly_iri": false,
		"water_shallow": Color(0.10, 0.08, 0.28, 0.96),
		"water_deep": Color(0.03, 0.02, 0.11, 0.99),
		"water_foam": Color(0.52, 0.90, 1.0, 1.0),
		"water_foam2": Color(1.0, 0.86, 0.46, 1.0),
		"water_cutoff": 0.60,
		"water_chromatic": true,
		"water_emit": 1.10,
		"ambient_col": Color(0.48, 0.46, 0.82, 1.0),
		"ambient_energy": 0.86,
		"light_col": Color(0.86, 0.88, 1.0, 1.0),
		"light_energy": 0.96,
		"vine_dark": Color(0.16, 0.14, 0.38, 1.0),
		"vine_moss": Color(0.38, 0.32, 0.74, 1.0),
		"vine_bud": Color(1.0, 0.88, 0.46, 1.0),
		"prop_primary": Color(1.0, 0.85, 0.42, 1.0),
		"prop_secondary": Color(0.50, 0.90, 1.0, 1.0)
	}

	# 3. Volcanic Caldera (Dark obsidian basalt plates, glowing magma fissures & molten lava sea)
	_presets[BiomeId.VOLCANIC_CALDERA] = {
		"id": BiomeId.VOLCANIC_CALDERA,
		"name": "Volcanic Caldera",
		"floor_a1": Color(0.13, 0.11, 0.14, 1.0),
		"floor_a2": Color(0.20, 0.15, 0.17, 1.0),
		"floor_a3": Color(0.25, 0.16, 0.15, 1.0),
		"bank_col": Color(0.86, 0.32, 0.08, 1.0),
		"skirt_col": Color(0.10, 0.07, 0.08, 1.0),
		"fx_mode": 3,
		"fx_c1": Color(1.0, 0.88, 0.28, 1.0),
		"fx_c2": Color(0.98, 0.30, 0.06, 1.0),
		"fx_c3": Color(1.0, 0.56, 0.14, 1.0),
		"fx_emit": 1.45,
		"blade_density": 0.20,
		"blade_scale": 0.76,
		"grass_acc1": Color(1.0, 0.56, 0.14, 1.0),
		"grass_acc2": Color(0.92, 0.28, 0.10, 1.0),
		"tip_col": Color(1.0, 0.54, 0.12, 1.0),
		"tip_emit": 0.85,
		"anomaly_iri": false,
		"water_shallow": Color(0.92, 0.30, 0.06, 0.96),
		"water_deep": Color(0.46, 0.07, 0.04, 0.99),
		"water_foam": Color(1.0, 0.86, 0.24, 1.0),
		"water_foam2": Color(1.0, 0.52, 0.10, 1.0),
		"water_cutoff": 0.56,
		"water_chromatic": false,
		"water_emit": 1.35,
		"ambient_col": Color(0.78, 0.56, 0.50, 1.0),
		"ambient_energy": 0.84,
		"light_col": Color(1.0, 0.88, 0.76, 1.0),
		"light_energy": 1.02,
		"vine_dark": Color(0.18, 0.11, 0.12, 1.0),
		"vine_moss": Color(0.52, 0.20, 0.12, 1.0),
		"vine_bud": Color(1.0, 0.76, 0.20, 1.0),
		"prop_primary": Color(0.19, 0.15, 0.18, 1.0),
		"prop_secondary": Color(1.0, 0.58, 0.14, 1.0)
	}

	# 4. Arcane Anomaly (League of Legends Arcane Wild-Rune / Hexcore oil-slick iridescence!)
	_presets[BiomeId.ARCANE_ANOMALY] = {
		"id": BiomeId.ARCANE_ANOMALY,
		"name": "Arcane Anomaly",
		"floor_a1": Color(0.10, 0.07, 0.18, 1.0),
		"floor_a2": Color(0.18, 0.09, 0.28, 1.0),
		"floor_a3": Color(0.08, 0.18, 0.26, 1.0),
		"bank_col": Color(0.16, 0.88, 0.96, 1.0),
		"skirt_col": Color(0.08, 0.05, 0.15, 1.0),
		"fx_mode": 4,
		"fx_c1": Color(0.12, 0.96, 1.0, 1.0),   # Hextech Electric Cyan
		"fx_c2": Color(1.0, 0.18, 0.68, 1.0),   # Shimmer Neon Magenta
		"fx_c3": Color(1.0, 0.90, 0.52, 1.0),   # Wild Rune Gold
		"fx_emit": 1.25,
		"blade_density": 0.34,
		"blade_scale": 0.94,
		"grass_acc1": Color(0.16, 0.96, 1.0, 1.0),
		"grass_acc2": Color(1.0, 0.24, 0.70, 1.0),
		"tip_col": Color(0.22, 0.94, 1.0, 1.0),
		"tip_emit": 0.85,
		"anomaly_iri": true,
		"water_shallow": Color(0.15, 0.08, 0.28, 0.96),
		"water_deep": Color(0.05, 0.03, 0.12, 0.99),
		"water_foam": Color(0.14, 0.96, 1.0, 1.0),
		"water_foam2": Color(1.0, 0.22, 0.68, 1.0),
		"water_cutoff": 0.58,
		"water_chromatic": true,
		"water_emit": 1.25,
		"ambient_col": Color(0.56, 0.52, 0.82, 1.0),
		"ambient_energy": 0.86,
		"light_col": Color(0.92, 0.88, 1.0, 1.0),
		"light_energy": 0.98,
		"vine_dark": Color(0.15, 0.10, 0.28, 1.0),
		"vine_moss": Color(0.14, 0.68, 0.82, 1.0),
		"vine_bud": Color(1.0, 0.24, 0.70, 1.0),
		"prop_primary": Color(0.14, 0.94, 1.0, 1.0),
		"prop_secondary": Color(1.0, 0.22, 0.68, 1.0)
	}
