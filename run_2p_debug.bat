@echo off
set "GODOT_EXE=C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"

if exist "%GODOT_EXE%" goto :launch
echo Godot executable not found at %GODOT_EXE%
pause
exit /b 1

:launch

echo Launching 2-Player Auto-Join Debug Windows...
start "" "%GODOT_EXE%" --path "%~dp0." res://debug/multiplayer_debug.tscn
start "" "%GODOT_EXE%" --path "%~dp0." res://debug/multiplayer_debug.tscn
