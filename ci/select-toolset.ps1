# 选工具集：weasel.props/vcxproj 把 PlatformToolset 写死成 v142，而 runner 上的 VS 18
# 只有 14.51.36231 那套装了 ATL（14.29/14.44 都是 ATL=False），于是编译报
# C1083 atlbase.h / RC1015 afxres.h。MSB8052 又说明 14.51 对应的工具集名字是 v145。
#
# 这里不再无脑改写：先看 v142（14.2x）到底有没有 ATL —— 有就一个字都不改（本地/老 runner
# 就是这种情况）；没有才把工程里的 v142 换成「装了 ATL 的那套工具集」对应的名字。
# 名字规则是 MSVC 自己的：14.2x→v142、14.3x→v143、14.4x→v144、14.5x→v145。
$ErrorActionPreference = 'Continue'
$ws = $env:GITHUB_WORKSPACE
if (-not $ws) { $ws = (Get-Location).Path }
$log = Join-Path $ws 'build-output.log'

function Say([string]$m) {
  $m | Out-File -FilePath $log -Append -Encoding utf8
  Write-Host $m
}

function Get-ToolsetName([string]$v) {
  $p = $v.Split('.')
  if ($p.Count -ge 2 -and $p[1].Length -ge 1) { return ('v14' + $p[1].Substring(0, 1)) }
  return $null
}

Say '===== 工具集选择 ====='
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vs = ''
if (Test-Path $vswhere) { $vs = (& $vswhere -latest -products * -property installationPath | Select-Object -First 1) }
Say "VS=$vs"
$msvcRoot = Join-Path $vs 'VC\Tools\MSVC'
$rows = @()
if (Test-Path $msvcRoot) {
  $rows = @(Get-ChildItem $msvcRoot -Directory | ForEach-Object {
    [pscustomobject]@{
      Name    = $_.Name
      Atl     = (Test-Path (Join-Path $_.FullName 'atlmfc\include\atlbase.h'))
      Toolset = (Get-ToolsetName $_.Name)
    }
  })
}
foreach ($r in $rows) { Say ("  工具集 {0}  ATL={1}  -> {2}" -f $r.Name, $r.Atl, $r.Toolset) }

$v142 = $rows | Where-Object { $_.Name -like '14.2*' -and $_.Atl } | Select-Object -First 1
$atl = @($rows | Where-Object { $_.Atl } | Sort-Object Name -Descending)
$target = $null
if ($v142) {
  Say 'v142(14.2x) 自带 ATL —— 工程文件保持原样，不做任何改写'
} elseif ($atl.Count -gt 0) {
  $target = $atl[0].Toolset
  Say "v142 没有 ATL，改用 $($atl[0].Name) 对应的 $target"
} else {
  Say 'FATAL: 这台机器上没有任何装了 ATL 的工具集'
  exit 0
}

if ($target) {
  $n = 0
  Get-ChildItem $ws -Recurse -Include *.vcxproj, *.props -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\deps\\boost_' } |
    ForEach-Object {
      $raw = Get-Content $_.FullName -Raw
      if ($raw -match 'v142') {
        Set-Content -Path $_.FullName -Value ($raw -replace 'v142', $target) -Encoding utf8 -NoNewline
        $n++
      }
    }
  Say "已把 $n 个工程文件里的 v142 改为 $target"
  "PLATFORM_TOOLSET=$target" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8
  "PlatformToolset=$target" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8

  $tsRoot = Join-Path $msvcRoot $atl[0].Name
  $inc = Join-Path $tsRoot 'atlmfc\include'
  $lib = Join-Path $tsRoot 'atlmfc\lib\x64'
  Say "ATL include=$inc lib=$lib"
  if (Test-Path $inc) { "INCLUDE=$inc" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8 }
  # ATL 链接库不再走 _LINK_（x64/x86 的库目录不同，写死会出错），改由仓库根的 Directory.Build.props
  # 按 $(PlatformShortName) 给 Weasel* 工程加 atls.lib + atlthunk.lib（见该文件注释）。
}
exit 0
