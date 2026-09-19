Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;using System.Runtime.InteropServices;using System.Text;
public class TD{
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
 [DllImport("user32.dll")]public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")]public static extern void mouse_event(uint f,uint x,uint y,uint d,UIntPtr e);
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
 public static string Title(IntPtr h){var sb=new StringBuilder(300);GetWindowText(h,sb,300);return sb.ToString();}
 public static string Rect(IntPtr h){var r=new R();GetWindowRect(h,out r);return r.L+","+r.T+","+r.Rr+","+r.B;}
 // 用真实鼠标点击把焦点交给目标窗口（比 SetForegroundWindow 可靠）
 public static bool ClickFocus(IntPtr hwnd){
   ShowWindow(hwnd,9); MoveWindow(hwnd,40,20,1240,700,true); System.Threading.Thread.Sleep(400);
   var r=new R(); GetWindowRect(hwnd,out r);
   int cx=(r.L+r.Rr)/2, cy=r.T+200;      // 页面里 textarea 的位置
   SetCursorPos(cx,cy); System.Threading.Thread.Sleep(150);
   mouse_event(0x0002,0,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(60);
   mouse_event(0x0004,0,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(400);
   return GetForegroundWindow()==hwnd;
 }
}
'@
$VK=@{ 'a'=0x41;'b'=0x42;'c'=0x43;'d'=0x44;'e'=0x45;'f'=0x46;'g'=0x47;'h'=0x48;'i'=0x49;'j'=0x4A;'k'=0x4B;'l'=0x4C;'m'=0x4D;'n'=0x4E;'o'=0x4F;'p'=0x50;'q'=0x51;'r'=0x52;'s'=0x53;'t'=0x54;'u'=0x55;'v'=0x56;'w'=0x57;'x'=0x58;'y'=0x59;'z'=0x5A;
 '0'=0x30;'1'=0x31;'2'=0x32;'3'=0x33;'4'=0x34;'5'=0x35;'6'=0x36;'7'=0x37;'8'=0x38;'9'=0x39;'esc'=0x1B;'space'=0x20;'del'=0x2E;'back'=0x08 }
function K([string]$k){ [TD]::Tap([byte]$VK[$k]) }
function Clr { [TD]::TapMod(0x11,0x41); K 'del'; Start-Sleep -Milliseconds 400 }
function WebShot([string]$p){ $bmp=New-Object Drawing.Bitmap 1300,760; $g=[Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen(20,10,0,0,(New-Object Drawing.Size(1300,760))); $bmp.Save($p,[Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose() }

# 先把残留的测试窗口全部关掉，否则它们会抢走按键
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'ime-notepad' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force; "  关掉残留测试窗口 pid=$($_.ProcessId)" }
Start-Sleep -Milliseconds 600

$hwnd=[TD]::FindByTitle('IME WEB TEST')
if($hwnd -eq [IntPtr]::Zero){ "❌ 没找到网页窗口"; exit 1 }
$focused=[TD]::ClickFocus($hwnd)
"网页窗口 = $([TD]::Title($hwnd))"
"rect = $([TD]::Rect($hwnd))"
"点击后焦点交给网页 = $focused （前台窗口标题 = <$([TD]::Title([TD]::GetForegroundWindow()))>）"
K 'esc'; Start-Sleep -Milliseconds 300

"=== A) 网页里 v→2 打开剪贴板，再按 Backspace = 取消这次输入 ==="
Clr
K 'v'; Start-Sleep -Milliseconds 800; "   v 菜单 = $([TD]::Panel())"
K '2'; Start-Sleep -Milliseconds 1000; "   剪贴板列表 = $([TD]::Panel())"
K 'back'; Start-Sleep -Milliseconds 1000
"   按 Backspace 后 = $([TD]::Panel())（期望 none，且页面里什么都没上屏）"
WebShot 'D:\weasel-build\shots\x1_v2_backspace.png' | Out-Null

"=== B) 网页里 v→2 后按 1 = 上屏第一条剪贴板 ==="
Clr; K 'esc'; K 'v'; Start-Sleep -Milliseconds 800; K '2'; Start-Sleep -Milliseconds 1000
K '1'; Start-Sleep -Milliseconds 1100; "   候选窗 = $([TD]::Panel())"
WebShot 'D:\weasel-build\shots\x2_v2_commit.png' | Out-Null

"=== C) 网页里 v→3→c 计算 1+2*3 ==="
Clr; K 'esc'; K 'v'; Start-Sleep -Milliseconds 800; K '3'; Start-Sleep -Milliseconds 900
K 'c'; Start-Sleep -Milliseconds 800; K '1'; K '2'; K '3'; Start-Sleep -Milliseconds 900
K 'space'; Start-Sleep -Milliseconds 1000; "   候选窗 = $([TD]::Panel())"
WebShot 'D:\weasel-build\shots\x3_calc.png' | Out-Null

"=== D) 网页里普通拼音 shi + 空格 ==="
Clr; K 'esc'; K 's'; K 'h'; K 'i'; Start-Sleep -Milliseconds 800; K 'space'; Start-Sleep -Milliseconds 1000
WebShot 'D:\weasel-build\shots\x4_pinyin.png' | Out-Null
K 'esc'
"截图完成：x1/x2/x3/x4"
