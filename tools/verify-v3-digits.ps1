Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;using System.Runtime.InteropServices;using System.Text;
public class TA{
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
 '0'=0x30;'1'=0x31;'2'=0x32;'3'=0x33;'4'=0x34;'5'=0x35;'6'=0x36;'7'=0x37;'8'=0x38;'9'=0x39;'esc'=0x1B;'space'=0x20;'del'=0x2E }
function K([string]$k){ [TA]::Tap([byte]$VK[$k]) }
function Doc { (Get-Content 'D:\weasel-build\tst\typed.txt' -Raw -EA SilentlyContinue) }
function Clr { [IO.File]::WriteAllText('D:\weasel-build\tst\typed.txt','',(New-Object Text.UTF8Encoding($false))); [TA]::TapMod(0x11,0x41); K 'del'; Start-Sleep -Milliseconds 350 }

$hwnd=[TA]::FindByTitle('IME TEST PAD')
if($hwnd -eq [IntPtr]::Zero){ "测试窗口不在"; exit 1 }
"聚焦=$([TA]::Focus($hwnd))"

"=== 数字按「屏幕标签」走：标签 4 = 农历输入 / 5 = 数字货币转写 / 6 = Unicode ==="
Clr; K 'esc'; K 'v'; Start-Sleep -Milliseconds 700; K '3'; Start-Sleep -Milliseconds 800
K '4'; Start-Sleep -Milliseconds 800; "  按 4 后候选窗 = $([TA]::Panel())（255 左右 = 农历 N+今天）"
K 'space'; Start-Sleep -Milliseconds 800; "  ★ 上屏 = <$(Doc)>"

Clr; K 'esc'; K 'v'; Start-Sleep -Milliseconds 700; K '3'; Start-Sleep -Milliseconds 800
K '5'; Start-Sleep -Milliseconds 800; "  按 5 后候选窗 = $([TA]::Panel())（827 左右 = R 数字/金额转写）"
K '1'; K '2'; K '3'; Start-Sleep -Milliseconds 500; K 'space'; Start-Sleep -Milliseconds 800
"  ★ 上屏 = <$(Doc)>"

Clr; K 'esc'; K 'v'; Start-Sleep -Milliseconds 700; K '3'; Start-Sleep -Milliseconds 800
K '6'; Start-Sleep -Milliseconds 800; "  按 6 后候选窗 = $([TA]::Panel())（1300 左右 = U Unicode）"
K '4'; K 'e'; K '2'; K 'd'; Start-Sleep -Milliseconds 500; K 'space'; Start-Sleep -Milliseconds 800
"  ★ 上屏 = <$(Doc)>"

"=== 字母仍然与顺序无关：u 永远是 Unicode ==="
Clr; K 'esc'; K 'v'; Start-Sleep -Milliseconds 700; K '3'; Start-Sleep -Milliseconds 800
K 'u'; K '4'; K 'e'; K '2'; K 'd'; Start-Sleep -Milliseconds 500; K 'space'; Start-Sleep -Milliseconds 800
"  ★ 上屏 = <$(Doc)>"
K 'esc'
