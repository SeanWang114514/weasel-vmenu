# 彻底重启浏览器（让浏览器重新加载 weasel.dll）
#
# 为什么需要它：
#   候选窗是由**客户端 weasel.dll** 在进程内画的。TSF DLL 是进程内加载的，
#   所以换了 DLL 之后，**换 DLL 之前就已经开着的**程序（Chrome / 微信 / 编辑器）里
#   还是旧代码 —— 表现为：没有序号、候选按宽度折行、方向键行为不对。
#   注意：Chrome「关掉所有窗口」不等于退出（它还有后台进程），必须结束进程 / 用 chrome://restart。
#
# 用法（在 PowerShell 里）：
#   pwsh -NoProfile -ExecutionPolicy Bypass -File tools\restart-browsers.ps1
#   pwsh ... -File tools\restart-browsers.ps1 -Also Edge,WeChat
param(
  [string[]]$Also = @(),
  # 重启后自动打开的页面（默认把本会话的 Web GUI 打开，免得你找不到对话）
  [string]$Reopen = 'http://127.0.0.1:3080',
  [switch]$DryRun
)

$names = @('chrome', 'msedge') + $Also
$killed = @()
foreach ($n in $names) {
  $ps = @(Get-Process -Name $n -ErrorAction SilentlyContinue)
  if (-not $ps) { Write-Host ("  {0}: 没在运行" -f $n); continue }
  $oldest = ($ps | Sort-Object StartTime | Select-Object -First 1).StartTime
  Write-Host ("  {0}: {1} 个进程，最早启动于 {2}" -f $n, $ps.Count, $oldest.ToString('HH:mm:ss'))
  if ($DryRun) { Write-Host ("    [DryRun] 不结束 {0}" -f $n); continue }
  $ps | Stop-Process -Force -ErrorAction SilentlyContinue
  $killed += $n
  Write-Host ("    ✅ 已结束 {0}" -f $n)
}

if (-not $DryRun -and $killed.Count) {
  Start-Sleep 2
  if ($killed -contains 'chrome') {
    $chrome = @(
      "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
      "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
      "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($chrome) {
      Start-Process $chrome -ArgumentList $Reopen
      Write-Host ("  ✅ 已重新打开 Chrome: {0}" -f $Reopen)
    } else { Write-Host "  ⚠️ 没找到 chrome.exe，请手动打开" }
  }
  Write-Host ""
  Write-Host "现在检查一下新进程的启动时间（应该是刚刚）："
  foreach ($n in $killed) {
    Get-Process -Name $n -ErrorAction SilentlyContinue |
      Where-Object { $_.MainWindowHandle -ne 0 } |
      Select-Object -First 3 |
      ForEach-Object { Write-Host ("    {0,-8} pid {1,-7} 启动 {2}" -f $_.Name, $_.Id, $_.StartTime.ToString('HH:mm:ss')) }
  }
  Write-Host ""
  Write-Host "重启后在那个程序里打拼音试：候选词前应有 1-9；按 ↓ 展开成 9×4 网格。"
  Write-Host "如果仍然没有序号，就在该窗口按 Win+空格 切到「小狼毫」（Windows 会按程序记住输入法）。"
} elseif ($DryRun) {
  Write-Host ""
  Write-Host "（DryRun：什么都没动）"
}
