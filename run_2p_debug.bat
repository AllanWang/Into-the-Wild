@echo off
set "GODOT_EXE="
if defined GODOT_BIN if exist "%GODOT_BIN%" set "GODOT_EXE=%GODOT_BIN%"
if not defined GODOT_EXE if exist "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" set "GODOT_EXE=C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
if not defined GODOT_EXE where godot >nul 2>nul && set "GODOT_EXE=godot"

if defined GODOT_EXE goto :launch
echo Godot executable not found. Set GODOT_BIN or install Godot on PATH.
pause
exit /b 1

:launch

echo Launching 2-Player Auto-Join Debug Windows...
start "" "%GODOT_EXE%" --path "%~dp0." res://ui/lobby.tscn
start "" "%GODOT_EXE%" --path "%~dp0." res://ui/lobby.tscn
