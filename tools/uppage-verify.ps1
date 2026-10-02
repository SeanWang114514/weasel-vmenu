# (B) 专项验收：翻页后光标在第 1 行时按 ↑ = 翻回上一页（保持展开态）
#
# 用户口径（原话）：「翻到上页，且保持展开态、光标停在该页最后一行」
#
# 断言方法（客观、不靠肉眼）：
#   1) 候选窗高度 Panel()：展开态 ≈ 4 行（明显 > 收起态）。用来证明「还是展开的」。
#   2) 落点用「按数字选第 N 个候选上屏什么字」来反证高亮停在哪一格 ——
#      这是最硬的证据：数字键选的是**当前高亮所在行**的第 N 格吗？
#      不是。数字键 1..9 选的是当前**可见页**的第 1..9 个。
#      所以要证明「光标停在上页最后一行」，改用一个更直接的观察量：
#      **按空格上屏的候选**（空格 = 上屏当前高亮项）。
#      于是：page1 第 1 行第 1 格 的空格上屏结果已知（记为 U0）；
#            page2 第 1 行第 1 格 的空格上屏结果记为 U1（≠ U0，证明确实翻页了）；
#            在 page2 第 1 行按 ↑ 之后，再按空格上屏，结果应为 U_restore；
#            断言 U_restore == 「上页最后一行第 1 格」对应的字。
#      上页最后一行第 1 格 = 索引 (rows-1)*cols = 3*6 = 18（0-based）。
#      我们不需要预先知道那个字是什么，只要断言：
#            U_restore == (回到 page1 后，先按 ↓ 三次到第 4 行再取第 1 格) 的结果。
#      即「用两条不同路径到达同一格，结果必须一致」。
#
#   更简单也更稳的等价断言（本脚本采用）：
#      路径 A：page1 → 直接按 ↓ 三次（第4行）→ 空格上屏   => 期望值 X
#      路径 B：page1 → 记 U0 → 翻到 page2 → ↑ → 空格上屏   => 实际值 Y
#      断言 X == Y，且 X != U0（证明它确实不是第 1 行）。
#
# 另外断言：↑ 之后候选窗仍然很高（展开态没被收起）。

Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;using System.Runtime.InteropServices;using System.Text;
public class TB3{
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
 [DllImport("user32.dll")]public static extern bool EnumChildWindows(IntPtr p,EnumProc cb,IntPtr l);
 [DllImport("user32.dll",CharSet=CharSet.Auto)]public static extern IntPtr SendMessage(IntPtr h,uint m,IntPtr w,string l);
 public struct R{public int L,T,Rr,B;}
 public delegate bool EnumProc(IntPtr h,IntPtr l);
 public static void Tap(byte vk){byte sc=(byte)MapVirtualKey(vk,0);keybd_event(vk,sc,0,UIntPtr.Zero);System.Threading.Thread.Sleep(60);keybd_event(vk,sc,2,UIntPtr.Zero);System.Threading.Thread.Sleep(170);}
 public static string Panel(){string res="none";EnumWindows((h,l)=>{if(!IsWindowVisible(h))return true;var c=new StringBuilder(64);GetClassName(h,c,64);
  if(c.ToString().StartsWith("ATL:")){var r=new R();GetWindowRect(h,out r);res=(r.Rr-r.L)+"x"+(r.B-r.T);} return true;},IntPtr.Zero);return res;}
 public static IntPtr FindByTitle(string t){IntPtr res=IntPtr.Zero;EnumWindows((h,l)=>{if(!IsWindowVisible(h))return true;var sb=new StringBuilder(300);GetWindowText(h,sb,300);
  if(sb.ToString().Contains(t)){res=h;return false;} return true;},IntPtr.Zero);return res;}
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

$hwnd=[IntPtr]::Zero
function K([string]$k){
  if([TB3]::GetForegroundWindow() -ne $hwnd){ [void][TB3]::Focus($hwnd); Start-Sleep -Milliseconds 400 }
  [TB3]::Tap([byte]$VK[$k])
}
function Doc { (Get-Content 'D:\weasel-build\tst\typed.txt' -Raw -Encoding UTF8 -EA SilentlyContinue) }
function Clr { [IO.File]::WriteAllText('D:\weasel-build\tst\typed.txt','',(New-Object Text.UTF8Encoding($false))); [TB3]::ClearText($hwnd); Start-Sleep -Milliseconds 350 }
function PH([string]$p){ if($p -eq 'none'){ return 0 }; $i=$p.IndexOf('x'); if($i -lt 1){ return 0 }; [int]$p.Substring($i+1) }

$fail=0
$logPath='D:\rime-sandbox\vmenu-debug.log'
$logOff=0
if(Test-Path $logPath){ $logOff=(Get-Item $logPath).Length }

Get-Process powershell -EA SilentlyContinue | Where-Object { $_.MainWindowTitle -like '*IME TEST PAD*' } | Stop-Process -Force
Start-Sleep -Seconds 1
Start-Process powershell.exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','D:\weasel-build\tst\ime-notepad.ps1' | Out-Null
for($i=1;$i -le 20;$i++){ Start-Sleep -Seconds 1; $hwnd=[TB3]::FindByTitle('IME TEST PAD'); if($hwnd -ne [IntPtr]::Zero){ break } }
if($hwnd -eq [IntPtr]::Zero){ "❌ 测试窗口没起来"; exit 1 }
$ok=$false
for($f=1;$f -le 5;$f++){ if([TB3]::Focus($hwnd)){ $ok=$true; break }; Start-Sleep -Milliseconds 600 }
"聚焦=$ok"
if(-not $ok){ "❌ 聚焦失败，弃测"; exit 1 }
K 'esc'

# 用一个候选足够多的输入：shiyan（试验/誓言/… 会有很多页）
$CODE = @('s','h','i','y','a','n')

"=== 1) 收起/展开高度基线 ==="
Clr; foreach($c in $CODE){ K $c }; Start-Sleep -Milliseconds 900
$pc=[TB3]::Panel(); "   收起态 = $pc"
K 'down'; Start-Sleep -Milliseconds 800
$pe=[TB3]::Panel(); "   展开态 = $pe （期望明显更高）"
if((PH $pe) -le (PH $pc)){ "❌ 展开失败（$pe vs $pc）"; $fail++ } else { "   ✓ 展开态确实更高" }
K 'esc'

"=== 2) 路径 A：展开 → ↓↓↓（走到第 4 行）→ 空格上屏，取得期望字 X ==="
Clr; foreach($c in $CODE){ K $c }; Start-Sleep -Milliseconds 900
K 'down'; Start-Sleep -Milliseconds 700
K 'down'; Start-Sleep -Milliseconds 300
K 'down'; Start-Sleep -Milliseconds 300
K 'down'; Start-Sleep -Milliseconds 500
$pA=[TB3]::Panel(); "   第 4 行时候选窗 = $pA"
K 'space'; Start-Sleep -Milliseconds 900
$X=(Doc); "   ★ X（第 4 行第 1 格）= <$X>"
if(-not $X){ "❌ 路径 A 没上屏，弃测"; $fail++; }
K 'esc'

"=== 3) 翻页确实生效：展开 → = 翻页 → 空格上屏，取得 U1 ==="
Clr; foreach($c in $CODE){ K $c }; Start-Sleep -Milliseconds 900
K 'down'; Start-Sleep -Milliseconds 700
K 'space'; Start-Sleep -Milliseconds 900
$U0=(Doc); "   ★ U0（第 1 页第 1 行）= <$U0>"
K 'esc'
Clr; foreach($c in $CODE){ K $c }; Start-Sleep -Milliseconds 900
K 'down'; Start-Sleep -Milliseconds 700
K 'equal'; Start-Sleep -Milliseconds 800
$pPg=[TB3]::Panel(); "   翻页后候选窗 = $pPg （应仍是展开态）"
if((PH $pPg) -le (PH $pc)){ "❌ 翻页后不是展开态（$pPg vs 收起 $pc）"; $fail++ } else { "   ✓ 翻页后仍是展开态" }
K 'space'; Start-Sleep -Milliseconds 900
$U1=(Doc); "   ★ U1（第 2 页第 1 行）= <$U1>"
if($U1 -eq $U0 -or -not $U1){ "❌ 翻页没生效（U1 == U0），后续断言无意义"; $fail++; } else { "   ✓ 翻页生效（U1 ≠ U0）" }
K 'esc'

"=== 4) ★ 核心：第 2 页第 1 行按 ↑ 应翻回上页且保持展开 ==="
Clr; foreach($c in $CODE){ K $c }; Start-Sleep -Milliseconds 900
K 'down'; Start-Sleep -Milliseconds 700
K 'equal'; Start-Sleep -Milliseconds 800
$pBeforeUp=[TB3]::Panel()
K 'up'; Start-Sleep -Milliseconds 800
$pAfterUp=[TB3]::Panel(); "   ↑ 之后候选窗 = $pAfterUp （期望仍 ≈ 展开态 $pe，不是收起态 $pc）"
if((PH $pAfterUp) -le (PH $pc)+20){ "❌ ↑ 把展开栏收起了（$pAfterUp）—— 用户报的 bug 仍在"; $fail++ }
else { "   ✓ ↑ 之后**仍然展开**（没被收起）" }

K 'space'; Start-Sleep -Milliseconds 900
$Y=(Doc); "   ★ Y（↑ 之后空格上屏）= <$Y>"
if($Y -eq $X){ "   ✓ 落点正确：Y == X = 上一页最后一行第 1 格" }
elseif($Y -eq $U0){ "❌ 落点错误：Y == U0，说明 ↑ 回到了上一页**第 1 行**，而不是最后一行"; $fail++ }
else { "❌ 落点不符：Y=<$Y>，既不是 X=<$X> 也不是 U0=<$U0>"; $fail++ }
K 'esc'

"=== 5) 回归：page 0 时按 ↑ 仍应收起展开栏 ==="
Clr; foreach($c in $CODE){ K $c }; Start-Sleep -Milliseconds 900
K 'down'; Start-Sleep -Milliseconds 700
$p0ex=[TB3]::Panel()
K 'up'; Start-Sleep -Milliseconds 800
$p0up=[TB3]::Panel(); "   未翻页时 ↑ 之后 = $p0up （期望 ≈ 收起态 $pc）"
if((PH $p0up) -ge (PH $p0ex)-20){ "❌ 未翻页时 ↑ 没有收起展开栏（$p0up vs $p0ex）——page 0 的原有行为被破坏"; $fail++ }
else { "   ✓ 未翻页时 ↑ 仍然收起展开栏（原有行为保留）" }
K 'esc'

"=== 6) 回归：普通打字 + 空格上屏 ==="
Clr; foreach($c in @('s','h','i')){ K $c }; Start-Sleep -Milliseconds 900
K 'space'; Start-Sleep -Milliseconds 900
$t4=(Doc); "   ★ 空格上屏 = <$t4>"
if(-not $t4 -or $t4 -match 'shi'){ "❌ 空格上屏失败"; $fail++ } else { "   ✓ 空格正常上屏" }
K 'esc'

"=== 7) 日志证据（up-page 记录）==="
if(Test-Path $logPath){
  $fs=[IO.File]::Open($logPath,'Open','Read','ReadWrite'); [void]$fs.Seek($logOff,'Begin')
  $sr=New-Object IO.StreamReader($fs,[Text.Encoding]::UTF8); $tail=$sr.ReadToEnd(); $sr.Close(); $fs.Close()
  $lines=$tail -split "`r?`n" | Where-Object { $_ -match 'up-page|展开网格|收起网格' }
  if($lines){ $lines | ForEach-Object { "   $_" } } else { "   （没有匹配行）" }
} else { "   （日志文件不存在）" }

""
if($fail -eq 0){ "✅ (B) 全部通过：翻页后第 1 行按 ↑ = 翻回上页 + 保持展开 + 落点是上页最后一行" }
else { "❌ 失败项 = $fail" }
exit $fail
