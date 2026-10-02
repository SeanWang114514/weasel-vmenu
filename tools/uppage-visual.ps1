# (B) 视觉验收（自包含）：在一个 PowerShell 进程里完成「聚焦 → 按键 → 截候选窗 → 存图」，
# 中间不启动子进程、不打印，避免焦点被抢走。
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;using System.Runtime.InteropServices;using System.Text;using System.Collections.Generic;
public class BV{
 [DllImport("user32.dll")]public static extern void keybd_event(byte vk,byte sc,uint f,UIntPtr e);
 [DllImport("user32.dll")]public static extern uint MapVirtualKey(uint c,uint t);
 [DllImport("user32.dll")]public static extern bool EnumWindows(P cb,IntPtr l);
 [DllImport("user32.dll")]public static extern int GetClassName(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")]public static extern bool GetWindowRect(IntPtr h,out R r);
 [DllImport("user32.dll")]public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")]public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")]public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")]public static extern int GetWindowText(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")]public static extern bool BringWindowToTop(IntPtr h);
 [DllImport("user32.dll")]public static extern bool ShowWindow(IntPtr h,int c);
 [DllImport("user32.dll")]public static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 [DllImport("kernel32.dll")]public static extern uint GetCurrentThreadId();
 [DllImport("user32.dll")]public static extern bool AttachThreadInput(uint a,uint b,bool f);
 public struct R{public int L,T,Rr,B;}
 public delegate bool P(IntPtr h,IntPtr l);
 public static void Tap(byte vk){byte sc=(byte)MapVirtualKey(vk,0);keybd_event(vk,sc,0,UIntPtr.Zero);System.Threading.Thread.Sleep(50);keybd_event(vk,sc,2,UIntPtr.Zero);System.Threading.Thread.Sleep(140);}
 public static bool Rect(out int l,out int t,out int w,out int h){
   int rl=0,rt=0,rw=0,rh=0; bool f=false;
   EnumWindows((hh,li)=>{ if(!IsWindowVisible(hh))return true;
     var c=new StringBuilder(128);GetClassName(hh,c,128);
     if(c.ToString().StartsWith("ATL:")){ var r=new R();GetWindowRect(hh,out r);
       if(r.Rr-r.L>1 && r.B-r.T>1){ rl=r.L;rt=r.T;rw=r.Rr-r.L;rh=r.B-r.T; f=true; } }
     return true;},IntPtr.Zero);
   l=rl;t=rt;w=rw;h=rh; return f; }
 public static IntPtr Find(string t){IntPtr res=IntPtr.Zero;EnumWindows((h,l)=>{if(!IsWindowVisible(h))return true;var sb=new StringBuilder(300);GetWindowText(h,sb,300);
  if(sb.ToString().Contains(t)){res=h;return false;} return true;},IntPtr.Zero);return res;}
 public static string FG(){ var sb=new StringBuilder(300); GetWindowText(GetForegroundWindow(),sb,300); return sb.ToString(); }
 public static bool Focus(IntPtr hwnd){
   ShowWindow(hwnd,9); System.Threading.Thread.Sleep(150);
   uint zpid=0; uint tid1=GetWindowThreadProcessId(GetForegroundWindow(),out zpid); uint tid2=GetCurrentThreadId();
   AttachThreadInput(tid1,tid2,true); BringWindowToTop(hwnd); SetForegroundWindow(hwnd); AttachThreadInput(tid1,tid2,false);
   System.Threading.Thread.Sleep(200); return GetForegroundWindow()==hwnd; }
}
'@

$outDir = 'D:\VibeCoding\输入法\repo\weasel-vmenu\shots\cfg'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

function Shoot([string]$name){
  $l=0;$t=0;$w=0;$h=0
  if(-not [BV]::Rect([ref]$l,[ref]$t,[ref]$w,[ref]$h)){ return "NOPANEL" }
  $bmp = New-Object Drawing.Bitmap $w, $h
  $g = [Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($l, $t, 0, 0, (New-Object Drawing.Size($w,$h)))
  $bmp.Save((Join-Path $outDir "$name.png"))
  $g.Dispose(); $bmp.Dispose()
  return "${w}x${h}@${l},${t}"
}

$h=[BV]::Find('Notepad')
if($h -eq [IntPtr]::Zero){ "找不到记事本"; exit 1 }
[void][BV]::Focus($h)

$VK = @{ s=0x53;h=0x48;i=0x49;y=0x59;a=0x41;n=0x4E;down=0x28;up=0x26;equal=0xBB;esc=0x1B }
function T([string]$k){ [BV]::Tap([byte]$VK[$k]) }

T 'esc'
foreach($c in @('s','h','i','y','a','n')){ T $c }
$res = @()
$res += "1) 收起态         -> $(Shoot 'B20-collapsed')"

T 'down'
$res += "2) 展开-第1行     -> $(Shoot 'B21-exp-row1')"

T 'down'; T 'down'; T 'down'
$res += "3) 展开-第4行     -> $(Shoot 'B22-exp-row4')"

T 'up'; T 'up'; T 'up'
$res += "4) 回-第1行       -> $(Shoot 'B23-exp-row1b')"

T 'equal'
$res += "5) 翻页后-第1行   -> $(Shoot 'B24-page2-row1')"

T 'up'
$res += "6) **UP 之后**    -> $(Shoot 'B25-after-up')"

T 'esc'
$res += "7) esc 之后       -> $(Shoot 'B26-after-esc')"

$res | ForEach-Object { $_ }
