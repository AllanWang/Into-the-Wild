# Agent Setup Guide (`Into the Wild`)

This guide is written for **AI coding agents** provisioning **Into the Wild** on a fresh clone or a new workstation.

Because third-party editor tooling (`addons/godot_ai/`, i.e. [`hi-godot/godot-ai`](https://github.com/hi-godot/godot-ai)) is intentionally **`.gitignore`d**, a fresh clone does not include the `godot-ai` MCP plugin or Godot Project Manager registration (`projects.cfg`). Follow the steps below to install the addon, register the project with Godot 4.7+, connect your MCP client, and verify the workspace without committing local editor state.

---

## Prerequisites

- **Godot Engine 4.7+** (`config/features=PackedStringArray("4.7", "GL Compatibility")`; `godot_ai` requires Godot `>= 4.7`)
- **`uv` / `uvx`** (manages Python `>=3.11,<3.15` automatically for `godot-ai attach`)
- **Git** (repository root `project.godot` already includes `_mcp_game_helper` and `res://addons/godot_ai/plugin.cfg`; CI strips them automatically during Web exports)

---

## Fast Path (Windows PowerShell)

From the repository root, run the automated bootstrap script:

```powershell
powershell -ExecutionPolicy Bypass -File .agents/skills/setup-godot-ai-mcp/scripts/setup.ps1
```

Optional parameters:
- `-GodotBin "<path-to-godot-executable>"` — explicitly specify Godot 4.7+ instead of auto-discovering it
- `-Version "<x.y.z>"` — pin a specific `hi-godot/godot-ai` release tag instead of querying `releases/latest`
- `-SkipProjectLink` — skip adding this workspace to Godot's Project Manager (`projects.cfg`)

This script performs all steps below idempotently: locates Godot, downloads `addons/godot_ai/`, ensures `project.godot` entries exist, updates `mcp_config.json`, links the repo as a favorite in `projects.cfg`, and runs a one-time headless import check.

---

## Step-by-Step Cross-Platform Agent Procedure

Use these steps directly on macOS/Linux or when running setup manually without `setup.ps1`.

### 1. Locate Godot 4.7+ Executable (`GODOT_BIN`)

Check locations in order and verify `"$GODOT_BIN" --version` reports `4.7` or newer:

- **Environment / `PATH`**: `$env:GODOT_BIN` / `$GODOT_BIN`, `godot`, `godot4`
- **Windows (Steam)**: `C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe` (and any extra library roots in `C:\Program Files (x86)\Steam\steamapps\libraryfolders.vdf`)
- **Windows (Winget / Scoop)**: `%LOCALAPPDATA%\Microsoft\WinGet\Links\godot.exe`, `%USERPROFILE%\scoop\apps\godot\current\godot.exe`
- **macOS**: `/Applications/Godot.app/Contents/MacOS/Godot`, `~/Library/Application Support/Steam/steamapps/common/Godot Engine/...`
- **Linux**: `~/.steam/steam/steamapps/common/Godot Engine/...`, `/usr/bin/godot`, `/usr/local/bin/godot`

### 2. Install `addons/godot_ai` (`hi-godot/godot-ai`)

1. Query `https://api.github.com/repos/hi-godot/godot-ai/releases/latest` for `<VERSION>` and download the release asset `godot-ai-v4-plugin.zip`.
2. Extract `addons/godot_ai/` from the archive into `<repo>/addons/godot_ai/`.
3. Verify `<repo>/addons/godot_ai/plugin.cfg` exists and `git status --short` stays clean (`/addons/godot_ai/` is gitignored).
4. Verify `project.godot` contains both registrations (add them only if missing):
   ```ini
   [autoload]
   _mcp_game_helper="*res://addons/godot_ai/runtime/game_helper.gd"

   [editor_plugins]
   enabled=PackedStringArray("res://addons/godot_ai/plugin.cfg")
   ```

### 3. Link Project into Godot Project Manager (`projects.cfg`)

Godot stores its Project Manager list in `projects.cfg` in one of two modes:

1. **Self-Contained / Steam Mode**: If `_sc_`, `._sc_`, or `editor_data/` exists next to the Godot executable, Godot reads:
   - `<GodotBinaryDir>/editor_data/projects.cfg`
2. **Standard OS Config Mode**:
   - **Windows**: `%APPDATA%\Godot\projects.cfg`
   - **macOS**: `~/Library/Application Support/Godot/projects.cfg`
   - **Linux**: `${XDG_CONFIG_HOME:-~/.config}/godot/projects.cfg`

Normalize the repository's absolute path with **forward slashes** (no trailing slash) and append this section to the active `projects.cfg` if `[<normalized_repo_path>]` is not already present:

```ini
[C:/path/to/Into-the-Wild]

favorite=true
```

### 4. Configure Agent MCP Client (`mcp_config.json`)

Register the `godot-ai` MCP server in your agent harness config (for Antigravity: `~/.gemini/config/mcp_config.json` and/or `~/.gemini/antigravity/mcp_config.json`; for Cursor: `~/.cursor/mcp.json`; for Claude Code: `.mcp.json` or `~/.claude.json`):

```json
{
  "mcpServers": {
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
  }
}
```

> [!NOTE]
> Once the Godot Editor opens with the plugin active, the **Godot AI** dock's built-in `ClientConfigurator` keeps `mcp_config.json` synchronized automatically after in-editor plugin self-updates.

### 5. Run One-Time Headless Import & Sanity Check

Populate `.godot/` imported assets and verify clean script compilation before opening the editor:

```powershell
& "$GODOT_BIN" --headless --path "." --quit
```

Confirm exit code `0`.

### 6. Hand Off to User to Open Godot Editor

> [!IMPORTANT]
> **NEVER launch or restart the interactive Godot Editor GUI from an agent shell** (`godot --editor`, `godot -e`, etc.). Doing so causes stdout/stderr handle locks, Steam DRM hook conflicts, and hung background tasks.

Ask the user to launch **Into the Wild** from Godot's Project Manager (where it is now favorited), then verify the live WebSocket MCP bridge (default port `9500`) using `editor_state`.

---

## Standalone / CI Mode (Without `godot-ai`)

If an environment must import, run, or export the project **without** installing `addons/godot_ai/` (for example, Ubuntu CI in `.github/workflows/deploy-web.yml`), strip the two plugin references from `project.godot` locally before invoking Godot CLI:

```bash
sed -i '/^_mcp_game_helper=/d; /addons\/godot_ai\/plugin\.cfg/d' project.godot
```

Do not commit the stripped `project.godot` unless intentionally retiring `godot-ai` from the project.
