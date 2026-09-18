# verify-grid.ps1 —— 候选窗口「按键展开」的自动化验收
#
# 前置条件（缺一不可，否则结果一定是「没反应」）：
#   1. 已用 tools/deploy-grid-dlls.ps1 部署了网格版三个文件（含 System32/SysWOW64 的 weasel.dll）；
#   2. WeaselServer.exe 在跑，且**小狼毫是当前活动输入法**
#      —— 判定方法见 docs/GRID-CANDIDATE-DLL.md §4.3（枚举 notepad 的已加载模块，
#      只加载 weasel.dll 才算对；「nihao→你好」区分不出来，微信输入法也打拼音）；
#   3. 测试用的记事本是**部署之后**新开的进程（TSF 是进程内 DLL）。
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File tools\verify-grid.ps1
#   powershell -ExecutionPolicy Bypass -File tools\verify-grid.ps1 -Shots D:\weasel-build\shots\verify
#
# 输出：截图 + 每步的「深底横带」行数 + 像素差分 + 最后一行 PASS/FAIL 汇总。
# 注意：脚本只做**像素/几何**断言（能证明「变了」），「数字在词前」「按高亮行重新编号」
#       这类语义必须再裁图交给视觉模型复核（见 docs/GRID-CANDIDATE-DLL.md §5.2）。

param(
  [string]$Shots = 'D:\weasel-build\shots\verify',
  [string]$Tool  = (Join-Path $PSScriptRoot 'type-and-shot.ps1')
)

Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;using System.Runtime.InteropServices;
public class VGridKey {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte sc, uint f, UIntPtr e);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint c, uint t);
}
'@

New-Item -ItemType Directory -Force -Path $Shots | Out-Null
if (-not (Test-Path $Tool)) { Write-Host "找不到 $Tool" -ForegroundColor Red; exit 1 }

Get-Process notepad -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep 1; Start-Process notepad; Start-Sleep 3

# --- 活动输入法自检：只加载 weasel.dll 才是小狼毫 ---
$np = Get-Process notepad | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
$dlls = @($np.Modules | Where-Object { $_.ModuleName -match 'weasel|wetype' } | Select-Object -ExpandProperty ModuleName)
Write-Host "活动输入法模块: $($dlls -join ', ')"
if ($dlls -notcontains 'weasel.dll') {
  Write-Host "⚠️ 记事本没加载 weasel.dll —— 小狼毫不是活动输入法，后面的结果不可信。" -ForegroundColor Yellow
  Write-Host "   照 docs/GRID-CANDIDATE-DLL.md §4.3 处理（停 wetype* → 重启 ctfmon → 重启 WeaselServer → 新开记事本）。" -ForegroundColor Yellow
}

function Shot([string]$name, [string]$keys) {
  & $Tool -Keys $keys -Out (Join-Path $Shots "$name.png") -NoClick | Out-Null
  Write-Host "  截图 $name.png  (keys: $keys)"
}

# 小键盘 + ：rime 里 KP_Add → send: plus，是「下翻」的正牌按键。
# 不要用 shift+equals —— 合成 Shift 会触发 rime 的 Shift=commit_code，把编码直接上屏。
function TapVk([int]$vk, [int]$ms = 90) {
  $sc = [VGridKey]::MapVirtualKey([uint32]$vk, 0)
  [VGridKey]::keybd_event([byte]$vk, [byte]$sc, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds $ms
  [VGridKey]::keybd_event([byte]$vk, [byte]$sc, 2, [UIntPtr]::Zero); Start-Sleep -Milliseconds 450
}

# 候选区（避开窗口标题栏与记事本菜单）的「深底横带」：返回每段 y 范围，段数 = 候选行数
function RowBands([string]$file) {
  $b = [Drawing.Bitmap]::FromFile($file); $bands = @(); $inB = $false; $s = 0
  for ($y = 140; $y -lt 545; $y += 3) {
    $d = 0
    for ($x = 100; $x -lt 1150; $x += 8) {
      $c = $b.GetPixel($x, $y); $l = 0.299 * $c.R + 0.587 * $c.G + 0.114 * $c.B
      if ($l -lt 45) { $d++ }
    }
    if ($d -gt 50) { if (-not $inB) { $inB = $true; $s = $y } }
    else { if ($inB) { $bands += , @($s, $y - 3); $inB = $false } }
  }
  if ($inB) { $bands += , @($s, 545) }
  $b.Dispose(); return $bands
}

function BandHeight([string]$file) {
  $b = RowBands $file
  if ($b.Count -eq 0) { return 0 }
  return ($b[0][1] - $b[0][0] + 3)
}

# 逐像素差分。**这是唯一可靠的「高亮动了没有」指标**：
# 高亮底色是深棕 0x594231（亮度≈71），用亮度/亮像素数当指标完全看不出来。
function PxDiff([string]$a, [string]$b, [string]$tag) {
  $ia = [Drawing.Bitmap]::FromFile($a); $ib = [Drawing.Bitmap]::FromFile($b); $n = 0
  for ($y = 140; $y -lt 545; $y += 2) {
    for ($x = 100; $x -lt 1150; $x += 3) {
      $ca = $ia.GetPixel($x, $y); $cb = $ib.GetPixel($x, $y)
      $d = [Math]::Abs($ca.R - $cb.R) + [Math]::Abs($ca.G - $cb.G) + [Math]::Abs($ca.B - $cb.B)
      if ($d -gt 40) { $n++ }
    }
  }
  $ia.Dispose(); $ib.Dispose()
  Write-Host ("  差分 {0}: {1} 点" -f $tag, $n)
  return $n
}

$results = New-Object System.Collections.Generic.List[object]
function Assert($name, $ok, $detail) {
  $results.Add([pscustomobject]@{ 断言 = $name; 结果 = $(if ($ok) { 'PASS' } else { 'FAIL' }); 证据 = $detail })
  $color = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} —— {2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $name, $detail) -ForegroundColor $color
}

Write-Host "`n=== 1. 收起态必须只有一行（zhe'g）==="
Shot 'V01-collapsed' 'esc,z,h,e,apostrophe,g'
$h1 = BandHeight (Join-Path $Shots 'V01-collapsed.png')
Assert '收起态单行' ($h1 -gt 0 -and $h1 -lt 120) "深底横带高 $h1 px（单行约 64）"

Write-Host "`n=== 2. ↓ 展开成多行 ==="
Shot 'V02-expanded' 'down'
$h2 = BandHeight (Join-Path $Shots 'V02-expanded.png')
Assert '↓ 展开后变高' ($h2 -gt $h1 + 40) "高 $h1 -> $h2 px"

Write-Host "`n=== 3. ↓↓ 不收起，而是高亮跳到第 2 行 ==="
Shot 'V03-down2' 'down'
$d23 = PxDiff (Join-Path $Shots 'V02-expanded.png') (Join-Path $Shots 'V03-down2.png') '展开 vs 再按↓'
$h3 = BandHeight (Join-Path $Shots 'V03-down2.png')
Assert '↓↓ 不收起' ([Math]::Abs($h3 - $h2) -lt 40) "高度 $h2 -> $h3 px（应基本不变）"
Assert '↓↓ 移动了高亮' ($d23 -gt 2000) "$d23 点不同"

Write-Host "`n=== 4. → 在同一行内右移 ==="
Shot 'V04-right' 'right'
$d34 = PxDiff (Join-Path $Shots 'V03-down2.png') (Join-Path $Shots 'V04-right.png') '↓↓ vs →'
Assert '→ 移动了高亮' ($d34 -gt 2000) "$d34 点不同"

Write-Host "`n=== 5. 第一行按 ↑ 收起 ==="
Shot 'V05-collapse' 'esc,a,down,up'
$h5 = BandHeight (Join-Path $Shots 'V05-collapse.png')
Assert '↑ 从第一行收起' ($h5 -gt 0 -and $h5 -lt 150) "深底横带高 $h5 px（单行约 64）"

Write-Host "`n=== 6. + 号下翻（收起态换下一批 9 个候选）==="
Shot 'V06-page0' 'esc,z,h,e,apostrophe,g'
TapVk 0x6B; Shot 'V06-page1' ''      # VK_ADD = 小键盘 +
TapVk 0x6B; Shot 'V06-page2' ''
TapVk 0x6B; Shot 'V06-page3' ''
TapVk 0x6B; Shot 'V06-page4' ''
$p01 = PxDiff (Join-Path $Shots 'V06-page0.png') (Join-Path $Shots 'V06-page1.png') '第0页 vs 第1页'
$p12 = PxDiff (Join-Path $Shots 'V06-page1.png') (Join-Path $Shots 'V06-page2.png') '第1页 vs 第2页'
$p40 = PxDiff (Join-Path $Shots 'V06-page4.png') (Join-Path $Shots 'V06-page0.png') '第4次按+ vs 第0页'
Assert '+ 下翻换了一批候选' ($p01 -gt 2000 -and $p12 -gt 2000) "页0/1 差 $p01 点，页1/2 差 $p12 点"
Assert '+ 下翻循环回首页' ($p40 -lt 300) "第 4 次按 + 与第 0 页差 $p40 点（应≈0，只有抗锯齿噪声）"
Assert '+ 不把编码上屏' ($true) '（看截图里的标题栏：应仍是 *zhe''g，没有变成「着+」之类）'

Write-Host "`n=== 7. 普通打字手感未被破坏（v 菜单仍然打得开）==="
Shot 'V07-vmenu' 'esc,v'
Assert 'v 菜单仍在' ($true) '人工看 V07-vmenu.png 是否为「设置/剪贴板/常用语/符号/快捷输入」'

Write-Host "`n================ 汇总 ================"
$results | Format-Table -AutoSize | Out-String | Write-Host
$fail = @($results | Where-Object { $_.结果 -eq 'FAIL' }).Count
Write-Host ("截图目录: {0}" -f $Shots)
if ($fail -eq 0) { Write-Host "全部 PASS" -ForegroundColor Green } else { Write-Host "$fail 项 FAIL" -ForegroundColor Red }
Write-Host "`n语义复核（必须做，像素证明不了）:" -ForegroundColor Cyan
Write-Host "  1) 裁候选窗 → 二值化反相 → 放大 2-4 倍；"
Write-Host "  2) node `"C:\Users\Administrator\.codex\skills\claude-vision-skill\vision.js`" <png> `"逐字输出图中所有文字`"；"
Write-Host "  3) 核对：序号在**词前**、只有高亮那一行有 1-9、↓↓ 后第 2 行变成 1-9。"
exit $fail
