Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public class M5 {
 [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h,int x,int y,int w,int ht,bool r);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern void keybd_event(byte vk,byte sc,uint f,UIntPtr e);
 [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint c,uint t); }
'@
$t='D:\VibeCoding\输入法\repo\weasel-vmenu\tools\type-and-shot.ps1'
$LOG='D:\rime-sandbox\vmenu-debug.log'
function Tap([byte]$vk){ $sc=[M5]::MapVirtualKey([uint32]$vk,0)
  [M5]::keybd_event($vk,[byte]$sc,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 40
  [M5]::keybd_event($vk,[byte]$sc,2,[UIntPtr]::Zero); Start-Sleep -Milliseconds 80 }
function Read-Np { Tap 0x1B; Start-Sleep -Milliseconds 300
  [M5]::keybd_event(0x11,0,0,[UIntPtr]::Zero); Tap 0x41; Tap 0x43
  [M5]::keybd_event(0x11,0,2,[UIntPtr]::Zero); Start-Sleep -Milliseconds 400
  $x=Get-Clipboard -Raw -EA SilentlyContinue; if($null -eq $x){return '<空>'}; return $x }
function Lines { (Get-Content $LOG -EA SilentlyContinue | Measure-Object -Line).Lines }
function List { (Get-Content $LOG -Tail 1 -EA SilentlyContinue) }
function Items([string]$line){ $m=[regex]::Matches($line,'(\d+)\[([^\]]*)\]'); $h=@{}; foreach($x in $m){ $h[[int]$x.Groups[1].Value]=$x.Groups[2].Value }; return $h }
function New-Np {
  Get-Process notepad -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep -Milliseconds 900; Start-Process notepad; Start-Sleep -Seconds 3
  $np=Get-Process notepad | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  [void][M5]::MoveWindow($np.MainWindowHandle,60,40,1040,460,$true)
  [M5]::SetForegroundWindow($np.MainWindowHandle); Start-Sleep -Milliseconds 400; return $np }
function TypeShi {
  $n0 = Lines
  for($i=1;$i -le 6;$i++){
    & $t -Target notepad -Keys 's,h,i' -Out 'D:\weasel-build\shots\_t.png' -NoClick *> $null
    Start-Sleep -Milliseconds 600
    if((Lines) -gt $n0){ return $true }
    Tap 0x10; Start-Sleep -Milliseconds 350 }
  return $false }

$cases = @(
  @{ name='C 展开+↓到第2行    按 3'; pre=@('down','down');      digit='3'; row=1 },
  @{ name='D 展开+=翻页       按 1'; pre=@('down','equals');    digit='1'; row=0 },
  @{ name='E 展开+=翻页       按 3'; pre=@('down','equals');    digit='3'; row=0 },
  @{ name='F 展开+↓一行+=翻页 按 2'; pre=@('down','down','equals'); digit='2'; row=1 }
)
foreach($c in $cases){
  [void](New-Np)
  if(-not (TypeShi)){ "[$($c.name)] ❌ 中文态失败"; continue }
  Start-Sleep -Milliseconds 500
  foreach($k in $c.pre){
    if($k -eq 'down'){ Tap 0x28 } else { & $t -Target notepad -Keys $k -Out 'D:\weasel-build\shots\_t.png' -NoClick *> $null }
    Start-Sleep -Milliseconds 700 }
  $line = List; $map = Items $line
  $d = [int]([char]$c.digit) - 0x30
  $expIdx = $c.row*9 + $d
  $exp = if($map.ContainsKey($expIdx)){ $map[$expIdx] } else { '(无)' }
  & $t -Target notepad -Keys $c.digit -Out 'D:\weasel-build\shots\_t.png' -NoClick *> $null
  Start-Sleep -Milliseconds 800
  $got = Read-Np
  $ok = if($exp -ne '(无)' -and $got -match [regex]::Escape($exp)){'✅'}else{'❌'}
  "[$($c.name)] 上屏=「$got」  期望=「$exp」(表内第$expIdx 位)  $ok"
}
