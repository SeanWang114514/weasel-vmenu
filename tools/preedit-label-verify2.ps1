# Safe web verification for the v-menu preedit labels.
# 上一版脚本「点一下就当焦点到手」是错的：这次每个按键前都做两道硬检查，
#   1) WindowFromPoint(点击点) 的根窗口 == 目标窗口
#   2) GetForegroundWindow() == 目标窗口
# 任何一条不满足就**立刻退出，一个键都不发**（避免把按键打进别的窗口）。
# ASCII only (PS 5.1 needs a BOM for non-ASCII scripts).
param([switch]$SkipFocus)
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;using System.Runtime.InteropServices;using System.Text;
public class SF{
 [DllImport("user32.dll")]public static extern void keybd_event(byte vk,byte sc,uint f,UIntPtr e);
 [DllImport("user32.dll")]public static extern uint MapVirtualKey(uint c,uint t);
 [DllImport("user32.dll")]public static extern bool EnumWindows(EnumProc cb,IntPtr l);
 [DllImport("user32.dll")]public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")]public static extern bool GetWindowRect(IntPtr h,out R r);
 [DllImport("user32.dll")]public static extern int GetClassName(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")]public static extern int GetWindowText(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")]public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")]public static extern IntPtr WindowFromPoint(P pt);
 [DllImport("user32.dll")]public static extern IntPtr GetAncestor(IntPtr h,uint f);
 [DllImport("user32.dll")]public static extern bool ShowWindow(IntPtr h,int c);
 [DllImport("user32.dll")]public static extern bool MoveWindow(IntPtr h,int x,int y,int w,int t,bool r);
 [DllImport("user32.dll")]public static extern bool SetWindowPos(IntPtr h,IntPtr after,int x,int y,int w,int t,uint f);
 [DllImport("user32.dll")]public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")]public static extern void mouse_event(uint f,uint x,uint y,uint d,UIntPtr e);
 public struct R{public int L,T,Rr,B;} public struct P{public int X,Y;}
 public delegate bool EnumProc(IntPtr h,IntPtr l);
 public static readonly IntPtr TOPMOST=new IntPtr(-1), NOTOPMOST=new IntPtr(-2);
 public static void Tap(byte vk){byte sc=(byte)MapVirtualKey(vk,0);keybd_event(vk,sc,0,UIntPtr.Zero);System.Threading.Thread.Sleep(60);keybd_event(vk,sc,2,UIntPtr.Zero);System.Threading.Thread.Sleep(180);}
 public static void TapMod(byte mod,byte vk){byte sc=(byte)MapVirtualKey(vk,0);keybd_event(mod,0,0,UIntPtr.Zero);System.Threading.Thread.Sleep(30);keybd_event(vk,sc,0,UIntPtr.Zero);System.Threading.Thread.Sleep(50);keybd_event(vk,sc,2,UIntPtr.Zero);System.Threading.Thread.Sleep(30);keybd_event(mod,0,2,UIntPtr.Zero);System.Threading.Thread.Sleep(180);}
 public static string Panel(){string res="none";EnumWindows((h,l)=>{if(!IsWindowVisible(h))return true;var c=new StringBuilder(64);GetClassName(h,c,64);
  if(c.ToString().StartsWith("ATL:")){var r=new R();GetWindowRect(h,out r);res=(r.Rr-r.L)+"x"+(r.B-r.T);} return true;},IntPtr.Zero);return res;}
 public static IntPtr FindByTitle(string t){IntPtr res=IntPtr.Zero;EnumWindows((h,l)=>{if(!IsWindowVisible(h))return true;var sb=new StringBuilder(300);GetWindowText(h,sb,300);
  if(sb.ToString().Contains(t)){res=h;return false;} return true;},IntPtr.Zero);return res;}
 public static string Title(IntPtr h){var sb=new StringBuilder(300);GetWindowText(h,sb,300);return sb.ToString();}
 public static string Rect(IntPtr h){var r=new R();GetWindowRect(h,out r);return r.L+","+r.T+","+r.Rr+","+r.B;}
 public static IntPtr RootAt(int x,int y){var p=new P();p.X=x;p.Y=y;return GetAncestor(WindowFromPoint(p),2);}
 public static bool Top(IntPtr h,bool on){return SetWindowPos(h,on?TOPMOST:NOTOPMOST,40,20,1240,700,0x0040);}
}
'@
$VK=@{ 'a'=0x41;'b'=0x42;'c'=0x43;'d'=0x44;'e'=0x45;'f'=0x46;'g'=0x47;'h'=0x48;'i'=0x49;'j'=0x4A;'k'=0x4B;'l'=0x4C;'m'=0x4D;'n'=0x4E;'o'=0x4F;'p'=0x50;'q'=0x51;'r'=0x52;'s'=0x53;'t'=0x54;'u'=0x55;'v'=0x56;'w'=0x57;'x'=0x58;'y'=0x59;'z'=0x5A;
 '0'=0x30;'1'=0x31;'2'=0x32;'3'=0x33;'4'=0x34;'5'=0x35;'6'=0x36;'7'=0x37;'8'=0x38;'9'=0x39;'esc'=0x1B;'space'=0x20;'del'=0x2E;'back'=0x08;'ret'=0x0D }
$script:VK=$VK
function K([string]$k){ [SF]::Tap([byte]$script:VK[$k]) }
function Shot([string]$p){ $bmp=New-Object Drawing.Bitmap 1300,760; $g=[Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen(20,10,0,0,(New-Object Drawing.Size(1300,760))); $bmp.Save($p,[Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose() }
function CropBox([string]$src,[string]$dst,[int]$x,[int]$y,[int]$w,[int]$h,[double]$scale){
  $b=[Drawing.Image]::FromFile($src)
  $rect=New-Object Drawing.Rectangle $x,$y,$w,$h
  $ow=[int]($w*$scale); $oh=[int]($h*$scale)
  $out=New-Object Drawing.Bitmap $ow,$oh
  $g=[Drawing.Graphics]::FromImage($out)
  $g.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.DrawImage($b,(New-Object Drawing.Rectangle 0,0,$ow,$oh),$rect,[Drawing.GraphicsUnit]::Pixel)
  $out.Save($dst,[Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $out.Dispose(); $b.Dispose() }
# textarea 区（窗口在 40,20；textarea 约 y=74..224）+ mirror 区（约 y=236..302）
function Snap([string]$out){
  $dir='D:\weasel-build\shots'
  $full=Join-Path $dir "$out.png"; Shot $full
  # 整个测试窗口（含标题栏，1.6x）：textarea 行、候选窗、mirror 都在里面，OCR 一次看全
  CropBox $full (Join-Path $dir "${out}_win.png")  30 15 1260 715 1.6
  # 输入框行（窗口标题栏 ~31px + padding，textarea 约在屏幕 y=105..255）
  CropBox $full (Join-Path $dir "${out}_crop.png") 50 100 620 95 2.5
  CropBox $full (Join-Path $dir "${out}_mirror.png") 50 260 820 90 1.8
}

$dir='D:\weasel-build\shots'
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'ime-notepad' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force; "  killed leftover pad pid=$($_.ProcessId)" }
Start-Sleep -Milliseconds 500

$hwnd=[SF]::FindByTitle('IME WEB TEST')
if($hwnd -eq [IntPtr]::Zero){ "ABORT: no 'IME WEB TEST' window"; exit 1 }
if(-not $SkipFocus){
  [void][SF]::ShowWindow($hwnd,9)
  [void][SF]::Top($hwnd,$true)
  Start-Sleep -Milliseconds 700
  $cx=660; $cy=220
  $rootAt=[SF]::RootAt($cx,$cy)
  "click point ($cx,$cy) belongs to root hwnd=$rootAt  target=$hwnd  same=$($rootAt -eq $hwnd)"
  if($rootAt -ne $hwnd){ "ABORT: the click point is covered by another window <$([SF]::Title($rootAt))> -- NOT sending any key"; exit 2 }
  [void][SF]::SetCursorPos($cx,$cy); Start-Sleep -Milliseconds 200
  [SF]::mouse_event(0x0002,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 80
  [SF]::mouse_event(0x0004,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 500
  $fg=[SF]::GetForegroundWindow()
  "after click: foreground=<$([SF]::Title($fg))>  is target=$($fg -eq $hwnd)"
  if($fg -ne $hwnd){ "ABORT: focus did not land on the test page -- NOT sending any key"; exit 3 }
}
# 每个按键前再确认一次焦点还在测试页上
function CanType([string]$where){
  $fg=[SF]::GetForegroundWindow()
  if($fg -ne $hwnd){ "ABORT before key at [$where]: foreground=<$( [SF]::Title($fg) )>"; [void][SF]::Top($hwnd,$false); exit 4 }
  return $true
}

"=== seed: type abc + Enter so the textarea is not empty (kills the placeholder) ==="
CanType 'seed' | Out-Null
K 'a'; K 'b'; K 'c'; K 'ret'; Start-Sleep -Milliseconds 600

function Step([string]$name,[string]$out,[string[]]$keys){
  CanType $name | Out-Null
  K 'esc'; Start-Sleep -Milliseconds 350
  foreach($k in $keys){ CanType $name | Out-Null; K $k; Start-Sleep -Milliseconds 550 }
  Start-Sleep -Milliseconds 400
  "  [$name] keys=$($keys -join ',')  panel=$([SF]::Panel())"
  Snap $out
}

"=== 1) v (menu) ===";            Step 'v'   'r1_v'   @('v')
"=== 2) v 2 (clipboard) ===";     Step 'v2'  'r2_v2'  @('v','2')
"=== 3) v 3 (quick input) ===";   Step 'v3'  'r3_v3'  @('v','3')
"=== 4) v 4 (favorites) ===";     Step 'v4'  'r4_v4'  @('v','4')
"=== 5) v 5 (raw symbol mode -- must stay as a raw code) ==="; Step 'v5' 'r5_v5' @('v','5')
"=== 6) plain pinyin shi (regression) ==="; Step 'shi' 'r6_shi' @('s','h','i')

"=== 7) Backspace cancels the WHOLE input in every v function ==="
foreach($t in @(@('vclip',@('v','2')), @('vqi',@('v','3')), @('vfav',@('v','4')), @('v',@('v')))){
  $nm=$t[0]; $ks=$t[1]
  CanType "back-$nm" | Out-Null
  K 'esc'; Start-Sleep -Milliseconds 300
  foreach($k in $ks){ K $k; Start-Sleep -Milliseconds 550 }
  $before=[SF]::Panel()
  K 'back'; Start-Sleep -Milliseconds 800
  $after=[SF]::Panel()
  "  [back in $nm] panel before=$before after=$after"
}
Snap 'r7_after_back'
K 'esc'

"=== 8) v 2 then 1 commits the first clipboard entry ==="
CanType 'commit' | Out-Null
K 'esc'; Start-Sleep -Milliseconds 300
K 'v'; Start-Sleep -Milliseconds 650; K '2'; Start-Sleep -Milliseconds 900
Snap 'r8_v2_list'
K '1'; Start-Sleep -Milliseconds 1200
Snap 'r8b_committed'
K 'esc'
[void][SF]::Top($hwnd,$false)
"done: r1..r8 shots (+ _crop / _mirror)"
