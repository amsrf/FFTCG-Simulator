# Runs every probe in tests/ headless with the Godot 4.7.2 binary and prints one summary line per probe.
#
#   Double-click tools\run_all_probes.bat, or from a terminal in the project folder:
#     powershell -ExecutionPolicy Bypass -File tools\run_all_probes.ps1
#     powershell -ExecutionPolicy Bypass -File tools\run_all_probes.ps1 -Filter "*summon*"   # only some probes
#
# Close the Godot editor first: a second instance can fight over the .godot import cache (see AGENTS.md).
# Full logs land in tools\probe_logs\<probe>.log (ignored by git).
param(
	[string]$Godot = "C:\Users\KABUM\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe",
	[string]$Filter = "*",
	[int]$TimeoutSec = 180
)

$root = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $root "tools\probe_logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
if (-not (Test-Path $Godot)) {
	Write-Host "Godot not found at $Godot - pass -Godot <path to Godot_v4.7.2-stable_win64.exe>" -ForegroundColor Red
	exit 1
}

$probes = Get-ChildItem (Join-Path $root "tests") -Filter "$Filter.tscn" | Sort-Object Name
$passed = 0; $failed = @(); $started = Get-Date
foreach ($p in $probes) {
	$name = $p.BaseName
	$log = Join-Path $logDir "$name.log"
	$err = Join-Path $logDir "$name.err.log"
	$t0 = Get-Date
	$proc = Start-Process -FilePath $Godot -NoNewWindow -PassThru `
		-ArgumentList @("--headless", "--path", "`"$root`"", "res://tests/$($p.Name)", "--quit-after", "20000") `
		-RedirectStandardOutput $log -RedirectStandardError $err
	if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
		$proc.Kill()
		$status = "TIMEOUT after $TimeoutSec s"
		$ok = $false
	} else {
		$text = ""
		if (Test-Path $log) { $text += Get-Content $log -Raw }
		if (Test-Path $err) { $text += Get-Content $err -Raw }
		$result = [regex]::Matches($text, "RESULT:\s*(.*)") | Select-Object -Last 1
		$scriptErrors = ([regex]::Matches($text, "SCRIPT ERROR|Parse Error|Compile Error")).Count
		if ($result) { $status = $result.Groups[1].Value.Trim() } else { $status = "NO RESULT LINE" }
		$ok = ($status -match "all checks passed|measured") -and ($scriptErrors -eq 0)
		if ($scriptErrors -gt 0) { $status += "  |  $scriptErrors script error(s)" }
	}
	$secs = [int]((Get-Date) - $t0).TotalSeconds
	if ($ok) {
		$passed++
		Write-Host ("  ok    {0,-40} {1,4}s  {2}" -f $name, $secs, $status) -ForegroundColor Green
	} else {
		$failed += $name
		Write-Host ("  FAIL  {0,-40} {1,4}s  {2}" -f $name, $secs, $status) -ForegroundColor Red
	}
}

$total = [int]((Get-Date) - $started).TotalMinutes
Write-Host ""
Write-Host ("{0} of {1} probes passed in {2} min" -f $passed, $probes.Count, $total)
if ($failed.Count -gt 0) {
	Write-Host "Failed or unclear (logs in tools\probe_logs):" -ForegroundColor Yellow
	$failed | ForEach-Object { Write-Host "  $_" }
}
