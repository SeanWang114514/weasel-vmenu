param(
  [string]$OutDir = 'D:\VibeCoding\输入法\shots\vp',
  [string]$Target = 'notepad',
  [int]$TargetPid = 0,
  [string]$DocState = ''
)
# Sequential vpick panel test harness.
# Sends one key group per step, captures a screenshot, and (optionally) dumps the
# document text via Ctrl+A/Ctrl+C so we get an authoritative "what got committed".
# ASCII only on purpose (BOM-less .ps1 parses as ANSI on PS 5.1).

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public class VpT {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint c, uint t);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int t, bool r);
}
'@

$script:ShotX = 40; $script:ShotY = 40; $script:ShotW = 1200; $script:ShotH = 560
$script:UiDumpTargetPid = $TargetPid

function Focus-Target {
  $proc = Get-Process $Target -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } |
          Where-Object { $TargetPid -le 0 -or $_.Id -eq $TargetPid } | Select-Object -First 1
  if (-not $proc) { Write-Error "target $Target not found"; exit 2 }
  $hwnd = $proc.MainWindowHandle
  [void][VpT]::ShowWindow($hwnd, 9)
  [void][VpT]::MoveWindow($hwnd, 60, 40, 1040, 460, $true)
  Start-Sleep -Milliseconds 200
  $zpid = 0
  $fgw = [VpT]::GetForegroundWindow()
  $tid1 = [VpT]::GetWindowThreadProcessId($fgw, [ref]$zpid)
  $tid2 = [VpT]::GetCurrentThreadId()
  [void][VpT]::AttachThreadInput($tid1, $tid2, $true)
  [void][VpT]::BringWindowToTop($hwnd)
  [void][VpT]::SetForegroundWindow($hwnd)
  [void][VpT]::AttachThreadInput($tid1, $tid2, $false)
  $sb = New-Object Text.StringBuilder 256
  [void][VpT]::GetWindowText([VpT]::GetForegroundWindow(), $sb, 256)
  if ($sb.ToString() -ne $proc.MainWindowTitle) {
    [VpT]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 40
    [VpT]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 80
    [void][VpT]::SetForegroundWindow($hwnd)
    Start-Sleep -Milliseconds 120
  }
  return $proc.Id
}

$script:VKMAP = @{
  'UP' = 0x26; 'DOWN' = 0x28; 'LEFT' = 0x25; 'RIGHT' = 0x27
  'ENTER' = 0x0D; 'ESC' = 0x1B; 'BACK' = 0x08; 'SPACE' = 0x20
  'SHIFT' = 0x10; 'TAB' = 0x09; 'HOME' = 0x24; 'END' = 0x23
  'PGUP' = 0x21; 'PGDN' = 0x22; 'DELETE' = 0x2E
}

function Tap([string]$spec) {
  # spec: literal characters (letters/digits/-/=) and {NAME} tokens
  # ({UP} {DOWN} {LEFT} {RIGHT} {ENTER} {ESC} {BACK} {SPACE} {PGUP} {PGDN}).
  # keybd_event instead of SendKeys: SendKeys treats + - ^ % ( ) as syntax.
  $tokens = @()
  $rest = $spec
  while ($rest.Length -gt 0) {
    if ($rest.StartsWith('{')) {
      $e = $rest.IndexOf('}')
      if ($e -lt 0) { throw "bad token: $rest" }
      $tokens += , @('name', $rest.Substring(1, $e - 1))
      $rest = $rest.Substring($e + 1)
    } else {
      $tokens += , @('char', $rest.Substring(0, 1))
      $rest = $rest.Substring(1)
    }
  }
  foreach ($t in $tokens) {
    # 逐键重新抢焦点：并行会话会不断把窗口拉到前台，焦点被抢走时这颗键就丢进了别的窗口
    #（实测丢 ↓ / 丢 → 都是这么来的）。每次发键前确认前台还是目标窗口。
    Focus-Target | Out-Null
    $vk = 0
    if ($t[0] -eq 'name') {
      $n = $t[1].ToUpper()
      if (-not $script:VKMAP.ContainsKey($n)) { throw "unknown key: $($t[1])" }
      $vk = [int]$script:VKMAP[$n]
    } else {
      $c = $t[1]
      if ($c -cmatch '[a-zA-Z]') { $vk = [int][char]$c.ToUpper() }
      elseif ($c -match '[0-9]') { $vk = 0x30 + [int]$c }
      elseif ($c -eq ' ') { $vk = 0x20 }
      elseif ($c -eq '-') { $vk = 0xBD }
      elseif ($c -eq '=') { $vk = 0xBB }
      elseif ($c -eq '+') { $vk = 0x6B }   # numpad + (KP_Add) = page down
      else { throw "unknown char: $c" }
    }
    $sc = [VpT]::MapVirtualKey([uint32]$vk, 0)
    [VpT]::keybd_event([byte]$vk, [byte]$sc, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 45
    [VpT]::keybd_event([byte]$vk, [byte]$sc, 2, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 260
  }
  Start-Sleep -Milliseconds 300
}

function Shot([string]$name) {
  if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
  $bmp = New-Object Drawing.Bitmap $script:ShotW, $script:ShotH
  $g = [Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($script:ShotX, $script:ShotY, 0, 0, (New-Object Drawing.Size $script:ShotW, $script:ShotH))
  $p = Join-Path $OutDir "$name.png"
  $bmp.Save($p, [Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
  return $p
}

function DumpUi {
  # Authoritative read of the editor text via UI Automation (synchronous, no
  # timer lag like the state-file mirror). Prints the same DOC[]-style line.
  if ($script:UiDumpTargetPid -le 0) {
    $p = Get-Process $Target -ErrorAction SilentlyContinue |
      Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if ($p) { $script:UiDumpTargetPid = $p.Id } else { return }
  }
  try {
    Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop
    Add-Type -AssemblyName UIAutomationTypes -ErrorAction Stop
  } catch { return }
  try {
    $auto = [System.Windows.Automation.AutomationElement]
    $root = $auto::RootElement
    $cond = New-Object System.Windows.Automation.PropertyCondition(
      $auto::ProcessIdProperty, [int]$script:UiDumpTargetPid)
    $win = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
    if (-not $win) { Write-Output 'UIDOC=<NO_WINDOW>'; return }
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $stack = New-Object System.Collections.Stack
    $stack.Push($win)
    $best = $null; $bestLen = -1
    while ($stack.Count -gt 0) {
      $n = $stack.Pop()
      $tp = $null
      if ($n.TryGetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern, [ref]$tp) -and $tp) {
        $t = $tp.DocumentRange.GetText(8000)
        if ($t.Length -gt $bestLen) { $bestLen = $t.Length; $best = $t }
      }
      $child = $walker.GetFirstChild($n)
      while ($child) { $stack.Push($child); $child = $walker.GetNextSibling($child) }
    }
    if ($null -eq $best) { Write-Output 'UIDOC=<NO_TEXTPATTERN>'; return }
    $shown = ($best -replace "`r", '<CR>' -replace "`n", '<NL>')
    Write-Output ("UIDOC=[{0}] len={1}" -f $shown, $bestLen)
  } catch {
    Write-Output ('UIDOC=<ERR ' + $_.Exception.Message + '>')
  }
}

function DumpDoc([string]$tag) {
  if ($DocState -ne '') {
    # Editor window mirrors its text into a file (see vp-editor.ps1): no clipboard,
    # no race with the other sessions in this workspace.
    Start-Sleep -Milliseconds 650
    $txt = ''
    for ($i = 0; $i -lt 6; $i++) {
      if (Test-Path $DocState) { $txt = [System.IO.File]::ReadAllText($DocState); break }
      Start-Sleep -Milliseconds 150
    }
    $shown = ($txt -replace "`r", '<CR>' -replace "`n", '<NL>')
    Write-Output ("DOC[{0}]=[{1}] len={2}" -f $tag, $shown, $txt.Length)
    DumpUi
    return
  }
  [System.Windows.Forms.SendKeys]::SendWait('^a')
  Start-Sleep -Milliseconds 200
  [System.Windows.Forms.SendKeys]::SendWait('^c')
  Start-Sleep -Milliseconds 250
  $txt = Get-Clipboard -Raw
  if ($null -eq $txt) { $txt = '' }
  $shown = ($txt -replace "`r", '<CR>' -replace "`n", '<NL>')
  Write-Output ("DOC[{0}]=[{1}] len={2}" -f $tag, $shown, $txt.Length)
  [System.Windows.Forms.SendKeys]::SendWait('{RIGHT}')
  Start-Sleep -Milliseconds 200
}

function Step([string]$name, [string]$keys, [switch]$Dump) {
  Focus-Target | Out-Null
  if ($keys -ne '') { Tap $keys }
  Start-Sleep -Milliseconds 500
  $p = Shot $name
  Write-Output ("STEP {0} keys=[{1}] shot={2}" -f $name, $keys, $p)
  if ($Dump) { DumpDoc $name }
}

function ClearDoc {
  # Wipe the editor text. Only call while no composition is open.
  # 用 keybd_event 而不是 SendKeys：并行会话会在发键前抢走焦点，SendKeys 丢一次
  # 文档里就留下上一轮的字（实测），所以清完用状态文件复查、最多重试 4 次。
  $txt = 'x'
  for ($try = 0; $try -lt 4 -and $txt -ne ''; $try++) {
    Focus-Target | Out-Null
    [VpT]::keybd_event(0x11, 0, 0, [UIntPtr]::Zero)   # Ctrl down
    Start-Sleep -Milliseconds 40
    [VpT]::keybd_event(0x41, 0, 0, [UIntPtr]::Zero)   # A down
    Start-Sleep -Milliseconds 40
    [VpT]::keybd_event(0x41, 0, 2, [UIntPtr]::Zero)   # A up
    [VpT]::keybd_event(0x11, 0, 2, [UIntPtr]::Zero)   # Ctrl up
    Start-Sleep -Milliseconds 250
    [VpT]::keybd_event(0x2E, 0, 0, [UIntPtr]::Zero)   # Delete down
    Start-Sleep -Milliseconds 40
    [VpT]::keybd_event(0x2E, 0, 2, [UIntPtr]::Zero)   # Delete up
    Start-Sleep -Milliseconds 350
    $txt = ''
    if (Test-Path $DocState) { $txt = [System.IO.File]::ReadAllText($DocState) }
  }
  if ($txt -ne '') {
    Write-Output ('WARNCLEAR=[' + ($txt -replace "`r", '<CR>' -replace "`n", '<NL>') + ']')
  }
}
