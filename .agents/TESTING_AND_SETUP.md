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
   - 2 instances: Left / Right halves.
   - 3-4 instances: $2 \times 2$ quadrant grid.
3. **Auto-naming**:
   - Instance 0 defaults to `"HostPlayer"`.
   - Instance 1 defaults to `"Player_2"`, etc.

## 4. Multiplayer Network Protocol Conventions
- **Autoload**: `NetworkManager` (`res://network/network_manager.gd`)
- **Default Port**: `7777` (over ENet)
- **Authority**:
  - Server (peer ID `1`) has host authority.
  - Clients sync state via `@rpc("any_peer", "unreliable_ordered")` or `@rpc("call_local", "reliable")`.
- **Entity Spawning**:
  - Instantiated dynamically in `Main.tscn` under the `$Players` container.
  - Node names in `$Players` are set to `str(peer_id)` to ensure matching RPC node paths across peers.

## 5. Godot AI MCP Server Setup (`hi-godot/godot-ai`)
- **Plugin Location**: `addons/godot_ai/` (v4.3.0)
- **Editor Plugin Setting**: Enabled in `project.godot` under `[editor_plugins]`.
- **MCP Client Transport**: `uvx --from godot-ai==4.3.0 godot-ai attach --port 8000 --ws-port 9500`
- **Configuration File**: Automatically recognized by Antigravity at `~/.gemini/config/mcp_config.json`.
- When the Godot editor is running with this project open, the Godot AI editor plugin starts the internal WebSocket bridge on port 9500 and the MCP server exposes over 120+ live editor operations (node hierarchy, inspector properties, runtime scene tree, etc.).

