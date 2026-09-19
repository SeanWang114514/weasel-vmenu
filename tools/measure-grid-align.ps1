<#
.SYNOPSIS
  客观量「候选方格是否行列对齐」：自动找出候选面板，按行切开，量每行**每一列候选词**的
  起点 x，再看同一列在各行是否落在同一条竖线上。

.DESCRIPTION
  为什么不能固定阈值：小狼毫主题有深色/浅色两套，截图里还可能混着别的窗口。
  所以这里先**从图里学出面板底色**（暗像素里出现最多的颜色），再以它为基准找文字。

  判定标准（docs/GRID-CANDIDATE-DLL.md §7.1 的验收方法）：
    * 第 k 列候选词的起点 x 在各行之间一致（差 ≤ -Tolerance）→ 严格对齐 ✅
    * 展开态第一行是「序号+词」交替（簇数≈2×列数），第 2 行起只有词。

.EXAMPLE
  pwsh -File tools\measure-grid-align.ps1 -Image D:\weasel-build\shots\e2_exp.png
#>
param(
  [Parameter(Mandatory = $true)][string]$Image,
  [int]$TextDelta = 150,      # 比面板底色亮这么多就算文字
  [int]$Tolerance = 6,        # 同一列允许的像素误差（量的是**墨迹**起点：字形左边缘空白、
                              #   高亮粗体的墨迹都会差几个像素，实测正常 ≤5px）
  [int]$MinClusterGap = 3,    # 簇之间至少空这么多列
  [int]$MaxCols = 12          # 一列以上、最多按多少列算
)

Add-Type -AssemblyName System.Drawing
$bmp = [System.Drawing.Bitmap]::FromFile($Image)
$W = $bmp.Width; $H = $bmp.Height

# ---- 1) 学出面板底色：暗像素里出现最多的颜色 ----
$freq = @{}
for ($y = 0; $y -lt $H; $y += 2) {
  for ($x = 0; $x -lt $W; $x += 2) {
    $c = $bmp.GetPixel($x, $y)
    $s = $c.R + $c.G + $c.B
    if ($s -lt 400) {
      $key = "$($c.R),$($c.G),$($c.B)"
      if ($freq.ContainsKey($key)) { $freq[$key]++ } else { $freq[$key] = 1 }
    }
  }
}
if ($freq.Count -eq 0) { Write-Error '图里没有暗色像素，找不到候选面板'; $bmp.Dispose(); exit 1 }
$bgKey = ($freq.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Key
$bgParts = $bgKey -split ','
$bgR = [int]$bgParts[0]; $bgG = [int]$bgParts[1]; $bgB = [int]$bgParts[2]
$bgSum = $bgR + $bgG + $bgB
$thr = $bgSum + $TextDelta
Write-Host ("面板底色 = R{0} G{1} B{2}（{3} 个采样）  文字阈值 = 亮度和 > {4}" -f $bgR, $bgG, $bgB, $freq[$bgKey], $thr)

function Is-Bg($c) { return ([Math]::Abs($c.R - $bgR) + [Math]::Abs($c.G - $bgG) + [Math]::Abs($c.B - $bgB)) -lt 24 }
function Is-Text($c) { return ($c.R + $c.G + $c.B) -gt $thr }

# ---- 2) 面板 y 范围：底色像素占多数的行 ----
$rowBg = New-Object 'int[]' $H
for ($y = 0; $y -lt $H; $y++) {
  $n = 0
  for ($x = 0; $x -lt $W; $x += 2) { if (Is-Bg $bmp.GetPixel($x, $y)) { $n++ } }
  $rowBg[$y] = $n
}
$py0 = -1; $py1 = -1
for ($y = 0; $y -lt $H; $y++) { if ($rowBg[$y] -gt ($W / 2) * 0.25) { if ($py0 -lt 0) { $py0 = $y }; $py1 = $y } }
if ($py0 -lt 0) { Write-Error '找不到面板区域（底色行太少）'; $bmp.Dispose(); exit 1 }
Write-Host ("面板 y 范围: {0}..{1}（{2}px 高）" -f $py0, $py1, ($py1 - $py0 + 1))

# ---- 3) 面板内文本行带 ----
# 面板里除了文字，还有一条**每行都亮**的底噪（描边/高亮块边缘，实测约 162px），
# 所以行带判定用「底噪 + 20」做阈值，否则 4 行会被并成 1 行（第一版就踩了这个坑）。
$rowCnt = New-Object 'int[]' ($py1 - $py0 + 1)
for ($y = $py0; $y -le $py1; $y++) {
  $n = 0
  for ($x = 0; $x -lt $W; $x++) { if (Is-Text $bmp.GetPixel($x, $y)) { $n++ } }
  $rowCnt[$y - $py0] = $n
}
$baseline = ($rowCnt | Measure-Object -Minimum).Minimum
$rowThr = $baseline + 20
Write-Host ("面板内每行亮像素底噪 = {0} → 行带阈值 = {1}" -f $baseline, $rowThr)
$bands = @(); $cur = $null
for ($y = $py0; $y -le $py1; $y++) {
  $n = $rowCnt[$y - $py0]
  if ($n -ge $rowThr) {
    if ($null -eq $cur) { $cur = [pscustomobject]@{ top = $y; bottom = $y } } else { $cur.bottom = $y }
  } elseif ($null -ne $cur) { if (($cur.bottom - $cur.top) -ge 3) { $bands += $cur }; $cur = $null }
}
if ($null -ne $cur -and ($cur.bottom - $cur.top) -ge 3) { $bands += $cur }
Write-Host ("文本行带: {0} 行" -f $bands.Count)

# ---- 4) 每行的文本簇 + 区分「序号(窄)」与「候选词(宽)」----
# 面板左右描边也是亮的，会混进来当窄簇，所以先按宽度分类再丢掉贴边的簇。
$panelL = -1; $panelR = -1
for ($x = 0; $x -lt $W; $x++) {
  $nb = 0; $nt = 0
  for ($y = $py0; $y -le $py1; $y++) {
    $c = $bmp.GetPixel($x, $y)
    if (Is-Bg $c) { $nb++ } elseif (Is-Text $c) { $nt++ }
  }
  if ($nt -gt ($py1 - $py0) * 0.6) { if ($panelL -lt 0) { $panelL = $x }; $panelR = $x }
}
Write-Host ("面板左右描边: x={0} / x={1}" -f $panelL, $panelR)

$rows = @()
foreach ($b in $bands) {
  $colText = New-Object 'int[]' $W
  for ($x = 0; $x -lt $W; $x++) {
    $n = 0
    for ($y = $b.top; $y -le $b.bottom; $y++) { if (Is-Text $bmp.GetPixel($x, $y)) { $n++ } }
    $colText[$x] = $n
  }
  $cl = @(); $cs = -1; $lastHit = -1
  for ($x = 0; $x -lt $W; $x++) {
    if ($colText[$x] -gt 0) {
      if ($cs -lt 0) { $cs = $x }
      elseif (($x - $lastHit) -gt $MinClusterGap) { $cl += [pscustomobject]@{ start = $cs; end = $lastHit }; $cs = $x }
      $lastHit = $x
    }
  }
  if ($cs -ge 0) { $cl += [pscustomobject]@{ start = $cs; end = $lastHit } }
  # 丢掉贴描边的簇（描边本身是竖线，宽度很小但位置在两端）
  $cl = @($cl | Where-Object { -not (($panelL -ge 0 -and $_.start -le $panelL + 2) -or ($panelR -ge 0 -and $_.start -ge $panelR - 2)) })
  $words = @($cl | Where-Object { ($_.end - $_.start) -ge 17 })   # 汉字/emoji 至少 17px 宽
  $digits = @($cl | Where-Object { ($_.end - $_.start) -lt 17 })
  $rows += [pscustomobject]@{ top = $b.top; bottom = $b.bottom; clusters = $cl; words = $words; digits = $digits }
}
$bmp.Dispose()

# ---- 5) 输出每行的候选词起点 ----
Write-Host ''
$wordStarts = @()
foreach ($r in $rows) {
  $w = @($r.words | ForEach-Object { $_.start })
  $wordStarts += , $w
  Write-Host ("行 y {0,4}..{1,4}  簇 {2,2}（序号 {3,2} / 词 {4,2}）  词起点: {5}" -f `
      $r.top, $r.bottom, $r.clusters.Count, $r.digits.Count, $r.words.Count, ($w -join ', '))
}

# ---- 6) 判定 ----
Write-Host ''
if ($wordStarts.Count -lt 2) { Write-Host '只有 1 行候选（收起态）→ 只能看行内列间距是否均匀' }

# 列距（同一行相邻列的词起点差）：网格正确时应当处处等于统一列宽
foreach ($r in $rows) {
  $w = @($r.words | ForEach-Object { $_.start })
  if ($w.Count -lt 3) { continue }
  $p = @(); for ($i = 1; $i -lt $w.Count; $i++) { $p += ($w[$i] - $w[$i - 1]) }
  Write-Host ("行 y {0,4}..{1,4} 列距: {2}  (min={3} max={4} 极差={5}px)" -f `
      $r.top, $r.bottom, ($p -join ', '), ($p | Measure-Object -Minimum).Minimum, `
      ($p | Measure-Object -Maximum).Maximum, (($p | Measure-Object -Maximum).Maximum - ($p | Measure-Object -Minimum).Minimum))
}

# 第 1 行相对最后一行的**逐列漂移**：这是"参差不齐"最直接的证据
if ($wordStarts.Count -ge 2) {
  $a = $wordStarts[0]; $b = $wordStarts[-1]
  $n = [Math]::Min($a.Count, $b.Count)
  if ($n -ge 2) {
    $d = @(); for ($i = 0; $i -lt $n; $i++) { $d += ($a[$i] - $b[$i]) }
    Write-Host ("第 1 行相对最后一行逐列偏移: {0}  (最大 {1}px)" -f ($d -join ', '), (($d | ForEach-Object { [Math]::Abs($_) }) | Measure-Object -Maximum).Maximum)
  }
}
Write-Host ''
$ok = $true
$nCols = ($wordStarts | Where-Object { $_.Count -gt 0 } | ForEach-Object { $_.Count } | Measure-Object -Minimum).Minimum
for ($i = 0; $i -lt $nCols; $i++) {
  $vals = @($wordStarts | Where-Object { $_.Count -gt $i } | ForEach-Object { $_[$i] })
  if ($vals.Count -lt 2) { continue }
  $min = ($vals | Measure-Object -Minimum).Minimum
  $max = ($vals | Measure-Object -Maximum).Maximum
  $spread = $max - $min
  $mark = if ($spread -le $Tolerance) { 'OK  ' } else { $ok = $false; 'BAD ' }
  Write-Host ("{0}第 {1,2} 列词起点: {2}   (min={3} max={4} 差={5}px)" -f $mark, $i, ($vals -join ', '), $min, $max, $spread)
}
Write-Host ''
if ($ok) { Write-Host '结论：各行同一列的候选词起点一致 → 严格对齐 ✅' } else { Write-Host '结论：存在不对齐的列 ❌' }
