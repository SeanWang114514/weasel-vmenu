<#
.SYNOPSIS
  量「按下一个键 → 画面真的变了」的端到端延迟（毫秒）。用来客观判断打字是否卡顿。

.DESCRIPTION
  做法：先对候选面板所在的小区域截屏取哈希当基线，然后按下键，之后每 ~5ms 截同一
  区域并算哈希，一旦变了就记下耗时。区域故意选**候选面板那一带**（不含文字光标），
  否则光标的闪烁会被误判成「画面变了」。

.EXAMPLE
  pwsh -File tools\measure-key-latency.ps1 -Target notepad -Keys n,i,h,a,o,s,h,i
#>
param(
  [string]$Target = 'notepad',
  # 注意：用 pwsh -File 调用时逗号不会拆成数组（这是 -File 与 -Command 的行为差异），
  # 所以这里收一个字符串，脚本内部自己按逗号切开。
  [string]$Keys = 'n,i,h,a,o,s,h,i',
  [int]$X = 60, [int]$Y = 205, [int]$W = 900, [int]$H = 45,   # 候选面板首行一带
  [int]$TimeoutMs = 2000,
  [int]$Warmup = 3
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public class Lat {
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

$VK = @{ 'a'=0x41;'b'=0x42;'c'=0x43;'d'=0x44;'e'=0x45;'f'=0x46;'g'=0x47;'h'=0x48;'i'=0x49;'j'=0x4A;
  'k'=0x4B;'l'=0x4C;'m'=0x4D;'n'=0x4E;'o'=0x4F;'p'=0x50;'q'=0x51;'r'=0x52;'s'=0x53;'t'=0x54;
  'u'=0x55;'v'=0x56;'w'=0x57;'x'=0x58;'y'=0x59;'z'=0x5A;'space'=0x20;'back'=0x08 }

# 截一小条并取哈希（用 LockBits + MD5，比逐像素 GetPixel 快两个数量级）
function Get-StripHash {
  $bmp = New-Object Drawing.Bitmap $W, $H
  $g = [Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($X, $Y, 0, 0, (New-Object Drawing.Size($W, $H)))
  $g.Dispose()
  $rect = New-Object Drawing.Rectangle 0, 0, $W, $H
  $d = $bmp.LockBits($rect, [Drawing.Imaging.ImageLockMode]::ReadOnly, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $bytes = New-Object byte[] ($d.Stride * $H)
  [System.Runtime.InteropServices.Marshal]::Copy($d.Scan0, $bytes, 0, $bytes.Length)
  $bmp.UnlockBits($d); $bmp.Dispose()
  $md5 = [System.Security.Cryptography.MD5]::Create()
  return [BitConverter]::ToString($md5.ComputeHash($bytes))
}

function Get-FgTitle {
  $sb = New-Object Text.StringBuilder 256
  [void][Lat]::GetWindowText([Lat]::GetForegroundWindow(), $sb, 256)
  return $sb.ToString()
}

$tp = Get-Process $Target -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $tp) { Write-Error "target $Target not found"; exit 2 }
$hwnd = $tp.MainWindowHandle
[void][Lat]::ShowWindow($hwnd, 9)
[void][Lat]::MoveWindow($hwnd, 60, 40, 1040, 460, $true)   # 与 type-and-shot.ps1 一致，面板位置可预期
Start-Sleep -Milliseconds 300
$z = 0
$fg = [Lat]::GetForegroundWindow()
$t1 = [Lat]::GetWindowThreadProcessId($fg, [ref]$z); $t2 = [Lat]::GetCurrentThreadId()
[void][Lat]::AttachThreadInput($t1, $t2, $true)
[void][Lat]::BringWindowToTop($hwnd); [void][Lat]::SetForegroundWindow($hwnd)
[void][Lat]::AttachThreadInput($t1, $t2, $false)
if ((Get-FgTitle) -ne $tp.MainWindowTitle) {
  [Lat]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 40
  [Lat]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero); Start-Sleep -Milliseconds 80
  [void][Lat]::SetForegroundWindow($hwnd); Start-Sleep -Milliseconds 150
}
"FOCUSED=$(Get-FgTitle)"
"区域 x=$X y=$Y ${W}x${H}"

# 先把中文候选窗叫出来（预热键不进统计）
foreach ($k in @('shift', 'shift')) { [Lat]::keybd_event([byte]$VK[$k], [byte][Lat]::MapVirtualKey([uint32]$VK[$k], 0), 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 30; [Lat]::keybd_event([byte]$VK[$k], [byte][Lat]::MapVirtualKey([uint32]$VK[$k], 0), 2, [UIntPtr]::Zero); Start-Sleep -Milliseconds 120 }
Start-Sleep -Milliseconds 300

$res = @()
$first = $true
foreach ($k in ($Keys.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })) {
  $kv = $VK[$k.ToLower()]
  if ($null -eq $kv) { continue }
  $sc = [Lat]::MapVirtualKey([uint32]$kv, 0)
  $before = Get-StripHash
  $sw = [Diagnostics.Stopwatch]::StartNew()
  [Lat]::keybd_event([byte]$kv, [byte]$sc, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 25
  [Lat]::keybd_event([byte]$kv, [byte]$sc, 2, [UIntPtr]::Zero)
  $ms = -1
  while ($sw.ElapsedMilliseconds -lt $TimeoutMs) {
    if ((Get-StripHash) -ne $before) { $ms = $sw.ElapsedMilliseconds; break }
  }
  $sw.Stop()
  if ($first) { $first = $false; continue }   # 第一个键只是让候选窗出现，不计入
  $res += [pscustomobject]@{ key = $k; ms = $ms }
  Start-Sleep -Milliseconds 250
}

""
"按键 → 画面更新延迟："
$res | ForEach-Object { "  {0,-3} {1,4} ms" -f $_.key, $_.ms }
$ok = @($res | Where-Object { $_.ms -ge 0 })
if ($ok.Count) {
  $avg = ($ok | Measure-Object ms -Average).Average
  $max = ($ok | Measure-Object ms -Maximum).Maximum
  ""
  "样本 {0} 个：平均 {1:N1} ms，最大 {2} ms" -f $ok.Count, $avg, $max
  if ($max -le 60) { "结论：按键响应跟手（全部 ≤60ms）✅" } else { "结论：存在可感知延迟 ⚠️" }
}
