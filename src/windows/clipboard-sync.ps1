param(
  [string]$RimeDir = 'D:\rime-sandbox',
  [int]$Max = 50,
  [int]$IntervalMs = 1000
)
# Clipboard history sync - fully independent of the IME process.
# The IME side (lua/vmenu_core.lua) ONLY reads/writes this text file; it never
# spawns a process, which is what used to freeze the input method.
#
# File format: one clipboard entry per line, newest first.
# Entries are de-duplicated, capped at $Max, oldest dropped first.
# ASCII-only source on purpose: Windows PowerShell 5.1 parses BOM-less UTF-8
# scripts as ANSI, which breaks quoting when non-ASCII comments are present.

$ErrorActionPreference = 'SilentlyContinue'
New-Item -ItemType Directory -Force -Path $RimeDir | Out-Null
$cache = Join-Path $RimeDir 'clipboard-cache.txt'
$utf8 = New-Object Text.UTF8Encoding($false)

function Read-History {
  param([string]$Path)
  $items = @()
  if (Test-Path -LiteralPath $Path) {
    $items = @(Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction SilentlyContinue |
      Where-Object { $_ -ne $null -and $_.Trim().Length -gt 0 })
  }
  return $items
}

function Write-History {
  param([string]$Path, [string[]]$Items)
  $tmp = "$Path.tmp"
  $lines = @()
  foreach ($i in $Items) {
    if ($null -ne $i -and $i.Trim().Length -gt 0) { $lines += $i.Trim() }
  }
  $text = ''
  if ($lines.Count -gt 0) { $text = ($lines -join "`n") + "`n" }
  [IO.File]::WriteAllText($tmp, $text, $utf8)
  Move-Item -Force $tmp $Path
}

function Get-ClipText {
  $t = $null
  try { $t = Get-Clipboard -Raw -ErrorAction Stop } catch { return $null }
  if ($null -eq $t) { return $null }
  # Flatten newlines: the cache format is one entry per line.
  $t = ($t -replace "`r`n", ' ') -replace "[`r`n]", ' '
  $t = $t.Trim()
  if ($t.Length -eq 0) { return $null }
  if ($t.Length -gt 2000) { $t = $t.Substring(0, 2000) }
  return $t
}

$history = @(Read-History -Path $cache)
if ($history.Count -gt $Max) { $history = $history[0..($Max - 1)] }
$lastSeen = ''
if ($history.Count -gt 0) { $lastSeen = $history[0] }
# Make sure the file exists even on first run.
if (-not (Test-Path -LiteralPath $cache)) { Write-History -Path $cache -Items $history }

while ($true) {
  $text = Get-ClipText
  if ($text -and $text -ne $lastSeen) {
    $lastSeen = $text
    $new = @($text)
    foreach ($old in $history) { if ($old -ne $text) { $new += $old } }
    if ($new.Count -gt $Max) { $new = $new[0..($Max - 1)] }
    $history = $new
    Write-History -Path $cache -Items $history
  }
  Start-Sleep -Milliseconds $IntervalMs
}
