Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;using System.Runtime.InteropServices;using System.Text;using System.Collections.Generic;
public class IV{
 [DllImport("user32.dll")]public static extern void keybd_event(byte vk,byte sc,uint f,UIntPtr e);
 [DllImport("user32.dll")]public static extern uint MapVirtualKey(uint c,uint t);
 [DllImport("user32.dll")]public static extern bool EnumWindows(P cb,IntPtr l);
 [DllImport("user32.dll")]public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")]public static extern int GetClassName(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")]public static extern bool GetWindowRect(IntPtr h,out R r);
 [DllImport("user32.dll")]public static extern int GetWindowText(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")]public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")]public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")]public static extern bool BringWindowToTop(IntPtr h);
 [DllImport("user32.dll")]public static extern bool ShowWindow(IntPtr h,int c);
 [DllImport("user32.dll")]public static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 [DllImport("kernel32.dll")]public static extern uint GetCurrentThreadId();
 [DllImport("user32.dll")]public static extern bool AttachThreadInput(uint a,uint b,bool f);
 public struct R{public int L,T,Rr,B;}
 public delegate bool P(IntPtr h,IntPtr l);
 public static void Tap(byte vk){byte sc=(byte)MapVirtualKey(vk,0);keybd_event(vk,sc,0,UIntPtr.Zero);System.Threading.Thread.Sleep(55);keybd_event(vk,sc,2,UIntPtr.Zero);System.Threading.Thread.Sleep(150);}
 // ★ 候选窗由**客户端进程**创建（ATL: 类名），要按 pid 找
 public static string Panel(uint wantPid){
   var res=new List<string>();
   EnumWindows((h,l)=>{ if(!IsWindowVisible(h))return true;
     uint pid=0; GetWindowThreadProcessId(h,out pid);
     if(pid!=wantPid) return true;
     var c=new StringBuilder(128);GetClassName(h,c,128);
     if(c.ToString().StartsWith("ATL:")){ var r=new R();GetWindowRect(h,out r);
       res.Add(string.Format("{0}x{1} @{2},{3}",r.Rr-r.L,r.B-r.T,r.L,r.T)); }
     return true;},IntPtr.Zero);
   return res.Count==0? "none" : string.Join(" ; ",res); }
 public static IntPtr Find(string t){IntPtr res=IntPtr.Zero;EnumWindows((h,l)=>{if(!IsWindowVisible(h))return true;var sb=new StringBuilder(300);GetWindowText(h,sb,300);
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
 public static string Text(uint pid){
   string res="";
   EnumWindows((h,l)=>{ uint p=0; GetWindowThreadProcessId(h,out p);
     if(p==pid && IsWindowVisible(h)){ var sb=new StringBuilder(300);GetWindowText(h,sb,300);
       if(sb.Length>0) res+="["+sb+"]"; }
     return true;},IntPtr.Zero);
   return res; }
}
'@

$target = 'notepad'
$log = "$PSScriptRoot\..\..\..\tmp\uppage-measure.txt"

# 目标进程（记事本）—— 可能残留多个，全杀掉再起一个
Get-Process notepad -EA SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 1200
Start-Process notepad
Start-Sleep -Seconds 3
$np = @(Get-Process notepad | Sort-Object Id -Descending)
$pidNp = [uint32]$np[0].Id
"记事本 pid=$pidNp  (共 $($np.Count) 个)"
$h=[IV]::Find('Notepad')
"hwnd=$h  focus=$([IV]::Focus($h))"

$VK = @{ 's'=0x53;'h'=0x48;'i'=0x49;'y'=0x59;'a'=0x41;'n'=0x4E;'e'=0x45;'q'=0x51;'u'=0x55;'space'=0x20;'esc'=0x1B;'down'=0x28;'up'=0x26;'equal'=0xBB }
function T([string]$k){ [IV]::Tap([byte]$VK[$k]) }

""
"=== 逐状态测量候选窗（由客户端进程 $pidNp 创建）==="
T 'esc'
foreach($c in @('s','h','i','y','a','n')){ T $c }
Start-Sleep -Milliseconds 900
"1) 收起态   : $([IV]::Panel($pidNp))"
T 'down'; Start-Sleep -Milliseconds 900
"2) 展开态   : $([IV]::Panel($pidNp))"
T 'equal'; Start-Sleep -Milliseconds 900
"3) 翻页后   : $([IV]::Panel($pidNp))"
T 'up'; Start-Sleep -Milliseconds 900
"4) ↑ 之后   : $([IV]::Panel($pidNp))   ← (B) 核心断言：应仍 ≈ 展开态高度"
T 'esc'; Start-Sleep -Milliseconds 600
"5) esc 后   : $([IV]::Panel($pidNp))"
