# 把 CI 编出来的 weasel.dll / weaselx64.dll / WeaselServer.exe 装进小狼毫安装目录，
# **并同步换掉系统目录里那两个 TSF 客户端 DLL**。
#
# 网格布局（WeaselUI/HorizontalLayout）、序号（GetLabelText 覆写）和方向键导航
# （RimeWithWeasel）都编译在 WeaselServer.exe 里（它持有 UI host 和 RimeWithWeaselHandler），
# 所以安装目录那三个文件必须一起换；而**应用真正加载的 weasel.dll 在系统目录**
# （注册表 InprocServer32 指向 System32 / SysWOW64），只换安装目录等于没换。
#
# 安全约定（血泪教训）：
#   * 三个文件必须同时存在，缺一个就整体拒绝（半套会让输入法直接不工作）。
#   * 先备份到 BackupRoot\<时间戳>（系统目录那两个放进 system-dlls 子目录），
#     再改名（已被加载的文件不能覆盖、但可以改名），最后复制新的进来。
#   * 绝不碰 rime.dll（那是 librime 引擎，本项目不改它）。
#   * 旧 WeaselServer.exe 会先备份（包括它旁边可能存在的 .vmenu-bak 标记）。
param(
  [string]$Zip,
  [string]$SourceDir,
  [string]$InstallDir = 'C:\Program Files\Rime\weasel-0.17.4',
  [string]$BackupRoot = 'D:\weasel-build\dll-backup',
  [switch]$Force,
  [switch]$SkipSystemDlls      # 只换安装目录（一般不要用：应用侧不会变）
)

$ErrorActionPreference = 'Stop'
$targets = @('weasel.dll', 'weaselx64.dll', 'WeaselServer.exe')

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
  throw ("包里缺少 {0} —— 拒绝安装（半套会让输入法失灵）。找到的内容：{1}" -f ($missing -join ', '), (
      (Get-ChildItem $src.Dir -Recurse -File | Select-Object -First 20 -ExpandProperty Name) -join ', '))
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $BackupRoot $stamp
New-Item -ItemType Directory -Force -Path $backup | Out-Null

Write-Host '== 当前安装目录里的文件 =='
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
    Move-Item $dst $old -Force        # 被加载中的文件不能覆盖，但可以改名
  }
  Copy-Item $new $dst -Force
  $i = Get-Item $dst
  Write-Host ("装入 {0}  {1} bytes  md5={2}" -f $n, $i.Length, (Get-FileHash $dst -Algorithm MD5).Hash)
}

Start-Process (Join-Path $InstallDir 'WeaselServer.exe')
Start-Sleep -Seconds 3
Write-Host ("WeaselServer 运行中: {0}" -f [bool](Get-Process WeaselServer -ErrorAction SilentlyContinue))

# ============================================================================
# ★ 第 2 步：TSF 客户端 DLL **不在安装目录**，必须同时换系统目录里那两个 ★
#   HKLM\SOFTWARE\Classes\CLSID\{A3F4CDED-B1E9-41EE-9CA6-7B4D0DE6CB0A}\InprocServer32
#     → C:\Windows\System32\weasel.dll      （x64，来自 weaselx64.dll）
#     → WOW6432Node\...\InprocServer32      （x86，来自 weasel.dll）
#       …实际文件在 C:\Windows\SysWOW64\weasel.dll
#   只换安装目录 = 应用侧**一点变化都没有**（实测 md5 对比确认过），会误判成「补丁没生效」。
# ============================================================================
if (-not $SkipSystemDlls) {
  $sysPairs = @(
    @{ Dst = Join-Path $env:WINDIR 'System32\weasel.dll'; Src = 'weaselx64.dll'; Arch = 'x64' },
    @{ Dst = Join-Path $env:WINDIR 'SysWOW64\weasel.dll'; Src = 'weasel.dll';    Arch = 'x86' }
  )
  $sysBackup = Join-Path $backup 'system-dlls'
  New-Item -ItemType Directory -Force -Path $sysBackup | Out-Null

  foreach ($p in $sysPairs) {
    if (-not (Test-Path $p.Dst)) { Write-Host ("跳过 {0}（不存在）" -f $p.Dst); continue }
    $before = (Get-FileHash $p.Dst -Algorithm MD5).Hash
    Copy-Item $p.Dst (Join-Path $sysBackup ("weasel-{0}.dll" -f $p.Arch)) -Force
    # 已被无数进程加载的 DLL 不能直接覆盖，但可以改名。
    # ⚠️ 旧名必须唯一：上次留下的 weasel.dll.grid-old 仍被运行中的程序加载着、删不掉，
    #    固定复用同一个名字会撞成「当文件已存在时，无法创建该文件」而整步跳过（踩过）。
    $old = "$($p.Dst).old-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    try {
      Move-Item $p.Dst $old -Force
    } catch {
      Write-Host ("⚠️ 无法改名 {0}（{1}）—— 可能需要管理员权限；跳过" -f $p.Dst, $_.Exception.Message)
      continue
    }
    Copy-Item $src.Files[$p.Src].FullName $p.Dst -Force
    $after = (Get-FileHash $p.Dst -Algorithm MD5).Hash
    Write-Host ("装入 {0}  [{1}]  {2} bytes  md5={3}（原 md5={4}）" -f `
        $p.Dst, $p.Arch, (Get-Item $p.Dst).Length, $after, $before)
    if ($after -ne (Get-FileHash $src.Files[$p.Src].FullName -Algorithm MD5).Hash) {
      Write-Host '  ⚠️ md5 与新文件不一致，请人工确认！'
    }
  }
  Write-Host ''
  Write-Host '★ 换了 weasel.dll：**必须重启要用输入法的程序**（记事本等）才会加载新 DLL。'
}

Write-Host ''
Write-Host '完成。回滚：把备份目录里的同名文件复制回去（安装目录 3 个 + system-dlls 里 2 个），再重启 WeaselServer。'
Write-Host '⚠️ 重启服务后确认没被微信输入法抢走活动权：'
Write-Host '   (Get-Process notepad).Modules | ? ModuleName -match "weasel|wetype"   # 只应有 weasel.dll'
