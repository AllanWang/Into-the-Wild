# Multi-Instance Testing, Headless Verification & Launch References

This reference details the project's testing setup, headless script verification, and multi-instance debugging architecture.

## 1. Local Godot Executable Paths
The verified Godot 4 executable on this machine is:
- **Steam Default**: `C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`
- Environment variable override: `$env:GODOT_BIN`

## 2. Headless Verification & Static Check
Before committing GDScript or scene modifications, run a headless syntax and scene load check:
```powershell
& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path "." --quit
```
If there are parse errors, cyclic dependencies, missing scripts, or invalid scene UIDs, Godot outputs errors directly to standard error/output and returns non-zero.

To run a specific test script headlessly:
```powershell
& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path "." -s "res://test_script.gd" --quit
```

> [!NOTE]
> **Why Headless Works via Antigravity**:
> Headless mode (`--headless --quit`) runs purely as a command-line parser and validator without initializing the Windows display server, DirectX/Vulkan swapchain, or Steam overlay hooks. It terminates synchronously in ~2 seconds and works reliably from Antigravity. Only **interactive GUI modes** (`--editor` or interactive game windows) fail when launched from Antigravity subshells.

## 3. Multi-Instance Testing Workflow
The project includes automated scripts for multi-instance multiplayer testing:
- **PowerShell**: [`launch_multiplayer_test.ps1`](file:///c:/Users/user7/PA/Godot-AI/launch_multiplayer_test.ps1)
- **Batch**: [`launch_multiplayer_test.bat`](file:///c:/Users/user7/PA/Godot-AI/launch_multiplayer_test.bat)

### Dynamic Window Placement System (`debug_tools.gd`)
We implemented an automatic port-probing grid layout based on [Godot Proposal #10262](https://github.com/godotengine/godot-proposals/issues/10262#issuecomment-2756914788):
1. **Instance ID Discovery**:
   - Autoload [`debug_tools.gd`](file:///c:/Users/user7/PA/Godot-AI/debug_tools.gd) loops through local TCP ports `5920, 5921, 5922, ...` and attempts `server.listen(port)`.
   - The first available port becomes that instance's assigned port and unique `instance_index`.
2. **Desktop Grid Snapping**:
   - Probes active instances and queries `DisplayServer.screen_get_usable_rect()` to avoid overlapping the Windows taskbar.
   - 1 instance: Centered `1280x720`.
   - 2 instances (Landscape): Left / Right halves.
   - 2 instances (Portrait): Vertically stacked (top window centered horizontally with 16px top padding; bottom window directly below).
   - 3-4 instances: $2 \times 2$ quadrant grid.
3. **Auto-naming & 2-Window Auto-Join**:
   - Instance 0 defaults to `"HostPlayer"`.
   - Instance 1 defaults to `"Player_2"`, etc.
   - **2-Window Auto-Join**: When launching in 2-window mode, Instance 0 automatically hosts and broadcasts an auto-join signal to Instance 1, immediately launching both players into the match without manual button clicks.
   - **CLI Override**: Pass `--no-auto-join`, `--no-autostart`, or `--manual` to disable auto-join and remain on the Lobby UI.
4. **Player Collision Geometry**:
   - Player characters use a `CapsuleShape3D` (`radius = 0.25`, `height = 0.6`) centered at `(0, 0.3, 0)`.
   - The capsule provides a radially symmetric horizontal footprint that avoids edge catching and eliminates perspective diamond distortion when rotating.

## 4. Multiplayer Network Protocol & Worktree Isolation Conventions
- **Autoload**: `NetworkManager` (`res://network/network_manager.gd`)
- **Authority**:
  - Server (peer ID `1`) has host authority.
  - Clients sync state via `@rpc("any_peer", "unreliable_ordered")` or `@rpc("call_local", "reliable")`.
- **Entity Spawning**:
  - Instantiated dynamically in `Main.tscn` under the `$Players` container.
  - Node names in `$Players` are set to `str(peer_id)` to ensure matching RPC node paths across peers.

### Worktree Port Isolation Architecture
When running multiple AI agent conversations or git worktrees concurrently, network ports and debug windows are automatically isolated to prevent collisions:

1. **Deterministic Workspace Base Port**:
   - `NetworkManager.get_workspace_default_port()` hashes the project's absolute directory path into a 5,000-port range (`7000`–`11999`):
     ```gdscript
     var offset: int = abs(project_dir.hash()) % 5000
     return 7000 + offset
     ```
   - Instances launched from the **same** worktree naturally target the same port range, while instances in **different** worktrees/conversations get non-overlapping ports.

2. **Auto-Scan Fallback on Conflict**:
   - If candidate port is occupied, `host_game()` automatically scans candidate ports (`starting_port + attempt`) up to 20 attempts before failing.

3. **Ephemeral Runtime Discovery (`res://.godot/host_port`)**:
   - When a host binds a port, it writes the bound port number to `res://.godot/host_port`.
   - Because `.godot/` is in `.gitignore`, this file is **strictly git-ignored** and never committed.
   - Companion clients in the same worktree discover the running host port via `NetworkManager.get_discovered_host_port()` without requiring manual port input.
   - Cleaned up automatically on `leave_game()` or process exit.

4. **CLI Argument Override**:
   - Both host and client accept `--port <num>` or `-p <num>` from the command line:
     ```powershell
     & "godot.exe" --path "." -- --port 7850
     ```

5. **DebugTools Window Layout Isolation (`debug_tools.gd`)**:
   - Window layout coordination similarly uses a workspace-derived base port (`5900 + (hash % 50) * 10`) so window tiling servers do not cross-talk between different conversations.

6. **Automated Worktree Merge & Cleanup Rule**:
   - When the user asks to merge a feature worktree back into `main`:
     1. Commit all worktree changes and rebase onto latest `main`.
     2. Fast-forward merge into `main` and execute headless verification.
     3. Upon successful merge and zero remaining diff, **automatically remove the worktree** (`git worktree remove <path>`) and **delete the merged branch** (`git branch -d <branch>`) without asking for manual confirmation.
     4. Note on Windows: If the conversation session process still holds an open directory handle on the empty worktree folder, Git cleanly deregisters the worktree and deletes the branch, and the empty directory is cleaned up when the session handle releases.

## 5. Godot AI MCP Server Setup (`hi-godot/godot-ai`)
- **Plugin Location**: `addons/godot_ai/` (v4.3.0)
- **Editor Plugin Setting**: Enabled in `project.godot` under `[editor_plugins]`.
- **MCP Client Transport**: `uvx --from godot-ai==4.3.0 godot-ai attach --port 8000 --ws-port 9500`
- **Configuration File**: Automatically recognized by Antigravity at `~/.gemini/config/mcp_config.json`.
- When the Godot editor is running with this project open, the Godot AI editor plugin starts the internal WebSocket bridge on port 9500 and the MCP server exposes over 120+ live editor operations (node hierarchy, inspector properties, runtime scene tree, etc.).

### Critical Agent Workflow & Execution Rules
1. **Prioritize Using the MCP Server**:
   - When inspecting or editing the Godot project (scenes, nodes, properties, script attachment, editor state), **always prioritize using the `godot-ai` MCP server tools** (`scene_manage`, `node_create`, `node_set_property`, `script_patch`, etc.).
   - If the MCP server is not connected (`PLUGIN_DISCONNECTED` or session count 0), **ask the user to take a look first to make sure Godot is running and open to this project**.
2. **Never Launch the Godot Editor Directly**:
   - AI agents must **NEVER** attempt to launch or restart the Godot editor GUI (e.g. `godot.exe --editor`, `godot.exe -e`, or spawning background GUI tasks).
   - Launching interactive Godot through Antigravity terminal runners causes stdout/stderr handle locking, Steam DRM/hook conflicts, frozen window rendering, and blocked background tasks.
   - Headless CLI checks (`--headless --quit`) for static syntax/compile verification are fully supported and encouraged.
3. **Editor Restarts & Hot-Reloading**:
   - Restarts should **rarely be needed**: Godot automatically hot-reloads modified GDScript files, resources, and scenes on disk, and the MCP WebSocket bridge maintains or restores connections seamlessly.
   - If an editor restart is genuinely required (e.g. initial plugin enablement or severe engine freeze), **prompt the user** to close and reopen the editor themselves. Do not attempt to kill or restart the editor process programmatically.

