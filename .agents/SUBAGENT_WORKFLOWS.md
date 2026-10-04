# Subagent Workflows & Task Delegation Guidelines

To maintain code quality, separation of concerns, and clean context boundaries, complex Godot development tasks should be decomposed into incremental, specialized subagent roles.

## Why Subagent Decomposition?
- **Context Preservation**: Prevents token saturation and keeps hallucination low.
- **Entity & Domain Separation**: Game engines combine networking, physics, rendering, shaders, and UI. Blurring these together produces monolithic, fragile code.
- **Piece-by-Piece Verification**: Every subagent produces a discrete, verifiable chunk that can be tested with headless runs or scene checks before moving on.

---

## Standard Subagent Personas

### 1. `Architect & Interface Planner`
- **Focus**: Signal contracts, Data Resources (`Resource`), Public API signatures, scene hierarchy layout.
- **Inputs**: Feature requirements, existing autoloads (`NetworkManager`, `DebugTools`).
- **Outputs**: Interface specifications, typed method signatures, signal definitions, component breakdown.
- **Rules**: Does NOT write low-level game loops or physics algorithms; defines boundaries and contracts.

### 2. `Gameplay & Entity Specialist`
- **Focus**: `CharacterBody2D`, state machines, physics, component nodes (e.g., `HitboxComponent`, `HealthComponent`), player controls.
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

## Incremental Build Protocol
When tackling a feature request:
1. **Deconstruct**: Identify the 2–4 distinct layers (e.g. Data/Resource -> Component -> UI -> Network).
2. **Execute Sequentially**: Spawn or delegate to a subagent for layer 1. Validate.
3. **Integrate**: Delegate the next layer with the completed interface contract.
4. **Verify**: Run headless check or multi-window launch test.
