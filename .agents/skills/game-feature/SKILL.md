---
name: game-feature
description: End-to-end sequential pipeline for creating new game features and gameplay mechanics (Discovery -> Technical Design Plan -> Implementation & MCP Validation). Trigger when developing new features, abilities, mechanics, or game systems.
---

# Game Feature Creation Pipeline (`/game-feature`)

Use this skill when designing and implementing **new features, combat abilities, gameplay mechanics, or complex systems** for this 2.5D fast-paced roguelike/platformer/shooter (inspired by *Shape of Dreams*, *Windblown*, *Hades*).

> [!NOTE]
> **When NOT to use this full flow**:
> Minor tweaks, quick bugfixes, simple UI text/color edits (e.g. "change the lobby title", "change the font color"), or straightforward configuration changes should bypass the full 3-stage discovery flow. For those, proceed directly with best-practice implementation and MCP verification.

---

## Game Profile & Identity
- **Genre**: 2.5D Action Roguelike / Platformer / Shooter.
- **Reference Titles**:
  - *Shape of Dreams*: Dynamic build crafting, responsive ability combinations, reactive cooldowns, projectile pacing.
  - *Windblown*: Snappy movement, crisp dashing/dash-attacking, animation cancels, readable telegraphs, co-op synchronization.
  - *Hades*: Tight combat feedback, punchy hitstop, visual clarity under dense effects, boon/enhancement synergies.
- **Engine**: Godot 4.x (Static typing, Component composition, ENet multiplayer networking).

---

## 3-Stage Sequential Execution Pipeline

Always execute features **sequentially** (one feature through all 3 stages before starting another) to avoid file write conflicts, scene tree race conditions, and dirty git states.

```
[1. Discovery] ──> [2. Design (Plan for Review)] ──> [User Review] ──> [3. Implementation & MCP Validation] ──> [Git Commit]
```

### Stage 1: Discovery (`feature_discovery`)
1. **Peer Game Research**:
   - How do peer games (*Windblown*, *Hades*, *Shape of Dreams*, *Dead Cells*) implement this mechanic?
   - What pacing, input buffers, visual cues, and audio juice make it feel responsive and punchy?
2. **Pitfall Identification**:
   - What anti-patterns should be avoided (e.g. animation locks without cancel windows, unresponsive buffer queues, screen clutter)?
3. **Mechanical Interactions**:
   - How does this feature interact with existing movement (velocity, dashing, deceleration) and multiplayer latency?

### Stage 2: Technical Design & Architecture (`feature_designer`)
Before touching code or scene files, create a plan and present it for review:
1. **Component & Resource Architecture**:
   - Strict "Signal Down, Call Down, Never Crawl Up" structure.
   - Component nodes (e.g. `HitboxComponent`, `HealthComponent`) vs Data Resources (`Resource`).
   - Signal signatures (past tense) and public API definitions.
2. **Multiplayer Handling**:
   - Authority model: Client Authority vs Server Authority (`is_multiplayer_authority()`).
   - Sync method: `MultiplayerSynchronizer` for continuous transforms vs `@rpc` for discrete events.
   - Peer path parity (`$Players/{peer_id}`) and disconnect/reconnect handling.
3. **Edge Case Analysis**:
   - What happens if the player stuns/dashes mid-action?
   - Input buffering during cooldowns or animation locks.
   - What happens if the host or a client disconnects mid-cast or mid-state?
4. **Implementation & Review Checklist**:
   - Provide the complete blueprint for user review and approval before proceeding.

### Stage 3: Implementation & In-Editor MCP Validation (`feature_implementer`)
Once the plan is approved:
1. **Layer-by-Layer Implementation**:
   - Layer 1: Data Resources and Signal contracts.
   - Layer 2: Core Components and entity scripts.
   - Layer 3: Multiplayer replication and RPC hooks.
   - Layer 4: UI observation and visual feedback.
2. **Validation via `godot-ai` MCP Server**:
   - Check editor status: `editor_state`.
   - Inspect modified scenes: `scene_get_hierarchy`.
   - Run tests: `test_run`.
   - Check engine and script logs: `logs_read` (ensure zero warnings or errors).
   - *Note: If the MCP server is not connected, prompt the user to open Godot.*
3. **Commit Readiness**:
   - Confirm all touched files are clean, atomic, and ready for git commit.
