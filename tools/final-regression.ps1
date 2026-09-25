# Final regression after the Enter-leak + paging + Shift fixes.
# Covers: normal typing, grid expand/collapse, native Shift tap outside v mode,
# v2 open/space/digit/Enter/Shift+= paging, v3 Enter swallow, backspace cancel.
# ASCII-only source on purpose.
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;using System.Runtime.InteropServices;using System.Text;using System.Threading;
public class FR {
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
 static FR(){ SetProcessDPIAware(); }
 public static void Tap(byte vk){ byte sc=(byte)MapVirtualKey(vk,0);
   keybd_event(vk,sc,0,UIntPtr.Zero); Thread.Sleep(70);
   keybd_event(vk,sc,2,UIntPtr.Zero); Thread.Sleep(200); }
 public static void TapShift(byte vk){
   byte sc=(byte)MapVirtualKey(vk,0);
   keybd_event(0x10,0,0,UIntPtr.Zero); Thread.Sleep(40);
   keybd_event(vk,sc,0,UIntPtr.Zero); Thread.Sleep(70);
   keybd_event(vk,sc,2,UIntPtr.Zero);
   keybd_event(0x10,0,2,UIntPtr.Zero); Thread.Sleep(200); }
 public static void TapShiftOnly(){
   keybd_event(0x10,0,0,UIntPtr.Zero); Thread.Sleep(70);
   keybd_event(0x10,0,2,UIntPtr.Zero); Thread.Sleep(220); }
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
$VK=@{ 'a'=0x41;'h'=0x48;'i'=0x49;'j'=0x4A;'n'=0x4E;'g'=0x47;'s'=0x53;'u'=0x55;'v'=0x56;'2'=0x32;'3'=0x33;'1'=0x31;
  'space'=0x20;'enter'=0x0D;'esc'=0x1B;'back'=0x08;'down'=0x28;'up'=0x26;'equal'=0xBB;'minus'=0xBD;'left'=0x25;'right'=0x27 }
$hwnd=[FR]::FindByTitle('IME TEST PAD')
if($hwnd -eq [IntPtr]::Zero){
  Get-Process powershell -EA SilentlyContinue | Where-Object { $_.MainWindowTitle -like '*IME TEST PAD*' } | Stop-Process -Force
  Start-Sleep -Seconds 1
  Start-Process powershell.exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','D:\weasel-build\tst\ime-notepad.ps1' | Out-Null
  for($i=1;$i -le 20;$i++){ Start-Sleep -Seconds 1; $hwnd=[FR]::FindByTitle('IME TEST PAD'); if($hwnd -ne [IntPtr]::Zero){ break } }
}
if($hwnd -eq [IntPtr]::Zero){ 'TEST WINDOW NOT FOUND'; exit 1 }
$ok=$false
for($f=1;$f -le 5;$f++){ if([FR]::Focus($hwnd)){ $ok=$true; break }; Start-Sleep -Milliseconds 600 }
"focus=$ok"
if(-not $ok){ 'FOCUS FAILED'; exit 1 }
function K([string]$k){ if([FR]::GetForegroundWindow() -ne $hwnd){ [void][FR]::Focus($hwnd); Start-Sleep -Milliseconds 400 }; [FR]::Tap([byte]$VK[$k]) }
function KPlus { if([FR]::GetForegroundWindow() -ne $hwnd){ [void][FR]::Focus($hwnd); Start-Sleep -Milliseconds 400 }; [FR]::TapShift(0xBB) }
function KShiftTap { if([FR]::GetForegroundWindow() -ne $hwnd){ [void][FR]::Focus($hwnd); Start-Sleep -Milliseconds 400 }; [FR]::TapShiftOnly() }
function Doc { $t=(Get-Content 'D:\weasel-build\tst\typed.txt' -Raw -Encoding UTF8 -EA SilentlyContinue); if($null -eq $t){$t=''}; if($t.Length -gt 90){ '<'+$t.Length+'c> '+$t.Substring(0,90) } else { $t } }
function Clr { [IO.File]::WriteAllText('D:\weasel-build\tst\typed.txt','',(New-Object Text.UTF8Encoding($false))); [FR]::ClearText($hwnd); Start-Sleep -Milliseconds 350 }
function Shot([string]$tag){
  $r=[FR]::PanelBox()
  if($r.Rr -le $r.L){ "   panel[$tag] = none"; return }
  $w=$r.Rr-$r.L; $h=$r.B-$r.T
  $bmp=New-Object Drawing.Bitmap $w,$h
  $g=[Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($r.L,$r.T,0,0,(New-Object Drawing.Size($w,$h)))
  $out="D:\weasel-build\tst\final-$tag.png"
  $bmp.Save($out,[Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose();$bmp.Dispose()
  "   panel[$tag] = ${w}x${h} -> $out"
}
function Rpt([string]$what){
  $t=Doc
  $bad=if($t -match 'vclip|vqi|vfav|vset'){ ' <<<< BUG: internal code leaked' } else { '' }
  "   $what doc= <$t>$bad"
}
K 'esc'

"=== R1) normal typing shi + space ==="
Clr; K 's'; Start-Sleep -Milliseconds 250; K 'h'; Start-Sleep -Milliseconds 250; K 'i'; Start-Sleep -Milliseconds 600
Shot 'r1-shi'
K 'space'; Start-Sleep -Milliseconds 700
Rpt 'R1 shi+space (expect hanzi, not raw shi)'

"=== R2) grid expand with Down, collapse with Up ==="
Clr; K 'j'; Start-Sleep -Milliseconds 200; K 'i'; Start-Sleep -Milliseconds 200; K 'a'; Start-Sleep -Milliseconds 200; K 'n'; Start-Sleep -Milliseconds 200; K 'g'; Start-Sleep -Milliseconds 700
Shot 'r2-single'
K 'down'; Start-Sleep -Milliseconds 600; Shot 'r2-expand'
K 'up';   Start-Sleep -Milliseconds 600; Shot 'r2-collapse'
K 'esc';  Start-Sleep -Milliseconds 500

"=== R3) native Shift tap OUTSIDE v mode (must still toggle EN/CN) ==="
Clr; KShiftTap; Start-Sleep -Milliseconds 400
K 's'; Start-Sleep -Milliseconds 250; K 'h'; Start-Sleep -Milliseconds 250; K 'i'; Start-Sleep -Milliseconds 600
K 'space'; Start-Sleep -Milliseconds 700
Rpt 'R3 shi+space with ascii ON (raw "shi" expected = toggle worked)'
K 'esc'
KShiftTap; Start-Sleep -Milliseconds 500
Clr; K 's'; Start-Sleep -Milliseconds 250; K 'h'; Start-Sleep -Milliseconds 250; K 'i'; Start-Sleep -Milliseconds 600
K 'space'; Start-Sleep -Milliseconds 700
Rpt 'R3b shi+space after toggle back (hanzi expected)'
if((Doc) -match 'shi'){ '   -> ascii mode stuck ON, tapping Shift to restore Chinese'; KShiftTap; Start-Sleep -Milliseconds 500; Clr }

"=== R4) v2: open, space paste, no leak ==="
Clr; K 'v'; Start-Sleep -Milliseconds 700; K '2'; Start-Sleep -Milliseconds 900
Shot 'r4-v2'
K 'space'; Start-Sleep -Milliseconds 900
Rpt 'R4 v2+space (first clip entry expected)'
K 'esc'

"=== R5) v2: Shift+= pages ==="
Clr; K 'v'; Start-Sleep -Milliseconds 700; K '2'; Start-Sleep -Milliseconds 900
KPlus; Start-Sleep -Milliseconds 800
Shot 'r5-page1'
K '1'; Start-Sleep -Milliseconds 900
Rpt 'R5 v2 + shift+= + digit1 (entry #7 expected)'
K 'esc'

"=== R6) v2: Enter pastes highlighted ==="
Clr; K 'v'; Start-Sleep -Milliseconds 700; K '2'; Start-Sleep -Milliseconds 900
K 'enter'; Start-Sleep -Milliseconds 900
Rpt 'R6 v2+enter (no vclip expected)'
K 'esc'

"=== R7) v3: Enter swallowed ==="
Clr; K 'v'; Start-Sleep -Milliseconds 700; K '3'; Start-Sleep -Milliseconds 900
K 'enter'; Start-Sleep -Milliseconds 900
Rpt 'R7 v3+enter (empty expected)'
K 'esc'

"=== R8) v2 backspace cancels whole input ==="
Clr; K 'v'; Start-Sleep -Milliseconds 700; K '2'; Start-Sleep -Milliseconds 800
K 'back'; Start-Sleep -Milliseconds 700
K 'space'; Start-Sleep -Milliseconds 700
Rpt 'R8 backspace then space (expect empty or one space char; vclip/clip-entry = BUG)'
'=== done ==='
