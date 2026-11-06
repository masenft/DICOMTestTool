# Measures start time (until the main window exists) and idle CPU of DICOMTestTool.exe on Windows.
# Usage: measure-perf.ps1 -Exe <path> -Label <name>
param([Parameter(Mandatory)] [string]$Exe, [Parameter(Mandatory)] [string]$Label)
$ErrorActionPreference = "Stop"
$data = Join-Path $env:RUNNER_TEMP ("dtt-perf-" + [guid]::NewGuid())
$env:DICOMTESTTOOL_DATA_DIR = $data
$sw = [Diagnostics.Stopwatch]::StartNew()
$p = Start-Process -FilePath $Exe -PassThru
while ($p.MainWindowHandle -eq 0 -and $sw.Elapsed.TotalSeconds -lt 120) { Start-Sleep -Milliseconds 100; $p.Refresh() }
$start = $sw.Elapsed.TotalSeconds
Start-Sleep -Seconds 10
$p.Refresh(); $c1 = $p.TotalProcessorTime.TotalSeconds; $t1 = $sw.Elapsed.TotalSeconds
Start-Sleep -Seconds 20
$p.Refresh(); $c2 = $p.TotalProcessorTime.TotalSeconds; $t2 = $sw.Elapsed.TotalSeconds
$core = 100 * ($c2 - $c1) / ($t2 - $t1)
$total = $core / [Environment]::ProcessorCount
$mem = [math]::Round($p.WorkingSet64 / 1MB)
Stop-Process -Id $p.Id -Force
$line = "| $Label | {0:N1} s | {1:N1} % eines Kerns ({2:N1} % gesamt) | $mem MB |" -f $start, $core, $total
Write-Host $line
if ($env:GITHUB_STEP_SUMMARY) { Add-Content $env:GITHUB_STEP_SUMMARY $line }
