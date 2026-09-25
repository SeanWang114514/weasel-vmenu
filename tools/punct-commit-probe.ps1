# Focused probe: does punctuation inside v2 commit anything? And does Clr really clear?
# ASCII-only source on purpose.
Add-Type -TypeDefinition @'
using System;using System.Runtime.InteropServices;using System.Text;using System.Threading;
public class P2 {
 [DllImport("user32.dll")]public static extern void keybd_event(byte vk,byte sc,uint f,UIntPtr e);
 [DllImport("user32.dll")]public static extern uint MapVirtualKey(uint c,uint t);
 [DllImport("user32.dll")]public static extern bool EnumWindows(EnumProc cb,IntPtr l);
 [DllImport("user32.dll")]public static extern bool IsWindowVisible(IntPtr h);
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
 public delegate bool EnumProc(IntPtr h,IntPtr l);
 static P2(){ SetProcessDPIAware(); }
 public static void Tap(byte vk){ byte sc=(byte)MapVirtualKey(vk,0);
   keybd_event(vk,sc,0,UIntPtr.Zero); Thread.Sleep(70);
   keybd_event(vk,sc,2,UIntPtr.Zero); Thread.Sleep(220); }
 [DllImport("user32.dll")]public static extern bool EnumChildWindows(IntPtr p,EnumProc cb,IntPtr l);
 [DllImport("user32.dll",CharSet=CharSet.Auto)]public static extern IntPtr SendMessage(IntPtr h,uint m,IntPtr w,string l);
 public static bool ClearText(IntPtr pad){
   if(pad==IntPtr.Zero) return false;
   IntPtr child=IntPtr.Zero;
   EnumChildWindows(pad,(h,l)=>{ var c=new StringBuilder(64); GetClassName(h,c,64);
     if(c.ToString().IndexOf("EDIT")>=0){child=h;return false;} return true;},IntPtr.Zero);
   if(child==IntPtr.Zero) return false;
   SendMessage(child,0x000C,IntPtr.Zero,"");
   return true; }
 public static IntPtr FindByTitle(string t){ IntPtr res=IntPtr.Zero;
   EnumWindows((h,l)=>{ if(!IsWindowVisible(h))return true;
     var sb=new StringBuilder(300); GetWindowText(h,sb,300);
     if(sb.ToString().Contains(t)){res=h;return false;} return true;},IntPtr.Zero);
   return res; }
 public static bool Focus(IntPtr hwnd){
   ShowWindow(hwnd,9); Thread.Sleep(200);
   uint zpid=0; uint tid1=GetWindowThreadProcessId(GetForegroundWindow(),out zpid); uint tid2=GetCurrentThreadId();
   AttachThreadInput(tid1,tid2,true); BringWindowToTop(hwnd); SetForegroundWindow(hwnd); AttachThreadInput(tid1,tid2,false);
   Thread.Sleep(250); return GetForegroundWindow()==hwnd; }
}
'@
$VK=@{ 'v'=0x56;'2'=0x32;'comma'=0xBC;'period'=0xBE;'semicolon'=0xBA;'quote'=0xDE;'rbracket'=0xDD;'grave'=0xC0;'3'=0x33;'esc'=0x1B;'a'=0x41 }
$hwnd=[P2]::FindByTitle('IME TEST PAD')
if($hwnd -eq [IntPtr]::Zero){ 'NO TEST PAD'; exit 1 }
[void][P2]::Focus($hwnd); Start-Sleep -Milliseconds 400
function Tap([int]$vk){ if([P2]::GetForegroundWindow() -ne $hwnd){ [void][P2]::Focus($hwnd); Start-Sleep -Milliseconds 400 }; [P2]::Tap([byte]$vk) }
function Doc { $t = (Get-Content 'D:\weasel-build\tst\typed.txt' -Raw -Encoding UTF8 -EA SilentlyContinue); if($null -eq $t){ $t='' }; if($t.Length -gt 100){ '<'+$t.Length+' chars> '+$t.Substring(0,100) } else { $t } }
function Clr { [IO.File]::WriteAllText('D:\weasel-build\tst\typed.txt','',(New-Object Text.UTF8Encoding($false))); $ok=[P2]::ClearText($hwnd); Start-Sleep -Milliseconds 350; "   [clr ok=$ok doc now= <$(Doc)>]" }
foreach($k in @('period','semicolon','rbracket','grave','comma','3')){
  "--- v2 + key=$k ---"
  Clr
  Tap 0x56; Start-Sleep -Milliseconds 600
  Tap 0x32; Start-Sleep -Milliseconds 700
  Tap $VK[$k]; Start-Sleep -Milliseconds 800
  "   after key: doc= <$(Doc)>"
  Tap 0x1B; Start-Sleep -Milliseconds 400
  "   after esc: doc= <$(Doc)>"
}
'--- done ---'
