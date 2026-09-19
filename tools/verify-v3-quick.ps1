Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;using System.Runtime.InteropServices;using System.Text;
public class T5{
 [DllImport("user32.dll")]public static extern void keybd_event(byte vk,byte sc,uint f,UIntPtr e);
 [DllImport("user32.dll")]public static extern uint MapVirtualKey(uint c,uint t);
 [DllImport("user32.dll")]public static extern bool EnumWindows(EnumProc cb,IntPtr l);
 [DllImport("user32.dll")]public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")]public static extern bool GetWindowRect(IntPtr h,out R r);
 [DllImport("user32.dll")]public static extern int GetClassName(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")]public static extern int GetWindowText(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")]public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")]public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")]public static extern bool BringWindowToTop(IntPtr h);
 [DllImport("user32.dll")]public static extern bool ShowWindow(IntPtr h,int c);
 [DllImport("user32.dll")]public static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 [DllImport("kernel32.dll")]public static extern uint GetCurrentThreadId();
 [DllImport("user32.dll")]public static extern bool AttachThreadInput(uint a,uint b,bool f);
 public struct R{public int L,T,Rr,B;}
 public delegate bool EnumProc(IntPtr h,IntPtr l);
 public static void Tap(byte vk){byte sc=(byte)MapVirtualKey(vk,0);keybd_event(vk,sc,0,UIntPtr.Zero);System.Threading.Thread.Sleep(60);keybd_event(vk,sc,2,UIntPtr.Zero);System.Threading.Thread.Sleep(170);}
 public static void TapMod(byte mod,byte vk){byte sc=(byte)MapVirtualKey(vk,0);keybd_event(mod,0,0,UIntPtr.Zero);System.Threading.Thread.Sleep(30);keybd_event(vk,sc,0,UIntPtr.Zero);System.Threading.Thread.Sleep(50);keybd_event(vk,sc,2,UIntPtr.Zero);System.Threading.Thread.Sleep(30);keybd_event(mod,0,2,UIntPtr.Zero);System.Threading.Thread.Sleep(170);}
 public static string Panel(){string res="none";EnumWindows((h,l)=>{if(!IsWindowVisible(h))return true;var c=new StringBuilder(64);GetClassName(h,c,64);
  if(c.ToString().StartsWith("ATL:")){var r=new R();GetWindowRect(h,out r);res=(r.Rr-r.L)+"x"+(r.B-r.T);} return true;},IntPtr.Zero);return res;}
 public static IntPtr FindByTitle(string t){IntPtr res=IntPtr.Zero;EnumWindows((h,l)=>{if(!IsWindowVisible(h))return true;var sb=new StringBuilder(300);GetWindowText(h,sb,300);
  if(sb.ToString().Contains(t)){res=h;return false;} return true;},IntPtr.Zero);return res;}
 public static bool Focus(IntPtr hwnd){
   ShowWindow(hwnd,9); System.Threading.Thread.Sleep(200);
   uint zpid=0; uint tid1=GetWindowThreadProcessId(GetForegroundWindow(),out zpid); uint tid2=GetCurrentThreadId();
   AttachThreadInput(tid1,tid2,true); BringWindowToTop(hwnd); SetForegroundWindow(hwnd); AttachThreadInput(tid1,tid2,false);
   System.Threading.Thread.Sleep(250);
   if(GetForegroundWindow()!=hwnd){
     keybd_event(0x12,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(40); keybd_event(0x12,0,2,UIntPtr.Zero);
     System.Threading.Thread.Sleep(80); SetForegroundWindow(hwnd); System.Threading.Thread.Sleep(250); }
   return GetForegroundWindow()==hwnd; }
}
'@
$VK=@{ 'a'=0x41;'b'=0x42;'c'=0x43;'d'=0x44;'e'=0x45;'f'=0x46;'g'=0x47;'h'=0x48;'i'=0x49;'j'=0x4A;'k'=0x4B;'l'=0x4C;'m'=0x4D;'n'=0x4E;'o'=0x4F;'p'=0x50;'q'=0x51;'r'=0x52;'s'=0x53;'t'=0x54;'u'=0x55;'v'=0x56;'w'=0x57;'x'=0x58;'y'=0x59;'z'=0x5A;
 '0'=0x30;'1'=0x31;'2'=0x32;'3'=0x33;'4'=0x34;'5'=0x35;'6'=0x36;'7'=0x37;'8'=0x38;'9'=0x39;'esc'=0x1B;'space'=0x20;'enter'=0x0D;'del'=0x2E }
function Key([string]$k){ [T5]::Tap([byte]$VK[$k]) }
function Shot([string]$p){ $bmp=New-Object Drawing.Bitmap 1400,700; $g=[Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen(0,0,0,0,(New-Object Drawing.Size(1400,700))); $bmp.Save($p,[Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose() }
function Doc { (Get-Content 'D:\weasel-build\tst\typed.txt' -Raw -EA SilentlyContinue) }
function Clear { [IO.File]::WriteAllText('D:\weasel-build\tst\typed.txt','',(New-Object Text.UTF8Encoding($false))); [T5]::TapMod(0x11,0x41); Key 'del'; Start-Sleep -Milliseconds 400 }

$hwnd=[T5]::FindByTitle('IME TEST PAD')
if($hwnd -eq [IntPtr]::Zero){
  Start-Process powershell.exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','D:\weasel-build\tst\ime-notepad.ps1' | Out-Null
  for($i=1;$i -le 20;$i++){ Start-Sleep -Seconds 1; $hwnd=[T5]::FindByTitle('IME TEST PAD'); if($hwnd -ne [IntPtr]::Zero){ break } }
}
if($hwnd -eq [IntPtr]::Zero){ "❌ 没找到测试窗口"; exit 1 }
"测试窗口聚焦=$([T5]::Focus($hwnd))"
Key 'esc'

"=== A) v → 3：子菜单应只剩 6 项 + 返回 ==="
Clear; Key 'esc'
Key 'v'; Start-Sleep -Milliseconds 700; "   v 菜单 = $([T5]::Panel())"
Key '3'; Start-Sleep -Milliseconds 900; "   子菜单 = $([T5]::Panel())"
Shot 'D:\weasel-build\shots\g1_quick6.png' | Out-Null
Key 'esc'; Start-Sleep -Milliseconds 400

"=== B) v3c（按 c）= 计算 ==="
Clear; Key 'esc'; Key 'v'; Start-Sleep -Milliseconds 600; Key '3'; Start-Sleep -Milliseconds 800; Key 'c'; Start-Sleep -Milliseconds 700
"   按 c 后候选窗 = $([T5]::Panel())"
Key '1'; [T5]::TapMod(0x10,0xBB); Key '2'; [T5]::TapMod(0x10,0x38); Key '3'; Start-Sleep -Milliseconds 700
"   敲 1+2*3 后候选窗 = $([T5]::Panel())"
Shot 'D:\weasel-build\shots\g2_v3c.png' | Out-Null
Key 'space'; Start-Sleep -Milliseconds 900
"   ★ 上屏 = <$(Doc)>"

"=== C) v3h（按 h）= 数字货币转写（R）==="
Clear; Key 'esc'; Key 'v'; Start-Sleep -Milliseconds 600; Key '3'; Start-Sleep -Milliseconds 800; Key 'h'; Start-Sleep -Milliseconds 700
"   按 h 后候选窗 = $([T5]::Panel())"
Key '1'; Key '2'; Key '3'; Start-Sleep -Milliseconds 700
Shot 'D:\weasel-build\shots\g3_v3h.png' | Out-Null
Key 'space'; Start-Sleep -Milliseconds 900
"   ★ 上屏 = <$(Doc)>"

"=== D) v3u（按 u）= Unicode ==="
Clear; Key 'esc'; Key 'v'; Start-Sleep -Milliseconds 600; Key '3'; Start-Sleep -Milliseconds 800; Key 'u'; Start-Sleep -Milliseconds 700
Key '4'; Key 'e'; Key '2'; Key 'd'; Start-Sleep -Milliseconds 800
"   候选窗 = $([T5]::Panel())"
Shot 'D:\weasel-build\shots\g4_v3u.png' | Out-Null
Key 'space'; Start-Sleep -Milliseconds 900
"   ★ 上屏 = <$(Doc)>"

"=== E) v3n（按 n）= 农历 ==="
Clear; Key 'esc'; Key 'v'; Start-Sleep -Milliseconds 600; Key '3'; Start-Sleep -Milliseconds 800; Key 'n'; Start-Sleep -Milliseconds 900
"   按 n 后候选窗 = $([T5]::Panel())"
Shot 'D:\weasel-build\shots\g5_v3n.png' | Out-Null
Key 'space'; Start-Sleep -Milliseconds 900
"   ★ 上屏 = <$(Doc)>"

"=== F) v3r（按 r）= 日期 / v3s（按 s）= 时间 ==="
Clear; Key 'esc'; Key 'v'; Start-Sleep -Milliseconds 600; Key '3'; Start-Sleep -Milliseconds 800; Key 'r'; Start-Sleep -Milliseconds 900
"   日期候选窗 = $([T5]::Panel())"
Key 'space'; Start-Sleep -Milliseconds 800
Clear; Key 'esc'; Key 'v'; Start-Sleep -Milliseconds 600; Key '3'; Start-Sleep -Milliseconds 800; Key 's'; Start-Sleep -Milliseconds 900
"   时间候选窗 = $([T5]::Panel())"
Key 'space'; Start-Sleep -Milliseconds 800
"   ★ 上屏 = <$(Doc)>"

"=== G) 回归：直接输入原前缀 cC（不走菜单）==="
Clear; Key 'esc'; Key 'c'; Key 'C'; Key '1'; [T5]::TapMod(0x10,0xBB); Key '2'; Start-Sleep -Milliseconds 800
"   候选窗 = $([T5]::Panel())"
Key 'space'; Start-Sleep -Milliseconds 900
"   ★ 上屏 = <$(Doc)>"

"=== H) 回归：v 菜单主菜单仍是 5 项 ==="
Clear; Key 'esc'; Key 'v'; Start-Sleep -Milliseconds 800
"   主菜单 = $([T5]::Panel())（842 宽 = 5 项主菜单）"
Key 'esc'
