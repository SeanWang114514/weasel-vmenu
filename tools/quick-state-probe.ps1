# Quick state probe: is the IME still in Chinese mode? does v2 still work?
# ASCII-only source on purpose.
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;using System.Runtime.InteropServices;using System.Text;using System.Threading;
public class Q {
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
 [DllImport("user32.dll")]public static extern bool SetProcessDPIAware();
 public struct R{public int L,T,Rr,B;}
 public delegate bool EnumProc(IntPtr h,IntPtr l);
 static Q(){ SetProcessDPIAware(); }
 public static void Tap(byte vk){ byte sc=(byte)MapVirtualKey(vk,0);
   keybd_event(vk,sc,0,UIntPtr.Zero); Thread.Sleep(60);
   keybd_event(vk,sc,2,UIntPtr.Zero); Thread.Sleep(200); }
 public static string Panel(){ string res="none";
   EnumWindows((h,l)=>{ if(!IsWindowVisible(h))return true;
     var c=new StringBuilder(64); GetClassName(h,c,64);
     if(c.ToString().StartsWith("ATL:")){ var r=new R(); GetWindowRect(h,out r);
       res=(r.Rr-r.L)+"x"+(r.B-r.T);} return true;},IntPtr.Zero);
   return res; }
 public static IntPtr FindByTitle(string t){ IntPtr res=IntPtr.Zero;
   EnumWindows((h,l)=>{ if(!IsWindowVisible(h))return true;
     var sb=new StringBuilder(300); GetWindowText(h,sb,300);
     if(sb.ToString().Contains(t)){res=h;return false;} return true;},IntPtr.Zero);
   return res; }
 [DllImport("user32.dll")]public static extern bool EnumChildWindows(IntPtr p,EnumProc cb,IntPtr l);
 [DllImport("user32.dll",CharSet=CharSet.Auto)]public static extern IntPtr SendMessage(IntPtr h,uint m,IntPtr w,string l);
 public static void ClearText(IntPtr pad){
   if(pad==IntPtr.Zero) return;
   IntPtr child=IntPtr.Zero;
   EnumChildWindows(pad,(h,l)=>{ var c=new StringBuilder(64); GetClassName(h,c,64);
     if(c.ToString().IndexOf("EDIT")>=0){child=h;return false;} return true;},IntPtr.Zero);
   if(child!=IntPtr.Zero) SendMessage(child,0x000C,IntPtr.Zero,""); }
 public static bool Focus(IntPtr hwnd){
   ShowWindow(hwnd,9); Thread.Sleep(200);
   uint zpid=0; uint tid1=GetWindowThreadProcessId(GetForegroundWindow(),out zpid); uint tid2=GetCurrentThreadId();
   AttachThreadInput(tid1,tid2,true); BringWindowToTop(hwnd); SetForegroundWindow(hwnd); AttachThreadInput(tid1,tid2,false);
   Thread.Sleep(250);
   return GetForegroundWindow()==hwnd; }
}
'@
$hwnd=[Q]::FindByTitle('IME TEST PAD')
if($hwnd -eq [IntPtr]::Zero){ 'NO TEST PAD'; exit 1 }
[void][Q]::Focus($hwnd); Start-Sleep -Milliseconds 400
function Tap([int]$vk){ if([Q]::GetForegroundWindow() -ne $hwnd){ [void][Q]::Focus($hwnd); Start-Sleep -Milliseconds 400 }; [Q]::Tap([byte]$vk) }
function Doc { (Get-Content 'D:\weasel-build\tst\typed.txt' -Raw -Encoding UTF8 -EA SilentlyContinue) }
function Clr { [IO.File]::WriteAllText('D:\weasel-build\tst\typed.txt','',(New-Object Text.UTF8Encoding($false))); [Q]::ClearText($hwnd); Start-Sleep -Milliseconds 300 }

'TAP 1: plain typing shi + space (expect a hanzi if Chinese mode is on)'
Clr; Tap 0x53; Tap 0x48; Tap 0x49; Start-Sleep -Milliseconds 600
"   panel = $([Q]::Panel())"
Tap 0x20; Start-Sleep -Milliseconds 600
"   doc = <$(Doc)>   (empty/literal 'shi' = ascii mode stuck)"

'TAP 2: v then 2 (expect clipboard list panel)'
Clr; Tap 0x56; Start-Sleep -Milliseconds 600
"   after v : panel = $([Q]::Panel())"
Tap 0x32; Start-Sleep -Milliseconds 700
"   after 2 : panel = $([Q]::Panel())"
"   doc = <$(Doc)>   (must be empty; 'vclip' = leak)"
Tap 0x1B; Start-Sleep -Milliseconds 400

'TAP 3: v2 then plain = (page next, no shift involved)'
Clr; Tap 0x56; Start-Sleep -Milliseconds 500; Tap 0x32; Start-Sleep -Milliseconds 700
"   page0 panel = $([Q]::Panel())"
Tap 0xBB; Start-Sleep -Milliseconds 800
"   after '=' : panel = $([Q]::Panel())"
"   doc = <$(Doc)>   (must be empty; 'vclip' = leak)"
Tap 0x1B
'done'
