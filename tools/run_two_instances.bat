@echo off
rem Opens TWO copies of the game, to try online play on one PC:
rem click Host in one window, and Join (127.0.0.1) in the other.
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
start "Game 1 (host)" "%GODOT%" --path "%PROJECT%" --position 40,60 --resolution 1280x720
start "Game 2 (join)" "%GODOT%" --path "%PROJECT%" --position 660,380 --resolution 1280x720
