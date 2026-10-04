@echo off
set "GODOT_EXE=C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"

if exist "%GODOT_EXE%" goto :launch
echo Godot executable not found at %GODOT_EXE%
pause
exit /b 1

:launch

echo Launching Solo Debug World...
start "" "%GODOT_EXE%" --path "%~dp0." res://debug/single_player_debug.tscn
