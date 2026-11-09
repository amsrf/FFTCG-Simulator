@echo off
rem Opens TWO copies of the game that start an online match by themselves, on the practice board:
rem the first window hosts, the second joins it (127.0.0.1). Each window plays one side.
rem Pass a different Godot path as the first argument if yours moved.
set "GODOT=C:\Users\KABUM\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
if not "%~1"=="" set "GODOT=%~1"
if not exist "%GODOT%" (
  echo Godot not found at: %GODOT%
  echo Run this script with the path to your Godot .exe as the first argument.
  pause
  exit /b 1
)
set "PROJECT=%~dp0.."
start "Game 1 (host)" "%GODOT%" --path "%PROJECT%" --position 40,60 --resolution 1280x720 -- --host --practice
rem Give the host a moment to start listening before the second window joins.
timeout /t 3 /nobreak >nul
start "Game 2 (join)" "%GODOT%" --path "%PROJECT%" --position 660,380 --resolution 1280x720 -- --join
