@echo off
rem Runs every probe (close the Godot editor first). See tools\run_all_probes.ps1 for options.
powershell -ExecutionPolicy Bypass -File "%~dp0run_all_probes.ps1" %*
pause
