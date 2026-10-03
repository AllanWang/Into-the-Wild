# 2D Stylized Pixel Art Grass Game

This project is a 2D stylized pixel-art grass system in Godot, featuring a player-controlled blue square moving around a 2D scene with WASD and Arrow keys, with grass blades displacing dynamically as the player walks over them.

This project was generated using the **AntiGravity** coding assistant.

## Credits & Attribution

The grass textures (`grassleaf.png` and `accentleaf.png`) are created by **Dylearn** and licensed under **Creative Commons Attribution 4.0 (CC BY 4.0)**.
- Grass assets by **Dylearn** (refer to the [Dylearn-3D-Pixel-Art-Grass-Demo repository](https://github.com/DylearnDev/Dylearn-3D-Pixel-Art-Grass-Demo)).

All source code (scripts, shaders, and tools) is licensed under the **MIT License**.

## Features

- Stylized 2D pixel-art grass (Sprite2D instances)
- Wind-animated grass sprites using a custom CanvasItem shader
- Player-reactive displacement via a global shader uniform
- Stepped height-based toon shading
- Smooth camera tracking and movement (WASD & Arrow Keys)
