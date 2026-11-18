# Into the Wild — Project Agent System

Welcome to the `.agents` documentation and reference hub for **Into the Wild**.

This project is a Godot 4 action roguelike with dynamic multi-instance grid layout debugging, ENet multiplayer networking, solo static Web export (`OfflineMultiplayerPeer`), and component-based 2.5D gameplay.

## Reference Directory

| Document / Skill | Purpose |
| :--- | :--- |
| [`.agents/GODOT_RULES.md`](file:///c:/Users/user7/PA/Into-the-Wild/.agents/GODOT_RULES.md) | Godot 4 syntax rules, static typing guidelines, signal bus & component patterns. |
| [`.agents/TESTING_AND_SETUP.md`](file:///c:/Users/user7/PA/Into-the-Wild/.agents/TESTING_AND_SETUP.md) | Headless test execution, local Godot binary path, and multi-instance grid launch scripts. |
| [`.agents/SUBAGENT_WORKFLOWS.md`](file:///c:/Users/user7/PA/Into-the-Wild/.agents/SUBAGENT_WORKFLOWS.md) | Role specifications for decomposing complex features into isolated subagent tasks. |
| [`game-feature`](file:///c:/Users/user7/PA/Into-the-Wild/.agents/skills/game-feature/SKILL.md) | 3-stage sequential feature creation pipeline (Discovery -> Design Plan -> Implementation & MCP Validation). |
| [`setup-godot-ai-mcp`](file:///c:/Users/user7/PA/Into-the-Wild/.agents/skills/setup-godot-ai-mcp/SKILL.md) | Automated skill to install, configure, or update the Godot AI MCP server across fresh clones. |

## Verification & Quick Commands

### Primary Verification: Godot AI MCP Server
During normal development, keep the Godot Editor open and verify via the `godot-ai` MCP server:
- Check editor state and live scene: `editor_state`
- Run in-editor test suites: `test_run`
- Check editor/runtime error output: `logs_read`
- *Note: If the MCP server is not connected, ask the user to open the project in Godot rather than falling back to headless execution.*

### Headless Syntax & Scene Check (Initial Setup / CI Only)
```powershell
& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path "." --quit
```

### Launch 2-Instance Local Multiplayer Test
```powershell
powershell -ExecutionPolicy Bypass -File .\launch_multiplayer_test.ps1
```
*(Or double-click `launch_multiplayer_test.bat`)*

## Core Project Architecture
- **Engine Version**: Godot 4.3+ (`config/features=PackedStringArray("4.7", "GL Compatibility")`).
- **Autoloads**:
  - `DebugTools` (`res://debug_tools.gd`): Automatic window placement & multi-instance port detection.
  - `NetworkManager` (`res://network/network_manager.gd`): ENet peer management, player dictionary, and connection signals.
- **Scenes**:
  - `res://ui/lobby.tscn`: Start scene with quick host/join buttons.
  - `res://Main.tscn`: Game arena with checkered ground plane and player container.
  - `res://player/player.tscn`: Box character body with name tag, camera authority, and RPC position sync.
