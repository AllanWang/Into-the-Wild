# Godot 4 GDScript & Architecture Guidelines

This document provides foundational rules and standards for all agents working on this Godot 4 codebase.

## 1. Engine & Language Version
- **Godot 4.x only** (Target: Godot 4.3+ / 4.x syntax).
- NEVER use Godot 3 patterns:
  - Use `CharacterBody2D` / `CharacterBody3D`, NOT `KinematicBody2D/3D`.
  - Use `await signal_or_coroutine`, NOT `yield`.
  - Use `@onready`, `@export`, `@rpc` annotations instead of `onready var` or `export var`.
  - Use callable syntax: `button.pressed.connect(_on_button_pressed)`, NOT `connect("pressed", self, "_on_button_pressed")`.
  - Instantiation: `scene.instantiate()`, NOT `scene.instance()`.

## 2. GDScript Typing & Code Style
- **Strict Static Typing**: Always use explicit types for variables, function parameters, and return types.
  ```gdscript
  var speed: float = 200.0
  var target_node: Node2D = null

  func calculate_velocity(direction: Vector2, delta: float) -> Vector2:
      return direction * speed * delta
  ```
- **Naming Conventions**:
  - Files and folders: `snake_case` (e.g., `network_manager.gd`, `player_controller.gd`)
  - Node names in scene tree: `PascalCase` (e.g., `CollisionShape2D`, `InfoLabel`)
  - Classes: `class_name PascalCase`
  - Constants and Enums: `UPPER_SNAKE_CASE`
  - Variables and Functions: `snake_case`
  - Private / Internal functions and vars: prefix with underscore `_` (e.g., `_process()`, `_update_hud()`)
  - Signals: Past-tense or action-completed naming (e.g., `health_changed`, `player_spawned`)

## 3. Architecture & Entity Separation
- **Signal Down, Call Down, Never Crawl Up**:
  - Parents call methods on children (`child.do_something()`).
  - Children emit signals to communicate upwards (`emit_signal(...)` or `signal_name.emit(...)`).
  - Do NOT hardcode relative node paths up the tree like `get_parent().get_parent()`.
- **Component & Composition over Deep Inheritance**:
  - Break complex behavior into independent nodes/components (e.g., `HealthComponent`, `HitboxComponent`, `MovementComponent`).
  - Entities (Player, Enemy, NPC) should compose components rather than inheriting monolithic mega-classes.
- **Single Responsibility Principle (SRP)**:
  - Separate Gameplay logic from UI logic. UI observes state via signals; UI never drives core game simulation state directly.
  - Separate Network synchronization from Local simulation.
  - Separate Data models (use `Resource` or `RefCounted`) from Scene nodes (`Node`, `Node2D`, `Control`).

## 4. Scene & Node Tree Discipline
- Always use `@onready var node_name: Type = $Path` or `%UniqueName` accessors instead of repeated `get_node()` inside `_process()` or frequent calls.
- Prefer Unique Node Names (`%NodeName`) for critical UI or component nodes that might shift positions in the scene hierarchy.
- When creating scenes programmatically, ensure proper ownership (`child.owner = owner`) if saving to disk, or ensure clean lifecycle management (`queue_free()`).

## 5. Subagent Delegation & Incremental Development
- **No Monolithic Overhauls**: Break complex requests into focused subagent tasks:
  1. *Architecture / Interface Design* (defining signals, public methods, and resources).
  2. *Core Entity / Component Implementation* (focused on a single node or script).
  3. *UI / Integration Layer* (connecting signals and visual presentation).
  4. *Testing & Verification* (scene test or script verification).
- Keep agent contexts concise and task-specific.

## 6. Godot Editor Process & Execution Rules for AI Agents
- **Prioritize Using the MCP Server**:
  - When inspecting or modifying the Godot project (scenes, nodes, properties, script attachment, editor state), **always prioritize using the `godot-ai` MCP server tools** (`scene_manage`, `node_create`, `node_set_property`, `script_patch`, etc.).
  - If the MCP server is not connected (`PLUGIN_DISCONNECTED` or session count 0), **ask the user to take a look first to make sure Godot is running and open to this project**.
- **NEVER Launch the Godot Editor Directly**:
  - AI agents must **NEVER** run commands to launch or restart the interactive Godot editor GUI (e.g. `godot.exe --editor`, `godot.exe -e`, or spawning background GUI tasks).
  - Spawning the interactive Godot editor from an Antigravity/agent terminal runner causes stdout/handle locking, Steam DRM/hook conflicts, window focus stalls, and hanging background tasks.
  - Headless execution for static compilation/syntax checks (`godot.exe --headless --path "." --quit`) is safe and encouraged.
- **Handling Editor Restarts**:
  - Restarts should **rarely be needed** in normal development (Godot automatically hot-reloads modified GDScript files, resources, and scenes on disk, and the `godot-ai` MCP bridge maintains live state).
  - If an editor restart is ever genuinely required (e.g., after initial plugin installation or after engine crash/freeze), **PROMPT THE USER** to restart the Godot editor themselves instead of attempting to do so autonomously.
