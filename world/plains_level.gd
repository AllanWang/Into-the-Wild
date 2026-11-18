class_name PlainsLevel
extends Node3D

## Level controller for world/plains_level.tscn.
## Uses PlainsGenerator (extending ProceduralWorld) for Shape of Dreams web maps
## with 100% authentic grass_multimesh.tres tile-cropped meadow textures.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const MapPresetConfigScript = preload("res://world/map_preset_config.gd")
const GameOverOverlayScript = preload("res://ui/game_over_overlay.gd")
const RewardDraftOverlayScript = preload("res://ui/reward_draft_overlay.gd")

@onready var generator: PlainsGenerator = $PlainsGenerator
@onready var encounter_manager: ArenaEncounterManager = get_node_or_null("ArenaEncounterManager") as ArenaEncounterManager
@onready var players_container: Node3D = $Players
@onready var camera: Camera3D = $Camera3D
@onready var hud_layer: CanvasLayer = $HUD
@onready var encounter_banner: Label = %EncounterBanner if has_node("%EncounterBanner") else null
@onready var player_health_bar: Control = %PlayerHealthBar if has_node("%PlayerHealthBar") else null

# HUD elements
@onready var info_label: Label = %InfoLabel
@onready var debug_overlay: MarginContainer = %DebugOverlay
@onready var stats_label: Label = %StatsLabel
@onready var preset_button: Button = %PresetButton if has_node("%PresetButton") else null
@onready var overview_button: Button = %OverviewButton
@onready var regen_button: Button = %RegenButton
@onready var teleport_button: Button = %TeleportButton if has_node("%TeleportButton") else null
@onready var leave_button: Button = %LeaveButton

# Camera states (Shape of Dreams MOBA/roguelike arena framing)
var player_cam_offset: Vector3 = Vector3(-18.0, 18.0, 18.0)
var overview_cam_pos: Vector3 = Vector3(-90.0, 90.0, 60.0)
var is_overview_mode: bool = false
var normal_cam_size: float = 13.5
var overview_cam_size: float = 110.0
var current_spawn_pos: Vector3 = Vector3(0.0, 0.0, 6.8)
const MIN_CAMERA_SIZE: float = 7.0
const MAX_CAMERA_SIZE: float = 16.0
const ZOOM_STEP: float = 0.75

var _waypoints: Array[Dictionary] = []
var _current_waypoint_idx: int = 0
var _local_player: CharacterBody3D = null
var _active_arena_title: String = "Combat Arena"
var _banner_fade_timer: float = 0.0
var _game_over_overlay: Control = null
var _reward_draft_overlay: Control = null


func _ready() -> void:
	var is_emb: bool = Engine.is_embedded_in_editor() or ("--wid" in OS.get_cmdline_args()) or (DebugTools != null and DebugTools.is_embedded)
	if not OS.has_feature("web") and not is_emb and not EngineDebugger.is_active():
		DisplayServer.window_move_to_foreground()

	if not NetworkManager.peer:
		NetworkManager.host_game(0, "SoloPlayer")

	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)

	_setup_btn(leave_button, _on_leave_pressed)
	_setup_btn(regen_button, _on_regen_pressed)
	_setup_btn(overview_button, _on_overview_pressed)
	_setup_btn(preset_button, _on_preset_pressed)
	_setup_btn(teleport_button, _on_teleport_pressed)

	if debug_overlay:
		debug_overlay.visible = OS.is_debug_build()

	for lbl in [stats_label, info_label]:
		if lbl:
			lbl.add_theme_constant_override("outline_size", 4)
			lbl.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.12, 0.9))

	generator.map_generated.connect(_on_map_generated)
	generator.graph_ready.connect(_on_graph_ready)

	if encounter_manager:
		encounter_manager.players_container = players_container
		encounter_manager.encounter_started.connect(_on_encounter_started)
		encounter_manager.wave_incoming.connect(_on_wave_incoming)
		encounter_manager.wave_started.connect(_on_wave_started)
		encounter_manager.encounter_progress_changed.connect(_on_encounter_progress_changed)
		encounter_manager.encounter_cleared.connect(_on_encounter_cleared)
		encounter_manager.encounters_reset.connect(_on_encounters_reset)
		encounter_manager.reward_pedestal_interacted.connect(_on_reward_pedestal_interacted)

	if camera:
		camera.near = 0.05
		camera.far = 2500.0
		if not is_overview_mode:
			camera.size = normal_cam_size

	if not generator.current_graph:
		generator.generate_map(generator.map_seed, int(generator.preset_mode))

	_setup_reward_draft_overlay()
	_setup_game_over_overlay()
	_update_hud()
	NetworkManager.mark_client_ready()


func _setup_btn(btn: Button, cb: Callable) -> void:
	if btn == null:
		return
	btn.focus_mode = Control.FOCUS_NONE
	if not btn.pressed.is_connected(cb):
		btn.pressed.connect(cb)


func _unhandled_input(event: InputEvent) -> void:
	if is_overview_mode:
		return
	if event is InputEventMouseButton and event.pressed:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			normal_cam_size = clampf(normal_cam_size - ZOOM_STEP, MIN_CAMERA_SIZE, MAX_CAMERA_SIZE)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			normal_cam_size = clampf(normal_cam_size + ZOOM_STEP, MIN_CAMERA_SIZE, MAX_CAMERA_SIZE)


func _physics_process(delta: float) -> void:
	if _banner_fade_timer > 0.0:
		_banner_fade_timer -= delta
		if _banner_fade_timer <= 0.0 and encounter_banner and (encounter_manager == null or not encounter_manager.is_encounter_active()):
			encounter_banner.visible = false

	if camera == null:
		return
	if is_overview_mode:
		camera.global_position = camera.global_position.lerp(overview_cam_pos, clampf(8.0 * delta, 0.0, 1.0))
		camera.size = lerpf(camera.size, overview_cam_size, clampf(8.0 * delta, 0.0, 1.0))
	else:
		if _local_player == null or not is_instance_valid(_local_player):
			var my_id: int = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
			_local_player = players_container.get_node_or_null(str(my_id)) as CharacterBody3D
		if _local_player:
			var target_pos: Vector3 = _local_player.global_position + player_cam_offset
			camera.global_position = camera.global_position.lerp(target_pos, clampf(10.0 * delta, 0.0, 1.0))
		camera.size = lerpf(camera.size, normal_cam_size, clampf(8.0 * delta, 0.0, 1.0))


func _on_map_generated(spawn_pos: Vector3, _goal_pos: Vector3) -> void:
	current_spawn_pos = spawn_pos
	_waypoints = generator.get_room_waypoints()
	_current_waypoint_idx = 0
	_spawn_or_reposition_players()
	_update_stats_label()
	_update_teleport_label()


func _on_graph_ready(graph: PlainsGraph) -> void:
	if encounter_manager:
		encounter_manager.setup_for_graph(graph, generator.current_seed)
	var span: Vector2 = generator.map_bounds_span
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = maxf(0.6, vp_size.x / maxf(1.0, vp_size.y))
	var sum_span: float = span.x + span.y
	overview_cam_size = maxf(60.0, maxf(sum_span * 0.39, (sum_span * 0.66) / aspect))
	var pullback: float = maxf(85.0, sum_span * 0.65)
	overview_cam_pos = generator.map_bounds_center + Vector3(-pullback, pullback, pullback)


func _wire_player_signals_and_hud(p_node: Node) -> void:
	if p_node == null:
		return
	if p_node.has_signal("player_defeated"):
		var cb := Callable(self, "_on_player_defeated")
		if not p_node.is_connected("player_defeated", cb):
			p_node.connect("player_defeated", cb)


func _bind_local_player_health_hud() -> void:
	var my_id: int = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	_local_player = players_container.get_node_or_null(str(my_id)) as CharacterBody3D
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


func _on_reward_pedestal_interacted(pedestal: Node3D, player_node: Node) -> void:
	if _reward_draft_overlay and _reward_draft_overlay.has_method("open_for_pedestal"):
		_reward_draft_overlay.call("open_for_pedestal", pedestal, player_node)


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

	_game_over_overlay.connect("restart_new_map_requested", _on_game_over_restart_new_map)
	_game_over_overlay.connect("retry_sanctuary_requested", _on_game_over_retry_sanctuary)
	_game_over_overlay.connect("return_to_lobby_requested", _on_leave_pressed)


func _close_game_over_and_restore_hud() -> void:
	if _game_over_overlay and _game_over_overlay.has_method("hide_instant"):
		_game_over_overlay.call("hide_instant")
	if hud_layer:
		hud_layer.visible = true


func _on_game_over_restart_new_map() -> void:
	_close_game_over_and_restore_hud()
	for ch in players_container.get_children():
		if ch.has_method("reset_for_new_run"):
			ch.call("reset_for_new_run")
	_on_regen_pressed()


func _on_game_over_retry_sanctuary() -> void:
	_close_game_over_and_restore_hud()
	if encounter_manager and encounter_manager.is_encounter_active():
		encounter_manager.reset_active_encounter(false)
	_spawn_or_reposition_players()


func _on_player_defeated(_peer_id: int) -> void:
	if _reward_draft_overlay and _reward_draft_overlay.has_method("close_draft"):
		_reward_draft_overlay.call("close_draft")
	if hud_layer:
		hud_layer.visible = false
	if _game_over_overlay and _game_over_overlay.has_method("show_game_over"):
		_game_over_overlay.call("show_game_over")


func _spawn_or_reposition_players() -> void:
	var player_dict: Dictionary = NetworkManager.players
	if player_dict.is_empty():
		var solo_player: CharacterBody3D = players_container.get_node_or_null("1") as CharacterBody3D
		if not solo_player:
			solo_player = PLAYER_SCENE.instantiate() as CharacterBody3D
			solo_player.name = "1"
			players_container.add_child(solo_player)
			solo_player.call("setup", 1, {
				"name": "SoloPlayer",
				"color": Color(0.25, 0.6, 1.0)
			})
			_wire_player_signals_and_hud(solo_player)
		solo_player.velocity = Vector3.ZERO
		if "is_dashing" in solo_player:
			solo_player.set("is_dashing", false)
		if solo_player.has_method("restore_full_health"):
			solo_player.call("restore_full_health")
		solo_player.global_position = current_spawn_pos
	else:
		var peer_ids: Array = player_dict.keys()
		var count: int = peer_ids.size()
		for i in range(count):
			var peer_id: int = peer_ids[i]
			var info: Dictionary = player_dict[peer_id]
			var p_node: CharacterBody3D = players_container.get_node_or_null(str(peer_id)) as CharacterBody3D
			if not p_node:
				p_node = PLAYER_SCENE.instantiate() as CharacterBody3D
				p_node.name = str(peer_id)
				players_container.add_child(p_node)
				p_node.call("setup", peer_id, info)
				_wire_player_signals_and_hud(p_node)
			p_node.velocity = Vector3.ZERO
			if "is_dashing" in p_node:
				p_node.set("is_dashing", false)
			if p_node.has_method("restore_full_health"):
				p_node.call("restore_full_health")
			var angle: float = float(i) * (TAU / float(maxi(1, count)))
			var offset_v: Vector3 = Vector3(cos(angle) * 1.8, 0.0, sin(angle) * 1.8) if count > 1 else Vector3.ZERO
			p_node.global_position = current_spawn_pos + offset_v

	_bind_local_player_health_hud()

	if camera and not is_overview_mode:
		camera.global_position = current_spawn_pos + player_cam_offset
		camera.reset_physics_interpolation()


func _update_hud() -> void:
	if not is_inside_tree() or not info_label:
		return
	var my_id: int = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	var total: int = NetworkManager.get_player_count()
	if total == 0:
		total = 1
	info_label.text = "Peer ID: %d | Players: %d" % [my_id, total]


func _update_stats_label() -> void:
	if not generator.current_graph:
		return
	var g: PlainsGraph = generator.current_graph
	if preset_button:
		preset_button.text = "Mode: %s" % g.preset_name
	if stats_label:
		stats_label.text = "[%s] Seed: %d | Arenas: %d | Paths: %d | Grass: %d" % [
			g.preset_name,
			generator.current_seed,
			g.areas.size(),
			g.paths.size(),
			generator.total_grass_blades
		]


func _update_teleport_label() -> void:
	if not teleport_button:
		return
	if _waypoints.is_empty():
		teleport_button.text = "Next Room"
		return
	var next_idx: int = (_current_waypoint_idx + 1) % _waypoints.size()
	teleport_button.text = "Go: %s" % str(_waypoints[next_idx]["label"])


func _on_overview_pressed() -> void:
	if generator.current_graph:
		_on_graph_ready(generator.current_graph)
	is_overview_mode = not is_overview_mode
	if overview_button:
		overview_button.text = "Player Cam" if is_overview_mode else "Overview Cam"


func _on_preset_pressed() -> void:
	if _reward_draft_overlay and _reward_draft_overlay.has_method("close_draft"):
		_reward_draft_overlay.call("close_draft")
	var next_mode: int = (int(generator.preset_mode) + 1) % MapPresetConfigScript.get_preset_count()
	generator.generate_map(0, next_mode)


func _on_regen_pressed() -> void:
	if _reward_draft_overlay and _reward_draft_overlay.has_method("close_draft"):
		_reward_draft_overlay.call("close_draft")
	generator.generate_map(0, int(generator.preset_mode))


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
	if is_overview_mode:
		is_overview_mode = false
		if overview_button:
			overview_button.text = "Overview Cam"
	_update_teleport_label()


func _on_player_connected(peer_id: int, info: Dictionary) -> void:
	if not players_container.has_node(str(peer_id)):
		var player_instance: Node3D = PLAYER_SCENE.instantiate() as Node3D
		player_instance.name = str(peer_id)
		players_container.add_child(player_instance)
		player_instance.call("setup", peer_id, info)
		player_instance.global_position = current_spawn_pos
	_update_hud()


func _on_player_disconnected(peer_id: int) -> void:
	var player_node: Node = players_container.get_node_or_null(str(peer_id))
	if player_node:
		player_node.queue_free()
	_update_hud()


func _on_server_disconnected() -> void:
	if get_tree() and get_tree().current_scene and get_tree().current_scene.scene_file_path != "res://ui/lobby.tscn":
		get_tree().change_scene_to_file("res://ui/lobby.tscn")


func _on_leave_pressed() -> void:
	NetworkManager.leave_game()
	get_tree().change_scene_to_file("res://ui/lobby.tscn")


func _on_encounter_started(_area_idx: int, area_name: String, wave_idx: int, total_waves: int, total_enemies: int) -> void:
	_active_arena_title = area_name
	_banner_fade_timer = 0.0
	if encounter_banner:
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
		encounter_banner.text = "%s Locked — Wave %d / %d  |  Enemies: %d / %d" % [
			_active_arena_title, wave_idx, total_waves, remaining, total
		]


func _on_encounter_cleared(_area_idx: int, area_name: String) -> void:
	if encounter_banner:
		encounter_banner.add_theme_color_override("font_color", Color(0.55, 1.0, 0.52, 1.0))
		encounter_banner.text = "%s Cleared — Upgrade Pedestal Unlocked!" % area_name
		encounter_banner.visible = true
		_banner_fade_timer = 3.0


func _on_encounters_reset() -> void:
	_banner_fade_timer = 0.0
	if encounter_banner:
		encounter_banner.visible = false
