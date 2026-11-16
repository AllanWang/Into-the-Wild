extends Node3D

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const MapPresetConfigScript = preload("res://world/map_preset_config.gd")
const GameOverOverlayScript = preload("res://ui/game_over_overlay.gd")
const RewardDraftOverlayScript = preload("res://ui/reward_draft_overlay.gd")
const TutorialModalScript = preload("res://ui/tutorial_modal.gd")

@onready var procedural_world: ProceduralWorld = $ProceduralWorld
@onready var encounter_manager: ArenaEncounterManager = get_node_or_null("ArenaEncounterManager") as ArenaEncounterManager
@onready var players_container: Node3D = $Players
@onready var camera: Camera3D = $Camera3D
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
var default_camera_size: float = 11.0
const MIN_CAMERA_SIZE: float = 7.0
const MAX_CAMERA_SIZE: float = 13.5
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

@export var overview_mode: bool = false:
	set(val):
		overview_mode = val
		is_overview = val
		if cam_button:
			cam_button.text = "Player Cam" if is_overview else "Overview Cam"


func _ready() -> void:
	var is_emb: bool = ("--wid" in OS.get_cmdline_args()) or (DebugTools != null and DebugTools.is_embedded)
	if not is_emb:
		DisplayServer.window_move_to_foreground()

	if not NetworkManager.peer:
		NetworkManager.host_game(0, "SoloPlayer")

	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)

	_configure_button(leave_button, _on_leave_pressed)
	_configure_button(cam_button, _on_cam_button_pressed)
	_configure_button(teleport_button, _on_teleport_pressed)
	_configure_button(preset_button, _on_preset_pressed)
	_configure_button(regen_button, _on_regen_pressed)

	if cam_button:
		cam_button.text = "Player Cam" if is_overview else "Overview Cam"

	if debug_overlay:
		debug_overlay.visible = OS.is_debug_build()

	for lbl in [stats_label, info_label]:
		if lbl:
			lbl.add_theme_constant_override("outline_size", 4)
			lbl.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.12, 0.9))

	if camera:
		camera.far = 2500.0

	if encounter_manager:
		encounter_manager.players_container = players_container
		encounter_manager.encounter_started.connect(_on_encounter_started)
		encounter_manager.wave_incoming.connect(_on_wave_incoming)
		encounter_manager.wave_started.connect(_on_wave_started)
		encounter_manager.encounter_progress_changed.connect(_on_encounter_progress_changed)
		encounter_manager.encounter_cleared.connect(_on_encounter_cleared)
		encounter_manager.encounters_reset.connect(_on_encounters_reset)
		encounter_manager.reward_pedestal_interacted.connect(_on_reward_pedestal_interacted)
		encounter_manager.stage_portal_entered.connect(_on_stage_portal_entered)

	if procedural_world:
		procedural_world.world_generated.connect(_on_world_generated)
		procedural_world.graph_ready.connect(_on_world_graph_ready)
		var initial_seed: int = NetworkManager.active_map_seed if NetworkManager.active_map_seed > 0 else procedural_world.map_seed
		var initial_preset: int = NetworkManager.active_map_preset
		procedural_world.generate_world(initial_seed if initial_seed > 0 else -1, initial_preset)

	spawn_players()
	_setup_reward_draft_overlay()
	_setup_tutorial_modal()
	_setup_game_over_overlay()
	_update_hud()
	NetworkManager.mark_client_ready()

	if is_overview and camera:
		camera.size = overview_size
		camera.global_position = overview_pos
		camera.reset_physics_interpolation()


func _configure_button(btn: Button, callback: Callable) -> void:
	if btn == null:
		return
	btn.focus_mode = Control.FOCUS_NONE
	if not btn.pressed.is_connected(callback):
		btn.pressed.connect(callback)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var ke: InputEventKey = event as InputEventKey
		if ke.keycode == KEY_F1 or ke.keycode == KEY_H:
			_on_tutorial_pressed()
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
		camera.size = lerpf(camera.size, default_camera_size, clampf(8.0 * delta, 0.0, 1.0))
		if _local_player == null or not is_instance_valid(_local_player):
			var my_id: int = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
			_local_player = players_container.get_node_or_null(str(my_id)) as CharacterBody3D
		if _local_player:
			var target_pos: Vector3 = _local_player.global_position + camera_offset
			camera.global_position = camera.global_position.lerp(target_pos, clampf(10.0 * delta, 0.0, 1.0))


func _on_world_generated(spawn_pos: Vector3, _goal_pos: Vector3) -> void:
	_spawn_pos = spawn_pos
	_waypoints = procedural_world.get_room_waypoints()
	_current_waypoint_idx = 0
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


func _on_stage_portal_entered(_player_node: Node) -> void:
	_on_regen_pressed()
	if camera and _local_player and is_instance_valid(_local_player) and not is_overview:
		camera.global_position = _local_player.global_position + camera_offset
		camera.reset_physics_interpolation()
	if encounter_banner and procedural_world:
		encounter_banner.add_theme_color_override("font_color", Color(0.76, 0.88, 1.0, 1.0))
		encounter_banner.text = "Rift Traversed — Entered New Map (Seed %d)" % procedural_world.current_seed
		encounter_banner.visible = true
		_banner_fade_timer = 3.8


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


func _update_debug_labels() -> void:
	if procedural_world == null or procedural_world.current_graph == null:
		return
	var g: PlainsGraph = procedural_world.current_graph
	if preset_button:
		preset_button.text = "Mode: %s" % g.preset_name
	if stats_label:
		stats_label.text = "[%s] Seed: %d | Arenas: %d | Paths: %d | Grass: %d" % [
			g.preset_name,
			procedural_world.current_seed,
			g.areas.size(),
			g.paths.size(),
			procedural_world.total_grass_blades
		]


func _on_cam_button_pressed() -> void:
	_recompute_overview_camera()
	overview_mode = not overview_mode


func _on_preset_pressed() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	var next_mode: int = (int(procedural_world.preset_mode) + 1) % MapPresetConfigScript.get_preset_count()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var new_seed: int = int(rng.seed & 0x7FFFFFFF)
	NetworkManager.active_map_preset = next_mode
	NetworkManager.active_map_seed = new_seed
	if multiplayer.has_multiplayer_peer():
		_sync_world_layout.rpc(new_seed, next_mode)
	else:
		_sync_world_layout(new_seed, next_mode)


func _on_regen_pressed() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var new_seed: int = maxi(1, int(rng.randi() & 0x7FFFFFFF))
	if procedural_world and new_seed == procedural_world.current_seed:
		new_seed = maxi(1, int((new_seed + 7919) & 0x7FFFFFFF))
	var cur_mode: int = int(procedural_world.preset_mode)
	NetworkManager.active_map_seed = new_seed
	if multiplayer.has_multiplayer_peer():
		_sync_world_layout.rpc(new_seed, cur_mode)
	else:
		_sync_world_layout(new_seed, cur_mode)


@rpc("authority", "call_local", "reliable")
func _sync_world_layout(p_seed: int, p_mode: int) -> void:
	if _reward_draft_overlay and _reward_draft_overlay.has_method("close_draft"):
		_reward_draft_overlay.call("close_draft")
	NetworkManager.active_map_seed = p_seed
	NetworkManager.active_map_preset = p_mode
	if ProjectilePool and ProjectilePool.has_method("release_all"):
		ProjectilePool.call("release_all")
	procedural_world.generate_world(p_seed, p_mode)
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
	if camera and not is_overview and _local_player:
		camera.global_position = _local_player.global_position + camera_offset
		camera.reset_physics_interpolation()


func _on_game_over_retry_sanctuary() -> void:
	_close_game_over_and_restore_hud()
	if encounter_manager and encounter_manager.is_encounter_active():
		encounter_manager.reset_active_encounter(false)
	_reposition_existing_players(_spawn_pos)
	if camera and not is_overview and _local_player:
		camera.global_position = _local_player.global_position + camera_offset
		camera.reset_physics_interpolation()


func _on_player_defeated(_peer_id: int) -> void:
	# Keep the 3D world and remaining arena units active in the background while fading to grayscale
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
	if is_overview:
		overview_mode = false
	_update_teleport_button_label()
