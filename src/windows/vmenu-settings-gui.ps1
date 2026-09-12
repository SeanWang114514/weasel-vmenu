param(
  [string]$RimeDir = 'D:\rime-sandbox',
  [switch]$ShowNow
)
# 小狼毫 v 功能 —— 可视化设置界面（WinForms）
#
# 与输入法共享同一批文件，格式与 lua/vmenu_core.lua 完全一致：
#   <RimeDir>\clipboard-cache.txt        剪贴板历史，一行一条，最新在最前，上限 50
#   <RimeDir>\cn_dicts\favorites.dict.yaml  收藏，正文在 "..." 之后，格式 内容<Tab>键<Tab>词频
#   <RimeDir>\vmenu-settings.txt         clip_page=<20|30|40|50>
# 所有文件都以「UTF-8 无 BOM」写出：带 BOM 会让第一条剪贴板内容多出不可见字符。
#
# 本文件必须保存为「UTF-8 带 BOM」，否则 Windows PowerShell 5.1 会按 ANSI 解析，
# 界面上的中文会全部变成乱码。

$ErrorActionPreference = 'Stop'

# 默认目录不可用时退回注册表里登记的 RimeUserDir，避免开了窗口却读不到文件
if (-not (Test-Path -LiteralPath $RimeDir)) {
  try {
    $reg = Get-ItemProperty -Path 'HKCU:\Software\Rime\Weasel' -Name RimeUserDir -ErrorAction Stop
    if ($reg.RimeUserDir -and (Test-Path -LiteralPath $reg.RimeUserDir)) { $RimeDir = $reg.RimeUserDir }
  } catch { }
}

# ---------------------------------------------------------------------------
# 单实例
#   已经有实例在跑时不要重复开窗口，而是写一个标记文件，
#   让常驻实例（每 60ms 看一次）立刻把窗口亮出来。
# ---------------------------------------------------------------------------
$mutex = New-Object System.Threading.Mutex($false, 'RimeVMenuSettingsGui')
$isFirst = $false
try { $isFirst = $mutex.WaitOne(0) }
catch [System.Threading.AbandonedMutexException] { $isFirst = $true }
catch { $isFirst = $false }
if (-not $isFirst) {
  try {
    $flagPath0 = Join-Path $RimeDir 'open-settings.flag'
    [IO.File]::WriteAllText($flagPath0, (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
  } catch { }
  exit 0
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

if (-not (Test-Path -LiteralPath $RimeDir)) {
  [void][System.Windows.Forms.MessageBox]::Show("找不到 Rime 用户目录：`n`n$RimeDir", '无法打开设置')
  exit 1
}

$UTF8 = New-Object Text.UTF8Encoding($false)
$CLIP_PATH = Join-Path $RimeDir 'clipboard-cache.txt'
$FAV_PATH = Join-Path $RimeDir 'cn_dicts\favorites.dict.yaml'
$SET_PATH = Join-Path $RimeDir 'vmenu-settings.txt'
$FLAG_PATH = Join-Path $RimeDir 'open-settings.flag'

$MAX_CLIP = 50
$MIN_PAGE = 20
$MAX_PAGE = 50
$STEP = 10

$script:pageSize = $MIN_PAGE
$script:clip = @()
$script:favs = @()

# ---------------------------------------------------------------------------
# 文件读写（UTF-8 无 BOM）
# ---------------------------------------------------------------------------
function Read-AllLines {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return @() }
  return @([IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) -split "`r?`n")
}

function Write-TextFile {
  param([string]$Path, [string]$Text)
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $tmp = "$Path.tmp"
  [IO.File]::WriteAllText($tmp, $Text, $UTF8)
  Move-Item -Force $tmp $Path
}

function Load-Settings {
  $script:pageSize = $MIN_PAGE
  foreach ($line in (Read-AllLines -Path $SET_PATH)) {
    if ($line -match '^\s*clip_page\s*=\s*(\d+)') {
      $n = [int]$Matches[1]
      if ($n -ge $MIN_PAGE -and $n -le $MAX_PAGE) { $script:pageSize = $n }
    }
  }
}

function Save-Settings {
  param([int]$Page)
  if ($Page -lt $MIN_PAGE) { $Page = $MIN_PAGE }
  if ($Page -gt $MAX_PAGE) { $Page = $MAX_PAGE }
  Write-TextFile -Path $SET_PATH -Text "# v 功能菜单设置`nclip_page=$Page`n"
  $script:pageSize = $Page
}

function Load-Clipboard {
  $list = New-Object System.Collections.ArrayList
  foreach ($line in (Read-AllLines -Path $CLIP_PATH)) {
    $t = "$line".Trim()
    if ($t.Length -gt 0) {
      [void]$list.Add($t)
      if ($list.Count -ge $MAX_CLIP) { break }
    }
  }
  $script:clip = @($list)
}

function Save-Clipboard {
  $text = ''
  if ($script:clip.Count -gt 0) { $text = ($script:clip -join "`n") + "`n" }
  Write-TextFile -Path $CLIP_PATH -Text $text
}

$FAV_HEADER = "# Rime dictionary`n# encoding: utf-8`n---`nname: favorites`nversion: `"2026-09-11`"`nsort: by_weight`n...`n"

function Load-Favorites {
  $list = New-Object System.Collections.ArrayList
  $body = $false
  foreach ($line in (Read-AllLines -Path $FAV_PATH)) {
    if (-not $body) {
      if ($line -match '^\.\.\.') { $body = $true }
      continue
    }
    $parts = $line -split "`t"
    if ($parts.Count -ge 2) {
      $w = $parts[0].Trim()
      $k = $parts[1].Trim()
      if ($w.Length -gt 0 -and $k.Length -gt 0) {
        [void]$list.Add([pscustomobject]@{ Word = $w; Key = $k })
      }
    }
  }
  $script:favs = @($list)
}

function Save-Favorites {
  $sb = New-Object Text.StringBuilder
  [void]$sb.Append($FAV_HEADER)
  foreach ($f in $script:favs) {
    [void]$sb.Append($f.Word).Append("`t").Append($f.Key).Append("`t100000`n")
  }
  Write-TextFile -Path $FAV_PATH -Text $sb.ToString()
}

function Confirm {
  param([string]$Message, [string]$Title = '请确认')
  $r = [Windows.Forms.MessageBox]::Show($Message, $Title,
        [Windows.Forms.MessageBoxButtons]::YesNo,
        [Windows.Forms.MessageBoxIcon]::Warning,
        [Windows.Forms.MessageBoxDefaultButton]::Button2)
  return ($r -eq [Windows.Forms.DialogResult]::Yes)
}

# ---------------------------------------------------------------------------
# 窗体
# ---------------------------------------------------------------------------
$form = New-Object Windows.Forms.Form
$form.Text = '小狼毫 v 功能 · 可视化设置'
$form.AutoScaleMode = 'None'
$form.ClientSize = New-Object Drawing.Size(960, 620)
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = New-Object Drawing.Size(820, 520)
$form.Font = New-Object Drawing.Font('Microsoft YaHei UI', 9)

$tabs = New-Object Windows.Forms.TabControl
$tabs.Dock = 'Fill'
$tabs.Padding = New-Object Drawing.Point(14, 6)

$tabClip = New-Object Windows.Forms.TabPage
$tabClip.Text = '  剪贴板历史  '
$tabFav = New-Object Windows.Forms.TabPage
$tabFav.Text = '  收藏内容  '
$tabSet = New-Object Windows.Forms.TabPage
$tabSet.Text = '  设置与缓存  '

$status = New-Object Windows.Forms.StatusStrip
$statusLabel = New-Object Windows.Forms.ToolStripStatusLabel
$statusLabel.Text = '就绪'
$statusLabel.Spring = $true
$statusLabel.TextAlign = 'MiddleLeft'
[void]$status.Items.Add($statusLabel)

# ===== 剪贴板页 =====
# 位置一律由 Layout-Tabs 按「实际客户区尺寸」现算，不用 Dock / Anchor：
# 本进程没有 DPI 感知清单，Windows 会对坐标做 DPI 虚拟化，写死的绝对坐标会被
# 平移放大，按钮会跑到窗口外面（表现为「只有列表、没有按钮」）。
$clipInfo = New-Object Windows.Forms.Label
$clipInfo.Padding = New-Object Windows.Forms.Padding(8, 8, 8, 0)
$clipInfo.Text = ''

$clipList = New-Object Windows.Forms.ListView
$clipList.View = 'Details'
$clipList.FullRowSelect = $true
$clipList.GridLines = $true
$clipList.MultiSelect = $true
$clipList.HideSelection = $false
$clipList.Font = New-Object Drawing.Font('Microsoft YaHei UI', 9)
[void]$clipList.Columns.Add('序', 46)
[void]$clipList.Columns.Add('剪贴板内容（最新在最上面）', 720)

$clipPanel = New-Object Windows.Forms.Panel
if ($env:VMENU_GUI_DEBUG) { $clipPanel.BackColor = [Drawing.Color]::Red }

function New-SideButton {
  param([string]$Text, [int]$Top)
  $b = New-Object Windows.Forms.Button
  $b.Text = $Text
  $b.Left = 10
  $b.Top = $Top
  $b.Width = 146
  $b.Height = 34
  $b.FlatStyle = 'System'
  return $b
}

$btnClipCopy   = New-SideButton '复制到剪贴板' 12
$btnClipDel    = New-SideButton '删除选中' 54
$btnClipClear  = New-SideButton '清空全部' 96
$btnClipReload = New-SideButton '重新载入' 138
$btnClipTop    = New-SideButton '把选中项置顶' 190

$clipHint = New-Object Windows.Forms.Label
$clipHint.Left = 10
$clipHint.Top = 236
$clipHint.Width = 160
$clipHint.Height = 280
$clipHint.Text = "输入法里按 v → 2 可以快速取用。`n`n超过 50 条时自动丢弃最旧的。`n`n多行内容会被压平成一行。"

function Refresh-Clipboard {
  Load-Clipboard
  $clipList.BeginUpdate()
  $clipList.Items.Clear()
  for ($i = 0; $i -lt $script:clip.Count; $i++) {
    $t = $script:clip[$i]
    $show = $t
    if ($show.Length -gt 160) { $show = $show.Substring(0, 160) + ' …' }
    $it = New-Object Windows.Forms.ListViewItem(("" + ($i + 1)))
    [void]$it.SubItems.Add($show)
    $it.Tag = $i
    [void]$clipList.Items.Add($it)
  }
  $clipList.EndUpdate()
  $clipInfo.Text = "当前缓存 $($script:clip.Count) 条（上限 $MAX_CLIP 条）。输入法剪贴板列表默认显示 $($script:pageSize) 条，按 m 键每次 +$STEP 条，最多 $MAX_PAGE 条。"
}

# ===== 收藏页 =====
$favInfo = New-Object Windows.Forms.Label
$favInfo.Padding = New-Object Windows.Forms.Padding(8, 8, 8, 0)

$favList = New-Object Windows.Forms.ListView
$favList.View = 'Details'
$favList.FullRowSelect = $true
$favList.GridLines = $true
$favList.MultiSelect = $true
$favList.HideSelection = $false
[void]$favList.Columns.Add('序', 46)
[void]$favList.Columns.Add('内容', 420)
[void]$favList.Columns.Add('编码', 280)

$favPanel = New-Object Windows.Forms.Panel

$btnFavAdd    = New-SideButton '添加' 12
$btnFavEdit   = New-SideButton '修改选中' 54
$btnFavDel    = New-SideButton '删除选中' 96
$btnFavClear  = New-SideButton '清空全部' 138
$btnFavReload = New-SideButton '重新载入' 180
$btnFavUp     = New-SideButton '上移' 232
$btnFavDown   = New-SideButton '下移' 274

$favHint = New-Object Windows.Forms.Label
$favHint.Left = 10
$favHint.Top = 318
$favHint.Width = 160
$favHint.Height = 200
$favHint.Text = "用法：`n· 打字时键入编码的前 3 位，内容就会出现在候选第 2 位（纯数字编码则把编码打完）。`n`n· 输入法里按 v → 3 也能搜索取用。`n`n· 这里的改动立即生效（输入法直接读这个文件）。"

function Refresh-Favorites {
  Load-Favorites
  $favList.BeginUpdate()
  $favList.Items.Clear()
  for ($i = 0; $i -lt $script:favs.Count; $i++) {
    $it = New-Object Windows.Forms.ListViewItem(("" + ($i + 1)))
    [void]$it.SubItems.Add($script:favs[$i].Word)
    [void]$it.SubItems.Add($script:favs[$i].Key)
    $it.Tag = $i
    [void]$favList.Items.Add($it)
  }
  $favList.EndUpdate()
  $favInfo.Text = "共 $($script:favs.Count) 条收藏。打字时键入编码前 3 位，内容会出现在候选第 2 位。"
}

function Edit-Favorite {
  param([int]$Index = -1)
  $dlg = New-Object Windows.Forms.Form
  $dlg.Text = if ($Index -ge 0) { '修改收藏' } else { '添加收藏' }
  $dlg.ClientSize = New-Object Drawing.Size(420, 190)
  $dlg.StartPosition = 'CenterParent'
  $dlg.FormBorderStyle = 'FixedDialog'
  $dlg.MaximizeBox = $false
  $dlg.MinimizeBox = $false
  $dlg.Font = $form.Font

  $l1 = New-Object Windows.Forms.Label
  $l1.Text = '内容（要上屏的文字）'; $l1.Left = 18; $l1.Top = 18; $l1.Width = 380
  $t1 = New-Object Windows.Forms.TextBox
  $t1.Left = 18; $t1.Top = 40; $t1.Width = 380

  $l2 = New-Object Windows.Forms.Label
  $l2.Text = '编码（拼音等，用于 vfav 搜索；可留空则与内容相同）'; $l2.Left = 18; $l2.Top = 74; $l2.Width = 380
  $t2 = New-Object Windows.Forms.TextBox
  $t2.Left = 18; $t2.Top = 96; $t2.Width = 380

  if ($Index -ge 0 -and $Index -lt $script:favs.Count) {
    $t1.Text = $script:favs[$Index].Word
    $t2.Text = $script:favs[$Index].Key
  }

  $ok = New-Object Windows.Forms.Button
  $ok.Text = '确定'; $ok.Left = 214; $ok.Top = 136; $ok.Width = 88; $ok.DialogResult = 'OK'
  $cancel = New-Object Windows.Forms.Button
  $cancel.Text = '取消'; $cancel.Left = 310; $cancel.Top = 136; $cancel.Width = 88; $cancel.DialogResult = 'Cancel'

  $dlg.Controls.AddRange(@($l1, $t1, $l2, $t2, $ok, $cancel))
  $dlg.AcceptButton = $ok
  $dlg.CancelButton = $cancel

  if ($dlg.ShowDialog($form) -ne [Windows.Forms.DialogResult]::OK) { return }
  $w = $t1.Text.Trim()
  $k = $t2.Text.Trim()
  if ($w.Length -eq 0) { [void][Windows.Forms.MessageBox]::Show('内容不能为空。', '提示'); return }
  if ($k.Length -eq 0) { $k = $w }
  if ($Index -ge 0) {
    $script:favs[$Index].Word = $w
    $script:favs[$Index].Key = $k
  } else {
    $script:favs = @($script:favs) + [pscustomobject]@{ Word = $w; Key = $k }
  }
  Save-Favorites
  Refresh-Favorites
  $statusLabel.Text = if ($Index -ge 0) { "已修改：$w" } else { "已添加：$w（编码 $k）" }
}

# ===== 设置页 =====
$tabSet.Padding = New-Object Windows.Forms.Padding(16)

$grpPage = New-Object Windows.Forms.GroupBox
$grpPage.Text = '剪贴板列表默认显示条数'
$grpPage.Left = 16; $grpPage.Top = 16; $grpPage.Width = 900; $grpPage.Height = 150
$grpPage.Anchor = 'Top,Left,Right'

$lblPage = New-Object Windows.Forms.Label
$lblPage.Text = '默认显示：'; $lblPage.Left = 18; $lblPage.Top = 34; $lblPage.Width = 70
$cmbPage = New-Object Windows.Forms.ComboBox
$cmbPage.Left = 90; $cmbPage.Top = 30; $cmbPage.Width = 90
$cmbPage.DropDownStyle = 'DropDownList'
[void]$cmbPage.Items.AddRange(@('20', '30', '40', '50'))

$btnPageSave = New-Object Windows.Forms.Button
$btnPageSave.Text = '保存'; $btnPageSave.Left = 196; $btnPageSave.Top = 29; $btnPageSave.Width = 88; $btnPageSave.Height = 28

$lblPageHint = New-Object Windows.Forms.Label
$lblPageHint.Left = 18; $lblPageHint.Top = 72; $lblPageHint.Width = 860; $lblPageHint.Height = 62
$lblPageHint.Text = "20 条是下限、50 条是上限（超出部分自动丢弃最旧的）。`n在输入法剪贴板列表里按 m 键（或 + 键）每次多看 10 条，翻页用 - / = 或鼠标滚轮。"

$grpClear = New-Object Windows.Forms.GroupBox
$grpClear.Text = '缓存清理（二次确认）'
$grpClear.Left = 16; $grpClear.Top = 180; $grpClear.Width = 900; $grpClear.Height = 130
$grpClear.Anchor = 'Top,Left,Right'

$lblClear = New-Object Windows.Forms.Label
$lblClear.Left = 18; $lblClear.Top = 30; $lblClear.Width = 860; $lblClear.Height = 40
$lblClear.Text = '清空剪贴板历史缓存：删除 clipboard-cache.txt 里的全部内容，不可恢复。'

$btnClearClip = New-Object Windows.Forms.Button
$btnClearClip.Text = '清理剪贴板缓存'; $btnClearClip.Left = 18; $btnClearClip.Top = 74; $btnClearClip.Width = 160; $btnClearClip.Height = 32

$btnClearFav = New-Object Windows.Forms.Button
$btnClearFav.Text = '清空全部收藏'; $btnClearFav.Left = 190; $btnClearFav.Top = 74; $btnClearFav.Width = 160; $btnClearFav.Height = 32

$grpFiles = New-Object Windows.Forms.GroupBox
$grpFiles.Text = '文件位置（改动即时写入）'
$grpFiles.Left = 16; $grpFiles.Top = 322; $grpFiles.Width = 900; $grpFiles.Height = 180
$grpFiles.Anchor = 'Top,Left,Right'

$tbFiles = New-Object Windows.Forms.TextBox
$tbFiles.Left = 18; $tbFiles.Top = 28; $tbFiles.Width = 860; $tbFiles.Height = 130
$tbFiles.Multiline = $true
$tbFiles.ReadOnly = $true
$tbFiles.ScrollBars = 'Vertical'
$tbFiles.BackColor = [Drawing.Color]::White
$tbFiles.Text = "剪贴板历史：$CLIP_PATH`r`n收藏：$FAV_PATH`r`n设置：$SET_PATH`r`n`r`n" +
  "提示：改完这里的内容后无需重启输入法；输入法每次打开 v 菜单都会重新读取。`r`n" +
  "若在输入法里改了内容想在这里看到，点「重新载入」即可。"

# ---------------------------------------------------------------------------
# 事件
# ---------------------------------------------------------------------------
$btnClipCopy.Add_Click({
  if ($clipList.SelectedItems.Count -eq 0) { return }
  $i = [int]$clipList.SelectedItems[0].Tag
  [Windows.Forms.Clipboard]::SetText($script:clip[$i])
  $statusLabel.Text = "已复制第 $($i + 1) 条到剪贴板"
})

$btnClipDel.Add_Click({
  if ($clipList.SelectedItems.Count -eq 0) { $statusLabel.Text = '请先选中要删除的条目'; return }
  $idx = @($clipList.SelectedItems | ForEach-Object { [int]$_.Tag }) | Sort-Object -Descending
  $n = $idx.Count
  if (-not (Confirm -Message "确定删除选中的 $n 条剪贴板记录？此操作不可恢复。" -Title '删除剪贴板记录')) { return }
  $list = New-Object System.Collections.ArrayList
  for ($i = 0; $i -lt $script:clip.Count; $i++) {
    if ($idx -notcontains $i) { [void]$list.Add($script:clip[$i]) }
  }
  $script:clip = @($list)
  Save-Clipboard
  Refresh-Clipboard
  $statusLabel.Text = "已删除 $n 条剪贴板记录"
})

$btnClipClear.Add_Click({
  if ($script:clip.Count -eq 0) { $statusLabel.Text = '剪贴板缓存已经是空的'; return }
  if (-not (Confirm -Message "确定清空全部 $($script:clip.Count) 条剪贴板历史？此操作不可恢复。" -Title '清空剪贴板缓存')) { return }
  $script:clip = @()
  Save-Clipboard
  Refresh-Clipboard
  $statusLabel.Text = '剪贴板缓存已清空'
})

$btnClipReload.Add_Click({ Refresh-Clipboard; $statusLabel.Text = '已重新载入' })

$btnClipTop.Add_Click({
  if ($clipList.SelectedItems.Count -eq 0) { return }
  $i = [int]$clipList.SelectedItems[0].Tag
  if ($i -eq 0) { return }
  $item = $script:clip[$i]
  $list = New-Object System.Collections.ArrayList
  [void]$list.Add($item)
  for ($j = 0; $j -lt $script:clip.Count; $j++) { if ($j -ne $i) { [void]$list.Add($script:clip[$j]) } }
  $script:clip = @($list)
  Save-Clipboard
  Refresh-Clipboard
  $statusLabel.Text = '已置顶'
})

$clipList.Add_DoubleClick({
  if ($clipList.SelectedItems.Count -eq 0) { return }
  $i = [int]$clipList.SelectedItems[0].Tag
  [Windows.Forms.Clipboard]::SetText($script:clip[$i])
  $statusLabel.Text = "已复制第 $($i + 1) 条到剪贴板"
})

$btnFavAdd.Add_Click({ Edit-Favorite -Index -1 })

$btnFavEdit.Add_Click({
  if ($favList.SelectedItems.Count -eq 0) { $statusLabel.Text = '请先选中要修改的条目'; return }
  Edit-Favorite -Index ([int]$favList.SelectedItems[0].Tag)
})

$btnFavDel.Add_Click({
  if ($favList.SelectedItems.Count -eq 0) { $statusLabel.Text = '请先选中要删除的条目'; return }
  $idx = @($favList.SelectedItems | ForEach-Object { [int]$_.Tag }) | Sort-Object -Descending
  $n = $idx.Count
  if (-not (Confirm -Message "确定删除选中的 $n 条收藏？此操作不可恢复。" -Title '删除收藏')) { return }
  $list = New-Object System.Collections.ArrayList
  for ($i = 0; $i -lt $script:favs.Count; $i++) {
    if ($idx -notcontains $i) { [void]$list.Add($script:favs[$i]) }
  }
  $script:favs = @($list)
  Save-Favorites
  Refresh-Favorites
  $statusLabel.Text = "已删除 $n 条收藏"
})

$btnFavClear.Add_Click({
  if ($script:favs.Count -eq 0) { $statusLabel.Text = '收藏已经是空的'; return }
  if (-not (Confirm -Message "确定清空全部 $($script:favs.Count) 条收藏？此操作不可恢复。" -Title '清空收藏')) { return }
  $script:favs = @()
  Save-Favorites
  Refresh-Favorites
  $statusLabel.Text = '收藏已全部清空'
})

$btnFavReload.Add_Click({ Refresh-Favorites; $statusLabel.Text = '已重新载入' })

$btnFavUp.Add_Click({
  if ($favList.SelectedItems.Count -eq 0) { return }
  $i = [int]$favList.SelectedItems[0].Tag
  if ($i -le 0) { return }
  $tmp = $script:favs[$i - 1]
  $script:favs[$i - 1] = $script:favs[$i]
  $script:favs[$i] = $tmp
  Save-Favorites
  Refresh-Favorites
  $favList.Items[$i - 1].Selected = $true
  $statusLabel.Text = '已上移'
})

$btnFavDown.Add_Click({
  if ($favList.SelectedItems.Count -eq 0) { return }
  $i = [int]$favList.SelectedItems[0].Tag
  if ($i -ge $script:favs.Count - 1) { return }
  $tmp = $script:favs[$i + 1]
  $script:favs[$i + 1] = $script:favs[$i]
  $script:favs[$i] = $tmp
  Save-Favorites
  Refresh-Favorites
  $favList.Items[$i + 1].Selected = $true
  $statusLabel.Text = '已下移'
})

$btnPageSave.Add_Click({
  $v = [int]$cmbPage.SelectedItem
  Save-Settings -Page $v
  Refresh-Clipboard
  $statusLabel.Text = "默认显示条数已保存为 $v 条"
})

$btnClearClip.Add_Click({
  if (-not (Confirm -Message "确定清理剪贴板历史缓存？`n`n这会删除 clipboard-cache.txt 的全部内容，不可恢复。" -Title '清理缓存 · 二次确认')) { return }
  $script:clip = @()
  Save-Clipboard
  Refresh-Clipboard
  $statusLabel.Text = '剪贴板缓存已清理'
})

$btnClearFav.Add_Click({
  if (-not (Confirm -Message "确定清空全部收藏？`n`n这会删除 favorites.dict.yaml 里的全部词条，不可恢复。" -Title '清空收藏 · 二次确认')) { return }
  $script:favs = @()
  Save-Favorites
  Refresh-Favorites
  $statusLabel.Text = '收藏已清空'
})

# ---------------------------------------------------------------------------
# 组装
# ---------------------------------------------------------------------------
$INFO_H = 48
$PANEL_W = 184
$GAP = 8

# 一切坐标都在这里按「控件的实际客户区」现算，因此在任何 DPI 缩放下都成立。
function Layout-Tabs {
  $w = $tabClip.ClientSize.Width
  $h = $tabClip.ClientSize.Height
  if ($w -lt 480) { $w = 960 }
  if ($h -lt 320) { $h = 560 }
  $clipInfo.SetBounds(0, 0, $w, $INFO_H)
  $clipList.SetBounds(0, $INFO_H, $w - $PANEL_W - $GAP, $h - $INFO_H)
  $clipPanel.SetBounds($w - $PANEL_W, $INFO_H, $PANEL_W, $h - $INFO_H)
  if ($clipList.Columns.Count -ge 2) {
    $clipList.Columns[1].Width = [Math]::Max(160, $clipList.Width - 56)
  }

  $w2 = $tabFav.ClientSize.Width
  $h2 = $tabFav.ClientSize.Height
  if ($w2 -lt 480) { $w2 = 960 }
  if ($h2 -lt 320) { $h2 = 560 }
  $favInfo.SetBounds(0, 0, $w2, $INFO_H)
  $favList.SetBounds(0, $INFO_H, $w2 - $PANEL_W - $GAP, $h2 - $INFO_H)
  $favPanel.SetBounds($w2 - $PANEL_W, $INFO_H, $PANEL_W, $h2 - $INFO_H)
  if ($favList.Columns.Count -ge 3) {
    $favList.Columns[1].Width = [Math]::Max(150, $favList.Width - 356)
    $favList.Columns[2].Width = [Math]::Max(140, $favList.Width - $favList.Columns[1].Width - 56)
  }
}

$clipPanel.Controls.AddRange(@($btnClipCopy, $btnClipDel, $btnClipClear, $btnClipReload, $btnClipTop, $clipHint))
$tabClip.Controls.Add($clipList)
$tabClip.Controls.Add($clipPanel)
$tabClip.Controls.Add($clipInfo)

$favPanel.Controls.AddRange(@($btnFavAdd, $btnFavEdit, $btnFavDel, $btnFavClear, $btnFavReload, $btnFavUp, $btnFavDown, $favHint))
$tabFav.Controls.Add($favList)
$tabFav.Controls.Add($favPanel)
$tabFav.Controls.Add($favInfo)

$grpPage.Controls.AddRange(@($lblPage, $cmbPage, $btnPageSave, $lblPageHint))
$grpClear.Controls.AddRange(@($lblClear, $btnClearClip, $btnClearFav))
$grpFiles.Controls.Add($tbFiles)
$tabSet.Controls.AddRange(@($grpPage, $grpClear, $grpFiles))

[void]$tabs.TabPages.Add($tabClip)
[void]$tabs.TabPages.Add($tabFav)
[void]$tabs.TabPages.Add($tabSet)
[void]$form.Controls.Add($tabs)
[void]$form.Controls.Add($status)

$tabClip.Add_Resize({ Layout-Tabs })
$tabFav.Add_Resize({ Layout-Tabs })

# 初始载入
Load-Settings
$cmbPage.SelectedItem = "$($script:pageSize)"
if ($null -eq $cmbPage.SelectedItem) { $cmbPage.SelectedIndex = 0 }
Layout-Tabs
Refresh-Clipboard
Refresh-Favorites

$form.Add_Shown({
  Layout-Tabs
  $form.Activate()
  if ($env:VMENU_GUI_DEBUG) {
    $dbg = New-Object System.Collections.ArrayList
    [void]$dbg.Add("form ClientSize = $($form.ClientSize.Width)x$($form.ClientSize.Height)")
    [void]$dbg.Add("form Bounds = $($form.Left),$($form.Top) $($form.Width)x$($form.Height)")
    [void]$dbg.Add("tabs = $($tabs.Left),$($tabs.Top) $($tabs.Width)x$($tabs.Height)")
    [void]$dbg.Add("tabClip client = $($tabClip.ClientSize.Width)x$($tabClip.ClientSize.Height)")
    foreach ($c in @($clipInfo, $clipList, $clipPanel, $btnClipCopy, $btnClipDel, $clipHint)) {
      [void]$dbg.Add(("{0} '{1}' = {2},{3} {4}x{5} vis={6} parentVisible={7}" -f `
        $c.GetType().Name, $c.Text, $c.Left, $c.Top, $c.Width, $c.Height, $c.Visible, $c.Parent.Visible))
    }
    try {
      $g = [Drawing.Graphics]::FromHwnd($form.Handle)
      [void]$dbg.Add("DpiX = $($g.DpiX)  DpiY = $($g.DpiY)")
      $g.Dispose()
    } catch { [void]$dbg.Add("DpiX query failed: $_") }
    [IO.File]::WriteAllLines((Join-Path $env:TEMP 'vmenu-gui-debug.txt'), $dbg)

    $form.Refresh()
    try {
      $bw = $form.ClientSize.Width
      $bh = $form.ClientSize.Height
      $bmp = New-Object Drawing.Bitmap($bw, $bh)
      $form.DrawToBitmap($bmp, (New-Object Drawing.Rectangle(0, 0, $bw, $bh)))
      $bmp.Save((Join-Path $env:TEMP 'vmenu-form-bitmap.png'), [Drawing.Imaging.ImageFormat]::Png)
      $bmp.Dispose()
    } catch {
      [IO.File]::AppendAllText((Join-Path $env:TEMP 'vmenu-gui-debug.txt'), "DrawToBitmap failed: $_`r`n")
    }
  }
})
# ---------------------------------------------------------------------------
# 常驻 + 秒开
#   进程起来时就把窗口建好（先摆到屏幕外 Show 一次再 Hide），之后每 60ms 看一次
#   标记文件。输入法按 v1 只写这个标记文件，所以窗口是「立刻」弹出来的 ——
#   不需要重新启动 PowerShell 再解析这 600 多行脚本（那要 2-4 秒，就是之前慢的原因）。
#   点 X 关窗不退出进程，只隐藏：下次 v1 依旧秒开。
#   真正退出：用 vmenu-watcher-stop.ps1 / clipboard-sync-stop.ps1，或直接结束进程。
# ---------------------------------------------------------------------------

function Take-Flag {
  try {
    if (Test-Path -LiteralPath $FLAG_PATH) {
      $txt = ([IO.File]::ReadAllText($FLAG_PATH)).Trim()
      Remove-Item -LiteralPath $FLAG_PATH -Force -ErrorAction SilentlyContinue
      return $txt
    }
  } catch { }
  return $null
}

function Hide-SettingsWindow {
  $form.Hide()
  $statusLabel.Text = '已隐藏 · 后台常驻，v→1 秒开'
}

function Center-SettingsWindow {
  # 居中到主屏工作区。本进程是 DPI 不感知的，所以这里的坐标和窗体自己的
  # 坐标空间一致（都是被系统缩放后的虚拟坐标），不需要换算。
  try {
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $form.StartPosition = 'Manual'
    $form.Location = New-Object Drawing.Point(
      [int]($wa.Left + ($wa.Width - $form.Width) / 2),
      [int]($wa.Top + ($wa.Height - $form.Height) / 2))
  } catch { }
}

function Show-SettingsWindow {
  if (-not $form.Visible) {
    Load-Settings
    $cmbPage.SelectedItem = "$($script:pageSize)"
    if ($null -eq $cmbPage.SelectedItem) { $cmbPage.SelectedIndex = 0 }
    Refresh-Clipboard
    Refresh-Favorites
    Layout-Tabs
  }
  # 位置：第一次居中；之后尊重用户拖动的位置，但窗口跑到屏幕外就拉回来
  if (-not $script:positioned) {
    Center-SettingsWindow
    $script:positioned = $true
  } elseif ($form.Left -lt -5000 -or $form.Top -lt -5000) {
    Center-SettingsWindow
  }
  $form.Show()
  if ($form.WindowState -eq [Windows.Forms.FormWindowState]::Minimized) {
    $form.WindowState = [Windows.Forms.FormWindowState]::Normal
  }
  try { [void]$form.Activate() } catch { }
  try { [void]$form.BringToFront() } catch { }
  # 前台窗口锁：TopMost 抖一下是最稳的置顶办法
  try { $form.TopMost = $true; $form.TopMost = $false } catch { }
  $statusLabel.Text = "已打开 · $(Get-Date -Format 'HH:mm:ss')"
}

$form.Add_FormClosing({
  param($sender, $e)
  if ($e.CloseReason -eq [Windows.Forms.CloseReason]::UserClosing) {
    $e.Cancel = $true
    Hide-SettingsWindow
  }
})

# 预建窗口句柄：在屏幕外真正 Show 一次再 Hide，把「第一次显示」要做的
# 布局 / 控件句柄创建工作提前做掉，这样用户第一次按 v→1 也是毫秒级；
# 屏幕外坐标（-32000）不会闪到用户。位置在第一次真正显示时再居中。
$script:positioned = $false
$form.StartPosition = 'Manual'
$form.Location = New-Object Drawing.Point(-32000, -32000)
$form.Show()
$form.Hide()

if ($ShowNow) { Show-SettingsWindow } else { $statusLabel.Text = '后台常驻 · v→1 打开' }

while (-not $form.IsDisposed) {
  [System.Windows.Forms.Application]::DoEvents()
  $flagText = Take-Flag
  if ($null -ne $flagText) {
    # 标记文件里写 hide 表示「隐藏窗口」（测试用）
    if ($flagText -eq 'hide') { Hide-SettingsWindow } else { Show-SettingsWindow }
  }
  Start-Sleep -Milliseconds 60
}

$mutex.ReleaseMutex()
$mutex.Dispose()
