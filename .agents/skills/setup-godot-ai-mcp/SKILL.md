---
name: setup-godot-ai-mcp
description: >-
  Use this skill to set up, re-install, or update the hi-godot/godot-ai Model Context Protocol (MCP) plugin
  in a Godot 4 project, including plugin installation, editor enablement, client mcp_config.json setup,
  and headless verification.
---

# Setup Godot AI MCP Skill

This skill provides an automated workflow to bootstrap or update the [`hi-godot/godot-ai`](https://github.com/hi-godot/godot-ai) MCP plugin in any Godot 4 project.

## Why this is required
In Godot, editor plugins must physically exist inside the project's `res://addons/<plugin_name>/` directory (containing `plugin.cfg`) for the engine to load them. The `godot-ai` plugin creates an in-editor WebSocket bridge (port `9500`) that connects to a local Python MCP server (`godot-ai attach`), giving AI agents live inspection of scenes, nodes, properties, and runtime logs.

---

## One-Step Automated Setup

Run the included PowerShell script from the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File .agents/skills/setup-godot-ai-mcp/scripts/setup.ps1
```

To install a specific version:
```powershell
powershell -ExecutionPolicy Bypass -File .agents/skills/setup-godot-ai-mcp/scripts/setup.ps1 -Version "4.3.0"
```

---

## What the Workflow Performs

1. **GitHub Release Download**:
   - Queries the GitHub API for the latest `hi-godot/godot-ai` release.
   - Downloads `godot-ai-v4-plugin.zip` to `$env:TEMP` and unpacks it.
2. **Addon Directory Installation**:
   - Copies `addons/godot_ai` into the project root `addons/godot_ai`.
3. **Editor Plugin Enablement**:
   - Ensures `project.godot` contains:
     ```ini
     [editor_plugins]
     enabled=PackedStringArray("res://addons/godot_ai/plugin.cfg")
     ```
4. **Client MCP Configuration**:
   - Configures the MCP stdio attach command in `~/.gemini/config/mcp_config.json` (and `~/.gemini/antigravity/mcp_config.json`):
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
5. **Headless Verification**:
   - Executes `godot.exe --headless --path "." --quit` to confirm scripts compile with zero cyclic errors or missing references.

---

## Verification & Usage

1. Open the project in the Godot Editor.
2. Verify the **Godot AI** dock tab appears in the editor interface and shows connected/listening on port `9500`.
3. Start or query tools through the MCP client.
