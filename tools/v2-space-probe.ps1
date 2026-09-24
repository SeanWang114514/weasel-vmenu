Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;using System.Runtime.InteropServices;using System.Text;
public class TB{
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
 public static string Panel(){string res="none";EnumWindows((h,l)=>{if(!IsWindowVisible(h))return true;var c=new StringBuilder(64);GetClassName(h,c,64);
  if(c.ToString().StartsWith("ATL:")){var r=new R();GetWindowRect(h,out r);res=(r.Rr-r.L)+"x"+(r.B-r.T);} return true;},IntPtr.Zero);return res;}
 public static IntPtr FindByTitle(string t){IntPtr res=IntPtr.Zero;EnumWindows((h,l)=>{if(!IsWindowVisible(h))return true;var sb=new StringBuilder(300);GetWindowText(h,sb,300);
  if(sb.ToString().Contains(t)){res=h;return false;} return true;},IntPtr.Zero);return res;}
 [DllImport("user32.dll")]public static extern bool EnumChildWindows(IntPtr p,EnumProc cb,IntPtr l);
 [DllImport("user32.dll",CharSet=CharSet.Auto)]public static extern IntPtr SendMessage(IntPtr h,uint m,IntPtr w,string l);
 public static void ClearText(IntPtr pad){
   if(pad==IntPtr.Zero) return;
   IntPtr child=IntPtr.Zero;
   EnumChildWindows(pad,(h,l)=>{var c=new StringBuilder(64);GetClassName(h,c,64);
     if(c.ToString().IndexOf("EDIT")>=0){child=h;return false;} return true;},IntPtr.Zero);
   if(child!=IntPtr.Zero) SendMessage(child,0x000C,IntPtr.Zero,""); }
 public static bool Focus(IntPtr hwnd){
   ShowWindow(hwnd,9); System.Threading.Thread.Sleep(200);
   uint zpid=0; uint tid1=GetWindowThreadProcessId(GetForegroundWindow(),out zpid); uint tid2=GetCurrentThreadId();
   AttachThreadInput(tid1,tid2,true); BringWindowToTop(hwnd); SetForegroundWindow(hwnd); AttachThreadInput(tid1,tid2,false);
   System.Threading.Thread.Sleep(250);
   if(GetForegroundWindow()!=hwnd){
     keybd_event(0x12,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(40); keybd_event(0x12,2,2,UIntPtr.Zero);
     System.Threading.Thread.Sleep(80); SetForegroundWindow(hwnd); System.Threading.Thread.Sleep(250); }
   return GetForegroundWindow()==hwnd; }
}
'@
$VK=@{ 'a'=0x41;'b'=0x42;'c'=0x43;'d'=0x44;'e'=0x45;'f'=0x46;'g'=0x47;'h'=0x48;'i'=0x49;'j'=0x4A;'k'=0x4B;'l'=0x4C;'m'=0x4D;'n'=0x4E;'o'=0x4F;'p'=0x50;'q'=0x51;'r'=0x52;'s'=0x53;'t'=0x54;'u'=0x55;'v'=0x56;'w'=0x57;'x'=0x58;'y'=0x59;'z'=0x5A;
 '0'=0x30;'1'=0x31;'2'=0x32;'3'=0x33;'4'=0x34;'5'=0x35;'6'=0x36;'7'=0x37;'8'=0x38;'9'=0x39;'esc'=0x1B;'space'=0x20;'del'=0x2E;'back'=0x08;'down'=0x28;'up'=0x26;'enter'=0x0D;'plus'=0xBB }
function K([string]$k){
  if([TB]::GetForegroundWindow() -ne $hwnd){ [void][TB]::Focus($hwnd); Start-Sleep -Milliseconds 400 }
  [TB]::Tap([byte]$VK[$k])
}
function Doc { (Get-Content 'D:\weasel-build\tst\typed.txt' -Raw -Encoding UTF8 -EA SilentlyContinue) }
function Clr { [IO.File]::WriteAllText('D:\weasel-build\tst\typed.txt','',(New-Object Text.UTF8Encoding($false))); [TB]::ClearText($hwnd); Start-Sleep -Milliseconds 350 }

$tag='CLIPTEST-' + (Get-Date -Format 'HHmmss')
Set-Clipboard -Value $tag
Start-Sleep -Seconds 2
"剪贴板历史第一行 = <$(Get-Content 'D:\rime-sandbox\clipboard-cache.txt' -Encoding UTF8 -TotalCount 1 -EA SilentlyContinue)>"

Get-Process powershell -EA SilentlyContinue | Where-Object { $_.MainWindowTitle -like '*IME TEST PAD*' } | Stop-Process -Force
Start-Sleep -Seconds 1
Start-Process powershell.exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','D:\weasel-build\tst\ime-notepad.ps1' | Out-Null
$existing=[TB]::FindByTitle('IME TEST PAD')
if(-not $existing){
  $hwnd=[IntPtr]::Zero
  for($i=1;$i -le 20;$i++){ Start-Sleep -Seconds 1; $hwnd=[TB]::FindByTitle('IME TEST PAD'); if($hwnd -ne [IntPtr]::Zero){ break } }
  if($hwnd -eq [IntPtr]::Zero){ "TEST window missing"; exit 1 }
}
$hwnd=[TB]::FindByTitle('IME TEST PAD')
$ok=$false
for($f=1;$f -le 5;$f++){
  [void][TB]::Focus($hwnd)
  Start-Sleep -Milliseconds 500
  if([TB]::GetForegroundWindow() -eq $hwnd){ $ok=$true; break }
  "focus retry $f..."
}
if(-not $ok){ "FOCUS FAILED - aborting before sending keys"; exit 1 }
"focus=True"
K 'esc'

"=== A) v2 + Enter ==="
Clr; K 'v'; Start-Sleep -Milliseconds 700; K '2'; Start-Sleep -Milliseconds 900
K 'enter'
Start-Sleep -Milliseconds 900
"A doc= <$(Doc)>   (vclip literal = BUG)"
K 'esc'

"=== B) v2 + space x6 (varied timing) ==="
foreach($d in 150,300,600,900,1200,400){
  Clr; K 'esc'; K 'v'; Start-Sleep -Milliseconds 650; K '2'; Start-Sleep -Milliseconds $d
  K 'space'; Start-Sleep -Milliseconds 800
  $t = (Doc)
  $bad = if($t -match 'vclip'){ ' <<<< BUG: vclip' } else { '' }
  "B($d ms) doc= <$t>$bad"
  K 'esc'
}

"=== C) v2 + Down (move highlight) + space ==="
Clr; K 'esc'; K 'v'; Start-Sleep -Milliseconds 650; K '2'; Start-Sleep -Milliseconds 800
K 'down'; Start-Sleep -Milliseconds 500
K 'space'; Start-Sleep -Milliseconds 900
"C doc= <$(Doc)>   (vclip literal = BUG)"
K 'esc'

"=== D) v2 + '+' page then space ==="
Clr; K 'esc'; K 'v'; Start-Sleep -Milliseconds 650; K '2'; Start-Sleep -Milliseconds 800
K 'plus'
Start-Sleep -Milliseconds 600
K 'space'; Start-Sleep -Milliseconds 900
"D doc= <$(Doc)>   (vclip literal = BUG)"
K 'esc'

"=== E) regression: v2 + 1 commits tag ==="
Clr; K 'esc'; K 'v'; Start-Sleep -Milliseconds 650; K '2'; Start-Sleep -Milliseconds 900
K '1'; Start-Sleep -Milliseconds 900
"E doc= <$(Doc)>  (expect $tag)"
K 'esc'

"=== F) regression: shi + space ==="
Clr; K 'esc'; K 's'; K 'h'; K 'i'; Start-Sleep -Milliseconds 800
K 'space'; Start-Sleep -Milliseconds 900
"F doc= <$(Doc)>  (expect a hanzi)"
K 'esc'
