class_name MapPresetConfig
extends Resource

## Data Resource defining procedural map topology and scale for Shape of Dreams-style
## node-web arenas connected by narrow meadow causeways (calibrated for Camera3D size = 11.0).

enum TopologyMode {
	DREAMSCAPE_WEB,        ## Standard Shape of Dreams branching/converging node web (~9-11 arenas)
	GRAND_DREAMSCAPE,      ## Expanded multi-lane expedition web (~13-16 arenas)
	DREAMSCAPE_CROSSROADS  ## Compact high-tempo diamond web (~7-9 arenas)
}

@export var preset_name: String = "Standard Web"
@export var topology_mode: TopologyMode = TopologyMode.DREAMSCAPE_WEB

@export_group("Web Topology")
@export var progression_tiers: int = 5      ## Number of forward tiers from Spawn (0) to Boss (tiers - 1)
@export var max_lanes: int = 3              ## Parallel lanes across intermediate tiers (2 or 3)
@export var cross_link_chance: float = 0.55 ## Chance of lateral causeways between adjacent lanes
@export var side_shrine_chance: float = 0.50 ## Chance of 1-hop side well/shrine chambers on outer lanes

@export_group("Scale & Spacing")
@export var bridge_width: float = 5.8       ## Narrow path width (~30% of screen height, contrasts with 38m-62m arenas)
@export var lane_spacing: float = 68.0      ## Lateral X spacing between adjacent web lanes
@export var tier_spacing: float = 66.0      ## Forward -Z spacing between progression tiers
@export var arena_scale: float = 1.0        ## Global multiplier on combat region dimensions
@export var position_jitter: float = 5.0    ## Subtle organic offset so the web feels natural, not rigid
@export var throat_fillet_radius: float = 2.0 ## Smooth curved funnel radius where bridges meet arenas

@export_group("Features")
@export var enable_spawn_pond: bool = true  ## Keep the signature organic pond in the Spawn Sanctuary


static func create_preset(mode: TopologyMode) -> MapPresetConfig:
	var cfg := MapPresetConfig.new()
	cfg.topology_mode = mode
	match mode:
		TopologyMode.DREAMSCAPE_WEB:
			cfg.preset_name = "Standard Web"
			cfg.progression_tiers = 5
			cfg.max_lanes = 3
			cfg.cross_link_chance = 0.55
			cfg.side_shrine_chance = 0.50
			cfg.bridge_width = 5.8
			cfg.lane_spacing = 68.0
			cfg.tier_spacing = 66.0
			cfg.arena_scale = 1.0
			cfg.position_jitter = 5.0
			cfg.throat_fillet_radius = 2.0
			cfg.enable_spawn_pond = true
		TopologyMode.GRAND_DREAMSCAPE:
			cfg.preset_name = "Large Web"
			cfg.progression_tiers = 6
			cfg.max_lanes = 3
			cfg.cross_link_chance = 0.65
			cfg.side_shrine_chance = 0.65
			cfg.bridge_width = 6.0
			cfg.lane_spacing = 74.0
			cfg.tier_spacing = 72.0
			cfg.arena_scale = 1.10
			cfg.position_jitter = 5.5
			cfg.throat_fillet_radius = 2.2
			cfg.enable_spawn_pond = true
		TopologyMode.DREAMSCAPE_CROSSROADS:
			cfg.preset_name = "Compact Crossroads"
			cfg.progression_tiers = 4
			cfg.max_lanes = 3
			cfg.cross_link_chance = 0.70
			cfg.side_shrine_chance = 0.40
			cfg.bridge_width = 5.6
			cfg.lane_spacing = 64.0
			cfg.tier_spacing = 62.0
			cfg.arena_scale = 0.95
			cfg.position_jitter = 4.0
			cfg.throat_fillet_radius = 1.9
			cfg.enable_spawn_pond = true
	return cfg


static func get_preset_count() -> int:
	return 3
