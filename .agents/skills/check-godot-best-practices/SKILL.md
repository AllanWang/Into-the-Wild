---
name: check-godot-best-practices
description: >-
  Review and validate Godot 4 GDScript code against documented best practices,
  performance gotchas, behavioural pitfalls, and debugging checklists.
  Trigger when the user asks to review code, audit a scene, check for
  common mistakes, or validate implementation quality. Also activate when
  '/check-godot-best-practices' is invoked.
---

# Godot Best-Practices Review (`/check-godot-best-practices`)

Use this skill to **review, audit, or validate** existing or newly written
Godot 4 code. The goal is to catch non-obvious gotchas that are easy to miss
during development — performance traps, behavioural foot-guns, and
hard-to-debug patterns — without cluttering the active conversation with the
full reference corpus.

> [!IMPORTANT]
> This skill is a **review / validation** pass. It should not be used as the
> primary implementation guide — use the `/game-feature` pipeline for feature
> creation. Activate this skill **after** code is written (or during a PR-style
> review) to catch issues.

---

## How to Run a Review

1. **Identify the scope** — file(s), scene(s), or system(s) to review.
2. **Read the full best-practices reference** for the categories that apply:
   - [Performance](./references/best-practices.md#1-performance)
   - [Behaviour & Patterns](./references/best-practices.md#2-behaviour--patterns)
   - [Debugging & Common Issues](./references/best-practices.md#3-debugging--common-issues)
   - [Architecture & Code Quality](./references/best-practices.md#4-architecture--code-quality)
   - [Engine & Workflow](./references/best-practices.md#5-engine--workflow)
3. **Audit the code** against each checklist item, producing a findings report.
4. **Report format** — produce an artifact with:
   - 🔴 **Critical** — will cause bugs, crashes, or severe perf regressions
   - 🟡 **Warning** — likely to cause issues under certain conditions
   - 🟢 **Suggestion** — improvement for maintainability or future-proofing
   - For each finding: cite the checklist rule, the offending code location
     (file + line), and a recommended fix.

---

## Quick Checklist (Top-Level)

Use this as a fast mental scan; consult the full reference when a check fails.

### Performance
- [ ] No `get_node()` / `find_child()` inside `_process` / `_physics_process`
- [ ] Node references cached in `_ready()` via `@onready`
- [ ] No memory allocation (Array/Dictionary creation) inside hot loops
- [ ] Off-screen entities disabled via `VisibleOnScreenNotifier2D` or manual culling
- [ ] Object pooling used for frequently spawned/freed objects (bullets, particles)
- [ ] `preload()` used sparingly; heavy resources use `load()` or `ResourceLoader.load_threaded`
- [ ] MultiMesh used for large numbers of identical visual instances
- [ ] No unnecessary physics bodies (Area2D/RigidBody) where raycasts or simple checks suffice

### Behaviour & Patterns
- [ ] `_physics_process` for physics; `_process` for visuals/UI
- [ ] `_unhandled_input` for gameplay; `_input` only for UI controls
- [ ] No `scale.x = -1` for sprite flipping (use `flip_h` / `flip_v`)
- [ ] Signals emit upward; method calls go downward — no `get_parent().get_parent()`
- [ ] No signal "bubbling" through intermediate layers
- [ ] `await` return values handled (function becomes a coroutine)
- [ ] `queue_free()` used (not `free()`); `call_deferred` when freeing during physics

### Debugging & Stability
- [ ] Orphan node count monitored (Debugger > Monitors)
- [ ] Custom classes don't accidentally `extend Node` when `RefCounted` suffices
- [ ] `remove_child()` always followed by `queue_free()` unless intentionally re-parenting
- [ ] `.godot` cache cleared after engine version changes

### Architecture
- [ ] Static typing on all vars, params, and return types
- [ ] Component composition over deep inheritance
- [ ] Data in `Resource`/`RefCounted`, not in extra scene nodes
- [ ] UI observes via signals; never drives simulation state directly

---

## Full Reference

For detailed explanations, code examples, "why it matters", and debugging
procedures, see:

📖 **[Best Practices Reference](./references/best-practices.md)**
