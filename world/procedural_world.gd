class_name ProceduralWorld
extends Node3D

## Procedural World Generator for Shape of Dreams-style Arena & Causeway Webs.
## Builds a unified filleted landmass chunked into 40m x 40m regions for GPU frustum culling,
## zero-snag mitered ConvexPolygonShape3D coastline walls, and 100% authentic
## grass_multimesh.tres tile-cropped meadow textures.

const PlainsGraphScript = preload("res://world/plains_graph.gd")
const AreaPresetScript = preload("res://world/area_preset.gd")
const MapPresetConfigScript = preload("res://world/map_preset_config.gd")
const GrassTileStamperScript = preload("res://world/grass_tile_stamper.gd")
const BiomeThemeScript = preload("res://world/biome_theme.gd")
const VineBarrierScript = preload("res://world/vine_barrier.gd")
const SnowFootstepTrailScript = preload("res://world/snow_footstep_trail.gd")
const COSMIC_CORE_SHADER: Shader = preload("res://shaders/CosmicCore.gdshader")

const CHUNK_SIZE: float = 40.0

signal world_generated(spawn_pos: Vector3, goal_pos: Vector3)
signal graph_ready(graph: PlainsGraph)

@export_group("Preset & Seed")
@export var preset_mode: MapPresetConfig.TopologyMode = MapPresetConfig.TopologyMode.DREAMSCAPE_WEB
@export var map_seed: int = 0
@export var custom_preset: MapPresetConfig = null
@export var auto_generate_on_ready: bool = true

@export_group("Materials & Meshes")
@export var floor_material: ShaderMaterial = preload("res://assets/floor_material.tres")
@export var grass_material: ShaderMaterial = preload("res://assets/grass_material.tres")
@export var grass_multimesh: MultiMesh = preload("res://assets/grass_multimesh.tres")
@export var water_material: Material = preload("res://assets/plains_water_material.tres")
@export var pond_material: Material = preload("res://assets/water_pond_material.tres")

# Generated containers
var areas_root: Node3D = null
var bridges_root: Node3D = null
var props_root: Node3D = null
var collision_body: StaticBody3D = null
var skirt_instance: MeshInstance3D = null
var curb_instance: MeshInstance3D = null
var water_instance: MeshInstance3D = null
var pond_instance: MeshInstance3D = null
var snow_trail: Node3D = null

# Runtime state
var current_graph: PlainsGraph = null
var current_seed: int = 0
var current_biome_id: int = BiomeThemeScript.BiomeId.VERDANT_MEADOW
var total_grass_blades: int = 0
var spawn_world_pos: Vector3 = Vector3(0.0, 0.0, 6.8)
var goal_world_pos: Vector3 = Vector3.ZERO
var map_bounds_center: Vector3 = Vector3.ZERO
var map_bounds_span: Vector2 = Vector2(100.0, 100.0)

var _stamper: GrassTileStamper = null
var _skirt_material: StandardMaterial3D = null
var _curb_material: StandardMaterial3D = null
var _prop_mat_primary: StandardMaterial3D = null
var _prop_mat_secondary: StandardMaterial3D = null
var _outer_is_cw: bool = false
var _wake_pts: Array[Vector4] = [Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO]
var _wake_cursor: int = 0
var _last_wake_pos: Vector2 = Vector2(99999.0, 99999.0)

static var _mesh_ice_spire: CylinderMesh = null
static var _mesh_glacier_shelf: BoxMesh = null
static var _mesh_astral_obelisk: CylinderMesh = null
static var _mesh_hex_pillar: CylinderMesh = null
static var _mesh_astrolabe_ring: TorusMesh = null
static var _mesh_anomaly_ring: TorusMesh = null
static var _mesh_poly_core: SphereMesh = null
static var _mesh_octa_shard: SphereMesh = null
static var _mesh_medallion_plane: PlaneMesh = null
static var _mat_cosmic_medallion: ShaderMaterial = null


static func _ensure_prop_meshes() -> void:
	if _mesh_ice_spire != null:
		return

	_mesh_ice_spire = CylinderMesh.new()
	_mesh_ice_spire.top_radius = 0.04
	_mesh_ice_spire.bottom_radius = 0.56
	_mesh_ice_spire.height = 3.2
	_mesh_ice_spire.radial_segments = 5

	_mesh_glacier_shelf = BoxMesh.new()
	_mesh_glacier_shelf.size = Vector3(2.2, 1.25, 1.65)

	_mesh_astral_obelisk = CylinderMesh.new()
	_mesh_astral_obelisk.top_radius = 0.14
	_mesh_astral_obelisk.bottom_radius = 0.34
	_mesh_astral_obelisk.height = 2.6
	_mesh_astral_obelisk.radial_segments = 8

	_mesh_hex_pillar = CylinderMesh.new()
	_mesh_hex_pillar.top_radius = 0.62
	_mesh_hex_pillar.bottom_radius = 0.68
	_mesh_hex_pillar.height = 2.4
	_mesh_hex_pillar.radial_segments = 6

	_mesh_astrolabe_ring = TorusMesh.new()
	_mesh_astrolabe_ring.inner_radius = 1.18
	_mesh_astrolabe_ring.outer_radius = 1.26
	_mesh_astrolabe_ring.rings = 44
	_mesh_astrolabe_ring.ring_segments = 12

	_mesh_anomaly_ring = TorusMesh.new()
	_mesh_anomaly_ring.inner_radius = 0.92
	_mesh_anomaly_ring.outer_radius = 1.06
	_mesh_anomaly_ring.rings = 18
	_mesh_anomaly_ring.ring_segments = 6

	_mesh_poly_core = SphereMesh.new()
	_mesh_poly_core.radius = 0.54
	_mesh_poly_core.height = 1.08
	_mesh_poly_core.radial_segments = 6
	_mesh_poly_core.rings = 2

	_mesh_octa_shard = SphereMesh.new()
	_mesh_octa_shard.radius = 0.28
	_mesh_octa_shard.height = 0.68
	_mesh_octa_shard.radial_segments = 4
	_mesh_octa_shard.rings = 1

	_mesh_medallion_plane = PlaneMesh.new()
	_mesh_medallion_plane.size = Vector2(2.0, 2.0)

	_mat_cosmic_medallion = ShaderMaterial.new()
	_mat_cosmic_medallion.shader = COSMIC_CORE_SHADER


func _ready() -> void:
	set_process(false)
	_ensure_stamper()
	if auto_generate_on_ready:
		generate_world(map_seed, preset_mode, current_biome_id)


func _ensure_stamper() -> void:
	_ensure_prop_meshes()
	if _stamper == null:
		_stamper = GrassTileStamperScript.new()
		_stamper.initialize(grass_multimesh)
	if _skirt_material == null:
		_skirt_material = StandardMaterial3D.new()
		_skirt_material.albedo_color = Color(0.443137, 0.635294, 0.0, 1.0)
		_skirt_material.roughness = 1.0
		_skirt_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if _curb_material == null:
		_curb_material = StandardMaterial3D.new()
		_curb_material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		_curb_material.specular_mode = BaseMaterial3D.SPECULAR_TOON
		_curb_material.roughness = 0.38
		_curb_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if _prop_mat_primary == null:
		_prop_mat_primary = StandardMaterial3D.new()
		_prop_mat_primary.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		_prop_mat_primary.specular_mode = BaseMaterial3D.SPECULAR_TOON
		_prop_mat_primary.roughness = 0.35
		_prop_mat_primary.emission_enabled = true
	if _prop_mat_secondary == null:
		_prop_mat_secondary = StandardMaterial3D.new()
		_prop_mat_secondary.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if snow_trail == null or not is_instance_valid(snow_trail):
		snow_trail = SnowFootstepTrailScript.new()
		snow_trail.name = "SnowFootstepTrail"
		snow_trail.call("setup", self)
		add_child(snow_trail)


## Generates or regenerates the entire Shape of Dreams web world with coordinated Biome styling
func generate_world(p_seed: int = -1, p_mode: int = -1, p_biome: int = -1) -> void:
	_ensure_stamper()
	_cleanup()

	if p_mode >= 0:
		preset_mode = p_mode as MapPresetConfig.TopologyMode
	if p_biome >= 0:
		current_biome_id = posmod(p_biome, BiomeThemeScript.get_biome_count())

	var active_cfg: MapPresetConfig = custom_preset
	if active_cfg == null:
		active_cfg = MapPresetConfigScript.create_preset(preset_mode)

	var rng := RandomNumberGenerator.new()
	if p_seed > 0:
		rng.seed = p_seed
		current_seed = p_seed
	elif p_seed == 0 and map_seed > 0:
		rng.seed = map_seed
		current_seed = map_seed
	else:
		rng.randomize()
		current_seed = int(rng.seed & 0x7FFFFFFF)
		rng.seed = current_seed

	# 1. Synthesize planar Dreamscape Web graph with smooth filleted bridge throats & corners
	current_graph = PlainsGraphScript.generate_from_preset(rng, active_cfg)
	_outer_is_cw = bool(current_graph.get_meta("outer_is_cw", false))
	_compute_map_bounds()

	areas_root = Node3D.new()
	areas_root.name = "Areas"
	add_child(areas_root)

	bridges_root = Node3D.new()
	bridges_root.name = "Bridges"
	add_child(bridges_root)

	props_root = Node3D.new()
	props_root.name = "BiomeLandmarks"
	add_child(props_root)

	total_grass_blades = 0

	# 2. Apply Biome Shader Palette + Spawn Pond uniforms
	apply_biome_materials(current_biome_id)
	_sync_pond_uniforms(active_cfg.enable_spawn_pond)

	# 3. Build Seamless Chunked Floor & Tiled/Cropped Grass from the unified filleted landmass
	_build_chunked_filleted_landmass()

	# 4. Build Underwater Shoreline Rim Skirt & Highlighted Border Curb along all coastlines
	_build_shoreline_skirt()
	_build_shoreline_curb()

	# 5. Build Ground Floor + Watertight Mitered Coastline Collision Walls (zero corner snagging!)
	_build_world_collision()

	# 6. Build Surrounding Toon Water/Lava/Void & Optional Spawn Sanctuary Pond + 3D Biome Landmarks
	_build_surrounding_water()
	if active_cfg.enable_spawn_pond:
		_build_spawn_pond()
	_build_biome_landmarks(rng)

	var spawn_area: PlainsGraph.AreaData = current_graph.areas[current_graph.spawn_index]
	var goal_area: PlainsGraph.AreaData = current_graph.areas[current_graph.goal_index]

	if active_cfg.enable_spawn_pond:
		spawn_world_pos = Vector3(spawn_area.center.x, 0.0, spawn_area.center.y + 6.8)
	else:
		spawn_world_pos = Vector3(spawn_area.center.x, 0.0, spawn_area.center.y)
	goal_world_pos = Vector3(goal_area.center.x, 0.0, goal_area.center.y)

	graph_ready.emit(current_graph)
	world_generated.emit(spawn_world_pos, goal_world_pos)


func apply_biome_materials(biome_id: int) -> void:
	current_biome_id = posmod(biome_id, BiomeThemeScript.get_biome_count())
	var b: Dictionary = BiomeThemeScript.get_biome_data(current_biome_id)

	if floor_material:
		floor_material.set_shader_parameter("albedo1", b["floor_a1"])
		floor_material.set_shader_parameter("albedo2", b["floor_a2"])
		floor_material.set_shader_parameter("albedo3", b["floor_a3"])
		floor_material.set_shader_parameter("albedo2_scale", float(b.get("a2_scale", 0.11)))
		floor_material.set_shader_parameter("albedo3_scale", float(b.get("a3_scale", 0.10)))
		floor_material.set_shader_parameter("bank_color", b["bank_col"])
		floor_material.set_shader_parameter("biome_fx_mode", int(b["fx_mode"]))
		floor_material.set_shader_parameter("fx_color1", b["fx_c1"])
		floor_material.set_shader_parameter("fx_color2", b["fx_c2"])
		floor_material.set_shader_parameter("fx_color3", b["fx_c3"])
		floor_material.set_shader_parameter("fx_emission_strength", float(b["fx_emit"]))
		floor_material.set_shader_parameter("enable_cloud_shadows", (not OS.has_feature("web")) and bool(b.get("cloud_shadows", true)))

	if snow_trail and is_instance_valid(snow_trail):
		snow_trail.call("set_snow_enabled", current_biome_id == BiomeThemeScript.BiomeId.GLACIAL_FROSTFIELD)

	if grass_material:
		grass_material.set_shader_parameter("web_fast_mode", OS.has_feature("web"))
		grass_material.set_shader_parameter("albedo1", b["floor_a1"])
		grass_material.set_shader_parameter("albedo2", b["floor_a2"])
		grass_material.set_shader_parameter("albedo3", b["floor_a3"])
		grass_material.set_shader_parameter("blade_density", float(b["blade_density"]))
		var b_scale: float = float(b["blade_scale"])
		if OS.has_feature("web"):
			b_scale *= 1.16
		grass_material.set_shader_parameter("blade_scale", b_scale)
		grass_material.set_shader_parameter("accent_albedo1", b["grass_acc1"])
		grass_material.set_shader_parameter("accent_albedo2", b["grass_acc2"])
		grass_material.set_shader_parameter("tip_emission_color", b["tip_col"])
		grass_material.set_shader_parameter("tip_emission_strength", float(b["tip_emit"]))
		grass_material.set_shader_parameter("anomaly_iridescence", bool(b["anomaly_iri"]))

	for w_mat_var in [water_material, pond_material]:
		var w_mat: ShaderMaterial = w_mat_var as ShaderMaterial
		if w_mat:
			w_mat.set_shader_parameter("shallow_color", b["water_shallow"])
			w_mat.set_shader_parameter("deep_color", b["water_deep"])
			w_mat.set_shader_parameter("foam_color", b["water_foam"])
			w_mat.set_shader_parameter("secondary_foam_color", b["water_foam2"])
			w_mat.set_shader_parameter("surface_noise_cutoff", float(b["water_cutoff"]))
			w_mat.set_shader_parameter("chromatic_foam", bool(b["water_chromatic"]))
			w_mat.set_shader_parameter("cosmic_void", bool(b.get("water_cosmic", false)))
			w_mat.set_shader_parameter("emission_strength", float(b["water_emit"]))
			w_mat.set_shader_parameter("enable_cloud_shadows", not OS.has_feature("web"))

	if _skirt_material:
		_skirt_material.albedo_color = b["skirt_col"] as Color
	if _curb_material:
		var c_col: Color = b.get("curb_col", Color.WHITE) as Color
		var c_emit: float = float(b.get("curb_emit", 0.0))
		_curb_material.albedo_color = c_col
		_curb_material.emission_enabled = c_emit > 0.005
		_curb_material.emission = c_col
		_curb_material.emission_energy_multiplier = c_emit

	if _prop_mat_primary:
		var p1: Color = b["prop_primary"] as Color
		_prop_mat_primary.albedo_color = p1
		_prop_mat_primary.emission = p1.darkened(0.25)
		_prop_mat_primary.emission_energy_multiplier = 0.75 if current_biome_id != 3 else 0.18
	if _prop_mat_secondary:
		_prop_mat_secondary.albedo_color = b["prop_secondary"] as Color

	for i in range(4):
		_wake_pts[i] = Vector4(spawn_world_pos.x, 0.0, spawn_world_pos.z, 0.0)
	_wake_cursor = 0
	_last_wake_pos = Vector2(99999.0, 99999.0)
	if floor_material:
		floor_material.set_shader_parameter("player_focus_pos", spawn_world_pos)
		floor_material.set_shader_parameter("player_wake", _wake_pts)
	set_process(current_biome_id == BiomeThemeScript.BiomeId.ASTRAL_CONSTELLATION)

	VineBarrierScript.apply_biome_palette(
		b["vine_dark"] as Color,
		b["vine_moss"] as Color,
		b["vine_bud"] as Color,
		current_biome_id
	)


func _process(delta: float) -> void:
	if current_biome_id != BiomeThemeScript.BiomeId.ASTRAL_CONSTELLATION or floor_material == null:
		return
	var focus_pos: Vector3 = spawn_world_pos
	var parent_node: Node = get_parent()
	if parent_node != null:
		var players_node: Node = parent_node.get_node_or_null("Players")
		if players_node != null and players_node.get_child_count() > 0:
			var p3d: Node3D = players_node.get_child(0) as Node3D
			if p3d != null:
				focus_pos = p3d.global_position

	for i in range(4):
		_wake_pts[i].w = maxf(0.0, _wake_pts[i].w - delta * 0.30)

	var p2d := Vector2(focus_pos.x, focus_pos.z)
	if _last_wake_pos.distance_squared_to(p2d) >= 1.21:
		_wake_pts[_wake_cursor] = Vector4(focus_pos.x, 0.0, focus_pos.z, 1.0)
		_wake_cursor = (_wake_cursor + 1) % 4
		_last_wake_pos = p2d

	floor_material.set_shader_parameter("player_focus_pos", focus_pos)
	floor_material.set_shader_parameter("player_wake", _wake_pts)


func _build_biome_landmarks(rng: RandomNumberGenerator) -> void:
	if props_root == null or current_graph == null or current_biome_id == BiomeThemeScript.BiomeId.VERDANT_MEADOW:
		return

	# Place atmospheric 3D landmarks offshore along outer contours so combat arenas stay 100% snag-free!
	for poly in current_graph.outer_contours:
		var n: int = poly.size()
		if n < 6:
			continue
		var norm_sign: float = _contour_water_normal_sign(poly)
		var accum_dist: float = 0.0
		var next_spacing: float = rng.randf_range(9.0, 15.0)
		for i in range(n):
			var p1: Vector2 = poly[i]
			var p2: Vector2 = poly[(i + 1) % n]
			var seg_len: float = p1.distance_to(p2)
			if seg_len < 0.1:
				continue
			accum_dist += seg_len
			if accum_dist < next_spacing:
				continue
			accum_dist = 0.0
			next_spacing = rng.randf_range(11.0, 19.0)

			var edge_dir: Vector2 = (p2 - p1) / seg_len
			var out_norm: Vector2 = Vector2(-edge_dir.y, edge_dir.x) * norm_sign
			var mid: Vector2 = (p1 + p2) * 0.5

			# Subtle shoreline-rim crystal / basalt / hexcore accent right on the bank edge
			var rim_2d: Vector2 = mid - out_norm * 0.35
			if _is_point_on_filleted_land(rim_2d):
				_spawn_shoreline_rim_accent(Vector3(rim_2d.x, 0.0, rim_2d.y), rng)

			var offshore_dist: float = rng.randf_range(2.6, 5.8)
			var anchor_2d: Vector2 = mid + out_norm * offshore_dist
			if _is_point_on_filleted_land(anchor_2d):
				continue

			_spawn_single_biome_cluster(Vector3(anchor_2d.x, 0.0, anchor_2d.y), rng)

	if current_biome_id == BiomeThemeScript.BiomeId.ASTRAL_CONSTELLATION:
		_build_astral_ground_medallions()


func _build_astral_ground_medallions() -> void:
	if props_root == null or current_graph == null:
		return
	_ensure_prop_meshes()
	for area in current_graph.areas:
		if area.index == current_graph.spawn_index:
			continue
		var is_boss: bool = (area.index == current_graph.goal_index) or (area.role == AreaPresetScript.RoomRole.BOSS)
		var main_r: float = 5.0 if is_boss else (3.1 if (area.role == AreaPresetScript.RoomRole.HUB or area.role == AreaPresetScript.RoomRole.ELITE) else 2.35)
		_add_astral_medallion(Vector3(area.center.x, 0.014, area.center.y), main_r)
		if is_boss:
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var sat_2d := Vector2(area.center.x + sx * 8.8, area.center.y + sz * 8.8)
					if _is_point_on_filleted_land(sat_2d):
						_add_astral_medallion(Vector3(sat_2d.x, 0.014, sat_2d.y), 1.85)


func _add_astral_medallion(world_pos: Vector3, radius: float) -> void:
	var med := MeshInstance3D.new()
	med.name = "AstralGalaxyMedallion"
	med.mesh = _mesh_medallion_plane
	med.material_override = _mat_cosmic_medallion
	med.position = world_pos
	med.scale = Vector3(radius, 1.0, radius)
	med.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	props_root.add_child(med)


func _spawn_shoreline_rim_accent(rim_pos: Vector3, rng: RandomNumberGenerator) -> void:
	var accent := MeshInstance3D.new()
	accent.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	match current_biome_id:
		BiomeThemeScript.BiomeId.GLACIAL_FROSTFIELD:
			if rng.randf() < 0.45:
				accent.mesh = _mesh_glacier_shelf
				accent.material_override = _prop_mat_primary
				var sg: float = rng.randf_range(0.32, 0.52)
				accent.scale = Vector3(sg, sg * 0.34, sg * 0.85)
				accent.position = rim_pos + Vector3(0.0, sg * 0.14, 0.0)
				accent.rotation_degrees = Vector3(rng.randf_range(-8.0, 8.0), rng.randf_range(0.0, 360.0), rng.randf_range(-8.0, 8.0))
			else:
				accent.mesh = _mesh_ice_spire
				accent.material_override = _prop_mat_secondary
				var sc: float = rng.randf_range(0.24, 0.42)
				accent.scale = Vector3(sc, sc * 0.9, sc)
				accent.position = rim_pos + Vector3(0.0, sc * 1.1, 0.0)
				accent.rotation_degrees = Vector3(rng.randf_range(-18.0, 18.0), rng.randf_range(0.0, 360.0), rng.randf_range(-18.0, 18.0))
		BiomeThemeScript.BiomeId.ASTRAL_CONSTELLATION:
			if rng.randf() < 0.50:
				accent.mesh = _mesh_astral_obelisk
				accent.material_override = _prop_mat_primary
				var ob_s: float = rng.randf_range(0.26, 0.44)
				accent.scale = Vector3(ob_s, ob_s * 1.15, ob_s)
				accent.position = rim_pos + Vector3(0.0, ob_s * 1.2, 0.0)
				accent.rotation_degrees = Vector3(0.0, rng.randf_range(0.0, 360.0), 0.0)
			else:
				accent.mesh = _mesh_octa_shard
				accent.material_override = _prop_mat_secondary
				var sc_a: float = rng.randf_range(0.55, 0.95)
				accent.scale = Vector3.ONE * sc_a
				accent.position = rim_pos + Vector3(0.0, rng.randf_range(0.55, 1.05), 0.0)
				accent.rotation_degrees = Vector3(0.0, rng.randf_range(0.0, 360.0), 0.0)
		BiomeThemeScript.BiomeId.VOLCANIC_CALDERA:
			accent.mesh = _mesh_hex_pillar
			accent.material_override = _prop_mat_primary
			accent.scale = Vector3(rng.randf_range(0.45, 0.72), rng.randf_range(0.14, 0.30), rng.randf_range(0.45, 0.72))
			accent.position = rim_pos + Vector3(0.0, 0.12, 0.0)
			accent.rotation_degrees = Vector3(0.0, rng.randf_range(0.0, 360.0), 0.0)
		BiomeThemeScript.BiomeId.ARCANE_ANOMALY:
			accent.mesh = _mesh_poly_core
			accent.material_override = _prop_mat_primary if rng.randf() < 0.55 else _prop_mat_secondary
			var sc_h: float = rng.randf_range(0.28, 0.48)
			accent.scale = Vector3.ONE * sc_h
			accent.position = rim_pos + Vector3(0.0, rng.randf_range(0.52, 1.15), 0.0)
			accent.rotation_degrees = Vector3(rng.randf_range(0.0, 180.0), rng.randf_range(0.0, 180.0), 0.0)
	props_root.add_child(accent)


func _spawn_single_biome_cluster(base_pos: Vector3, rng: RandomNumberGenerator) -> void:
	match current_biome_id:
		BiomeThemeScript.BiomeId.GLACIAL_FROSTFIELD:
			# Tabular Glacier Iceberg Shelf + 2 Jagged Crystalline Spires along its crest
			var berg := MeshInstance3D.new()
			berg.mesh = _mesh_glacier_shelf
			berg.material_override = _prop_mat_primary
			var b_sc: float = rng.randf_range(0.85, 1.45)
			berg.scale = Vector3(b_sc, b_sc * rng.randf_range(0.55, 0.95), b_sc * rng.randf_range(0.8, 1.25))
			berg.position = base_pos + Vector3(0.0, 0.28 * b_sc, 0.0)
			berg.rotation_degrees = Vector3(rng.randf_range(-6.0, 6.0), rng.randf_range(0.0, 360.0), rng.randf_range(-6.0, 6.0))
			berg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			props_root.add_child(berg)

			for k in range(2):
				var spire := MeshInstance3D.new()
				spire.mesh = _mesh_ice_spire
				spire.material_override = _prop_mat_secondary if k == 0 else _prop_mat_primary
				var s_scale: float = rng.randf_range(0.65, 1.15) if k == 0 else rng.randf_range(0.42, 0.78)
				spire.scale = Vector3(s_scale, s_scale * rng.randf_range(0.85, 1.25), s_scale)
				spire.position = base_pos + Vector3(rng.randf_range(-0.65, 0.65), 0.75 * s_scale, rng.randf_range(-0.65, 0.65))
				spire.rotation_degrees = Vector3(rng.randf_range(-16.0, 16.0), rng.randf_range(0.0, 360.0), rng.randf_range(-16.0, 16.0))
				spire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				props_root.add_child(spire)

		BiomeThemeScript.BiomeId.ASTRAL_CONSTELLATION:
			# Anchored Celestial Obelisk + Floating Golden Astrolabe Ring & Glowing Cyan Star Core
			var obelisk := MeshInstance3D.new()
			obelisk.mesh = _mesh_astral_obelisk
			obelisk.material_override = _prop_mat_primary
			var ob_sc: float = rng.randf_range(0.70, 1.15)
			obelisk.scale = Vector3(ob_sc, ob_sc * 1.1, ob_sc)
			obelisk.position = base_pos + Vector3(0.0, 0.85 * ob_sc, 0.0)
			obelisk.rotation_degrees = Vector3(rng.randf_range(-6.0, 6.0), rng.randf_range(0.0, 360.0), rng.randf_range(-6.0, 6.0))
			obelisk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			props_root.add_child(obelisk)

			var hover_y: float = rng.randf_range(1.9, 3.1)
			var ring := MeshInstance3D.new()
			ring.mesh = _mesh_astrolabe_ring
			ring.material_override = _prop_mat_primary
			var r_sc: float = rng.randf_range(0.85, 1.45)
			ring.scale = Vector3.ONE * r_sc
			ring.position = base_pos + Vector3(0.0, hover_y, 0.0)
			ring.rotation_degrees = Vector3(rng.randf_range(35.0, 72.0), rng.randf_range(0.0, 360.0), rng.randf_range(-25.0, 25.0))
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			props_root.add_child(ring)

			var star := MeshInstance3D.new()
			star.mesh = _mesh_octa_shard
			star.material_override = _prop_mat_secondary
			star.scale = Vector3.ONE * (r_sc * 1.15)
			star.position = base_pos + Vector3(0.0, hover_y, 0.0)
			star.rotation_degrees = Vector3(0.0, rng.randf_range(0.0, 360.0), 0.0)
			star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			props_root.add_child(star)

		BiomeThemeScript.BiomeId.VOLCANIC_CALDERA:
			# Stepped cluster of 3 Hexagonal Basalt Columns + glowing Ember Shard
			for c_i in range(3):
				var col_inst := MeshInstance3D.new()
				col_inst.mesh = _mesh_hex_pillar
				col_inst.material_override = _prop_mat_primary
				var h_sc: float = rng.randf_range(0.55, 1.35)
				col_inst.scale = Vector3(rng.randf_range(0.75, 1.1), h_sc, rng.randf_range(0.75, 1.1))
				var ang: float = float(c_i) * (TAU / 3.0) + rng.randf_range(-0.3, 0.3)
				col_inst.position = base_pos + Vector3(cos(ang) * 0.72, h_sc * 0.65, sin(ang) * 0.72)
				col_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				props_root.add_child(col_inst)

			var ember := MeshInstance3D.new()
			ember.mesh = _mesh_octa_shard
			ember.material_override = _prop_mat_secondary
			ember.scale = Vector3.ONE * 0.85
			ember.position = base_pos + Vector3(0.0, rng.randf_range(1.9, 2.7), 0.0)
			ember.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			props_root.add_child(ember)

		BiomeThemeScript.BiomeId.ARCANE_ANOMALY:
			# Corrupted Arcane Hexcore Polyhedron + Twin Counter-Tilted Cyan/Magenta Halo Rings
			var anom_y: float = rng.randf_range(1.6, 3.1)
			var core := MeshInstance3D.new()
			core.mesh = _mesh_poly_core
			core.material_override = _prop_mat_primary
			var c_sc: float = rng.randf_range(0.8, 1.3)
			core.scale = Vector3.ONE * c_sc
			core.position = base_pos + Vector3(0.0, anom_y, 0.0)
			core.rotation_degrees = Vector3(rng.randf_range(0.0, 180.0), rng.randf_range(0.0, 180.0), 0.0)
			core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			props_root.add_child(core)

			for r_i in range(2):
				var h_ring := MeshInstance3D.new()
				h_ring.mesh = _mesh_anomaly_ring
				h_ring.material_override = _prop_mat_secondary if r_i == 0 else _prop_mat_primary
				h_ring.scale = Vector3.ONE * (c_sc * (1.15 + float(r_i) * 0.32))
				h_ring.position = base_pos + Vector3(0.0, anom_y, 0.0)
				h_ring.rotation_degrees = Vector3(52.0 if r_i == 0 else -48.0, rng.randf_range(0.0, 360.0), 34.0 if r_i == 0 else -38.0)
				h_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				props_root.add_child(h_ring)


## Returns world-space teleport waypoints ordered from Spawn -> Web Arenas -> Boss
func get_room_waypoints() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	if current_graph == null:
		return list

	for area in current_graph.areas:
		var pos3d := Vector3(area.center.x, 0.0, area.center.y)
		if area.index == current_graph.spawn_index and pond_instance != null:
			pos3d.z += 6.8
		list.append({
			"index": area.index,
			"label": "%s #%d" % [_role_name(area.role), area.index + 1],
			"role": area.role,
			"position": pos3d
		})
	return list


func _role_name(role: int) -> String:
	match role:
		AreaPresetScript.RoomRole.SPAWN:
			return "Sanctuary"
		AreaPresetScript.RoomRole.COMBAT:
			return "Arena"
		AreaPresetScript.RoomRole.ELITE:
			return "Elite"
		AreaPresetScript.RoomRole.DEADEND:
			return "Shrine"
		AreaPresetScript.RoomRole.HUB:
			return "Crossroads"
		AreaPresetScript.RoomRole.BOSS:
			return "Boss"
	return "Area"


func _cleanup() -> void:
	if areas_root and is_instance_valid(areas_root):
		areas_root.queue_free()
		areas_root = null
	if bridges_root and is_instance_valid(bridges_root):
		bridges_root.queue_free()
		bridges_root = null
	if props_root and is_instance_valid(props_root):
		props_root.queue_free()
		props_root = null
	if collision_body and is_instance_valid(collision_body):
		collision_body.queue_free()
		collision_body = null
	if skirt_instance and is_instance_valid(skirt_instance):
		skirt_instance.queue_free()
		skirt_instance = null
	if curb_instance and is_instance_valid(curb_instance):
		curb_instance.queue_free()
		curb_instance = null
	if water_instance and is_instance_valid(water_instance):
		water_instance.queue_free()
		water_instance = null
	if pond_instance and is_instance_valid(pond_instance):
		pond_instance.queue_free()
		pond_instance = null


func _sync_pond_uniforms(pond_enabled: bool) -> void:
	if floor_material:
		floor_material.set_shader_parameter("water_pool_center", Vector3.ZERO)
		floor_material.set_shader_parameter("water_pool_radius", 3.5 if pond_enabled else 0.0)
	if grass_material:
		grass_material.set_shader_parameter("water_pool_center", Vector3.ZERO)
		grass_material.set_shader_parameter("water_pool_radius", 4.2 if pond_enabled else 0.0)


func _compute_map_bounds() -> void:
	if current_graph == null or current_graph.outer_contours.is_empty():
		map_bounds_center = Vector3.ZERO
		map_bounds_span = Vector2(100.0, 100.0)
		return

	var min_pt := Vector2(INF, INF)
	var max_pt := Vector2(-INF, -INF)
	for poly in current_graph.outer_contours:
		for pt in poly:
			min_pt.x = minf(min_pt.x, pt.x)
			min_pt.y = minf(min_pt.y, pt.y)
			max_pt.x = maxf(max_pt.x, pt.x)
			max_pt.y = maxf(max_pt.y, pt.y)

	var c2d: Vector2 = (min_pt + max_pt) * 0.5
	map_bounds_center = Vector3(c2d.x, 0.0, c2d.y)
	map_bounds_span = max_pt - min_pt


## Slices the unified filleted landmass into 40m x 40m spatial chunks so:
## 1) Bridge throats & arena corners have 100% flush curved fillets with zero polygon seams,
## 2) Interior water courtyards inside loops remain open water (hole-free triangulation), and
## 3) Off-screen chunks are GPU frustum-culled automatically.
func _build_chunked_filleted_landmass() -> void:
	if current_graph == null or current_graph.outer_contours.is_empty():
		return

	var min_x: float = map_bounds_center.x - map_bounds_span.x * 0.5 - 1.0
	var max_x: float = map_bounds_center.x + map_bounds_span.x * 0.5 + 1.0
	var min_z: float = map_bounds_center.z - map_bounds_span.y * 0.5 - 1.0
	var max_z: float = map_bounds_center.z + map_bounds_span.y * 0.5 + 1.0

	# Precompute hole AABBs normalized to outer_is_cw for fast clipping
	var norm_holes: Array[PackedVector2Array] = []
	var hole_aabbs: Array[Rect2] = []
	for h in current_graph.hole_contours:
		var nh: PackedVector2Array = PlainsGraphScript._ensure_winding(h, _outer_is_cw)
		norm_holes.append(nh)
		hole_aabbs.append(_polygon_aabb(nh))

	var min_cx: int = floori(min_x / CHUNK_SIZE)
	var max_cx: int = floori(max_x / CHUNK_SIZE)
	var min_cz: int = floori(min_z / CHUNK_SIZE)
	var max_cz: int = floori(max_z / CHUNK_SIZE)

	var chunk_idx: int = 0
	for cz in range(min_cz, max_cz + 1):
		var z0: float = float(cz) * CHUNK_SIZE
		for cx in range(min_cx, max_cx + 1):
			var x0: float = float(cx) * CHUNK_SIZE
			var cell_rect := Rect2(x0, z0, CHUNK_SIZE, CHUNK_SIZE)
			var cell_poly: PackedVector2Array = PlainsGraphScript._ensure_winding(
				PackedVector2Array([
					Vector2(x0, z0),
					Vector2(x0 + CHUNK_SIZE, z0),
					Vector2(x0 + CHUNK_SIZE, z0 + CHUNK_SIZE),
					Vector2(x0, z0 + CHUNK_SIZE)
				]),
				_outer_is_cw
			)

			var pieces: Array[PackedVector2Array] = []
			for outer in current_graph.outer_contours:
				var inter: Array[PackedVector2Array] = Geometry2D.intersect_polygons(outer, cell_poly)
				for ip in inter:
					if ip.size() >= 3 and Geometry2D.is_polygon_clockwise(ip) == _outer_is_cw:
						pieces.append(ip)

			if pieces.is_empty():
				continue

			# Subtract any overlapping water holes (splitting if a hole lies completely inside a chunk)
			var relevant_holes: Array[PackedVector2Array] = []
			for hi in range(norm_holes.size()):
				if cell_rect.intersects(hole_aabbs[hi]):
					relevant_holes.append(norm_holes[hi])

			var simple_pieces: Array[PackedVector2Array] = []
			if relevant_holes.is_empty():
				simple_pieces = pieces
			else:
				for pc in pieces:
					_subtract_holes_into_simple_polys(pc, relevant_holes, 0, simple_pieces)

			for sp in simple_pieces:
				if sp.size() < 3:
					continue
				_spawn_land_chunk_node(chunk_idx, sp)
				chunk_idx += 1


func _subtract_holes_into_simple_polys(
	subject_poly: PackedVector2Array,
	holes: Array[PackedVector2Array],
	depth: int,
	out_simple: Array[PackedVector2Array]
) -> void:
	var current_outers: Array[PackedVector2Array] = [subject_poly]
	var enclosed_holes: Array[PackedVector2Array] = []

	for h in holes:
		var next_outers: Array[PackedVector2Array] = []
		for co in current_outers:
			var clipped: Array[PackedVector2Array] = Geometry2D.clip_polygons(co, h)
			for cp in clipped:
				if cp.size() < 3:
					continue
				if Geometry2D.is_polygon_clockwise(cp) == _outer_is_cw:
					next_outers.append(cp)
				else:
					enclosed_holes.append(PlainsGraphScript._ensure_winding(cp, _outer_is_cw))
		current_outers = next_outers

	if enclosed_holes.is_empty() or depth >= 4:
		for co in current_outers:
			out_simple.append(co)
		return

	# A water hole was strictly enclosed inside this chunk: split vertically across the hole's center!
	var split_x: float = _polygon_aabb_center(enclosed_holes[0]).x
	var left_clip: PackedVector2Array = PlainsGraphScript._ensure_winding(
		PackedVector2Array([
			Vector2(-20000.0, -20000.0), Vector2(split_x, -20000.0),
			Vector2(split_x, 20000.0), Vector2(-20000.0, 20000.0)
		]),
		_outer_is_cw
	)
	var right_clip: PackedVector2Array = PlainsGraphScript._ensure_winding(
		PackedVector2Array([
			Vector2(split_x, -20000.0), Vector2(20000.0, -20000.0),
			Vector2(20000.0, 20000.0), Vector2(split_x, 20000.0)
		]),
		_outer_is_cw
	)
	for half_box in [left_clip, right_clip]:
		var halves: Array[PackedVector2Array] = Geometry2D.intersect_polygons(subject_poly, half_box)
		for hv in halves:
			if hv.size() >= 3 and Geometry2D.is_polygon_clockwise(hv) == _outer_is_cw:
				_subtract_holes_into_simple_polys(hv, holes, depth + 1, out_simple)


func _spawn_land_chunk_node(chunk_idx: int, chunk_poly: PackedVector2Array) -> void:
	var aabb: Rect2 = _polygon_aabb(chunk_poly)
	if aabb.size.x < 0.05 or aabb.size.y < 0.05:
		return
	var center_2d: Vector2 = aabb.position + aabb.size * 0.5

	var chunk_node := Node3D.new()
	chunk_node.name = "LandChunk_%d" % chunk_idx
	chunk_node.position = Vector3(center_2d.x, 0.0, center_2d.y)
	areas_root.add_child(chunk_node)

	var floor_mesh: ArrayMesh = _create_flat_polygon_mesh(chunk_poly, center_2d)
	if floor_mesh:
		var floor_inst := MeshInstance3D.new()
		floor_inst.name = "FloorMesh"
		floor_inst.mesh = floor_mesh
		floor_inst.material_override = floor_material
		chunk_node.add_child(floor_inst)

	var enable_grass_now: bool = bool(BiomeThemeScript.get_biome_data(current_biome_id).get("enable_grass", true))
	if enable_grass_now:
		var mm: MultiMesh = _stamper.stamp_polygon(chunk_poly, center_2d)
		if mm:
			var grass_inst := MultiMeshInstance3D.new()
			grass_inst.name = "Grass"
			grass_inst.add_to_group("grass")
			grass_inst.material_override = grass_material
			grass_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			grass_inst.multimesh = mm
			chunk_node.add_child(grass_inst)
			total_grass_blades += mm.visible_instance_count


func _create_flat_polygon_mesh(world_poly: PackedVector2Array, local_origin: Vector2) -> ArrayMesh:
	var tri_indices: PackedInt32Array = Geometry2D.triangulate_polygon(world_poly)
	if tri_indices.size() < 3:
		return null

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var tri_count: int = floori(float(tri_indices.size()) / 3.0)
	for t in range(tri_count):
		var p0: Vector2 = world_poly[tri_indices[t * 3]]
		var p1: Vector2 = world_poly[tri_indices[t * 3 + 1]]
		var p2: Vector2 = world_poly[tri_indices[t * 3 + 2]]

		var v0 := Vector3(p0.x - local_origin.x, 0.0, p0.y - local_origin.y)
		var v1 := Vector3(p1.x - local_origin.x, 0.0, p1.y - local_origin.y)
		var v2 := Vector3(p2.x - local_origin.x, 0.0, p2.y - local_origin.y)

		# Godot 4 uses clockwise (CW) front-face winding when viewed from +Y:
		# (v1 - v0).cross(v2 - v0).y < 0.0 is front-facing UP (+Y). Swap if > 0.0.
		if (v1 - v0).cross(v2 - v0).y > 0.0:
			var tmp: Vector3 = v1
			v1 = v2
			v2 = tmp

		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(p0.x * 0.05, p0.y * 0.05))
		st.add_vertex(v0)

		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(p1.x * 0.05, p1.y * 0.05))
		st.add_vertex(v1)

		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(p2.x * 0.05, p2.y * 0.05))
		st.add_vertex(v2)

	return st.commit()


func _build_shoreline_skirt() -> void:
	if current_graph == null or current_graph.merged_polygons.is_empty():
		return

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var skirt_top_y: float = -0.015
	var skirt_bot_y: float = -0.28
	var added_any: bool = false

	for poly in current_graph.merged_polygons:
		var n: int = poly.size()
		if n < 3:
			continue
		var norm_sign: float = _contour_water_normal_sign(poly)
		for i in range(n):
			var p1: Vector2 = poly[i]
			var p2: Vector2 = poly[(i + 1) % n]
			if p1.distance_squared_to(p2) < 0.0004:
				continue

			var edge_dir: Vector2 = (p2 - p1).normalized()
			var water_norm: Vector2 = Vector2(-edge_dir.y, edge_dir.x) * norm_sign

			var ip1: Vector2 = p1 - water_norm * 0.03
			var ip2: Vector2 = p2 - water_norm * 0.03
			var nrm := Vector3(water_norm.x, 0.0, water_norm.y)

			var t1 := Vector3(ip1.x, skirt_top_y, ip1.y)
			var t2 := Vector3(ip2.x, skirt_top_y, ip2.y)
			var b1 := Vector3(ip1.x, skirt_bot_y, ip1.y)
			var b2 := Vector3(ip2.x, skirt_bot_y, ip2.y)

			st.set_normal(nrm)
			st.add_vertex(t1)
			st.add_vertex(t2)
			st.add_vertex(b2)

			st.set_normal(nrm)
			st.add_vertex(t1)
			st.add_vertex(b2)
			st.add_vertex(b1)
			added_any = true

	if not added_any:
		return

	skirt_instance = MeshInstance3D.new()
	skirt_instance.name = "ShorelineSkirt"
	skirt_instance.mesh = st.commit()
	skirt_instance.material_override = _skirt_material
	skirt_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(skirt_instance)


## Builds a sleek non-colliding beveled 3D border trim around every island & bridge shoreline
## so arena boundaries stand out sharply from surrounding void, water, or abyss floors.
func _build_shoreline_curb() -> void:
	if current_graph == null or current_graph.merged_polygons.is_empty():
		return

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var added_any: bool = false

	for poly in current_graph.merged_polygons:
		var n: int = poly.size()
		if n < 3:
			continue
		var norm_sign: float = _contour_water_normal_sign(poly)

		var edge_normals: Array[Vector2] = []
		edge_normals.resize(n)
		for i in range(n):
			var p1: Vector2 = poly[i]
			var p2: Vector2 = poly[(i + 1) % n]
			var diff: Vector2 = p2 - p1
			var d_len: float = diff.length()
			var dir: Vector2 = diff / d_len if d_len > 0.0001 else Vector2.RIGHT
			edge_normals[i] = Vector2(-dir.y, dir.x) * norm_sign

		var miters: Array[Vector2] = []
		miters.resize(n)
		for i in range(n):
			var n_prev: Vector2 = edge_normals[(i - 1 + n) % n]
			var n_curr: Vector2 = edge_normals[i]
			var sum_n: Vector2 = n_prev + n_curr
			var bis: Vector2 = sum_n.normalized() if sum_n.length_squared() > 0.0001 else n_curr
			var proj: float = maxf(0.45, bis.dot(n_curr))
			miters[i] = bis / proj

		for i in range(n):
			var next_i: int = (i + 1) % n
			var p1: Vector2 = poly[i]
			var p2: Vector2 = poly[next_i]
			if p1.distance_squared_to(p2) < 0.0009:
				continue

			var m1: Vector2 = miters[i]
			var m2: Vector2 = miters[next_i]
			var in1_2d: Vector2 = p1 - m1 * 0.26
			var in2_2d: Vector2 = p2 - m2 * 0.26
			var cr1_2d: Vector2 = p1 - m1 * 0.02
			var cr2_2d: Vector2 = p2 - m2 * 0.02
			var out1_2d: Vector2 = p1 + m1 * 0.08
			var out2_2d: Vector2 = p2 + m2 * 0.08

			var in1 := Vector3(in1_2d.x, 0.008, in1_2d.y)
			var in2 := Vector3(in2_2d.x, 0.008, in2_2d.y)
			var cr1 := Vector3(cr1_2d.x, 0.032, cr1_2d.y)
			var cr2 := Vector3(cr2_2d.x, 0.032, cr2_2d.y)
			var out1 := Vector3(out1_2d.x, -0.020, out1_2d.y)
			var out2 := Vector3(out2_2d.x, -0.020, out2_2d.y)

			st.set_normal(Vector3.UP)
			st.add_vertex(in1)
			st.add_vertex(in2)
			st.add_vertex(cr2)
			st.set_normal(Vector3.UP)
			st.add_vertex(in1)
			st.add_vertex(cr2)
			st.add_vertex(cr1)

			var en: Vector2 = edge_normals[i]
			var side_n := Vector3(en.x, 0.25, en.y).normalized()
			st.set_normal(side_n)
			st.add_vertex(cr1)
			st.add_vertex(cr2)
			st.add_vertex(out2)
			st.set_normal(side_n)
			st.add_vertex(cr1)
			st.add_vertex(out2)
			st.add_vertex(out1)
			added_any = true

	if not added_any:
		return

	curb_instance = MeshInstance3D.new()
	curb_instance.name = "ShorelineCurb"
	curb_instance.mesh = st.commit()
	curb_instance.material_override = _curb_material
	curb_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(curb_instance)


## Builds smooth, flush, zero-snag mitered ConvexPolygonShape3D shore walls.
## Unlike BoxShape3D (whose square end-caps jut into walkable land at concave corners),
## mitered prisms share exact vertex planes and sit 100% on the water side of the shoreline!
func _build_world_collision() -> void:
	if current_graph == null:
		return

	collision_body = StaticBody3D.new()
	collision_body.name = "WorldCollision"
	add_child(collision_body)

	# 1. Single smooth ground plane BoxShape3D under the entire walkable world
	var ground_col := CollisionShape3D.new()
	ground_col.name = "GroundFloorShape"
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(
		maxf(150.0, map_bounds_span.x + 80.0),
		0.4,
		maxf(150.0, map_bounds_span.y + 80.0)
	)
	ground_col.shape = ground_box
	ground_col.position = Vector3(map_bounds_center.x, -0.2, map_bounds_center.z)
	collision_body.add_child(ground_col)

	# 2. Watertight Mitered ConvexPolygonShape3D Wall Prisms along filleted coastlines
	var wall_bot_y: float = -0.25
	var wall_top_y: float = 2.4
	var wall_depth: float = 0.60

	for poly in current_graph.merged_polygons:
		var n: int = poly.size()
		if n < 3:
			continue

		var norm_sign: float = _contour_water_normal_sign(poly)

		# Precompute outward water normal for each edge
		var edge_normals: Array[Vector2] = []
		edge_normals.resize(n)
		for i in range(n):
			var p1: Vector2 = poly[i]
			var p2: Vector2 = poly[(i + 1) % n]
			var diff: Vector2 = p2 - p1
			var d_len: float = diff.length()
			var dir: Vector2 = diff / d_len if d_len > 0.0001 else Vector2.RIGHT
			edge_normals[i] = Vector2(-dir.y, dir.x) * norm_sign

		# Precompute exact miter vector at each vertex (strictly pointing into water)
		var vertex_miters: Array[Vector2] = []
		vertex_miters.resize(n)
		for i in range(n):
			var n_prev: Vector2 = edge_normals[(i - 1 + n) % n]
			var n_curr: Vector2 = edge_normals[i]
			var sum_n: Vector2 = n_prev + n_curr
			var bisector: Vector2 = sum_n.normalized() if sum_n.length_squared() > 0.0001 else n_curr
			var proj: float = maxf(0.45, bisector.dot(n_curr))
			vertex_miters[i] = bisector * (wall_depth / proj)

		# Extrude each mitered shoreline quad [p1, p2, q2, q1] into a solid 8-vertex ConvexPolygonShape3D
		for i in range(n):
			var next_i: int = (i + 1) % n
			var p1: Vector2 = poly[i]
			var p2: Vector2 = poly[next_i]
			if p1.distance_squared_to(p2) < 0.0025:
				continue

			var q1: Vector2 = p1 + vertex_miters[i]
			var q2: Vector2 = p2 + vertex_miters[next_i]
			var mid_2d: Vector2 = (p1 + p2 + q1 + q2) * 0.25

			var pts := PackedVector3Array([
				Vector3(p1.x - mid_2d.x, wall_bot_y, p1.y - mid_2d.y),
				Vector3(p2.x - mid_2d.x, wall_bot_y, p2.y - mid_2d.y),
				Vector3(q2.x - mid_2d.x, wall_bot_y, q2.y - mid_2d.y),
				Vector3(q1.x - mid_2d.x, wall_bot_y, q1.y - mid_2d.y),
				Vector3(p1.x - mid_2d.x, wall_top_y, p1.y - mid_2d.y),
				Vector3(p2.x - mid_2d.x, wall_top_y, p2.y - mid_2d.y),
				Vector3(q2.x - mid_2d.x, wall_top_y, q2.y - mid_2d.y),
				Vector3(q1.x - mid_2d.x, wall_top_y, q1.y - mid_2d.y)
			])

			var conv := ConvexPolygonShape3D.new()
			conv.points = pts
			var barrier := CollisionShape3D.new()
			barrier.shape = conv
			barrier.position = Vector3(mid_2d.x, 0.0, mid_2d.y)
			collision_body.add_child(barrier)


## Determines whether (+perp) or (-perp) points into water for a closed contour via majority vote
func _contour_water_normal_sign(poly: PackedVector2Array) -> float:
	var n: int = poly.size()
	if n < 3:
		return 1.0
	var votes_pos: int = 0
	var votes_neg: int = 0
	var step: int = maxi(1, floori(float(n) / 12.0))
	var idx: int = 0
	while idx < n:
		var p1: Vector2 = poly[idx]
		var p2: Vector2 = poly[(idx + 1) % n]
		var diff: Vector2 = p2 - p1
		if diff.length_squared() > 0.01:
			var dir: Vector2 = diff.normalized()
			var perp := Vector2(-dir.y, dir.x)
			var mid: Vector2 = (p1 + p2) * 0.5
			if _is_point_on_filleted_land(mid + perp * 0.45):
				votes_neg += 1
			else:
				votes_pos += 1
		idx += step
	return 1.0 if votes_pos >= votes_neg else -1.0


func _is_point_on_filleted_land(pt: Vector2) -> bool:
	if current_graph == null:
		return false
	var inside_outer: bool = false
	for outer in current_graph.outer_contours:
		if Geometry2D.is_point_in_polygon(pt, outer):
			inside_outer = true
			break
	if not inside_outer:
		return false
	for hole in current_graph.hole_contours:
		if Geometry2D.is_point_in_polygon(pt, hole):
			return false
	return true


func _polygon_aabb(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()
	var min_pt: Vector2 = poly[0]
	var max_pt: Vector2 = poly[0]
	for pt in poly:
		min_pt.x = minf(min_pt.x, pt.x)
		min_pt.y = minf(min_pt.y, pt.y)
		max_pt.x = maxf(max_pt.x, pt.x)
		max_pt.y = maxf(max_pt.y, pt.y)
	return Rect2(min_pt, max_pt - min_pt)


func _polygon_aabb_center(poly: PackedVector2Array) -> Vector2:
	var r: Rect2 = _polygon_aabb(poly)
	return r.position + r.size * 0.5


func _build_surrounding_water() -> void:
	water_instance = MeshInstance3D.new()
	water_instance.name = "SurroundingWater"

	var max_span: float = maxf(map_bounds_span.x, map_bounds_span.y)
	var water_size: float = maxf(900.0, max_span * 4.0)

	var water_pmesh := PlaneMesh.new()
	water_pmesh.size = Vector2(water_size, water_size)
	water_pmesh.subdivide_width = 96
	water_pmesh.subdivide_depth = 96

	water_instance.mesh = water_pmesh
	water_instance.material_override = water_material
	water_instance.position = Vector3(map_bounds_center.x, -0.05, map_bounds_center.z)
	add_child(water_instance)


func _build_spawn_pond() -> void:
	pond_instance = MeshInstance3D.new()
	pond_instance.name = "SpawnPond"

	var pond_pmesh := PlaneMesh.new()
	pond_pmesh.size = Vector2(6.0, 6.0)
	pond_pmesh.subdivide_width = 24
	pond_pmesh.subdivide_depth = 24

	pond_instance.mesh = pond_pmesh
	pond_instance.material_override = pond_material
	pond_instance.position = Vector3(0.0, 0.05, 0.0)
	add_child(pond_instance)
