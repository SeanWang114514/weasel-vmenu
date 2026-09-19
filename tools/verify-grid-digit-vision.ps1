Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public class VS{[DllImport("user32.dll")]public static extern bool MoveWindow(IntPtr h,int x,int y,int w,int ht,bool r);[DllImport("user32.dll")]public static extern bool SetForegroundWindow(IntPtr h);[DllImport("user32.dll")]public static extern void keybd_event(byte vk,byte sc,uint f,UIntPtr e);[DllImport("user32.dll")]public static extern uint MapVirtualKey(uint c,uint t);}'
function Tap([byte]$vk){ $sc=[VS]::MapVirtualKey([uint32]$vk,0); [VS]::keybd_event($vk,[byte]$sc,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 60; [VS]::keybd_event($vk,[byte]$sc,2,[UIntPtr]::Zero); Start-Sleep -Milliseconds 130 }
function Shot([string]$p){ $bmp=New-Object Drawing.Bitmap 1040,460; $g=[Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen(60,40,0,0,(New-Object Drawing.Size(1040,460))); $bmp.Save($p,[Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose() }
function Read-Np { Tap 0x1B; Start-Sleep -Milliseconds 300
  [VS]::keybd_event(0x11,0,0,[UIntPtr]::Zero); Tap 0x41; Tap 0x43
  [VS]::keybd_event(0x11,0,2,[UIntPtr]::Zero); Start-Sleep -Milliseconds 400
  $x=Get-Clipboard -Raw -EA SilentlyContinue; if($null -eq $x){return '<空>'}; return $x }
function NewNp {
  Get-Process notepad -EA SilentlyContinue | Stop-Process -Force; Start-Sleep -Milliseconds 900
  Start-Process notepad; Start-Sleep -Seconds 3
  $np=Get-Process notepad | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  [void][VS]::MoveWindow($np.MainWindowHandle,60,40,1040,460,$true); [VS]::SetForegroundWindow($np.MainWindowHandle); Start-Sleep -Milliseconds 400 }
function TypeShi {
  $t='D:\VibeCoding\输入法\repo\weasel-vmenu\tools\type-and-shot.ps1'
  for($i=1;$i -le 5;$i++){
    & $t -Target notepad -Keys 's,h,i' -Out 'D:\weasel-build\shots\_t.png' -NoClick *> $null; Start-Sleep -Milliseconds 700
    $c=Get-Clipboard -Raw -EA SilentlyContinue
    $wp=Get-Process notepad | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if($wp){ $r=[VS]::MapVirtualKey(0,0); return $true }
    Tap 0x1B; Tap 0x10; Start-Sleep -Milliseconds 300 }
  return $false }

"### 用例 1：展开 -> ↓ 到第 2 行 -> 按 3 ###"
NewNp
TypeShi | Out-Null
Start-Sleep -Milliseconds 300
Tap 0x1B; Start-Sleep -Milliseconds 200
TypeShi | Out-Null
Tap 0x28; Start-Sleep -Milliseconds 600      # ↓ 展开
Tap 0x28; Start-Sleep -Milliseconds 800      # ↓ 高亮下移一行
Shot 'D:\weasel-build\shots\h1_row2_before.png'
Tap 0x33; Start-Sleep -Milliseconds 900      # 3
"上屏 = 「$(Read-Np)」"

"### 用例 2：收起态 -> = 翻页 -> 按 3 ###"
NewNp
TypeShi | Out-Null
Tap 0x1B; Start-Sleep -Milliseconds 200
TypeShi | Out-Null
$t='D:\VibeCoding\输入法\repo\weasel-vmenu\tools\type-and-shot.ps1'
& $t -Target notepad -Keys 'equals' -Out 'D:\weasel-build\shots\_t.png' -NoClick *> $null
Start-Sleep -Milliseconds 900
Shot 'D:\weasel-build\shots\h2_paged_before.png'
Tap 0x33; Start-Sleep -Milliseconds 900
"上屏 = 「$(Read-Np)」"

"### 用例 3：纯数字编码 131 -> 回车（不能被抢） ###"
NewNp
TypeShi | Out-Null
Tap 0x1B; Start-Sleep -Milliseconds 250
foreach($d in 0x31,0x33,0x31){ Tap ([byte]$d) }
Start-Sleep -Milliseconds 400
Tap 0x0D; Start-Sleep -Milliseconds 800
"上屏 = 「$(Read-Np)」"
