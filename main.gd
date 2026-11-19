extends Node3D

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const MapPresetConfigScript = preload("res://world/map_preset_config.gd")
const BiomeThemeScript = preload("res://world/biome_theme.gd")
const GameOverOverlayScript = preload("res://ui/game_over_overlay.gd")
const RewardDraftOverlayScript = preload("res://ui/reward_draft_overlay.gd")
const TutorialModalScript = preload("res://ui/tutorial_modal.gd")
const PortalConfirmModalScript = preload("res://ui/portal_confirm_modal.gd")
const PauseMenuModalScript = preload("res://ui/pause_menu_modal.gd")
const ProjectileScript = preload("res://player/projectile.gd")
const ArchetypeScript = preload("res://enemies/enemy_archetype_data.gd")
const CombatZoneScript = preload("res://world/combat_zone_effect.gd")
const Trail3DScript = preload("res://scripts/trail_3d.gd")
const ENEMY_HAZARD_SHADER: Shader = preload("res://shaders/EnemyHazard.gdshader")
const COSMIC_CORE_SHADER: Shader = preload("res://shaders/CosmicCore.gdshader")
const OVERHEAD_BAR_SHADER: Shader = preload("res://shaders/OverheadBar.gdshader")
const CONTACT_SHADOW_SHADER: Shader = preload("res://shaders/ContactShadow.gdshader")

@onready var procedural_world: ProceduralWorld = $ProceduralWorld
@onready var encounter_manager: ArenaEncounterManager = get_node_or_null("ArenaEncounterManager") as ArenaEncounterManager
@onready var players_container: Node3D = $Players
@onready var camera: Camera3D = $Camera3D
@onready var world_env: WorldEnvironment = get_node_or_null("WorldEnvironment") as WorldEnvironment
@onready var dir_light: DirectionalLight3D = get_node_or_null("DirectionalLight3D") as DirectionalLight3D
@onready var hud_layer: CanvasLayer = $HUD
@onready var info_label: Label = $HUD/MarginContainer/HBoxContainer/InfoLabel
@onready var leave_button: Button = $HUD/MarginContainer/HBoxContainer/LeaveButton
@onready var encounter_banner: Label = %EncounterBanner if has_node("%EncounterBanner") else null
@onready var player_health_bar: Control = %PlayerHealthBar if has_node("%PlayerHealthBar") else null
@onready var debug_overlay: MarginContainer = $HUD.get_node_or_null("DebugOverlay") as MarginContainer
@onready var stats_label: Label = %StatsLabel if has_node("%StatsLabel") else null
@onready var preset_button: Button = %PresetButton if has_node("%PresetButton") else null
@onready var regen_button: Button = %RegenButton if has_node("%RegenButton") else null
@onready var teleport_button: Button = $HUD/MarginContainer/HBoxContainer.get_node_or_null("TeleportButton") as Button
@onready var cam_button: Button = $HUD/MarginContainer/HBoxContainer.get_node_or_null("CamButton") as Button

# Locked isometric offset from target on ground (Y=0) to Camera3D
var camera_offset: Vector3 = Vector3(-18.0, 18.0, 18.0)
var is_overview: bool = false
var overview_pos: Vector3 = Vector3(-90.0, 90.0, 60.0)
var overview_size: float = 110.0
var default_camera_size: float = 13.5
const MIN_CAMERA_SIZE: float = 7.0
const MAX_CAMERA_SIZE: float = 16.0
const ZOOM_STEP: float = 0.75

var _waypoints: Array[Dictionary] = []
var _current_waypoint_idx: int = 0
var _spawn_pos: Vector3 = Vector3(0.0, 0.0, 6.8)
var _local_player: CharacterBody3D = null
var _active_arena_title: String = "Combat Arena"
var _banner_fade_timer: float = 0.0
var _game_over_overlay: Control = null
var _reward_draft_overlay: Control = null
var _tutorial_modal: Control = null
var _tutorial_button: Button = null
var _portal_confirm_modal: Control = null
var _pause_menu_modal: Control = null
var _biome_button: Button = null
var _camera_shake_trauma: float = 0.0
var _shake_phase: float = 0.0
var _web_quality_idx: int = 0
var _web_curtain_rect: ColorRect = null
var _web_curtain_tween: Tween = null
var _portal_transition_busy: bool = false
var _god_mode_enabled: bool = false
var _god_mode_button: Button = null
var _boss_jump_button: Button = null


func add_camera_shake(trauma: float) -> void:
	_camera_shake_trauma = clampf(_camera_shake_trauma + trauma, 0.0, 1.0)

@export var overview_mode: bool = false:
	set(val):
		overview_mode = val
		is_overview = val
		if cam_button:
			cam_button.text = "Player Cam" if is_overview else "Overview Cam"


func _ready() -> void:
	add_to_group("world_camera_shake")
	_setup_web_transition_curtain()
	var is_emb: bool = Engine.is_embedded_in_editor() or ("--wid" in OS.get_cmdline_args()) or (DebugTools != null and DebugTools.is_embedded)
	if not OS.has_feature("web") and not is_emb and not EngineDebugger.is_active():
		DisplayServer.window_move_to_foreground()

	if not NetworkManager.peer:
		NetworkManager.host_game(0, "SoloPlayer")
		NetworkManager.is_game_running = true

	var online_supported: bool = NetworkManager.supports_online_multiplayer()
	if not online_supported:
		if leave_button:
			leave_button.visible = false
		if info_label:
			info_label.visible = OS.is_debug_build()

	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)

	_configure_button(leave_button, _on_leave_pressed)
	_configure_button(cam_button, _on_cam_button_pressed)
	_configure_button(teleport_button, _on_teleport_pressed)
	_configure_button(preset_button, _on_preset_pressed)
	_configure_button(regen_button, _on_regen_pressed)

	if OS.is_debug_build() and ("--god-mode" in OS.get_cmdline_args() or "--god-mode" in OS.get_cmdline_user_args()):
		_god_mode_enabled = true

	if regen_button and regen_button.get_parent():
		var dbg_row: Node = regen_button.get_parent()
		_biome_button = Button.new()
		_biome_button.name = "BiomeButton"
		_biome_button.custom_minimum_size = Vector2(188.0, 30.0)
		_biome_button.focus_mode = Control.FOCUS_NONE
		_biome_button.text = "Biome: Verdant Meadow"
		dbg_row.add_child(_biome_button)
		dbg_row.move_child(_biome_button, regen_button.get_index())
		_configure_button(_biome_button, _on_biome_pressed)

		_god_mode_button = Button.new()
		_god_mode_button.name = "GodModeButton"
		_god_mode_button.custom_minimum_size = Vector2(142.0, 30.0)
		_god_mode_button.focus_mode = Control.FOCUS_NONE
		_god_mode_button.text = "God Mode: ON [F2]" if _god_mode_enabled else "God Mode: OFF [F2]"
		dbg_row.add_child(_god_mode_button)
		_configure_button(_god_mode_button, _on_god_mode_pressed)

		_boss_jump_button = Button.new()
		_boss_jump_button.name = "BossJumpButton"
		_boss_jump_button.custom_minimum_size = Vector2(126.0, 30.0)
		_boss_jump_button.focus_mode = Control.FOCUS_NONE
		_boss_jump_button.text = "Boss Arena [F3]"
		dbg_row.add_child(_boss_jump_button)
		_configure_button(_boss_jump_button, _on_jump_to_boss_pressed)

	if cam_button:
		cam_button.text = "Player Cam" if is_overview else "Overview Cam"

	if debug_overlay:
		debug_overlay.visible = OS.is_debug_build()
		if OS.is_debug_build() and encounter_banner:
			encounter_banner.offset_top = 80.0
			encounter_banner.offset_bottom = 114.0

	for lbl in [stats_label, info_label]:
		if lbl:
			lbl.add_theme_constant_override("outline_size", 4)
			lbl.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.12, 0.9))

	if OS.has_feature("web") and dir_light:
		dir_light.shadow_enabled = false

	if camera:
		camera.far = 2500.0
		if not is_overview:
			camera.size = default_camera_size

	if encounter_manager:
		encounter_manager.players_container = players_container
		encounter_manager.encounter_started.connect(_on_encounter_started)
		encounter_manager.wave_incoming.connect(_on_wave_incoming)
		encounter_manager.wave_started.connect(_on_wave_started)
		encounter_manager.encounter_progress_changed.connect(_on_encounter_progress_changed)
		encounter_manager.encounter_cleared.connect(_on_encounter_cleared)
		encounter_manager.encounters_reset.connect(_on_encounters_reset)
		encounter_manager.reward_pedestal_interacted.connect(_on_reward_pedestal_interacted)
		encounter_manager.dropped_item_interacted.connect(_on_dropped_item_interacted)
		encounter_manager.stage_portal_entered.connect(_on_stage_portal_entered)

	if procedural_world:
		procedural_world.world_generated.connect(_on_world_generated)
		procedural_world.graph_ready.connect(_on_world_graph_ready)
		var initial_seed: int = NetworkManager.active_map_seed if NetworkManager.active_map_seed > 0 else procedural_world.map_seed
		var initial_preset: int = NetworkManager.active_map_preset
		var initial_biome: int = NetworkManager.active_biome_id
		procedural_world.generate_world(initial_seed if initial_seed > 0 else -1, initial_preset, initial_biome)

	spawn_players()
	_setup_reward_draft_overlay()
	_setup_tutorial_modal()
	_setup_portal_confirm_modal()
	_setup_game_over_overlay()
	_setup_pause_menu_modal()
	_update_hud()
	NetworkManager.mark_client_ready()

	if is_overview and camera:
		camera.size = overview_size
		camera.global_position = overview_pos
		camera.reset_physics_interpolation()

	if OS.has_feature("web"):
		var vp: Viewport = get_viewport()
		if vp != null and not vp.size_changed.is_connected(_on_web_viewport_resized):
			vp.size_changed.connect(_on_web_viewport_resized)
		_apply_web_quality_preset()
		_run_web_shader_prewarm()


func _configure_button(btn: Button, callback: Callable) -> void:
	if btn == null:
		return
	btn.focus_mode = Control.FOCUS_NONE
	if not btn.pressed.is_connected(callback):
		btn.pressed.connect(callback)


func _is_solo_session() -> bool:
	var p_count: int = NetworkManager.get_player_count()
	if p_count > 1:
		return false
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
		return false
	return true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var ke: InputEventKey = event as InputEventKey
		if ke.keycode == KEY_ESCAPE:
			if _game_over_overlay and _game_over_overlay.visible:
				return
			if _portal_confirm_modal and _portal_confirm_modal.has_method("is_open") and bool(_portal_confirm_modal.call("is_open")):
				_portal_confirm_modal.call("close_modal")
				get_viewport().set_input_as_handled()
				return
			if _tutorial_modal and _tutorial_modal.has_method("is_open") and bool(_tutorial_modal.call("is_open")):
				_tutorial_modal.call("close_modal")
				get_viewport().set_input_as_handled()
				return
			if _reward_draft_overlay and bool(_reward_draft_overlay.get("_is_open")):
				_reward_draft_overlay.call("close_draft")
				get_viewport().set_input_as_handled()
				return
			if player_health_bar:
				if player_health_bar.has_method("is_pickup_placement_active") and bool(player_health_bar.call("is_pickup_placement_active")):
					return
				if bool(player_health_bar.get("_tab_toggled_open")) and player_health_bar.has_method("close_tab_edit_mode"):
					player_health_bar.call("close_tab_edit_mode")
					get_viewport().set_input_as_handled()
					return
			if _pause_menu_modal:
				if bool(_pause_menu_modal.call("is_open")):
					_pause_menu_modal.call("close_menu")
				else:
					_pause_menu_modal.call("open_menu", _local_player, _is_solo_session())
				get_viewport().set_input_as_handled()
				return
		if ke.keycode == KEY_F1 or ke.keycode == KEY_H:
			if _pause_menu_modal and bool(_pause_menu_modal.call("is_open")):
				return
			_on_tutorial_pressed()
			get_viewport().set_input_as_handled()
			return
		if ke.keycode == KEY_F2 and OS.is_debug_build():
			_on_god_mode_pressed()
			get_viewport().set_input_as_handled()
			return
		if ke.keycode == KEY_F3 and OS.is_debug_build():
			_on_jump_to_boss_pressed()
			get_viewport().set_input_as_handled()
			return
	if is_overview:
		return
	if event is InputEventMouseButton and event.pressed:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			default_camera_size = clampf(default_camera_size - ZOOM_STEP, MIN_CAMERA_SIZE, MAX_CAMERA_SIZE)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			default_camera_size = clampf(default_camera_size + ZOOM_STEP, MIN_CAMERA_SIZE, MAX_CAMERA_SIZE)


func _physics_process(delta: float) -> void:
	if _banner_fade_timer > 0.0:
		_banner_fade_timer -= delta
		if _banner_fade_timer <= 0.0 and encounter_banner and (encounter_manager == null or not encounter_manager.is_encounter_active()):
			encounter_banner.visible = false

	if camera == null:
		return

	if is_overview:
		camera.size = lerpf(camera.size, overview_size, clampf(6.0 * delta, 0.0, 1.0))
		camera.global_position = camera.global_position.lerp(overview_pos, clampf(6.0 * delta, 0.0, 1.0))
	else:
		var target_zoom: float = default_camera_size
		if encounter_manager != null and encounter_manager.is_boss_encounter_active():
			target_zoom = minf(17.5, default_camera_size + 2.2)
		camera.size = lerpf(camera.size, target_zoom, clampf(8.0 * delta, 0.0, 1.0))
		if _local_player == null or not is_instance_valid(_local_player):
			var my_id: int = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
			_local_player = players_container.get_node_or_null(str(my_id)) as CharacterBody3D
		if _local_player:
			var target_pos: Vector3 = _local_player.global_position + camera_offset
			camera.global_position = camera.global_position.lerp(target_pos, clampf(10.0 * delta, 0.0, 1.0))
			if _camera_shake_trauma > 0.005:
				_shake_phase += delta * 46.0
				var shake_amp: float = _camera_shake_trauma * _camera_shake_trauma * 0.42
				camera.global_position += Vector3(sin(_shake_phase) * shake_amp, cos(_shake_phase * 1.3) * shake_amp * 0.5, cos(_shake_phase * 0.9) * shake_amp)
				_camera_shake_trauma = maxf(0.0, _camera_shake_trauma - 2.2 * delta)


func _on_world_generated(spawn_pos: Vector3, _goal_pos: Vector3) -> void:
	_spawn_pos = spawn_pos
	_waypoints = procedural_world.get_room_waypoints()
	_current_waypoint_idx = 0
	if procedural_world:
		_apply_biome_environment(procedural_world.current_biome_id)
	_recompute_overview_camera()
	_update_debug_labels()
	_update_teleport_button_label()


func _on_world_graph_ready(graph: PlainsGraph) -> void:
	if encounter_manager:
		encounter_manager.setup_for_graph(graph, procedural_world.current_seed)


func _on_encounter_started(_area_idx: int, area_name: String, wave_idx: int, total_waves: int, total_enemies: int) -> void:
	_active_arena_title = area_name
	_banner_fade_timer = 0.0
	if encounter_banner:
		if area_name == "Boss Citadel" or (encounter_manager != null and encounter_manager.is_boss_encounter_active()):
			encounter_banner.visible = false
			return
		encounter_banner.add_theme_color_override("font_color", Color(1.0, 0.72, 0.36, 1.0))
		encounter_banner.text = "%s Locked — Wave %d / %d  |  Enemies: %d / %d" % [
			_active_arena_title, wave_idx, total_waves, total_enemies, total_enemies
		]
		encounter_banner.visible = true


func _on_wave_incoming(_area_idx: int, area_name: String, next_wave_idx: int, total_waves: int) -> void:
	_active_arena_title = area_name
	if encounter_banner:
		encounter_banner.add_theme_color_override("font_color", Color(1.0, 0.86, 0.42, 1.0))
		encounter_banner.text = "%s Locked — Incoming Wave %d / %d..." % [
			_active_arena_title, next_wave_idx, total_waves
		]
		encounter_banner.visible = true


func _on_wave_started(_area_idx: int, area_name: String, wave_idx: int, total_waves: int, total_enemies: int) -> void:
	_active_arena_title = area_name
	if encounter_banner:
		encounter_banner.add_theme_color_override("font_color", Color(1.0, 0.72, 0.36, 1.0))
		encounter_banner.text = "%s Locked — Wave %d / %d  |  Enemies: %d / %d" % [
			_active_arena_title, wave_idx, total_waves, total_enemies, total_enemies
		]
		encounter_banner.visible = true


func _on_encounter_progress_changed(_area_idx: int, wave_idx: int, total_waves: int, remaining: int, total: int) -> void:
	if encounter_banner and remaining > 0:
		if _active_arena_title == "Boss Citadel" or (encounter_manager != null and encounter_manager.is_boss_encounter_active()):
			encounter_banner.visible = false
			return
		encounter_banner.text = "%s Locked — Wave %d / %d  |  Enemies: %d / %d" % [
			_active_arena_title, wave_idx, total_waves, remaining, total
		]


func _on_encounter_cleared(area_idx: int, area_name: String) -> void:
	var is_final_stage: bool = false
	if procedural_world and procedural_world.current_graph:
		var g: PlainsGraph = procedural_world.current_graph
		if area_idx == g.goal_index:
			is_final_stage = true
		elif area_idx >= 0 and area_idx < g.areas.size() and g.areas[area_idx].role == PlainsGraph.AreaPresetScript.RoomRole.BOSS:
			is_final_stage = true
	if encounter_banner:
		if is_final_stage:
			encounter_banner.add_theme_color_override("font_color", Color(0.66, 0.96, 1.0, 1.0))
			encounter_banner.text = "%s Conquered — 3 Upgrade Pedestals & Rift Portal Unlocked!" % area_name
			encounter_banner.visible = true
			_banner_fade_timer = 5.5
		else:
			encounter_banner.add_theme_color_override("font_color", Color(0.55, 1.0, 0.52, 1.0))
			encounter_banner.text = "%s Cleared — Upgrade Pedestal Unlocked!" % area_name
			encounter_banner.visible = true
			_banner_fade_timer = 3.0


func _on_stage_portal_entered(player_node: Node) -> void:
	if _tutorial_modal and _tutorial_modal.has_method("close_modal"):
		_tutorial_modal.call("close_modal")
	if _reward_draft_overlay and _reward_draft_overlay.has_method("close_draft"):
		_reward_draft_overlay.call("close_draft")

	var unclaimed: int = 0
	if encounter_manager and encounter_manager.has_method("get_unclaimed_pedestal_count"):
		unclaimed = int(encounter_manager.call("get_unclaimed_pedestal_count"))

	if unclaimed > 0 and _portal_confirm_modal != null and _portal_confirm_modal.has_method("open_for_unclaimed"):
		var p_target: Node = player_node if player_node != null else _local_player
		_portal_confirm_modal.call("open_for_unclaimed", unclaimed, p_target)
		return

	_traverse_stage_portal()


func _traverse_stage_portal() -> void:
	var use_curtain: bool = OS.has_feature("web") and _web_curtain_rect != null
	if use_curtain:
		if _portal_transition_busy:
			return
		_portal_transition_busy = true
		_show_web_curtain_instant()
		await get_tree().process_frame
		if not is_inside_tree():
			_portal_transition_busy = false
			return

	var next_biome: int = 0
	if procedural_world:
		next_biome = (procedural_world.current_biome_id + 1) % BiomeThemeScript.get_biome_count()
	NetworkManager.active_biome_id = next_biome
	_regen_with_biome(next_biome)
	if camera and _local_player and is_instance_valid(_local_player) and not is_overview:
		camera.global_position = _local_player.global_position + camera_offset
		camera.reset_physics_interpolation()
	if encounter_banner and procedural_world:
		var b_name: String = BiomeThemeScript.get_biome_name(procedural_world.current_biome_id)
		encounter_banner.add_theme_color_override("font_color", Color(0.76, 0.90, 1.0, 1.0))
		encounter_banner.text = "Rift Traversed — Entered %s (Seed %d)" % [b_name, procedural_world.current_seed]
		encounter_banner.visible = true
		_banner_fade_timer = 4.0

	if use_curtain:
		await get_tree().process_frame
		if is_inside_tree():
			_fade_out_web_curtain(0.20)
		_portal_transition_busy = false


func _on_encounters_reset() -> void:
	_banner_fade_timer = 0.0
	if encounter_banner:
		encounter_banner.visible = false


func _recompute_overview_camera() -> void:
	if procedural_world == null:
		return
	var span: Vector2 = procedural_world.map_bounds_span
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = maxf(0.6, vp_size.x / maxf(1.0, vp_size.y))
	var sum_span: float = span.x + span.y
	var v_fit: float = sum_span * 0.39
	var h_fit: float = (sum_span * 0.66) / aspect
	overview_size = maxf(60.0, maxf(v_fit, h_fit))

	var pullback: float = maxf(85.0, sum_span * 0.65)
	overview_pos = procedural_world.map_bounds_center + Vector3(-pullback, pullback, pullback)


func _apply_biome_environment(biome_id: int) -> void:
	var b: Dictionary = BiomeThemeScript.get_biome_data(biome_id)
	if world_env and world_env.environment:
		world_env.environment.ambient_light_color = b["ambient_col"] as Color
		world_env.environment.ambient_light_energy = float(b["ambient_energy"])
	if dir_light:
		dir_light.light_color = b["light_col"] as Color
		dir_light.light_energy = float(b["light_energy"])


func _update_debug_labels() -> void:
	if procedural_world == null or procedural_world.current_graph == null:
		return
	var g: PlainsGraph = procedural_world.current_graph
	var b_name: String = BiomeThemeScript.get_biome_name(procedural_world.current_biome_id)
	if preset_button:
		preset_button.text = "Mode: %s" % g.preset_name
	if _biome_button:
		_biome_button.text = "Biome: %s" % b_name
	if stats_label:
		stats_label.text = "[%s | %s] Seed: %d | Arenas: %d" % [
			g.preset_name,
			b_name,
			procedural_world.current_seed,
			g.areas.size()
		]


func _on_cam_button_pressed() -> void:
	_recompute_overview_camera()
	overview_mode = not overview_mode


func _on_biome_pressed() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	var next_biome: int = (procedural_world.current_biome_id + 1) % BiomeThemeScript.get_biome_count()
	NetworkManager.active_biome_id = next_biome
	var cur_seed: int = procedural_world.current_seed
	var cur_mode: int = int(procedural_world.preset_mode)
	if multiplayer.has_multiplayer_peer():
		_sync_world_layout.rpc(cur_seed, cur_mode, next_biome)
	else:
		_sync_world_layout(cur_seed, cur_mode, next_biome)


func _on_preset_pressed() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	var next_mode: int = (int(procedural_world.preset_mode) + 1) % MapPresetConfigScript.get_preset_count()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var new_seed: int = int(rng.seed & 0x7FFFFFFF)
	var cur_biome: int = procedural_world.current_biome_id
	NetworkManager.active_map_preset = next_mode
	NetworkManager.active_map_seed = new_seed
	if multiplayer.has_multiplayer_peer():
		_sync_world_layout.rpc(new_seed, next_mode, cur_biome)
	else:
		_sync_world_layout(new_seed, next_mode, cur_biome)


func _on_regen_pressed() -> void:
	var cur_biome: int = procedural_world.current_biome_id if procedural_world else 0
	_regen_with_biome(cur_biome)


func _regen_with_biome(target_biome: int) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var new_seed: int = maxi(1, int(rng.randi() & 0x7FFFFFFF))
	if procedural_world and new_seed == procedural_world.current_seed:
		new_seed = maxi(1, int((new_seed + 7919) & 0x7FFFFFFF))
	var cur_mode: int = int(procedural_world.preset_mode)
	NetworkManager.active_map_seed = new_seed
	NetworkManager.active_biome_id = target_biome
	if multiplayer.has_multiplayer_peer():
		_sync_world_layout.rpc(new_seed, cur_mode, target_biome)
	else:
		_sync_world_layout(new_seed, cur_mode, target_biome)


@rpc("authority", "call_local", "reliable")
func _sync_world_layout(p_seed: int, p_mode: int, p_biome: int = -1) -> void:
	if _reward_draft_overlay and _reward_draft_overlay.has_method("close_draft"):
		_reward_draft_overlay.call("close_draft")
	if _portal_confirm_modal and _portal_confirm_modal.has_method("close_modal"):
		_portal_confirm_modal.call("close_modal")
	NetworkManager.active_map_seed = p_seed
	NetworkManager.active_map_preset = p_mode
	if p_biome >= 0:
		NetworkManager.active_biome_id = p_biome
	if ProjectilePool and ProjectilePool.has_method("release_all"):
		ProjectilePool.call("release_all")
	procedural_world.generate_world(p_seed, p_mode, p_biome)
	_reposition_existing_players(_spawn_pos)


func _reposition_existing_players(base_pos: Vector3) -> void:
	var children: Array[Node] = players_container.get_children()
	var count: int = children.size()
	for i in range(count):
		var p_node: CharacterBody3D = children[i] as CharacterBody3D
		if p_node == null:
			continue
		p_node.velocity = Vector3.ZERO
		if "is_dashing" in p_node:
			p_node.set("is_dashing", false)
		if p_node.has_method("restore_full_health"):
			p_node.call("restore_full_health")
		var offset := Vector3.ZERO
		if count > 1:
			var angle: float = float(i) * (TAU / float(count))
			offset = Vector3(cos(angle) * 1.8, 0.0, sin(angle) * 1.8)
		p_node.global_position = base_pos + offset
		p_node.reset_physics_interpolation()


func _wire_player_signals_and_hud(p_node: Node) -> void:
	if p_node == null:
		return
	if p_node.has_signal("player_defeated"):
		var cb := Callable(self, "_on_player_defeated")
		if not p_node.is_connected("player_defeated", cb):
			p_node.connect("player_defeated", cb)
	if p_node.has_signal("item_replaced_for_drop"):
		var drop_cb := Callable(self, "_on_player_item_replaced_for_drop")
		if not p_node.is_connected("item_replaced_for_drop", drop_cb):
			p_node.connect("item_replaced_for_drop", drop_cb)


func _on_player_item_replaced_for_drop(category: String, item_id: int, drop_origin: Vector3) -> void:
	if encounter_manager and encounter_manager.has_method("spawn_dropped_item"):
		encounter_manager.call("spawn_dropped_item", category, item_id, drop_origin)


func _on_dropped_item_interacted(drop_node: Node3D, player_node: Node) -> void:
	if _tutorial_modal and _tutorial_modal.has_method("close_modal"):
		_tutorial_modal.call("close_modal")
	if _portal_confirm_modal and _portal_confirm_modal.has_method("close_modal"):
		_portal_confirm_modal.call("close_modal")
	if _reward_draft_overlay and _reward_draft_overlay.has_method("open_for_ground_item"):
		_reward_draft_overlay.call("open_for_ground_item", drop_node, player_node)


func _setup_portal_confirm_modal() -> void:
	if _portal_confirm_modal != null:
		return
	var confirm_layer := CanvasLayer.new()
	confirm_layer.name = "PortalConfirmLayer"
	confirm_layer.layer = 10
	add_child(confirm_layer)

	_portal_confirm_modal = PortalConfirmModalScript.new() as Control
	_portal_confirm_modal.name = "PortalConfirmModal"
	confirm_layer.add_child(_portal_confirm_modal)
	if _portal_confirm_modal.has_signal("proceed_confirmed"):
		_portal_confirm_modal.connect("proceed_confirmed", _traverse_stage_portal)


func _bind_local_player_health_hud() -> void:
	if player_health_bar and _local_player:
		if player_health_bar.has_method("bind_player"):
			player_health_bar.call("bind_player", _local_player)
		elif _local_player.has_method("get_health_component") and player_health_bar.has_method("bind_health_component"):
			var hc: HealthComponent = _local_player.call("get_health_component") as HealthComponent
			if hc:
				player_health_bar.call("bind_health_component", hc)


func _setup_reward_draft_overlay() -> void:
	if _reward_draft_overlay != null:
		return
	var draft_layer := CanvasLayer.new()
	draft_layer.name = "RewardDraftLayer"
	draft_layer.layer = 9
	add_child(draft_layer)

	_reward_draft_overlay = RewardDraftOverlayScript.new() as Control
	_reward_draft_overlay.name = "RewardDraftOverlay"
	draft_layer.add_child(_reward_draft_overlay)
	if player_health_bar and _reward_draft_overlay.has_method("bind_hud_bar"):
		_reward_draft_overlay.call("bind_hud_bar", player_health_bar)


func _on_reward_pedestal_interacted(pedestal: Node3D, player_node: Node) -> void:
	if _tutorial_modal and _tutorial_modal.has_method("close_modal"):
		_tutorial_modal.call("close_modal")
	if _reward_draft_overlay and _reward_draft_overlay.has_method("open_for_pedestal"):
		_reward_draft_overlay.call("open_for_pedestal", pedestal, player_node)


func _setup_tutorial_modal() -> void:
	if _tutorial_modal != null:
		return
	var tut_layer := CanvasLayer.new()
	tut_layer.name = "TutorialLayer"
	tut_layer.layer = 9
	add_child(tut_layer)

	_tutorial_modal = TutorialModalScript.new() as Control
	_tutorial_modal.name = "TutorialModal"
	tut_layer.add_child(_tutorial_modal)

	if leave_button and leave_button.get_parent():
		var hbox: Node = leave_button.get_parent()
		_tutorial_button = Button.new()
		_tutorial_button.name = "TutorialButton"
		_tutorial_button.text = "Tutorial"
		_tutorial_button.focus_mode = Control.FOCUS_NONE
		hbox.add_child(_tutorial_button)
		hbox.move_child(_tutorial_button, leave_button.get_index())
		_configure_button(_tutorial_button, _on_tutorial_pressed)


func _on_tutorial_pressed() -> void:
	if _tutorial_modal == null:
		return
	if _reward_draft_overlay and bool(_reward_draft_overlay.get("_is_open")):
		return
	if player_health_bar and player_health_bar.has_method("is_pickup_placement_active") and bool(player_health_bar.call("is_pickup_placement_active")):
		return
	if _tutorial_modal.has_method("toggle_for_player"):
		_tutorial_modal.call("toggle_for_player", _local_player)


func _setup_pause_menu_modal() -> void:
	if _pause_menu_modal != null:
		return
	var pause_layer := CanvasLayer.new()
	pause_layer.name = "PauseMenuLayer"
	pause_layer.layer = 11
	pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(pause_layer)

	_pause_menu_modal = PauseMenuModalScript.new() as Control
	_pause_menu_modal.name = "PauseMenuModal"
	pause_layer.add_child(_pause_menu_modal)
	if _pause_menu_modal.has_method("set_online_lobby_available"):
		_pause_menu_modal.call("set_online_lobby_available", NetworkManager.supports_online_multiplayer())
	_pause_menu_modal.connect("tutorial_requested", _on_tutorial_pressed)
	_pause_menu_modal.connect("web_quality_cycle_requested", _on_web_quality_cycle_requested)
	_pause_menu_modal.connect("main_menu_requested", _on_leave_pressed)
	_pause_menu_modal.connect("debug_biome_requested", _on_biome_pressed)
	_pause_menu_modal.connect("debug_preset_requested", _on_preset_pressed)
	_pause_menu_modal.connect("debug_regen_requested", _on_regen_pressed)
	_pause_menu_modal.connect("debug_teleport_requested", _on_teleport_pressed)
	_pause_menu_modal.connect("debug_boss_jump_requested", _on_jump_to_boss_pressed)
	_pause_menu_modal.connect("debug_overview_requested", _on_cam_button_pressed)
	_pause_menu_modal.connect("debug_god_mode_requested", _on_god_mode_pressed)
	if _pause_menu_modal.has_method("set_debug_god_mode_label"):
		_pause_menu_modal.call("set_debug_god_mode_label", _god_mode_enabled)


func _setup_game_over_overlay() -> void:
	if _game_over_overlay != null:
		return
	var layer := CanvasLayer.new()
	layer.name = "GameOverLayer"
	layer.layer = 10
	add_child(layer)

	_game_over_overlay = GameOverOverlayScript.new() as Control
	_game_over_overlay.name = "GameOverOverlay"
	layer.add_child(_game_over_overlay)
	if _game_over_overlay.has_method("set_online_lobby_available"):
		_game_over_overlay.call("set_online_lobby_available", NetworkManager.supports_online_multiplayer())

	_game_over_overlay.connect("restart_new_map_requested", _on_game_over_restart_new_map)
	_game_over_overlay.connect("retry_sanctuary_requested", _on_game_over_retry_sanctuary)
	_game_over_overlay.connect("return_to_lobby_requested", _on_leave_pressed)


func _close_game_over_and_restore_hud() -> void:
	if _game_over_overlay and _game_over_overlay.has_method("hide_instant"):
		_game_over_overlay.call("hide_instant")
	if hud_layer:
		hud_layer.visible = true


func _on_game_over_restart_new_map() -> void:
	if _pause_menu_modal and _pause_menu_modal.has_method("close_menu"):
		_pause_menu_modal.call("close_menu")
	if get_tree().paused:
		get_tree().paused = false
	_close_game_over_and_restore_hud()
	for ch in players_container.get_children():
		if ch.has_method("reset_for_new_run"):
			ch.call("reset_for_new_run")
	NetworkManager.active_biome_id = 0
	_regen_with_biome(0)
	if camera and not is_overview and _local_player:
		camera.global_position = _local_player.global_position + camera_offset
		camera.reset_physics_interpolation()


func _on_game_over_retry_sanctuary() -> void:
	if _pause_menu_modal and _pause_menu_modal.has_method("close_menu"):
		_pause_menu_modal.call("close_menu")
	if get_tree().paused:
		get_tree().paused = false
	_close_game_over_and_restore_hud()
	if encounter_manager and encounter_manager.is_encounter_active():
		encounter_manager.reset_active_encounter(false)
	_reposition_existing_players(_spawn_pos)
	if camera and not is_overview and _local_player:
		camera.global_position = _local_player.global_position + camera_offset
		camera.reset_physics_interpolation()


func _on_player_defeated(_peer_id: int) -> void:
	# Keep the 3D world and remaining arena units active in the background while fading to grayscale
	if _pause_menu_modal and _pause_menu_modal.has_method("close_menu"):
		_pause_menu_modal.call("close_menu")
	if get_tree().paused:
		get_tree().paused = false
	if _reward_draft_overlay and _reward_draft_overlay.has_method("close_draft"):
		_reward_draft_overlay.call("close_draft")
	if hud_layer:
		hud_layer.visible = false
	if _game_over_overlay and _game_over_overlay.has_method("show_game_over"):
		_game_over_overlay.call("show_game_over")


func spawn_players() -> void:
	for child in players_container.get_children():
		child.queue_free()

	var player_dict: Dictionary = NetworkManager.players
	if player_dict.is_empty():
		var solo_player: Node3D = PLAYER_SCENE.instantiate() as Node3D
		solo_player.name = "1"
		solo_player.position = _spawn_pos
		players_container.add_child(solo_player)
		solo_player.call("setup", 1, {
			"name": "SoloPlayer",
			"color": Color(0.25, 0.6, 1.0)
		})
		_wire_player_signals_and_hud(solo_player)
		_local_player = solo_player as CharacterBody3D
		_bind_local_player_health_hud()
		_apply_god_mode_to_players()
		if camera and not is_overview:
			camera.global_position = _spawn_pos + camera_offset
			camera.reset_physics_interpolation()
		return

	var peer_ids: Array = player_dict.keys()
	var count: int = peer_ids.size()

	for i in range(count):
		var peer_id: int = peer_ids[i]
		var info: Dictionary = player_dict[peer_id]

		var player_instance: Node3D = PLAYER_SCENE.instantiate() as Node3D
		player_instance.name = str(peer_id)

		if count > 1:
			var angle: float = float(i) * (TAU / float(count))
			player_instance.position = _spawn_pos + Vector3(cos(angle) * 1.8, 0.0, sin(angle) * 1.8)
		else:
			player_instance.position = _spawn_pos

		players_container.add_child(player_instance)
		player_instance.call("setup", peer_id, info)
		_wire_player_signals_and_hud(player_instance)

	var my_id: int = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	_local_player = players_container.get_node_or_null(str(my_id)) as CharacterBody3D
	_bind_local_player_health_hud()
	_apply_god_mode_to_players()
	if _local_player and camera and not is_overview:
		camera.global_position = _local_player.global_position + camera_offset
		camera.reset_physics_interpolation()


func _update_hud() -> void:
	if not is_inside_tree() or not info_label:
		return
	var my_id: int = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	var total: int = NetworkManager.get_player_count()
	if total == 0:
		total = 1
	info_label.text = "Peer ID: %d | Players: %d" % [my_id, total]


func _on_player_connected(peer_id: int, info: Dictionary) -> void:
	if not players_container.has_node(str(peer_id)):
		var player_instance: Node3D = PLAYER_SCENE.instantiate() as Node3D
		player_instance.name = str(peer_id)
		var angle: float = float(peer_id % 8) * (TAU / 8.0)
		player_instance.position = _spawn_pos + Vector3(cos(angle) * 1.8, 0.0, sin(angle) * 1.8)
		players_container.add_child(player_instance)
		player_instance.call("setup", peer_id, info)
		_wire_player_signals_and_hud(player_instance)
	_apply_god_mode_to_players()
	_update_hud()
	if _pause_menu_modal and bool(_pause_menu_modal.call("is_open")):
		_pause_menu_modal.call("refresh_pause_mode", _is_solo_session())


func _on_player_disconnected(peer_id: int) -> void:
	var player_node: Node = players_container.get_node_or_null(str(peer_id))
	if player_node:
		player_node.queue_free()
	_update_hud()
	if _pause_menu_modal and bool(_pause_menu_modal.call("is_open")):
		_pause_menu_modal.call("refresh_pause_mode", _is_solo_session())


func _on_server_disconnected() -> void:
	if _pause_menu_modal and _pause_menu_modal.has_method("close_menu"):
		_pause_menu_modal.call("close_menu")
	if get_tree() and get_tree().paused:
		get_tree().paused = false
	if not NetworkManager.supports_online_multiplayer():
		return
	if get_tree() and get_tree().current_scene and get_tree().current_scene.scene_file_path != "res://ui/lobby.tscn":
		get_tree().change_scene_to_file("res://ui/lobby.tscn")


func _on_leave_pressed() -> void:
	if not NetworkManager.supports_online_multiplayer():
		_on_game_over_restart_new_map()
		return
	if _pause_menu_modal and _pause_menu_modal.has_method("close_menu"):
		_pause_menu_modal.call("close_menu")
	if get_tree() and get_tree().paused:
		get_tree().paused = false
	NetworkManager.leave_game()
	get_tree().change_scene_to_file("res://ui/lobby.tscn")


func _update_teleport_button_label() -> void:
	if not teleport_button:
		return
	if _waypoints.is_empty():
		teleport_button.text = "Next Room"
		return
	var next_idx: int = (_current_waypoint_idx + 1) % _waypoints.size()
	teleport_button.text = "Go: %s" % str(_waypoints[next_idx]["label"])


func _on_teleport_pressed() -> void:
	if _waypoints.is_empty():
		return
	if encounter_manager and encounter_manager.is_encounter_active():
		encounter_manager.reset_active_encounter(true)
	_current_waypoint_idx = (_current_waypoint_idx + 1) % _waypoints.size()
	var target_pos: Vector3 = _waypoints[_current_waypoint_idx]["position"]
	var my_id: int = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	var local_player: CharacterBody3D = players_container.get_node_or_null(str(my_id)) as CharacterBody3D
	if local_player:
		local_player.velocity = Vector3.ZERO
		if "is_dashing" in local_player:
			local_player.set("is_dashing", false)
		local_player.global_position = target_pos
		local_player.reset_physics_interpolation()
	if is_overview:
		overview_mode = false
	_update_teleport_button_label()


func _on_jump_to_boss_pressed() -> void:
	if not OS.is_debug_build():
		return
	if encounter_manager == null:
		return
	if encounter_manager.is_encounter_active():
		encounter_manager.reset_active_encounter(false)
	var boss_center: Vector3 = encounter_manager.get_boss_area_center()
	var target_pos: Vector3 = boss_center + Vector3(0.0, 0.0, 7.5)
	_reposition_existing_players(target_pos)
	if is_overview:
		overview_mode = false
	if camera and not is_overview:
		camera.global_position = target_pos + camera_offset
		camera.reset_physics_interpolation()


func _on_god_mode_pressed() -> void:
	if not OS.is_debug_build():
		return
	_god_mode_enabled = not _god_mode_enabled
	_apply_god_mode_to_players()


func _apply_god_mode_to_players() -> void:
	if _god_mode_button:
		_god_mode_button.text = "God Mode: ON [F2]" if _god_mode_enabled else "God Mode: OFF [F2]"
	if _pause_menu_modal and _pause_menu_modal.has_method("set_debug_god_mode_label"):
		_pause_menu_modal.call("set_debug_god_mode_label", _god_mode_enabled)
	if players_container == null:
		return
	for ch in players_container.get_children():
		if ch != null and ch.has_method("set_debug_god_mode"):
			ch.call("set_debug_god_mode", _god_mode_enabled)


func _setup_web_transition_curtain() -> void:
	if not OS.has_feature("web") or _web_curtain_rect != null:
		return
	var curtain_layer := CanvasLayer.new()
	curtain_layer.name = "WebTransitionLayer"
	curtain_layer.layer = 100
	curtain_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(curtain_layer)

	_web_curtain_rect = ColorRect.new()
	_web_curtain_rect.name = "WebTransitionCurtain"
	_web_curtain_rect.color = Color(0.035, 0.05, 0.085, 1.0)
	_web_curtain_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_web_curtain_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_web_curtain_rect.modulate.a = 1.0
	_web_curtain_rect.visible = true
	curtain_layer.add_child(_web_curtain_rect)


func _show_web_curtain_instant() -> void:
	if _web_curtain_rect == null:
		return
	if _web_curtain_tween != null and is_instance_valid(_web_curtain_tween):
		_web_curtain_tween.kill()
		_web_curtain_tween = null
	_web_curtain_rect.modulate.a = 1.0
	_web_curtain_rect.visible = true


func _fade_out_web_curtain(duration_s: float) -> void:
	if _web_curtain_rect == null:
		return
	if _web_curtain_tween != null and is_instance_valid(_web_curtain_tween):
		_web_curtain_tween.kill()
	_web_curtain_tween = create_tween()
	_web_curtain_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_web_curtain_tween.tween_property(_web_curtain_rect, "modulate:a", 0.0, duration_s)
	_web_curtain_tween.finished.connect(func() -> void:
		if _web_curtain_rect != null and is_instance_valid(_web_curtain_rect):
			_web_curtain_rect.visible = false
	)


func _on_web_viewport_resized() -> void:
	if _web_quality_idx == 0:
		_apply_web_quality_preset()


func _apply_web_quality_preset() -> void:
	var vp: Viewport = get_viewport()
	if vp == null:
		return
	var label_text: String = "Graphics: Balanced (Auto 900p)"
	match _web_quality_idx:
		0:
			# Disable MSAA before downscaling 3D in WebGL2 GL Compatibility.
			vp.msaa_3d = Viewport.MSAA_DISABLED
			var longest: float = maxf(float(vp.size.x), float(vp.size.y) * (16.0 / 9.0))
			vp.scaling_3d_scale = clampf(1600.0 / maxf(1.0, longest), 0.50, 1.0)
			label_text = "Graphics: Balanced (Auto 900p)"
		1:
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.scaling_3d_scale = 0.60
			label_text = "Graphics: Performance (60% 3D)"
		2:
			vp.scaling_3d_scale = 1.0
			vp.msaa_3d = Viewport.MSAA_2X
			label_text = "Graphics: Crisp (Native + 2x AA)"
	if _pause_menu_modal and _pause_menu_modal.has_method("set_web_quality_label"):
		_pause_menu_modal.call("set_web_quality_label", label_text)


func _on_web_quality_cycle_requested() -> void:
	_web_quality_idx = (_web_quality_idx + 1) % 3
	_apply_web_quality_preset()


func _add_warmup_mesh(parent: Node3D, mesh_res: Mesh, mat: Material) -> void:
	if mesh_res == null or mat == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh_res
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _run_web_shader_prewarm() -> void:
	if camera == null or not is_inside_tree():
		_fade_out_web_curtain(0.18)
		return

	var warmup_root := Node3D.new()
	warmup_root.name = "_WebShaderWarmup"
	warmup_root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	warmup_root.scale = Vector3.ONE * 0.002
	add_child(warmup_root)
	warmup_root.global_position = camera.global_position - camera.global_transform.basis.z * 2.0

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	var sphere := SphereMesh.new()
	sphere.radius = 0.25
	sphere.height = 0.5
	sphere.radial_segments = 8
	sphere.rings = 4

	# 1. Projectile unshaded+emission material
	_add_warmup_mesh(warmup_root, sphere, ProjectileScript._get_tint_mat(Color(1.0, 0.88, 0.42)))

	# 2. Additive vertex-color trail strip (Trail3D / LightningArcEffect)
	var imm := ImmediateMesh.new()
	imm.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	imm.surface_set_color(Color.WHITE)
	imm.surface_add_vertex(Vector3.ZERO)
	imm.surface_set_color(Color.WHITE)
	imm.surface_add_vertex(Vector3(0.1, 0.0, 0.0))
	imm.surface_set_color(Color.WHITE)
	imm.surface_add_vertex(Vector3(0.0, 0.1, 0.0))
	imm.surface_end()
	_add_warmup_mesh(warmup_root, imm, Trail3DScript.get_shared_trail_material())

	# 3. CombatZoneEffect alpha ring/fill/frame palette materials
	var zone_mats: Array[StandardMaterial3D] = CombatZoneScript._get_palette_mats("warmup", Color(0.4, 0.85, 1.0))
	for zm in zone_mats:
		_add_warmup_mesh(warmup_root, quad, zm)

	# 4. EnemyHazard.gdshader & CosmicCore.gdshader
	var hazard_mat := ShaderMaterial.new()
	hazard_mat.shader = ENEMY_HAZARD_SHADER
	_add_warmup_mesh(warmup_root, plane, hazard_mat)
	var medallion_mat := ShaderMaterial.new()
	medallion_mat.shader = COSMIC_CORE_SHADER
	_add_warmup_mesh(warmup_root, plane, medallion_mat)

	# 5. OverheadBar.gdshader
	var bar_mat := ShaderMaterial.new()
	bar_mat.shader = OVERHEAD_BAR_SHADER
	_add_warmup_mesh(warmup_root, quad, bar_mat)

	# 6. ContactShadow.gdshader
	var shadow_mat := ShaderMaterial.new()
	shadow_mat.shader = CONTACT_SHADOW_SHADER
	_add_warmup_mesh(warmup_root, plane, shadow_mat)

	# 7. EnemyArchetypeData toon/unshaded/status materials
	var base_arch: EnemyArchetypeData = ArchetypeScript.get_archetype(0)
	if base_arch:
		_add_warmup_mesh(warmup_root, sphere, base_arch.body_material)
		_add_warmup_mesh(warmup_root, sphere, base_arch.trim_material)
	var chrono_arch: EnemyArchetypeData = ArchetypeScript.get_archetype(ArchetypeScript.ArchetypeId.BOSS_CHRONOMANCER)
	if chrono_arch:
		_add_warmup_mesh(warmup_root, sphere, chrono_arch.body_material)
		_add_warmup_mesh(warmup_root, sphere, chrono_arch.trim_material)
	_add_warmup_mesh(warmup_root, sphere, ArchetypeScript.get_hit_flash_material())
	_add_warmup_mesh(warmup_root, sphere, ArchetypeScript.get_status_frost_material())
	_add_warmup_mesh(warmup_root, sphere, ArchetypeScript.get_status_burn_material())
	_add_warmup_mesh(warmup_root, sphere, ArchetypeScript.get_status_poison_material())

	await get_tree().process_frame
	if is_inside_tree():
		await get_tree().process_frame
	if is_instance_valid(warmup_root):
		warmup_root.queue_free()
	if is_inside_tree():
		_fade_out_web_curtain(0.22)
