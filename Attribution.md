# Attributions & Third-Party Credits

This project incorporates and builds upon techniques, shaders, tutorials, and assets created by the open-source and game development community.

---

## 1. Stylized 3D Pixel Art Grass & Environment System

The stylized grass rendering pipeline, hybrid toon shading, quantized animation, and dynamic cloud shadows are based on the work of **Dylearn**:

- **Tutorial Video**: [How I made grass better than 99% of games | Stylized grass 3D pixel art](https://youtu.be/OxsuWDtjuGw?si=g1qIPgq77vQv5eYT) by **Dylearn**
- **Original Demo Repository**: [DylearnDev/Dylearn-3D-Pixel-Art-Grass-Demo](https://github.com/DylearnDev/Dylearn-3D-Pixel-Art-Grass-Demo)

### Assets & Shaders:
- **Textures & Sprites** (`assets/grassleaf.png`, `assets/accentleaf.png`):
  - Created by **Dylearn**.
  - Licensed under [Creative Commons Attribution 4.0 International (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/).
- **Shaders & Algorithms** (`shaders/Grass.gdshader`, `shaders/Floor.gdshader`, `shaders/clouds.gdshaderinc`, `shaders/ToonShader.gdshader`):
  - Created by **Dylearn** (adapted from [atzuk4451's Flexible Toon Shader](https://godotshaders.com/shader/flexible-toon-shader-godot-4/)).
  - Licensed under the [MIT License](https://opensource.org/licenses/MIT).
- **Procedural Noise Resources** (`assets/WindNoise.tres`, `assets/Cloud_Noise.tres`, `assets/Albedo2Noise.tres`, `assets/Albedo3Noise.tres`):
  - Created by **Dylearn**.
  - Licensed under the [MIT License](https://opensource.org/licenses/MIT).

---

## 2. Stylized Toon Water & Foam Shader

The stylized water shader architecture, depth gradient transitions, and edge foam logic are inspired by:

- **Reference / Inspiration**: [ToonWaterShader](https://github.com/IronWarrior/ToonWaterShader) by **Erik Roystan Ross (IronWarrior)**
- **Technical Writeup**: [Toon Water Shader Tutorial](https://roystan.net/articles/toon-water/) by **Erik Roystan Ross**
- **Adapted Implementation** (`shaders/ToonWater.gdshader`, `assets/water_noise.tres`, `assets/water_pond_material.tres`):
  - Adapted for Godot 4 spatial shaders with orthographic camera support, stepped toon light integration, Voronoi foam scrolling, and dynamic multi-agent ripple interactions.
  - Licensed under the [MIT License](https://opensource.org/licenses/MIT).

---

## 3. Base Toon Shading

- **Flexible Toon Shader for Godot 4**:
  - Author: **atzuk4451** ([GodotShaders.com profile](https://godotshaders.com/shader/flexible-toon-shader-godot-4/))
  - Used as the foundation for the discrete lighting band calculations across scene shaders.
  - Licensed under the [MIT License](https://opensource.org/licenses/MIT).

---

## 4. Multi-Instance Debug & Grid Layout Automation

- **Port-probed Grid Layout**:
  - Architecture inspired by [Godot Engine Proposal #10262](https://github.com/godotengine/godot-proposals/issues/10262#issuecomment-2756914788) for automated multi-window debugging without editor UI friction.
  - Implemented in `debug_tools.gd` under the [MIT License](https://opensource.org/licenses/MIT).

---

## 5. Project Code & Multiplayer Integration

All game networking, RPC player synchronization, character interaction managers, and lobby UI code written for this project are licensed under the [MIT License](https://opensource.org/licenses/MIT).
