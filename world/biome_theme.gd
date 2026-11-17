class_name BiomeTheme
extends Resource

## Painterly Toon Biome Catalog (Shape of Dreams x Arcane aesthetic).
## - Only Verdant Meadow uses the grass blade MultiMesh (`enable_grass = true`).
## - Non-grass biomes use broad, calm, low-frequency painterly floor washes so players,
##   enemies, and telegraphs pop with crisp figure-ground contrast, while bespoke 3D
##   shoreline & arena-edge sculptures establish each biome's world identity!

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

	# 0. Verdant Meadow (Classic Studio Ghibli / Shape of Dreams sunlit grass meadow)
	_presets[BiomeId.VERDANT_MEADOW] = {
		"id": BiomeId.VERDANT_MEADOW,
		"name": "Verdant Meadow",
		"enable_grass": true,
		"cloud_shadows": true,
		"floor_a1": Color(0.443, 0.635, 0.0, 1.0),
		"floor_a2": Color(0.557, 0.678, 0.212, 1.0),
		"floor_a3": Color(0.502, 0.655, 0.224, 1.0),
		"a2_scale": 0.11,
		"a3_scale": 0.10,
		"bank_col": Color(0.55, 0.62, 0.35, 1.0),
		"skirt_col": Color(0.36, 0.54, 0.08, 1.0),
		"curb_col": Color(0.56, 0.65, 0.36, 1.0),
		"curb_emit": 0.0,
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

	# 1. Glacial Frostfield (Voronoi glacier ice-sheet plates + deep cerulean crevasses vs. frigid Arctic abyss sea)
	_presets[BiomeId.GLACIAL_FROSTFIELD] = {
		"id": BiomeId.GLACIAL_FROSTFIELD,
		"name": "Glacial Frostfield",
		"enable_grass": false,
		"cloud_shadows": false,
		"floor_a1": Color(0.60, 0.78, 0.91, 1.0),
		"floor_a2": Color(0.72, 0.87, 0.96, 1.0),
		"floor_a3": Color(0.45, 0.66, 0.84, 1.0),
		"a2_scale": 0.018,
		"a3_scale": 0.012,
		"bank_col": Color(0.44, 0.66, 0.86, 1.0),
		"skirt_col": Color(0.12, 0.24, 0.42, 1.0),
		"curb_col": Color(0.86, 0.97, 1.0, 1.0),
		"curb_emit": 0.28,
		"fx_mode": 1,
		"fx_c1": Color(0.92, 0.98, 1.0, 1.0),
		"fx_c2": Color(0.08, 0.38, 0.68, 1.0),
		"fx_c3": Color(0.96, 0.99, 1.0, 1.0),
		"fx_emit": 0.16,
		"blade_density": 0.0,
		"blade_scale": 1.0,
		"grass_acc1": Color.WHITE,
		"grass_acc2": Color.WHITE,
		"tip_col": Color.BLACK,
		"tip_emit": 0.0,
		"anomaly_iri": false,
		"water_shallow": Color(0.05, 0.15, 0.28, 0.98),
		"water_deep": Color(0.02, 0.06, 0.14, 1.0),
		"water_foam": Color(0.84, 0.96, 1.0, 1.0),
		"water_foam2": Color(0.54, 0.82, 0.98, 1.0),
		"water_cutoff": 0.74,
		"water_chromatic": false,
		"water_emit": 0.12,
		"ambient_col": Color(0.62, 0.72, 0.88, 1.0),
		"ambient_energy": 0.80,
		"light_col": Color(0.95, 0.97, 1.0, 1.0),
		"light_energy": 0.92,
		"vine_dark": Color(0.28, 0.56, 0.82, 1.0),
		"vine_moss": Color(0.64, 0.90, 1.0, 1.0),
		"vine_bud": Color(0.90, 0.98, 1.0, 1.0),
		"prop_primary": Color(0.58, 0.86, 1.0, 1.0),
		"prop_secondary": Color(0.92, 0.98, 1.0, 1.0)
	}

	# 2. Astral Constellation (High-contrast astral-violet sanctuary marble + golden starlight rim vs. pitch-black cosmic abyss)
	_presets[BiomeId.ASTRAL_CONSTELLATION] = {
		"id": BiomeId.ASTRAL_CONSTELLATION,
		"name": "Astral Constellation",
		"enable_grass": false,
		"floor_a1": Color(0.21, 0.19, 0.39, 1.0),
		"floor_a2": Color(0.26, 0.23, 0.46, 1.0),
		"floor_a3": Color(0.17, 0.25, 0.44, 1.0),
		"a2_scale": 0.016,
		"a3_scale": 0.011,
		"bank_col": Color(0.36, 0.44, 0.72, 1.0),
		"skirt_col": Color(0.06, 0.06, 0.16, 1.0),
		"curb_col": Color(0.98, 0.84, 0.46, 1.0),
		"curb_emit": 0.65,
		"fx_mode": 2,
		"fx_c1": Color(0.52, 0.86, 1.0, 1.0),
		"fx_c2": Color(0.66, 0.46, 0.98, 1.0),
		"fx_c3": Color(1.0, 0.88, 0.50, 1.0),
		"fx_emit": 0.62,
		"blade_density": 0.0,
		"blade_scale": 1.0,
		"grass_acc1": Color.WHITE,
		"grass_acc2": Color.WHITE,
		"tip_col": Color.BLACK,
		"tip_emit": 0.0,
		"anomaly_iri": false,
		"water_shallow": Color(0.018, 0.014, 0.05, 0.99),
		"water_deep": Color(0.006, 0.005, 0.02, 1.0),
		"water_foam": Color(0.62, 0.84, 1.0, 1.0),
		"water_foam2": Color(0.98, 0.84, 0.48, 1.0),
		"water_cutoff": 0.72,
		"water_chromatic": true,
		"water_emit": 0.22,
		"ambient_col": Color(0.60, 0.62, 0.88, 1.0),
		"ambient_energy": 0.86,
		"light_col": Color(0.92, 0.94, 1.0, 1.0),
		"light_energy": 0.98,
		"vine_dark": Color(0.24, 0.22, 0.52, 1.0),
		"vine_moss": Color(0.44, 0.42, 0.82, 1.0),
		"vine_bud": Color(1.0, 0.88, 0.48, 1.0),
		"prop_primary": Color(0.98, 0.84, 0.46, 1.0),
		"prop_secondary": Color(0.52, 0.88, 1.0, 1.0)
	}

	# 3. Volcanic Caldera (Smooth dark matte basalt slabs + glowing molten lava sea around the islands)
	_presets[BiomeId.VOLCANIC_CALDERA] = {
		"id": BiomeId.VOLCANIC_CALDERA,
		"name": "Volcanic Caldera",
		"enable_grass": false,
		"floor_a1": Color(0.16, 0.14, 0.17, 1.0),
		"floor_a2": Color(0.21, 0.18, 0.20, 1.0),
		"floor_a3": Color(0.25, 0.19, 0.19, 1.0),
		"a2_scale": 0.017,
		"a3_scale": 0.011,
		"bank_col": Color(0.62, 0.24, 0.10, 1.0),
		"skirt_col": Color(0.11, 0.08, 0.09, 1.0),
		"curb_col": Color(0.96, 0.44, 0.12, 1.0),
		"curb_emit": 0.48,
		"fx_mode": 3,
		"fx_c1": Color(1.0, 0.68, 0.24, 1.0),
		"fx_c2": Color(0.84, 0.26, 0.08, 1.0),
		"fx_c3": Color(1.0, 0.48, 0.14, 1.0),
		"fx_emit": 0.38,
		"blade_density": 0.0,
		"blade_scale": 1.0,
		"grass_acc1": Color.WHITE,
		"grass_acc2": Color.WHITE,
		"tip_col": Color.BLACK,
		"tip_emit": 0.0,
		"anomaly_iri": false,
		"water_shallow": Color(0.84, 0.26, 0.06, 0.97),
		"water_deep": Color(0.42, 0.07, 0.04, 0.99),
		"water_foam": Color(1.0, 0.78, 0.22, 1.0),
		"water_foam2": Color(1.0, 0.48, 0.10, 1.0),
		"water_cutoff": 0.68,
		"water_chromatic": false,
		"water_emit": 0.95,
		"ambient_col": Color(0.76, 0.62, 0.58, 1.0),
		"ambient_energy": 0.84,
		"light_col": Color(1.0, 0.90, 0.80, 1.0),
		"light_energy": 1.0,
		"vine_dark": Color(0.20, 0.13, 0.14, 1.0),
		"vine_moss": Color(0.48, 0.20, 0.12, 1.0),
		"vine_bud": Color(1.0, 0.72, 0.20, 1.0),
		"prop_primary": Color(0.22, 0.18, 0.21, 1.0),
		"prop_secondary": Color(1.0, 0.56, 0.14, 1.0)
	}

	# 4. Arcane Anomaly (Moody Arcane painterly dusk-plum & teal washes + floating 3D Hexcore fractals!)
	_presets[BiomeId.ARCANE_ANOMALY] = {
		"id": BiomeId.ARCANE_ANOMALY,
		"name": "Arcane Anomaly",
		"enable_grass": false,
		"floor_a1": Color(0.14, 0.12, 0.22, 1.0),
		"floor_a2": Color(0.20, 0.14, 0.28, 1.0),
		"floor_a3": Color(0.12, 0.20, 0.26, 1.0),
		"a2_scale": 0.015,
		"a3_scale": 0.010,
		"bank_col": Color(0.20, 0.56, 0.68, 1.0),
		"skirt_col": Color(0.09, 0.07, 0.16, 1.0),
		"curb_col": Color(0.18, 0.88, 0.96, 1.0),
		"curb_emit": 0.52,
		"fx_mode": 4,
		"fx_c1": Color(0.16, 0.86, 0.96, 1.0),
		"fx_c2": Color(0.88, 0.24, 0.64, 1.0),
		"fx_c3": Color(0.98, 0.86, 0.52, 1.0),
		"fx_emit": 0.42,
		"blade_density": 0.0,
		"blade_scale": 1.0,
		"grass_acc1": Color.WHITE,
		"grass_acc2": Color.WHITE,
		"tip_col": Color.BLACK,
		"tip_emit": 0.0,
		"anomaly_iri": false,
		"water_shallow": Color(0.11, 0.07, 0.22, 0.97),
		"water_deep": Color(0.04, 0.03, 0.10, 0.99),
		"water_foam": Color(0.16, 0.90, 0.98, 1.0),
		"water_foam2": Color(0.92, 0.24, 0.66, 1.0),
		"water_chromatic": true,
		"water_cutoff": 0.68,
		"water_emit": 0.85,
		"ambient_col": Color(0.60, 0.58, 0.84, 1.0),
		"ambient_energy": 0.86,
		"light_col": Color(0.94, 0.90, 1.0, 1.0),
		"light_energy": 0.98,
		"vine_dark": Color(0.16, 0.12, 0.28, 1.0),
		"vine_moss": Color(0.16, 0.64, 0.78, 1.0),
		"vine_bud": Color(0.96, 0.28, 0.68, 1.0),
		"prop_primary": Color(0.18, 0.88, 0.98, 1.0),
		"prop_secondary": Color(0.94, 0.26, 0.68, 1.0)
	}
