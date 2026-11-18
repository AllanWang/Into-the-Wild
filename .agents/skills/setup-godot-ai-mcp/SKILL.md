---
name: setup-godot-ai-mcp
description: >-
  Use this skill to set up, re-install, or update the hi-godot/godot-ai Model Context Protocol (MCP) plugin
  in a Godot 4 project, including plugin installation, editor enablement, client mcp_config.json setup,
  and headless verification.
---

# Setup Godot AI MCP Skill

This skill provides an automated workflow to bootstrap or update the [`hi-godot/godot-ai`](https://github.com/hi-godot/godot-ai) MCP plugin in any Godot 4.7+ project. See [`.agents/SETUP.md`](../../../SETUP.md) for full cross-platform agent instructions (macOS/Linux, Godot linking, and CI standalone stripping).

## Why this is required
In Godot, editor plugins must physically exist inside the project's `res://addons/<plugin_name>/` directory (containing `plugin.cfg`) for the engine to load them. Because `addons/godot_ai/` is `.gitignore`d in this repository, every fresh clone or workstation must install it locally. The `godot-ai` plugin creates an in-editor WebSocket bridge (port `9500`) that connects to a local Python MCP server (`godot-ai attach`), giving AI agents live inspection of scenes, nodes, properties, and runtime logs.

---

## One-Step Automated Setup

Run the included PowerShell script from the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File .agents/skills/setup-godot-ai-mcp/scripts/setup.ps1
```

Optional parameters:
```powershell
powershell -ExecutionPolicy Bypass -File .agents/skills/setup-godot-ai-mcp/scripts/setup.ps1 -Version "4.4.2" -GodotBin "C:\Path\To\godot.exe"
```

---

## What the Workflow Performs

1. **GitHub Release Download**:
   - Queries the GitHub API for the latest `hi-godot/godot-ai` release.
   - Downloads `godot-ai-v4-plugin.zip` to `$env:TEMP` and unpacks it.
2. **Addon Directory Installation**:
   - Copies `addons/godot_ai` into the project root `addons/godot_ai`.
3. **Editor Plugin & Autoload Enablement**:
   - Ensures `project.godot` contains `[editor_plugins]` (`res://addons/godot_ai/plugin.cfg`) and `[autoload]` (`_mcp_game_helper="*res://addons/godot_ai/runtime/game_helper.gd"`).
4. **Client MCP Configuration**:
   - Configures the MCP stdio attach command in `~/.gemini/config/mcp_config.json` (and `~/.gemini/antigravity/mcp_config.json`, creating `~/.gemini/config/mcp_config.json` on fresh machines if missing):
     ```json
     "godot-ai": {
       "command": "uvx",
       "args": [
         "--from",
         "godot-ai==<VERSION>",
         "godot-ai",
         "attach",
         "--port",
         "8000",
         "--ws-port",
         "9500"
       ],
       "disabled": false
     }
     ```
5. **Godot Binary Discovery & Project Manager Linking (`projects.cfg`)**:
   - Resolves Godot 4.7+ from `-GodotBin`, `$env:GODOT_BIN`, `PATH`, Steam (`libraryfolders.vdf`), Winget, or Scoop.
   - Registers the normalized repository path with `favorite=true` in Godot's `projects.cfg` (`<GodotDir>\editor_data\projects.cfg` for Steam/self-contained installs and/or `%APPDATA%\Godot\projects.cfg`).
6. **Headless Verification (Initial Setup / CI Only)**:
   - Executes `godot.exe --headless --path "." --quit` solely as a one-time sanity check during initial bootstrap or in headless CI pipelines to confirm imports and script compilation succeed.

---

## Verification & Usage
 
 1. Have the user open the project in the Godot Editor (agents must **never** launch the interactive editor directly).
 2. Verify the **Godot AI** dock tab appears in the editor interface and shows connected/listening on port `9500`.
 3. Query, modify, and verify the project prioritizing the MCP server tools (`godot-ai`).
 
 ## Operational Rules for AI Agents
 - **Prioritize MCP Tools**: When inspecting, modifying, or testing the Godot project, always prioritize using MCP tools. Headless execution is restricted to initial setup scripts or CI pipelines.
 - **Prompt User If Disconnected**: If the MCP server is not connected or the editor is closed, **ask the user to open the project in the Godot editor** instead of falling back to headless execution.
 - **Do Not Launch Godot**: Never run commands to launch or restart the Godot editor GUI from the agent shell.
 - **Restarts**: Hot-reloading handles most changes. If an editor restart is genuinely required, prompt the user.
