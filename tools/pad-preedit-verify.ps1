# Verify the SECOND code path: non-TSF clients (WinForms = IMM32) use the server-side
# panel, i.e. RimeWithWeaselHandler::_GetContext(). The label must show up there too.
# ASCII only.
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;using System.Runtime.InteropServices;using System.Text;
public class SP{
 [DllImport("user32.dll")]public static extern void keybd_event(byte vk,byte sc,uint f,UIntPtr e);
 [DllImport("user32.dll")]public static extern uint MapVirtualKey(uint c,uint t);
 [DllImport("user32.dll")]public static extern bool EnumWindows(EnumProc cb,IntPtr l);
 [DllImport("user32.dll")]public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")]public static extern bool GetWindowRect(IntPtr h,out R r);
 [DllImport("user32.dll")]public static extern int GetWindowText(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")]public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")]public static extern IntPtr WindowFromPoint(P pt);
 [DllImport("user32.dll")]public static extern IntPtr GetAncestor(IntPtr h,uint f);
 [DllImport("user32.dll")]public static extern bool ShowWindow(IntPtr h,int c);
 [DllImport("user32.dll")]public static extern bool SetWindowPos(IntPtr h,IntPtr a,int x,int y,int w,int t,uint f);
 [DllImport("user32.dll")]public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")]public static extern void mouse_event(uint f,uint x,uint y,uint d,UIntPtr e);
 public struct R{public int L,T,Rr,B;} public struct P{public int X,Y;}
 public delegate bool EnumProc(IntPtr h,IntPtr l);
 public static readonly IntPtr TOPMOST=new IntPtr(-1), NOTOPMOST=new IntPtr(-2);
 public static void Tap(byte vk){byte sc=(byte)MapVirtualKey(vk,0);keybd_event(vk,sc,0,UIntPtr.Zero);System.Threading.Thread.Sleep(60);keybd_event(vk,sc,2,UIntPtr.Zero);System.Threading.Thread.Sleep(180);}
 public static IntPtr FindByTitle(string t){IntPtr res=IntPtr.Zero;EnumWindows((h,l)=>{if(!IsWindowVisible(h))return true;var sb=new StringBuilder(300);GetWindowText(h,sb,300);
  if(sb.ToString().Contains(t)){res=h;return false;} return true;},IntPtr.Zero);return res;}
 public static string Title(IntPtr h){var sb=new StringBuilder(300);GetWindowText(h,sb,300);return sb.ToString();}
 public static string Rect(IntPtr h){var r=new R();GetWindowRect(h,out r);return r.L+","+r.T+","+r.Rr+","+r.B;}
 public static IntPtr RootAt(int x,int y){var p=new P();p.X=x;p.Y=y;return GetAncestor(WindowFromPoint(p),2);}
 public static bool Top(IntPtr h,bool on){return SetWindowPos(h,on?TOPMOST:NOTOPMOST,60,40,900,380,0x0040);}
}
'@
$VK=@{ 'a'=0x41;'b'=0x42;'c'=0x43;'h'=0x48;'i'=0x49;'s'=0x53;'u'=0x55;'v'=0x56;'1'=0x31;'2'=0x32;'3'=0x33;'4'=0x34;'esc'=0x1B;'back'=0x08 }
function K([string]$k){ [SP]::Tap([byte]$VK[$k]) }
function Shot([string]$p,[int]$x,[int]$y,[int]$w,[int]$h){
  $bmp=New-Object Drawing.Bitmap $w,$h; $g=[Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($x,$y,0,0,(New-Object Drawing.Size($w,$h))); $bmp.Save($p,[Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose() }

# start a fresh pad
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'ime-notepad' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-Sleep -Milliseconds 500
Start-Process powershell.exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','D:\weasel-build\tst\ime-notepad.ps1'
Start-Sleep -Seconds 3
$hwnd=[SP]::FindByTitle('IME TEST PAD')
if($hwnd -eq [IntPtr]::Zero){ 'ABORT: pad window not found'; exit 1 }
[void][SP]::ShowWindow($hwnd,9); [void][SP]::Top($hwnd,$true); Start-Sleep -Milliseconds 700
$r=[SP]::Rect($hwnd); "pad rect = $r  title=<$([SP]::Title($hwnd))>"
# click inside the pad's textbox (client area, upper part)
$cx=500; $cy=180
$rootAt=[SP]::RootAt($cx,$cy)
"click point ($cx,$cy) root=$rootAt target=$hwnd same=$($rootAt -eq $hwnd)"
if($rootAt -ne $hwnd){ 'ABORT: pad is covered by another window'; exit 2 }
[void][SP]::SetCursorPos($cx,$cy); Start-Sleep -Milliseconds 200
[SP]::mouse_event(0x0002,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 80
[SP]::mouse_event(0x0004,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 500
$fg=[SP]::GetForegroundWindow()
"foreground=<$([SP]::Title($fg))> isPad=$($fg -eq $hwnd)"
if($fg -ne $hwnd){ 'ABORT: focus not on pad'; exit 3 }

K 'a'; K 'b'; K 'c'; Start-Sleep -Milliseconds 400   # seed some text
K 'esc'; Start-Sleep -Milliseconds 400
"=== pad: v then 2 (non-TSF path -> server panel) ==="
K 'v'; Start-Sleep -Milliseconds 700
Shot 'D:\weasel-build\shots\s1_pad_v.png' 40 20 1000 640
K '2'; Start-Sleep -Milliseconds 1000
Shot 'D:\weasel-build\shots\s2_pad_v2.png' 40 20 1000 640
"=== pad: backspace cancels the whole input ==="
K 'back'; Start-Sleep -Milliseconds 900
Shot 'D:\weasel-build\shots\s3_pad_back.png' 40 20 1000 640
K 'esc'
[void][SP]::Top($hwnd,$false)
"done: s1/s2/s3"