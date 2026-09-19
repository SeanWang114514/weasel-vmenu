Add-Type -TypeDefinition @'
using System;using System.Runtime.InteropServices;using System.Text;
public class TF{
 [DllImport("user32.dll")]public static extern void keybd_event(byte vk,byte sc,uint f,UIntPtr e);
 [DllImport("user32.dll")]public static extern uint MapVirtualKey(uint c,uint t);
 [DllImport("user32.dll")]public static extern bool EnumWindows(EnumProc cb,IntPtr l);
 [DllImport("user32.dll")]public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")]public static extern bool GetWindowRect(IntPtr h,out R r);
 [DllImport("user32.dll")]public static extern int GetClassName(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")]public static extern int GetWindowText(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")]public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")]public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")]public static extern void mouse_event(uint f,uint x,uint y,uint d,UIntPtr e);
 public struct R{public int L,T,Rr,B;}
 public delegate bool EnumProc(IntPtr h,IntPtr l);
 public static void Tap(byte vk){byte sc=(byte)MapVirtualKey(vk,0);keybd_event(vk,sc,0,UIntPtr.Zero);System.Threading.Thread.Sleep(60);keybd_event(vk,sc,2,UIntPtr.Zero);System.Threading.Thread.Sleep(170);}
 public static void TapMod(byte mod,byte vk){byte sc=(byte)MapVirtualKey(vk,0);keybd_event(mod,0,0,UIntPtr.Zero);System.Threading.Thread.Sleep(30);keybd_event(vk,sc,0,UIntPtr.Zero);System.Threading.Thread.Sleep(50);keybd_event(vk,sc,2,UIntPtr.Zero);System.Threading.Thread.Sleep(30);keybd_event(mod,0,2,UIntPtr.Zero);System.Threading.Thread.Sleep(170);}
 public static string Panel(){string res="none";EnumWindows((h,l)=>{if(!IsWindowVisible(h))return true;var c=new StringBuilder(64);GetClassName(h,c,64);
  if(c.ToString().StartsWith("ATL:")){var r=new R();GetWindowRect(h,out r);res=(r.Rr-r.L)+"x"+(r.B-r.T);} return true;},IntPtr.Zero);return res;}
 public static IntPtr FindByTitle(string t){IntPtr res=IntPtr.Zero;EnumWindows((h,l)=>{if(!IsWindowVisible(h))return true;var sb=new StringBuilder(300);GetWindowText(h,sb,300);
  if(sb.ToString().Contains(t)){res=h;return false;} return true;},IntPtr.Zero);return res;}
 public static bool Click(IntPtr hwnd){var r=new R();GetWindowRect(hwnd,out r);
   SetCursorPos((r.L+r.Rr)/2, r.T+200); System.Threading.Thread.Sleep(150);
   mouse_event(0x0002,0,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(60); mouse_event(0x0004,0,0,0,UIntPtr.Zero);
   System.Threading.Thread.Sleep(350); return GetForegroundWindow()==hwnd;}
}
'@
$lg='D:\rime-sandbox\vmenu-debug.log'
if(Test-Path $lg){ Remove-Item $lg -Force }
$hwnd=[TF]::FindByTitle('IME WEB TEST')
if($hwnd -eq [IntPtr]::Zero){ "❌ 网页窗口不在（可能被关了）"; exit 1 }
"焦点在网页 = $([TF]::Click($hwnd))"
[TF]::TapMod(0x11,0x41); [TF]::Tap(0x2E); Start-Sleep -Milliseconds 400
[TF]::Tap(0x1B); Start-Sleep -Milliseconds 300
[TF]::Tap(0x56); Start-Sleep -Milliseconds 800; "  v 菜单 = $([TF]::Panel())"
[TF]::Tap(0x32); Start-Sleep -Milliseconds 1000; "  剪贴板列表 = $([TF]::Panel())"
[TF]::Tap(0x08); Start-Sleep -Milliseconds 1000; "  按 Backspace 后 = $([TF]::Panel())"
"日志：" + $(if(Test-Path $lg){ (Get-Content $lg | Select-String 'v2 退格' | Select-Object -First 1) } else { '（无）' })
