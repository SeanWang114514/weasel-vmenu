Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;using System.Runtime.InteropServices;using System.Text;
public class T4{
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
 [DllImport("user32.dll")]public static extern bool MoveWindow(IntPtr h,int x,int y,int w,int t,bool r);
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
function Shot([string]$p){ $bmp=New-Object Drawing.Bitmap 1400,700; $g=[Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen(0,0,0,0,(New-Object Drawing.Size(1400,700))); $bmp.Save($p,[Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose() }
function Doc { (Get-Content 'D:\weasel-build\tst\typed.txt' -Raw -EA SilentlyContinue) }
function Clear { [IO.File]::WriteAllText('D:\weasel-build\tst\typed.txt','',(New-Object Text.UTF8Encoding($false))); [T4]::TapMod(0x11,0x41); [T4]::Tap(0x2E); Start-Sleep -Milliseconds 400 }

Start-Process powershell.exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','D:\weasel-build\tst\ime-notepad.ps1' | Out-Null
Start-Sleep -Seconds 4
$hwnd=[T4]::FindByTitle('IME TEST PAD')
if($hwnd -eq [IntPtr]::Zero){ "❌ 没找到测试窗口"; exit 1 }
$ok=[T4]::Focus($hwnd)
"测试窗口句柄=$hwnd 聚焦=$ok"
[T4]::Tap(0x1B); Start-Sleep -Milliseconds 300
"探针（敲 v）候选窗 = $([T4]::Panel())"
[T4]::Tap(0x1B); Start-Sleep -Milliseconds 300

"=== 测试1：v→3→1（计算）后敲 1+2*3 ==="
Clear
[T4]::Tap(0x56); Start-Sleep -Milliseconds 700; "   v 菜单 = $([T4]::Panel())"
[T4]::Tap(0x33); Start-Sleep -Milliseconds 800; "   快捷输入 = $([T4]::Panel())"
[T4]::Tap(0x31); Start-Sleep -Milliseconds 800; "   计算模式 = $([T4]::Panel())"
[T4]::Tap(0x31); Start-Sleep -Milliseconds 200
[T4]::TapMod(0x10,0xBB); Start-Sleep -Milliseconds 200
[T4]::Tap(0x32); Start-Sleep -Milliseconds 200
[T4]::TapMod(0x10,0x38); Start-Sleep -Milliseconds 200
[T4]::Tap(0x33); Start-Sleep -Milliseconds 700
"   敲完 1+2*3 候选窗 = $([T4]::Panel())"
Shot 'D:\weasel-build\shots\f1_calc.png' | Out-Null
[T4]::Tap(0x20); Start-Sleep -Milliseconds 900
"   ★ 上屏后窗口文本 = <$(Doc)>"
Shot 'D:\weasel-build\shots\f1b_calc_done.png' | Out-Null

"=== 测试2：v→3→7（数字大写）后敲 123 ==="
Clear
[T4]::Tap(0x1B); Start-Sleep -Milliseconds 300
[T4]::Tap(0x56); Start-Sleep -Milliseconds 700
[T4]::Tap(0x33); Start-Sleep -Milliseconds 700
[T4]::Tap(0x37); Start-Sleep -Milliseconds 800; "   数字大写 = $([T4]::Panel())"
[T4]::Tap(0x31); [T4]::Tap(0x32); [T4]::Tap(0x33); Start-Sleep -Milliseconds 600
"   敲完 123 候选窗 = $([T4]::Panel())"
Shot 'D:\weasel-build\shots\f2_rmb.png' | Out-Null
[T4]::Tap(0x20); Start-Sleep -Milliseconds 900
"   ★ 上屏后窗口文本 = <$(Doc)>"

"=== 测试3（回归）：v→3→8（Unicode）后敲 4E00 ==="
Clear
[T4]::Tap(0x1B); Start-Sleep -Milliseconds 300
[T4]::Tap(0x56); Start-Sleep -Milliseconds 700
[T4]::Tap(0x33); Start-Sleep -Milliseconds 700
[T4]::Tap(0x38); Start-Sleep -Milliseconds 800; "   Unicode = $([T4]::Panel())"
[T4]::Tap(0x34); [T4]::Tap(0x45); [T4]::Tap(0x30); [T4]::Tap(0x30); Start-Sleep -Milliseconds 700
"   敲完 4E00 候选窗 = $([T4]::Panel())"
Shot 'D:\weasel-build\shots\f3_unicode.png' | Out-Null
"   ★ 窗口文本（未上屏）= <$(Doc)>"

"=== 测试4（回归）：纯数字编码 131 + 回车 ==="
Clear
[T4]::Tap(0x1B); Start-Sleep -Milliseconds 300
[T4]::Tap(0x31); [T4]::Tap(0x33); [T4]::Tap(0x31); Start-Sleep -Milliseconds 500
"   候选窗 = $([T4]::Panel())"
[T4]::Tap(0x0D); Start-Sleep -Milliseconds 900
"   ★ 上屏后窗口文本 = <$(Doc)>"

"=== 测试5（回归）：拼音 shi + 数字 3（应选词上屏）==="
Clear
[T4]::Tap(0x1B); Start-Sleep -Milliseconds 300
[T4]::Tap(0x53); [T4]::Tap(0x48); [T4]::Tap(0x49); Start-Sleep -Milliseconds 500
"   shi 候选窗 = $([T4]::Panel())"
[T4]::Tap(0x33); Start-Sleep -Milliseconds 900
"   ★ 按 3 后窗口文本 = <$(Doc)>   候选窗=$([T4]::Panel())"
Shot 'D:\weasel-build\shots\f5_shi3.png' | Out-Null
