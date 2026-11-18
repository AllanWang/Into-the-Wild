# Into the Wild

## Overview

A stylized 2.5D isometric action roguelike built in **Godot 4.7** featuring 5 painterly biomes (*Verdant Meadow*, *Glacial Frostfield*, *Astral Constellation*, *Volcanic Caldera*, and *Arcane Anomaly*), procedural arena & bridge webs, dual-weapon + slottable shard + ability/artifact combat, *Hades*-inspired armored elites and multi-phase bosses, zero-header WebAssembly solo play, and desktop co-op multiplayer via `ENetMultiplayerPeer`.

- **Live Web Game (Solo):** https://allanwang.github.io/Into-the-Wild/
- **GitHub Repository:** https://github.com/AllanWang/Into-the-Wild
- **Third-Party Attributions:** [Attribution.md](Attribution.md) | **License:** [MIT](LICENSE)

---

## Attributions & Credits

This project builds on open-source shaders, tutorials, and assets from the Godot community:
- **Stylized Grass & Environment**: Based on tutorial and demo by [Dylearn](https://youtu.be/OxsuWDtjuGw?si=g1qIPgq77vQv5eYT).
- **Stylized Toon Water**: Inspired by [IronWarrior (Erik Roystan Ross)](https://github.com/IronWarrior/ToonWaterShader).
- **Toon Shading Foundation**: Adapted from [atzuk4451's Flexible Toon Shader](https://godotshaders.com/shader/flexible-toon-shader-godot-4/).

See [**`Attribution.md`**](Attribution.md) for full licensing information, author credits, and original project links.

---

## Features

- **Massive Stylized Grass Meadow**: Over 40,000 billboarded grass blades rendered via `MultiMeshInstance3D` in a single GPU draw call.
- **Multiplayer Character Displacement**: Grass automatically bends and parts around all connected players walking through the field.
- **3D Pixel-Art Look in Locked 2.5D**:
  - Orthogonal `Camera3D` locked to an isometric 2.5D viewing angle.
  - SubViewport pixel-art downscaling (`stretch_shrink = 2`) with nearest-neighbor texture filtering.
  - Stepped, quantized animation framerate (5 FPS) for retro animated character and grass flair.
- **Dynamic Wind & Atmosphere**:
  - Dual-layer noise-driven wind swaying with fake perspective UV scaling.
  - Cloud shadows dynamically drifting across the terrain and grass.
  - Stepped hybrid toon lighting with color heterogeneity across patches.
- **Multiplayer Lobby & Networking**:
  - Pre-game lobby supporting Quick Host / Quick Join via `ENetMultiplayerPeer`.
  - Automatic 2-Player Quick Join when launching in 2-window mode (pass `--no-auto-join`, `--no-autostart`, or `--manual` to disable).
  - RPC-based position synchronization with smooth client-side interpolation.
  - 3D box player model with omnidirectional `CapsuleShape3D` collision (radius `0.25`, height `0.6`), customizable peer colors, and billboarded nametags.
  - Multi-instance debug window auto-tiling: side-by-side on landscape screens, and top-to-bottom (top-center aligned with slight top padding) on portrait screens.
