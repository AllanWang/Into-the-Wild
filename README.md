# 3D Stylized Pixel Art Grass Multiplayer Game

A multiplayer Godot 4 game featuring a stylized 3D pixel-art grass meadow with locked 2.5D orthogonal perspective, multiplayer lobby, and RPC-based player synchronization.

---

## Tutorial & Attribution

The grass shader techniques and visual assets in this project are based on the tutorial:
- **YouTube Video**: [How I made grass better than 99% of games | Stylized grass 3D pixel art](https://youtu.be/OxsuWDtjuGw?si=g1qIPgq77vQv5eYT) by **Dylearn**
- **Demo Repository**: [DylearnDev/Dylearn-3D-Pixel-Art-Grass-Demo](https://github.com/DylearnDev/Dylearn-3D-Pixel-Art-Grass-Demo)

### Asset & Shader Credits

- **Textures & Sprites** (`grassleaf.png`, `accentleaf.png`): Created by **Dylearn**, licensed under **Creative Commons Attribution 4.0 International (CC BY 4.0)**.
- **Shaders & Algorithms** (`Grass.gdshader`, `Floor.gdshader`, `clouds.gdshaderinc`, `ToonShader.gdshader`): Created by **Dylearn** (adapted from atzuk4451's Flexible Toon Shader), licensed under the **MIT License**.
- **Procedural Noise Resources** (`WindNoise.tres`, `Cloud_Noise.tres`, `Albedo2Noise.tres`, `Albedo3Noise.tres`): Created by **Dylearn**, licensed under the **MIT License**.

All game networking, lobby, multi-instance debug tools, and 3D player integration code are licensed under the **MIT License**.

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
