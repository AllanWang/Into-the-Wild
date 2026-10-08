# Godot 4 Best Practices Reference

> Comprehensive reference for reviewing and validating Godot 4 GDScript code.
> Each section contains **the rule**, **why it matters**, **what can go wrong**,
> and **the correct approach** with code examples where applicable.
>
> **Sources**: [10 Things I Wish I Knew Before Starting a Large Godot Project](https://youtu.be/zLdTvkLsmgA),
> Godot official docs, community-vetted patterns.

---

## 1. Performance

### 1.1 Cache Node References — Never `get_node()` in Hot Loops

**Rule**: All node references used in `_process` or `_physics_process` must be
cached in `_ready()` using `@onready`.

**Why**: `get_node()` and `find_child()` perform a tree traversal every call.
Inside `_process` (running 60+ times/sec), this adds up fast.

```gdscript
# ❌ BAD — tree lookup every frame
func _process(delta: float) -> void:
    var label: Label = get_node("HUD/ScoreLabel")
    label.text = str(score)

# ✅ GOOD — cached once at ready
@onready var _score_label: Label = %ScoreLabel

func _process(delta: float) -> void:
    _score_label.text = str(score)
```

### 1.2 Avoid Memory Allocation in Hot Loops

**Rule**: Do not create new Arrays, Dictionaries, or Objects inside
`_process` / `_physics_process`.

**Why**: Every allocation triggers garbage collection pressure. Over thousands
of frames, this causes micro-stutters.

```gdscript
# ❌ BAD — new array allocated every physics frame
func _physics_process(delta: float) -> void:
    var nearby: Array[Node2D] = get_tree().get_nodes_in_group("enemies")
    for enemy in nearby:
        _check_distance(enemy)

# ✅ GOOD — reuse a cached list, or use signals/groups sparingly
var _cached_enemies: Array[Node2D] = []

func _on_enemies_changed() -> void:
    _cached_enemies = get_tree().get_nodes_in_group("enemies")
```

### 1.3 Disable Off-Screen Entities

**Rule**: Entities that are off-screen should have processing disabled.

**Why**: Enemies placed directly in a level will walk, collide, and execute AI
even when the player is three screens away. This wastes CPU on invisible work
and can cause enemies to wander away from their intended positions before the
player arrives.

**Approach** (from video — timestamp 07:12):
- **Simple**: Add `VisibleOnScreenEnabler2D` as a child. It automatically
  disables processing when the parent is offscreen. No code required.
- **Custom**: Use `VisibleOnScreenNotifier2D` and connect its
  `screen_entered` / `screen_exited` signals for fine-grained control
  (e.g., custom spawner logic, respawn conditions).

> [!TIP]
> In Godot 4.5+, use the **"Show Rect"** option on the notifier to hide the
> debug rectangle in the editor while keeping the logic active.

**Advanced — Custom Spawners**: For large projects, consider building a spawner
node that controls *when* enemies spawn, *where* they appear, and under what
conditions they respawn (e.g., only respawn if killed and spawner re-enters
screen, or continuously respawn at random intervals while visible).

### 1.4 Preload vs Load — Ownership and Memory Leaks

**Rule**: Only `preload()` small, reusable resources that are tightly coupled
to the script's lifetime. Never preload large scene chains from persistent
nodes.

**Why** (from video — timestamp 05:34): `preload()` behaves like a global
static reference that increments a ref count. If a scene is preloaded by a node
that **never leaves the scene tree** (like a main game manager), the entire
chain of assets stays alive in memory — even when those scenes are no longer
in the tree.

```gdscript
# ❌ BAD — main_game.gd (persistent autoload) preloads a chain
const MAIN_MENU: PackedScene = preload("res://scenes/main_menu.tscn")
# main_menu.gd preloads opening_cutscene.tscn
# opening_cutscene.gd preloads level_one.tscn
# → ALL stay in memory forever because main_game never leaves the tree

# ✅ GOOD — preload only small, always-needed resources close to usage
# player.gd (exists only while gameplay is active)
const PROJECTILE: PackedScene = preload("res://entities/projectile.tscn")
# → When the player is freed, the reference disappears too

# ✅ GOOD — for large/infrequent scenes, load at runtime
func _go_to_level(path: String) -> void:
    var scene: PackedScene = load(path)  # or ResourceLoader.load_threaded_request
    get_tree().change_scene_to_packed(scene)
```

**Key principle**: What matters isn't *"is the scene still in the tree?"* — it's
*"does anything still reference the resource?"*

### 1.5 Object Pooling for Frequent Spawn/Free Cycles

**Rule**: For objects that are rapidly created and destroyed (bullets,
particles, hit effects), use an object pool instead of repeated
`instantiate()` / `queue_free()`.

**Why**: Instantiation + tree insertion is expensive. `queue_free` defers
deletion to end-of-frame but still has overhead. Pools reuse existing nodes
by toggling visibility and resetting state.

### 1.6 Use MultiMesh for Mass Visual Instances

**Rule**: If you need hundreds+ of identical visual objects (grass, debris,
decorations), use `MultiMeshInstance2D` / `MultiMeshInstance3D`.

**Why**: Each individual `Sprite2D` or `MeshInstance3D` is a separate draw
call. MultiMesh batches them into one.

### 1.7 Right-Size Your Physics

**Rule**: Don't use `Area2D` / `RigidBody` for things that don't need full
physics simulation. Use simplified collision shapes, raycasts, or direct
distance checks where possible.

**Why**: The physics server scales with the number of active bodies and shapes.
For extreme scenarios (thousands of units), bypass nodes entirely and use
`PhysicsServer2D` / `PhysicsServer3D` or `RenderingServer` APIs directly.

### 1.8 Limit Editor FPS

**Rule**: Limit FPS during development to prevent the engine from rendering at
uncapped frame rates.

**Why** (from video — timestamp 14:49): Running the debug editor without an
FPS cap can cause your GPU to render at hundreds or thousands of FPS, generating
excessive heat and fan noise. Set a reasonable cap (60–144) in Project Settings
or via `Engine.max_fps`.

---

## 2. Behaviour & Patterns

### 2.1 `_process` vs `_physics_process`

| Use `_physics_process(delta)` for: | Use `_process(delta)` for: |
|-------------------------------------|----------------------------|
| `CharacterBody2D/3D` movement | UI updates |
| Collision detection & response | Procedural animations |
| `RigidBody` property changes | Camera smoothing |
| Anything that must be deterministic | Visual effects / particles |

**Why**: `_physics_process` runs at a fixed rate (default 60 Hz) for stable
simulation. `_process` runs as fast as the hardware allows (variable rate).
Mixing them up causes jittery physics or inconsistent visual updates.

### 2.2 Input Handling — `_unhandled_input` vs `_input`

**Rule**: Use `_unhandled_input(event)` for **gameplay** mechanics. Use
`_input(event)` or `_gui_input(event)` only for **UI** controls.

**Why**: `_unhandled_input` fires only after Control/UI nodes have had a chance
to consume the event. This prevents the player from shooting while clicking a
menu button.

For movement (continuous polling), use `Input.is_action_pressed()` inside
`_physics_process`. For discrete actions (jump, interact), use
`event.is_action_pressed("action")` inside `_unhandled_input`.

### 2.3 NEVER Flip by Negatively Scaling Nodes

**Rule**: Never use `scale.x = -1` to flip an entity's facing direction.

**Why** (from video — timestamp 03:57 — **this killed the author's entire
project**): Negative scaling on a parent node propagates to **every child**,
including Area2Ds, CollisionShapes, RayCasts, and Marker2Ds. The critical
trap is that **visible collision shapes look correct**, but the actual physics
interactions happen at the *wrong location*. This creates bugs that are nearly
impossible to diagnose: hits that miss, raycasts that lie, collision normals
that flip.

```gdscript
# ❌ BAD — breaks physics on all children
func _flip_direction() -> void:
    scale.x *= -1  # NEVER DO THIS

# ✅ GOOD — separate visual flip from physics truth
func _flip_direction(facing_right: bool) -> void:
    sprite.flip_h = !facing_right
    # Explicitly reposition physics children
    projectile_spawn.position.x = abs(projectile_spawn.position.x) * (1 if facing_right else -1)
    ledge_detector.position.x = abs(ledge_detector.position.x) * (1 if facing_right else -1)
```

**Principle**: *"Never let visual convenience dictate physics truth."*

### 2.4 Sprite2D: Offset vs Position

**Rule**: Use `offset` for animation art alignment. Use `position` for actual
game-world movement.

**Why** (from video — timestamp 01:19): `position` is inherited by the
Sprite2D's children (markers, collision shapes, etc.). `offset` only moves the
texture rendering. If you animate `position` to bob a sprite during a walk
cycle, attached spawn points and collision shapes will move with it — breaking
gameplay alignment.

| Property | Affects children? | Use for |
|----------|-------------------|---------|
| `position` | ✅ Yes | Real movement (game truth) |
| `offset` | ❌ No | Art alignment (animation fiction) |

### 2.5 Signal Patterns

**Rules**:
1. **Signals emit upward** — children signal parents/managers.
2. **Method calls go downward** — parents call methods on children.
3. **Never crawl up** — no `get_parent().get_parent().do_thing()`.
4. **No signal bubbling** — don't re-emit the same signal through intermediate layers.
5. **Use a Signal Bus (Autoload)** for truly global events (`game_over`, `level_changed`) to avoid threading references through deep trees.
6. **Prefer code connections** (`emitter.signal_name.connect(handler)`) over
   editor connections for refactoring visibility.

### 2.6 `await` and Coroutine Awareness

**Rule**: Any function that contains `await` becomes a coroutine. The caller
must also `await` it if it depends on the result.

**Gotchas**:
- Code after `await` executes in a **future frame**. The node might have been
  freed by then. Always guard with `if is_instance_valid(self)` after awaiting
  external signals.
- A common bug: calling an `await`-containing function without `await` at the
  call site — the caller continues immediately, ignoring the delay.

```gdscript
# ❌ BAD — code continues immediately, animation may not finish
func attack() -> void:
    play_attack_animation()  # contains await internally
    deal_damage()            # runs BEFORE animation finishes!

# ✅ GOOD
func attack() -> void:
    await play_attack_animation()
    if not is_instance_valid(self):
        return
    deal_damage()
```

### 2.7 `queue_free()` vs `free()` and `call_deferred`

**Rule**: Always use `queue_free()` rather than `free()`. When freeing during
physics callbacks or signal handlers, use `call_deferred("queue_free")`.

**Why**: `free()` immediately destroys the node while other systems may still
hold references to it. `queue_free()` waits until end-of-frame.
`call_deferred` adds an extra layer of safety when you're inside a physics
step or iterating over the tree.

---

## 3. Debugging & Common Issues

### 3.1 Build a Debug God Mode Early

**Rule** (from video — timestamp 02:34): Create a debug-only player state with:
- Fast movement (2x+ speed)
- No gravity / free flight
- Hurtbox disabled (invincible)
- Toggle via a debug key (e.g., F1)

**Why**: Without this, testing anything mid-level requires playing through
hazards, enemies, and platforming sections every time. The author spent
*months* without one, then built it in under 20 minutes.

**Bonus**: Debug tools can spark gameplay ideas. The author's "sprint" stress
test accidentally became a fun mechanic.

### 3.2 Time Scale for Debugging

**Rule** (from video — timestamp 14:09): Use `Engine.time_scale` to slow down
or speed up the entire game for debugging timing-sensitive interactions.

```gdscript
# Slow motion (25% speed) for debugging combat timing
Engine.time_scale = 0.25

# Fast forward (4x speed) for testing long sequences
Engine.time_scale = 4.0

# Normal
Engine.time_scale = 1.0
```

### 3.3 Orphan Node Detection

**Rule**: Monitor orphan nodes regularly during development.

**How**:
1. **Debugger → Monitors → Objects → Orphan Nodes**: Watch the count in
   real-time while the game runs.
2. **`print_orphan_nodes()`**: Call this at scene transitions to print leaked
   node types and IDs to the console.
3. **Remote tab**: Use the Scene dock's **Remote** tab during play to see the
   live hierarchy. Nodes lingering after they should have been destroyed =
   memory leak.

**Common causes of orphans**:
- Custom classes that `extends Node` when they should `extends RefCounted` or
  `extends Resource` — every `MyClass.new()` creates a node that must be freed.
- Using `remove_child()` without a follow-up `queue_free()` (remove ≠ delete).

### 3.4 `.godot` Cache Issues

**Rule** (from video — timestamp implicit): If you encounter weird,
unexplainable errors after updating Godot versions, **delete the `.godot/`
folder** in your project root and reopen the project.

**Why**: This folder contains cached imports, shader compilations, and editor
state. Stale cache from a previous engine version can cause phantom errors.
Note: this resets some editor settings (layouts, favorites, etc.).

### 3.5 Mouse Cursor Visibility

**Rule** (from video — timestamp 14:14): Explicitly control hardware mouse
cursor visibility. In gameplay, hide it; in menus, show it.

```gdscript
# Hide cursor during gameplay
Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
# or MOUSE_MODE_CAPTURED for FPS-style

# Show cursor for menus
Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
```

### 3.6 Alt + Right-Click for Precise Selection

**Tip** (from video — timestamp 14:20): In the editor (while in Select mode),
**Alt + Right-Click** lets you pick exactly which overlapping object to select
from a dropdown list.

### 3.7 Blurry Fonts — Enable MSDF

**Tip** (from video — timestamp 14:28): If fonts look blurry, especially at
non-native resolutions, enable **MSDF (Multi-Channel Signed Distance Field)**
rendering on the font resource or globally under Project Settings → GUI →
Theme → Font.

### 3.8 Using the Built-In Profiler

**Rule**: Never guess where a performance bottleneck is. Use the built-in
**Debugger → Profiler** to see which functions/nodes consume the most frame
time.

**Additional tools**:
- `OS.get_static_memory_usage()` for tracking memory over time.
- Performance monitors in the Debugger for draw calls, physics bodies, etc.

---

## 4. Architecture & Code Quality

### 4.1 Static Typing Everywhere

**Rule** (from video — timestamp 11:13): Use explicit types on **all**
variables, function parameters, and return types.

**Benefits**:
- Better editor autocompletion and Ctrl+Click navigation.
- Compile-time error detection instead of runtime crashes.
- Minor performance improvement (engine doesn't guess types at runtime).

**Enforcement**: Project Settings → General → Debug → GDScript → Untyped
Declaration → set to **Warn** (or Error for strict enforcement).

```gdscript
# ❌ BAD
var speed = 200
func move(direction, delta):
    return direction * speed * delta

# ✅ GOOD
var speed: float = 200.0
func move(direction: Vector2, delta: float) -> Vector2:
    return direction * speed * delta
```

### 4.2 Component Composition over Deep Inheritance

**Rule**: Prefer attaching modular component nodes (`HealthComponent`,
`HitboxComponent`, `MovementComponent`) over building deep class hierarchies.

**Why**: Godot's node system is designed for composition. Deep inheritance
creates rigid coupling; composition lets you mix and match behaviors freely.

### 4.3 Data in Resources, Not Extra Nodes

**Rule**: Use `Resource` or `RefCounted` subclasses for pure data (stats,
configs, inventories). Don't create Node subclasses just to hold data.

**Why**: Nodes have overhead: they're in the scene tree, receive process
callbacks, and carry transform data. Resources are lightweight data containers
with serialization support and no tree overhead.

### 4.4 UI ↔ Gameplay Separation

**Rule**: UI observes game state via signals and reads from exposed
properties. UI should **never** drive core simulation state directly.

**Why**: Coupling UI to gameplay makes both harder to test and refactor. If
the HUD directly modifies player health instead of observing it, you can't
change one without breaking the other.

---

## 5. Engine & Workflow

### 5.1 Resolution and Scaling Strategy

**Rule** (from video — timestamp 09:10): Decide on base resolution and scaling
**before** committing to a large project.

**Recommended starting points for pixel art**:
| Base Resolution | ×2 | ×3 | ×4 | ×6 |
|-----------------|------|-------|-------|------|
| 320 × 180 | 640×360 | 960×540 | 1280×720 | 1920×1080 |
| 640 × 360 | 1280×720 | 1920×1080 | 2560×1440 | 3840×2160 |

**Settings** (Project Settings → Display → Window):
- `Viewport Width` / `Viewport Height` → your base resolution
- `Window Width Override` / `Window Height Override` → comfortable launch size (e.g., 1920×1080)
- `Stretch → Mode` → `canvas_items` or `viewport`
- `Stretch → Aspect` → `keep`
- Enable **Integer Scaling** for clean pixel multiples (disable for non-pixel-art)

### 5.2 Version Control

**Rule** (from video — timestamp 12:43): Use Git from day one. Commit every
time a feature works.

**Key workflow**: The moment something works → commit. Then refactor freely,
knowing you can always diff against or revert to the last good state.

### 5.3 Editor Organization

**Tips** (from video — timestamp 14:38):
- **Favorite scenes**: Right-click scenes in the FileSystem dock → "Set as Favorite" for quick access.
- **Color-code folders/files**: Right-click → "Set Color" to visually organize large projects.
- **Customize layout**: Rearrange docks to suit your workflow (e.g., full-height FileSystem, Scene + Inspector side-by-side).

---

## 6. Review Checklist Summary

Use this condensed checklist during code reviews. Each item references the
detailed section above.

### 🔴 Critical (Will cause bugs or severe issues)
- [ ] No negative `scale.x` / `scale.y` flipping on nodes with physics children → §2.3
- [ ] No `get_node()` / `find_child()` inside `_process` / `_physics_process` → §1.1
- [ ] `queue_free()` used (not `free()`); `call_deferred` when inside physics → §2.7
- [ ] Orphan-producing classes use `RefCounted` not `Node` → §3.3
- [ ] `remove_child()` followed by `queue_free()` unless intentional re-parent → §3.3
- [ ] `await` properly chained; node validity checked after await → §2.6

### 🟡 Warning (Likely to cause issues at scale)
- [ ] No memory allocation inside hot loops → §1.2
- [ ] Off-screen entities disabled → §1.3
- [ ] Preload chains don't leak memory from persistent nodes → §1.4
- [ ] `_physics_process` for physics, `_process` for visuals → §2.1
- [ ] `_unhandled_input` for gameplay, not `_input` → §2.2
- [ ] Sprite animation uses `offset`, not `position` (when children must stay fixed) → §2.4
- [ ] Signals emit up, calls go down, no tree crawling → §2.5

### 🟢 Suggestion (Quality & maintainability)
- [ ] Static typing on all declarations → §4.1
- [ ] Component composition over deep inheritance → §4.2
- [ ] Data in Resources, not extra Nodes → §4.3
- [ ] UI observes via signals, never drives state → §4.4
- [ ] Debug god mode exists for testing → §3.1
- [ ] Base resolution decided and documented → §5.1
- [ ] Git used with meaningful commits → §5.2
