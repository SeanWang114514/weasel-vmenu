param(
  [string]$Target = 'notepad',
  [string]$Keys = '',
  [string]$Out = '',
  [switch]$NoShot
)
# Send keys to target, then Ctrl+A / Ctrl+C and return clipboard text (authoritative doc state).
# ASCII only (BOM-less ps1 parsed as ANSI on PS 5.1).
$ts = Join-Path $PSScriptRoot 'type-and-shot.ps1'
if ($Keys -ne '') {
  & $ts -Target $Target -Keys $Keys -Out $(if ($Out) { $Out } else { Join-Path $PSScriptRoot 'shots\probe.png' }) -NoClick | Out-Null
}
Start-Sleep -Milliseconds 300
& $ts -Target $Target -Keys 'ctrl+a,ctrl+c' -Out $(if ($NoShot) { Join-Path $env:TEMP 'probe-none.png' } else { $(if ($Out) { $Out + '.sel.png' } else { Join-Path $PSScriptRoot 'shots\probe.sel.png' }) }) -NoClick | Out-Null
Start-Sleep -Milliseconds 200
$text = Get-Clipboard -Raw
if ($null -eq $text) { $text = '' }
'DOC=[' + ($text -replace "`r", '\r' -replace "`n", '\n') + ']'
