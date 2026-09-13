# 把 CI 编出来的 weasel.dll / weaselx64.dll 装进小狼毫安装目录。
#
# 安全约定（血泪教训）：
#   * 只替换 weasel.dll 与 weaselx64.dll —— 绝不碰 WeaselServer.exe（它带着本项目的托盘菜单补丁，
#     且旁边有 WeaselServer.exe.vmenu-bak）。
#   * 两个 DLL 必须同时存在，缺一个就整体拒绝（半套 DLL 会让输入法直接不工作）。
#   * 先备份，再改名（已被客户端进程加载的 DLL 不能覆盖，但可以改名），最后才复制新的进来。
param(
  [string]$Zip,
  [string]$SourceDir,
  [string]$InstallDir = 'C:\Program Files\Rime\weasel-0.17.4',
  [string]$BackupRoot = 'D:\weasel-build\dll-backup',
  [switch]$Force
)

$ErrorActionPreference = 'Stop'
$targets = @('weasel.dll', 'weaselx64.dll')

function Get-Source([string]$dir) {
  $tmp = Join-Path $env:TEMP ('grid-dlls-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  if ($Zip) {
    if (-not (Test-Path $Zip)) { throw "找不到 zip：$Zip" }
    Expand-Archive -Path $Zip -DestinationPath $tmp -Force
  } elseif ($SourceDir) {
    Copy-Item (Join-Path $SourceDir '*') $tmp -Recurse -Force
  } else {
    throw '必须给 -Zip 或 -SourceDir'
  }
  # 递归找，取最新的一份
  $files = @{}
  foreach ($n in $targets) {
    $f = Get-ChildItem $tmp -Recurse -File -Filter $n -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($f) { $files[$n] = $f }
  }
  return @{ Dir = $tmp; Files = $files }
}

$src = Get-Source
$missing = @($targets | Where-Object { -not $src.Files.ContainsKey($_) })
if ($missing.Count -gt 0) {
  throw ("包里缺少 {0} —— 拒绝安装（半套 DLL 会让输入法失灵）。找到的内容：{1}" -f ($missing -join ', '), (
      (Get-ChildItem $src.Dir -Recurse -File | Select-Object -First 20 -ExpandProperty Name) -join ', '))
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $BackupRoot $stamp
New-Item -ItemType Directory -Force -Path $backup | Out-Null

Write-Host '== 当前安装目录里的 DLL =='
foreach ($n in $targets) {
  $p = Join-Path $InstallDir $n
  if (Test-Path $p) {
    $i = Get-Item $p
    Write-Host ("  {0}  {1} bytes  {2}" -f $n, $i.Length, $i.LastWriteTime)
    Copy-Item $p (Join-Path $backup $n) -Force
  } else {
    Write-Host "  $n 不存在"
  }
}
Write-Host "已备份到 $backup"

# 停服务（只停 server，不动别的）
Get-Process WeaselServer -ErrorAction SilentlyContinue | ForEach-Object {
  Write-Host "停 WeaselServer (pid $($_.Id))"
  try { $_.CloseMainWindow() | Out-Null } catch {}
  Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2

foreach ($n in $targets) {
  $dst = Join-Path $InstallDir $n
  $new = $src.Files[$n].FullName
  if (Test-Path $dst) {
    $old = "$dst.grid-old"
    Remove-Item $old -Force -ErrorAction SilentlyContinue
    Move-Item $dst $old -Force        # 被加载中的 DLL 不能覆盖，但可以改名
  }
  Copy-Item $new $dst -Force
  $i = Get-Item $dst
  Write-Host ("装入 {0}  {1} bytes  md5={2}" -f $n, $i.Length, (Get-FileHash $dst -Algorithm MD5).Hash)
}

Start-Process (Join-Path $InstallDir 'WeaselServer.exe')
Start-Sleep -Seconds 3
Write-Host ("WeaselServer 运行中: {0}" -f [bool](Get-Process WeaselServer -ErrorAction SilentlyContinue))
Write-Host '完成。如果输入法表现异常，把备份目录里的同名 DLL 复制回去再重启 WeaselServer 即可回滚。'
