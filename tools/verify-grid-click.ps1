Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Text; using System.Collections.Generic;
public class EN2 {
 public delegate bool EnumProc(IntPtr h, IntPtr l);
 [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
 [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
 [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h,int x,int y,int w,int ht,bool r);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern void keybd_event(byte vk,byte sc,uint f,UIntPtr e);
 [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint c,uint t);
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint dx,uint dy,uint d,UIntPtr e);
 [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left,Top,Right,Bottom; }
 [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X,Y; }
 public static string Panel(uint want) {
   string res = null;
   EnumWindows((h,l) => {
     uint pid; GetWindowThreadProcessId(h, out pid);
     if (pid == want && IsWindowVisible(h)) {
       var cn = new StringBuilder(256); GetClassName(h, cn, 256);
       if (cn.ToString().StartsWith("ATL")) { RECT r; GetWindowRect(h, out r);
         res = string.Format("{0},{1},{2},{3}", r.Left, r.Top, r.Right, r.Bottom); }
     }
     return true; }, IntPtr.Zero);
   return res; } }
'@
$TOOL='D:\VibeCoding\输入法\repo\weasel-vmenu\tools\type-and-shot.ps1'
$LOG='D:\rime-sandbox\vmenu-debug.log'
function Tap([byte]$vk){ $sc=[EN2]::MapVirtualKey([uint32]$vk,0)
  [EN2]::keybd_event($vk,[byte]$sc,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 30
  [EN2]::keybd_event($vk,[byte]$sc,2,[UIntPtr]::Zero); Start-Sleep -Milliseconds 60 }
function Read-Np { Tap 0x1B; Start-Sleep -Milliseconds 300
  [EN2]::keybd_event(0x11,0,0,[UIntPtr]::Zero); Tap 0x41; Tap 0x43
  [EN2]::keybd_event(0x11,0,2,[UIntPtr]::Zero); Start-Sleep -Milliseconds 400
  $t=Get-Clipboard -Raw -EA SilentlyContinue; if($null -eq $t){return '<空>'}; return $t }
function TypeShi {
  $s0=Get-Content $LOG -Tail 1 -EA SilentlyContinue
  for($i=1;$i -le 3;$i++){ Tap 0x10; Start-Sleep -Milliseconds 300
    & $TOOL -Target notepad -Keys 's,h,i' -Out 'D:\weasel-build\shots\_t.png' -NoClick *> $null
    Start-Sleep -Milliseconds 600
    if((Get-Content $LOG -Tail 1 -EA SilentlyContinue) -ne $s0){ return $true } }
  return $false }

Get-Process notepad -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 900; Start-Process notepad; Start-Sleep -Seconds 3
$np=Get-Process notepad | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
[void][EN2]::MoveWindow($np.MainWindowHandle,60,40,1040,460,$true)
[EN2]::SetForegroundWindow($np.MainWindowHandle); Start-Sleep -Milliseconds 400
if(-not (TypeShi)){ "❌ 未进中文态"; exit 1 }
$pr = [EN2]::Panel([uint32]$np.Id)
"候选窗矩形 = $pr"
$v = $pr.Split(',') | ForEach-Object { [int]$_ }
$L=$v[0];$T=$v[1];$R=$v[2];$B=$v[3]
$W=$R-$L; $cell=$W/9.0
"宽=$W 格宽=$([Math]::Round($cell,1)) 高=$($B-$T)"
$cy=[int](($T+$B)/2)
"===== 点第 2 格（十）====="
$cx=[int]($L + $cell*1.5)
$p=New-Object EN2+POINT; $p.X=$cx; $p.Y=$cy
$h=[EN2]::WindowFromPoint($p); $cn=New-Object Text.StringBuilder 256; [void][EN2]::GetClassName($h,$cn,256)
"目标 ($cx,$cy) → 命中 class=$($cn.ToString())"
[void][EN2]::SetCursorPos($cx,$cy); Start-Sleep -Milliseconds 250
[EN2]::mouse_event(0x0002,0,0,0,[UIntPtr]::Zero); [EN2]::mouse_event(0x0004,0,0,0,[UIntPtr]::Zero)
Start-Sleep -Milliseconds 900
"点完内容 = 「$(Read-Np)」"

"===== 点第 3 格（🔟）====="
if(-not (TypeShi)){ "❌ 重打失败"; exit 1 }
$pr = [EN2]::Panel([uint32]$np.Id); $v=$pr.Split(',') | ForEach-Object { [int]$_ }
$L=$v[0];$T=$v[1];$R=$v[2];$B=$v[3]; $cell=($R-$L)/9.0; $cy=[int](($T+$B)/2)
$cx=[int]($L + $cell*2.5)
"目标 ($cx,$cy)"
[void][EN2]::SetCursorPos($cx,$cy); Start-Sleep -Milliseconds 250
[EN2]::mouse_event(0x0002,0,0,0,[UIntPtr]::Zero); [EN2]::mouse_event(0x0004,0,0,0,[UIntPtr]::Zero)
Start-Sleep -Milliseconds 900
"点完内容 = 「$(Read-Np)」"
"最后候选表:"; Get-Content $LOG -Tail 1
