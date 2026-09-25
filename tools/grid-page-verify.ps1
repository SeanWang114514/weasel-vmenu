Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;using System.Runtime.InteropServices;using System.Text;
public class TB2{
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
     keybd_event(0x12,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(40); keybd_event(0x12,0,2,UIntPtr.Zero);
     System.Threading.Thread.Sleep(80); SetForegroundWindow(hwnd); System.Threading.Thread.Sleep(250); }
   return GetForegroundWindow()==hwnd; }
}
'@
$VK=@{ 'a'=0x41;'b'=0x42;'c'=0x43;'d'=0x44;'e'=0x45;'f'=0x46;'g'=0x47;'h'=0x48;'i'=0x49;'j'=0x4A;'k'=0x4B;'l'=0x4C;'m'=0x4D;'n'=0x4E;'o'=0x4F;'p'=0x50;'q'=0x51;'r'=0x52;'s'=0x53;'t'=0x54;'u'=0x55;'v'=0x56;'w'=0x57;'x'=0x58;'y'=0x59;'z'=0x5A;
  '0'=0x30;'1'=0x31;'2'=0x32;'3'=0x33;'4'=0x34;'5'=0x35;'6'=0x36;'7'=0x37;'8'=0x38;'9'=0x39;'esc'=0x1B;'space'=0x20;'del'=0x2E;'back'=0x08;
  'up'=0x26;'down'=0x28;'equal'=0xBB;'pgdn'=0x22;'pgup'=0x21;'kpadd'=0x6B }
function K([string]$k){
  if([TB2]::GetForegroundWindow() -ne $hwnd){ [void][TB2]::Focus($hwnd); Start-Sleep -Milliseconds 400 }
  [TB2]::Tap([byte]$VK[$k])
}
function Doc { (Get-Content 'D:\weasel-build\tst\typed.txt' -Raw -Encoding UTF8 -EA SilentlyContinue) }
function Clr { [IO.File]::WriteAllText('D:\weasel-build\tst\typed.txt','',(New-Object Text.UTF8Encoding($false))); [TB2]::ClearText($hwnd); Start-Sleep -Milliseconds 350 }
function PH([string]$p){ if($p -eq 'none'){ return 0 }; $i=$p.IndexOf('x'); if($i -lt 1){ return 0 }; [int]$p.Substring($i+1) }

$fail=0
$logPath='D:\rime-sandbox\vmenu-debug.log'
$logOff=0
if(Test-Path $logPath){ $logOff=(Get-Item $logPath).Length }

Get-Process powershell -EA SilentlyContinue | Where-Object { $_.MainWindowTitle -like '*IME TEST PAD*' } | Stop-Process -Force
Start-Sleep -Seconds 1
Start-Process powershell.exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','D:\weasel-build\tst\ime-notepad.ps1' | Out-Null
$hwnd=[IntPtr]::Zero
for($i=1;$i -le 20;$i++){ Start-Sleep -Seconds 1; $hwnd=[TB2]::FindByTitle('IME TEST PAD'); if($hwnd -ne [IntPtr]::Zero){ break } }
if($hwnd -eq [IntPtr]::Zero){ "❌ 测试窗口没起来"; exit 1 }
$ok=$false
for($f=1;$f -le 5;$f++){ if([TB2]::Focus($hwnd)){ $ok=$true; break }; Start-Sleep -Milliseconds 600 }
"聚焦=$ok"
if(-not $ok){ "❌ 聚焦失败，弃测"; exit 1 }
K 'esc'

"=== A) 基线：正常打 shi，按 1 选第一个候选 ==="
Clr; K 's'; K 'h'; K 'i'; Start-Sleep -Milliseconds 800
$pa=[TB2]::Panel(); "   收起态候选窗 = $pa"
K '1'; Start-Sleep -Milliseconds 900
$t0=(Doc); "   ★ T0（第一个候选）= <$t0>"
if(-not $t0 -or $t0 -match 'shi'){ "❌ 基线失败，弃测"; exit 1 }
K 'esc'

"=== B) 翻页生效验证：展开 → 翻到第 2 屏 → 按 1 ==="
Clr; K 's'; K 'h'; K 'i'; Start-Sleep -Milliseconds 800
K 'down'; Start-Sleep -Milliseconds 700
$pb=[TB2]::Panel(); "   展开态候选窗 = $pb（期望明显比收起态高）"
if((PH $pb) -le (PH $pa)){ "❌ 展开失败（$pb vs $pa）"; $fail++ }
K 'equal'; Start-Sleep -Milliseconds 700
K '1'; Start-Sleep -Milliseconds 900
$t1=(Doc); "   ★ T1（第 2 屏第一个候选）= <$t1>"
if($t1 -eq $t0 -or -not $t1){ "   ⚠ '= 号翻页没生效，改试 PageDown 重测"; 
  Clr; K 's'; K 'h'; K 'i'; Start-Sleep -Milliseconds 800; K 'down'; Start-Sleep -Milliseconds 700
  K 'pgdn'; Start-Sleep -Milliseconds 700; K '1'; Start-Sleep -Milliseconds 900
  $t1=(Doc); "   ★ T1（PageDown 后第 2 屏第一个候选）= <$t1>"
}
if($t1 -eq $t0 -or -not $t1){ "❌ 翻页没生效（T1 == T0），后面断言无意义，中止"; exit 1 }
"   ✓ 翻页生效：第 2 屏和第 1 屏内容不同"
K 'esc'

"=== C) 用户报障场景：第 2 屏 → ↑ 收起 → ↓ 重新展开 → 按 1 ==="
Clr; K 's'; K 'h'; K 'i'; Start-Sleep -Milliseconds 800
K 'down'; Start-Sleep -Milliseconds 700
$pc1=[TB2]::Panel()
K 'equal'; Start-Sleep -Milliseconds 700
K 'up'; Start-Sleep -Milliseconds 700
$pc2=[TB2]::Panel(); "   ↑ 收起后候选窗 = $pc2（期望回到单行高度 ≈ $pa）"
if((PH $pc2) -ge (PH $pc1)){ "❌ ↑ 没有收起（$pc2 vs $pc1）"; $fail++ }
K 'down'; Start-Sleep -Milliseconds 700
$pc3=[TB2]::Panel(); "   ↓ 重新展开候选窗 = $pc3（期望 ≈ $pc1）"
if((PH $pc3) -le (PH $pa)){ "❌ ↓ 没有重新展开（$pc3）"; $fail++ }
K '1'; Start-Sleep -Milliseconds 900
$t2=(Doc); "   ★ T2（重新展开后第一个候选）= <$t2>"
if($t2 -ne $t0){ "❌ BUG 仍在：重新展开停在旧页（T2=<$t2> ≠ T0=<$t0>）"; $fail++ }
else { "   ✓ 重新展开回到第 1 屏（T2 == T0）" }
K 'esc'

"=== D) 收起态也回第 1 屏：第 2 屏 → ↑ 收起 → 按 1 ==="
Clr; K 's'; K 'h'; K 'i'; Start-Sleep -Milliseconds 800
K 'down'; Start-Sleep -Milliseconds 700
K 'equal'; Start-Sleep -Milliseconds 700
K 'up'; Start-Sleep -Milliseconds 700
K '1'; Start-Sleep -Milliseconds 900
$t3=(Doc); "   ★ T3（收起后第一个候选）= <$t3>"
if($t3 -ne $t0){ "❌ 收起后仍停在旧页（T3=<$t3> ≠ T0=<$t0>）"; $fail++ }
else { "   ✓ 收起后也回到第 1 屏（T3 == T0）" }
K 'esc'

"=== E) 回归：正常打字 shi + 空格上屏 ==="
Clr; K 's'; K 'h'; K 'i'; Start-Sleep -Milliseconds 800
$pe=[TB2]::Panel(); "   默认候选窗 = $pe（期望单行，与 A 相同 = $pa）"
if((PH $pe) -gt (PH $pa)+40){ "❌ 新一次输入没回到收起态（$pe vs $pa）"; $fail++ }
K 'space'; Start-Sleep -Milliseconds 900
$t4=(Doc); "   ★ T4（空格上屏）= <$t4>"
if(-not $t4 -or $t4 -match 'shi'){ "❌ 空格上屏失败"; $fail++ }
else { "   ✓ 空格正常上屏" }
K 'esc'

"=== F) 日志证据（展开/收起时的页码复位记录）==="
if(Test-Path $logPath){
  $fs=[IO.File]::Open($logPath,'Open','Read','ReadWrite'); [void]$fs.Seek($logOff,'Begin')
  $sr=New-Object IO.StreamReader($fs,[Text.Encoding]::UTF8); $tail=$sr.ReadToEnd(); $sr.Close(); $fs.Close()
  $lines=$tail -split "`r?`n" | Where-Object { $_ -match '展开网格|收起网格' }
  if($lines){ $lines | ForEach-Object { "   $_" } } else { "   （没有匹配行 —— DEBUG_LOG 可能被关掉）" }
} else { "   （日志文件不存在）" }

""
if($fail -eq 0){ "✅ 全部通过：关闭后重新打开恒显示第 1 屏" } else { "❌ 失败项 = $fail" }
exit $fail
