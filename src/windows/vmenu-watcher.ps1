param(
  [string]$RimeDir = 'D:\rime-sandbox',
  [int]$IntervalMs = 500
)
# Supervisor for the RESIDENT settings window + the clipboard sync process.
#
# Why this design:
#   * The IME must NEVER spawn a process. Doing that from the Rime input thread
#     (io.popen / os.execute) is exactly what used to freeze the input method.
#     So the Lua side only writes <RimeDir>\open-settings.flag.
#   * vmenu-settings-gui.ps1 stays resident: it builds its window hidden,
#     then polls that flag file every 60 ms and shows itself instantly.
#     Pressing  v  then  1  therefore costs ~0.1 s instead of 2-4 s of script parse.
#   * This watcher keeps ONE resident GUI and ONE clipboard sync alive and
#     restarts either if it died, so v->1 and clipboard history always work.
#
# Process detection uses CIM (Get-CimInstance Win32_Process), NEVER
# Get-Process | Where CommandLine: Windows PowerShell 5.1's Get-Process has no
# CommandLine property, the match always fails, and a watchdog built on it
# respawns unconditionally every tick (that bug once produced 200+ processes).
# Every respawn additionally has a 5 s per-target cooldown as a second line of
# defence, and all three scripts are single-instance via named mutexes.
#
# ASCII-only source on purpose: Windows PowerShell 5.1 parses BOM-less UTF-8
# scripts as ANSI, which breaks quoting when non-ASCII characters are present.

$ErrorActionPreference = 'SilentlyContinue'

# Single instance: starting a second supervisor is harmless but pointless, so
# every extra one exits immediately.
$mutex = New-Object System.Threading.Mutex($false, 'RimeVMenuWatcher')
$isFirst = $false
try { $isFirst = $mutex.WaitOne(0) }
catch [System.Threading.AbandonedMutexException] { $isFirst = $true }
catch { $isFirst = $false }
if (-not $isFirst) { exit 0 }

$flag = Join-Path $RimeDir 'open-settings.flag'
# Assembled at runtime so that a command line merely mentioning a script name
# (including this process) can never match the pattern we search for.
$guiName = 'vmenu-' + 'settings-gui.ps1'
$syncName = 'clip' + 'board-sync.ps1'
$gui = Join-Path $PSScriptRoot $guiName
$sync = Join-Path $PSScriptRoot $syncName

if (-not (Test-Path -LiteralPath $gui)) {
  Write-Host "vmenu-watcher: GUI script not found: $gui"
  exit 1
}

function Test-Alive([string]$scriptName) {
  $me = $PID
  $procs = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'")
  foreach ($p in $procs) {
    if ($p.ProcessId -ne $me -and $p.CommandLine -and $p.CommandLine.IndexOf($scriptName) -ge 0) {
      return $true
    }
  }
  return $false
}

$tick = 0
$lastGui = [DateTime]::MinValue
$lastSync = [DateTime]::MinValue

while ($true) {
  Start-Sleep -Milliseconds $IntervalMs
  $tick++
  if ($tick -lt 4) { continue }   # check every ~2 s
  $tick = 0
  $now = Get-Date

  # (1) resident settings window
  if ((-not (Test-Alive $guiName)) -and (Test-Path -LiteralPath $gui) -and
      ($now - $lastGui).TotalSeconds -ge 5) {
    $lastGui = Get-Date
    $pArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $gui, '-RimeDir', $RimeDir)
    # A pending flag means the window was requested while nothing was alive:
    # start the new instance with the window already shown.
    if (Test-Path -LiteralPath $flag) { $pArgs += '-ShowNow' }
    Start-Process -FilePath 'powershell.exe' -ArgumentList $pArgs -WindowStyle Hidden
    Start-Sleep -Seconds 2
  }

  # (2) clipboard sync
  if ((Test-Path -LiteralPath $sync) -and (-not (Test-Alive $syncName)) -and
      ($now - $lastSync).TotalSeconds -ge 5) {
    $lastSync = Get-Date
    $sArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $sync, '-RimeDir', $RimeDir)
    Start-Process -FilePath 'powershell.exe' -ArgumentList $sArgs -WindowStyle Hidden
    Start-Sleep -Seconds 2
  }
}
