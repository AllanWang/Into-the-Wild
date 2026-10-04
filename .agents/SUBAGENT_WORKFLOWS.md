# Subagent Workflows & Task Delegation Guidelines

To maintain code quality, separation of concerns, and clean context boundaries, complex Godot development tasks should be decomposed into incremental, specialized subagent roles.

## Why Subagent Decomposition?
- **Context Preservation**: Prevents token saturation and keeps hallucination low.
- **Entity & Domain Separation**: Game engines combine networking, physics, rendering, shaders, and UI. Blurring these together produces monolithic, fragile code.
- **Piece-by-Piece Verification**: Every subagent produces a discrete, verifiable chunk verified via the `godot-ai` MCP server (e.g. `editor_state`, `scene_get_hierarchy`, `test_run`, `logs_read`) before moving on.

---

## Standard Subagent Personas

### 1. `Architect & Interface Planner`
- **Focus**: Signal contracts, Data Resources (`Resource`), Public API signatures, scene hierarchy layout.
- **Inputs**: Feature requirements, existing autoloads (`NetworkManager`, `DebugTools`).
- **Outputs**: Interface specifications, typed method signatures, signal definitions, component breakdown.
- **Rules**: Does NOT write low-level game loops or physics algorithms; defines boundaries and contracts.

### 2. `Gameplay & Entity Specialist`
- **Focus**: `CharacterBody2D` / `CharacterBody3D`, state machines, physics, component nodes (e.g., `HitboxComponent`, `HealthComponent`), player controls.
- **Inputs**: Architecture contract, scene requirements.
- **Outputs**: Isolated entity scripts and corresponding `.tscn` composition.
- **Rules**: Strictly follows Godot 4 syntax, static typing, and component composition. Never hardcodes UI updates directly into entity logic.

### 3. `Network & Synchronization Engineer`
- **Focus**: Multiplayer RPCs (`@rpc`), state replication, server reconciliation, interpolation, disconnect/reconnect lifecycle.
- **Inputs**: Gameplay inputs/states to sync, `NetworkManager` conventions.
- **Outputs**: Robust RPC methods, peer authority verification (`is_multiplayer_authority()`), position/rotation smoothing.
- **Rules**: Ensures node paths match across peers (`$Players/{peer_id}`). Handles edge cases when peers disconnect mid-action.

### 4. `UI & HUD Developer`
- **Focus**: Control nodes (`MarginContainer`, `VBoxContainer`, `Label`, etc.), responsive layouts, theme styling.
- **Inputs**: Signals from gameplay entities or network managers.
- **Outputs**: UI scenes (`.tscn`) and controllers (`.gd`).
- **Rules**: Passive observer pattern only. Listens to signals from entities or autoloads; never mutates game simulation directly.

### 5. `Quality Assurance & Verification Subagent`
- **Focus**: In-editor test runs via MCP (`test_run`), editor state verification (`editor_state`), and diagnostic log inspection (`logs_read`).
- **Inputs**: Modified `.gd` and `.tscn` files.
- **Outputs**: Test results, error logs, fix suggestions.
- **Rules**: Always verify via the `godot-ai` MCP server tools. Do not use headless CLI checks during normal development; headless execution is reserved only for initial bootstrap or offline CI. If MCP is disconnected, ask the user to open Godot.

---

## Standard Feature Creation Pipeline

For developing features cleanly without write conflicts, every feature progresses through three discrete, sequential stages:

```
[1. Discovery Agent] ──> [2. Design Agent (Plan for Review)] ──> [3. Implementation Agent & MCP Verify] ──> [Git Commit]
```

### Stage 1: Discovery (`feature_discovery`)
- **Game Profile**: Fast-paced 2.5D action roguelike / shooter / platformer (*Shape of Dreams*, *Windblown*, *Hades*).
- **Deliverables**: Research peer conventions, gameplay feel, juice/feedback cues, mechanical interactions, and common pitfalls.

### Stage 2: Design (`feature_designer`)
- **Deliverables**: Comprehensive technical plan for user review before implementation.
  - Component & Resource hierarchy breakdown.
  - Signal signatures and public API boundaries.
  - Edge case matrix (buffering, cancels, state interruption, disconnects).
  - Multiplayer synchronization plan (Authority, RPC vs Synchronizer, lag compensation).

### Stage 3: Implementation & Validation (`feature_implementer`)
- **Deliverables**:
  - Sequential code and scene implementation.
  - Validation via `godot-ai` MCP server (`editor_state`, `scene_get_hierarchy`, `test_run`, `logs_read`).
  - Self-contained, conflict-free commit readiness.

---

## Incremental Build Protocol
When tackling multiple features:
1. **Queue Sequentially**: Process one feature through Stages 1 -> 2 -> 3 completely before starting the next to avoid conflicting scene tree or resource modifications.
2. **Review Milestone**: Pause after Stage 2 to align on edge cases and multiplayer strategy with the team.
3. **Commit Cleanly**: Each implemented and MCP-verified feature forms a clean, atomic git commit.
