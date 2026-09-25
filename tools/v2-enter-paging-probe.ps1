# Probe for reported bugs:
#   A) Enter in v2/v3/v4/v menus commits the internal code (vclip / vqi / vfav) -> must be gone
#   B) v2 clipboard candidates cannot be paged (Down / + / = / PageDown) -> must page
#   C) leak sweep over other keys after v2
#   D) Shift paths: pure Shift tap / Shift+Enter / Shift+A in v2 -> no raw-code leak,
#      Shift+'=' must page (repr used to arrive as 'shift+plus' and fall through)
# ASCII-only source on purpose (BOM-less UTF-8 scripts get parsed as ANSI by PS 5.1).
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;using System.Runtime.InteropServices;using System.Text;using System.Threading;
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
 [DllImport("user32.dll")]public static extern bool SetProcessDPIAware();
 public struct R{public int L,T,Rr,B;}
 public delegate bool EnumProc(IntPtr h,IntPtr l);
 static TB(){ SetProcessDPIAware(); }
 public static void Tap(byte vk){
   byte sc=(byte)MapVirtualKey(vk,0);
   keybd_event(vk,sc,0,UIntPtr.Zero); Thread.Sleep(60);
   keybd_event(vk,sc,2,UIntPtr.Zero); Thread.Sleep(170);
 }
 public static void TapShift(byte vk){
   byte sc=(byte)MapVirtualKey(vk,0);
   keybd_event(0x10,0,0,UIntPtr.Zero); Thread.Sleep(30);
   keybd_event(vk,sc,0,UIntPtr.Zero); Thread.Sleep(60);
   keybd_event(vk,sc,2,UIntPtr.Zero);
   keybd_event(0x10,0,2,UIntPtr.Zero); Thread.Sleep(170);
 }
 public static void TapShiftOnly(){
   // pure Shift tap: press+release within 500ms, no key in between.
   // librime ascii_composer (Shift_L: commit_code) toggles ascii mode on this
   // and commits the raw input first -> used to leak 'vclip'.
   keybd_event(0x10,0,0,UIntPtr.Zero); Thread.Sleep(60);
   keybd_event(0x10,0,2,UIntPtr.Zero); Thread.Sleep(200);
 }
 public static string Panel(){ string res="none";
   EnumWindows((h,l)=>{ if(!IsWindowVisible(h))return true;
     var c=new StringBuilder(64); GetClassName(h,c,64);
     if(c.ToString().StartsWith("ATL:")){ var r=new R(); GetWindowRect(h,out r);
       res=(r.Rr-r.L)+"x"+(r.B-r.T);} return true;},IntPtr.Zero);
   return res; }
 public static R PanelBox(){ R res=new R();
   EnumWindows((h,l)=>{ if(!IsWindowVisible(h))return true;
     var c=new StringBuilder(64); GetClassName(h,c,64);
     if(c.ToString().StartsWith("ATL:")){ GetWindowRect(h,out res); return false;} return true;},IntPtr.Zero);
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
   if(GetForegroundWindow()!=hwnd){
     keybd_event(0x12,0,0,UIntPtr.Zero); Thread.Sleep(40); keybd_event(0x12,0,2,UIntPtr.Zero);
     Thread.Sleep(80); SetForegroundWindow(hwnd); Thread.Sleep(250); }
   return GetForegroundWindow()==hwnd; }
}
'@
$VK=@{ 'a'=0x41;'b'=0x42;'c'=0x43;'d'=0x44;'e'=0x45;'f'=0x46;'g'=0x47;'h'=0x48;'i'=0x49;'j'=0x4A;'k'=0x4B;'l'=0x4C;'m'=0x4D;'n'=0x4E;'o'=0x4F;'p'=0x50;'q'=0x51;'r'=0x52;'s'=0x53;'t'=0x54;'u'=0x55;'v'=0x56;'w'=0x57;'x'=0x58;'y'=0x59;'z'=0x5A;
  '0'=0x30;'1'=0x31;'2'=0x32;'3'=0x33;'4'=0x34;'5'=0x35;'6'=0x36;'7'=0x37;'8'=0x38;'9'=0x39;
  'esc'=0x1B;'space'=0x20;'back'=0x08;'enter'=0x0D;'tab'=0x09;'del'=0x2E;
  'up'=0x26;'down'=0x28;'left'=0x25;'right'=0x27;'pgdn'=0x22;'pgup'=0x21;'home'=0x24;'end'=0x23;
  'minus'=0xBD;'equal'=0xBB;'comma'=0xBC;'period'=0xBE;'slash'=0xBF;'semicolon'=0xBA;
  'quote'=0xDE;'lbracket'=0xDB;'rbracket'=0xDD;'backslash'=0xDC;'grave'=0xC0;'shift3'=0x33 }
function K([string]$k){
  if([TB]::GetForegroundWindow() -ne $hwnd){ [void][TB]::Focus($hwnd); Start-Sleep -Milliseconds 400 }
  [TB]::Tap([byte]$VK[$k])
}
function KPlus {
  if([TB]::GetForegroundWindow() -ne $hwnd){ [void][TB]::Focus($hwnd); Start-Sleep -Milliseconds 400 }
  [TB]::TapShift(0xBB)   # shift + '=' -> XK_plus
}
function KShiftTap {
  if([TB]::GetForegroundWindow() -ne $hwnd){ [void][TB]::Focus($hwnd); Start-Sleep -Milliseconds 400 }
  [TB]::TapShiftOnly()
}
function Doc { (Get-Content 'D:\weasel-build\tst\typed.txt' -Raw -Encoding UTF8 -EA SilentlyContinue) }
function Clr { [IO.File]::WriteAllText('D:\weasel-build\tst\typed.txt','',(New-Object Text.UTF8Encoding($false))); [TB]::ClearText($hwnd); Start-Sleep -Milliseconds 350 }
function Shot([string]$tag){
  $r=[TB]::PanelBox()
  if($r.Rr -le $r.L){ "   panel[$tag] = none"; return }
  $w=$r.Rr-$r.L; $h=$r.B-$r.T
  $bmp=New-Object Drawing.Bitmap $w,$h
  $g=[Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($r.L,$r.T,0,0,(New-Object Drawing.Size($w,$h)))
  $out="D:\weasel-build\tst\panel-$tag.png"
  $bmp.Save($out,[Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose();$bmp.Dispose()
  "   panel[$tag] = ${w}x${h} -> $out"
}
function Report([string]$what){
  $t = Doc
  $bad = if($t -match 'vclip|vqi|vfav|vset'){ ' <<<< BUG: internal code leaked' } else { '' }
  "   $what doc= <$t>$bad"
}

$clip = Get-Content 'D:\rime-sandbox\clipboard-cache.txt' -Encoding UTF8 | Where-Object { $_.Trim() -ne '' } | Select-Object -First 24
"--- clipboard cache (first 24) ---"
for($i=0;$i -lt [Math]::Min(12,$clip.Count);$i++){ "   {0}: {1}" -f ($i+1), $clip[$i].Substring(0,[Math]::Min(40,$clip[$i].Length)) }

Get-Process powershell -EA SilentlyContinue | Where-Object { $_.MainWindowTitle -like '*IME TEST PAD*' } | Stop-Process -Force
Start-Sleep -Seconds 1
Start-Process powershell.exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','D:\weasel-build\tst\ime-notepad.ps1' | Out-Null
$hwnd=[IntPtr]::Zero
for($i=1;$i -le 20;$i++){ Start-Sleep -Seconds 1; $hwnd=[TB]::FindByTitle('IME TEST PAD'); if($hwnd -ne [IntPtr]::Zero){ break } }
if($hwnd -eq [IntPtr]::Zero){ "TEST WINDOW NOT FOUND"; exit 1 }
$ok=$false
for($f=1;$f -le 5;$f++){ if([TB]::Focus($hwnd)){ $ok=$true; break }; Start-Sleep -Milliseconds 600 }
"focus=$ok"
if(-not $ok){ "FOCUS FAILED"; exit 1 }
K 'esc'

"=== A1) v2 + Enter (was: leaked 'vclip') ==="
Clr; K 'v'; Start-Sleep -Milliseconds 700; K '2'; Start-Sleep -Milliseconds 900
K 'enter'; Start-Sleep -Milliseconds 900
Report 'A1 v2+enter (list -> paste highlighted, must NOT be vclip)'
K 'esc'

"=== A2) v3 (quick menu) + Enter ==="
Clr; K 'v'; Start-Sleep -Milliseconds 700; K '3'; Start-Sleep -Milliseconds 900
K 'enter'; Start-Sleep -Milliseconds 900
Report 'A2 v3+enter (static menu -> swallow, expect empty)'
K 'esc'

"=== A3) v (main menu) + Enter ==="
Clr; K 'v'; Start-Sleep -Milliseconds 700
K 'enter'; Start-Sleep -Milliseconds 900
Report 'A3 v+enter (static menu -> swallow, expect empty)'
K 'esc'

"=== A4) v4 (favorites) + Enter ==="
Clr; K 'v'; Start-Sleep -Milliseconds 700; K '4'; Start-Sleep -Milliseconds 900
K 'enter'; Start-Sleep -Milliseconds 900
Report 'A4 v4+enter (list -> paste highlighted, must NOT be vfav)'
K 'esc'

"=== A5) v2 + space still pastes (regression) ==="
Clr; K 'v'; Start-Sleep -Milliseconds 700; K '2'; Start-Sleep -Milliseconds 900
K 'space'; Start-Sleep -Milliseconds 900
Report 'A5 v2+space (expect first clip entry)'
K 'esc'

"=== B1) v2 paging with arrow keys ==="
Clr; K 'v'; Start-Sleep -Milliseconds 700; K '2'; Start-Sleep -Milliseconds 900
Shot 'b1-page0'
K 'down'; Start-Sleep -Milliseconds 500; Shot 'b1-row1'
K 'down'; Start-Sleep -Milliseconds 500; Shot 'b1-row2'
K 'down'; Start-Sleep -Milliseconds 700; Shot 'b1-after-last-row'   # expect NEW page (items 7-12)
K 'down'; Start-Sleep -Milliseconds 700; Shot 'b1-page2-down'       # next page again
K 'up';   Start-Sleep -Milliseconds 700; Shot 'b1-page-back'        # back one page
K 'esc'

"=== B2) v2 paging with + / - / = / PageDown ==="
Clr; K 'v'; Start-Sleep -Milliseconds 700; K '2'; Start-Sleep -Milliseconds 900
Shot 'b2-page0'
KPlus;      Start-Sleep -Milliseconds 700; Shot 'b2-plus1';  Report 'B2 after shift+= (page1)'
KPlus;      Start-Sleep -Milliseconds 700; Shot 'b2-plus2';  Report 'B2 after shift+= (page2)'
K 'minus';  Start-Sleep -Milliseconds 700; Shot 'b2-minus';  Report 'B2 after minus'
K 'equal';  Start-Sleep -Milliseconds 700; Shot 'b2-equal';  Report 'B2 after equal'
K 'pgdn';   Start-Sleep -Milliseconds 700; Shot 'b2-pgdn';   Report 'B2 after PageDown'
K 'pgup';   Start-Sleep -Milliseconds 700; Shot 'b2-pgup';   Report 'B2 after PageUp'
K 'esc'

"=== B3) select on page 2 after paging (digit 1) ==="
Clr
K 'v'; Start-Sleep -Milliseconds 700; K '2'; Start-Sleep -Milliseconds 900
KPlus; Start-Sleep -Milliseconds 700
K '1'; Start-Sleep -Milliseconds 900
Report 'B3 v2 + plus + digit1 (expect clipboard entry #7)'
"   expected entry #7 = <$($clip[6])>"
K 'esc'

"=== C) leak sweep: other keys after v2 ==="
foreach($k in @('shift3','comma','period','slash','semicolon','quote','lbracket','rbracket','backslash','grave','a')){
  Clr; K 'v'; Start-Sleep -Milliseconds 500; K '2'; Start-Sleep -Milliseconds 700
  K $k; Start-Sleep -Milliseconds 700
  Report "C key=$k"
  K 'esc'
}

"=== D1) pure Shift tap inside v2 (ascii_composer commit_code path) ==="
Clr; K 'v'; Start-Sleep -Milliseconds 700; K '2'; Start-Sleep -Milliseconds 900
KShiftTap; Start-Sleep -Milliseconds 700
Report 'D1 v2 + Shift tap (must stay empty, list must stay alive)'
"   panel after shift tap = $([TB]::Panel())   (expect ~1059x2xx = vclip list still open)"
K 'esc'

"=== D1b) still Chinese after the Shift tap ==="
Clr; K 's'; Start-Sleep -Milliseconds 300; K 'h'; Start-Sleep -Milliseconds 300; K 'i'; Start-Sleep -Milliseconds 600
K 'space'; Start-Sleep -Milliseconds 700
Report 'D1b shi+space (expect shi-like hanzi; raw "shi" or nothing = ascii mode got stuck)'

"=== D2) Shift+Enter inside v2 (repr used to be shift+Return) ==="
Clr; K 'v'; Start-Sleep -Milliseconds 700; K '2'; Start-Sleep -Milliseconds 900
if($VK['enter']){ if([TB]::GetForegroundWindow() -ne $hwnd){ [void][TB]::Focus($hwnd); Start-Sleep -Milliseconds 400 }; [TB]::TapShift(0x0D) }
Start-Sleep -Milliseconds 900
Report 'D2 v2+Shift+Enter (must NOT contain vclip)'
K 'esc'

"=== D3) Shift+A inside v2 (uppercase falls into express_editor DirectCommit) ==="
Clr; K 'v'; Start-Sleep -Milliseconds 700; K '2'; Start-Sleep -Milliseconds 900
if([TB]::GetForegroundWindow() -ne $hwnd){ [void][TB]::Focus($hwnd); Start-Sleep -Milliseconds 400 }
[TB]::TapShift(0x41); Start-Sleep -Milliseconds 900
Report 'D3 v2+Shift+A (must NOT contain vclip; first-entry paste or swallow both acceptable)'
K 'esc'
"=== done ==="
