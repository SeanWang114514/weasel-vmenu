# 编 Boost 静态库（Weasel 链接只用到 thread/serialization/wserialization 等几个）。
#
# 为什么不能直接 b2：
#   1) runner 上是 **Visual Studio 2026（v18.9.2）**，工具集 14.29.30133 / 14.44.35207 / 14.51.36231。
#      Boost 1.84 的 tools/build/src/engine/guess_toolset.bat 只会去找 VS2017…VS2022 的安装路径
#      （以及对应注册表键），碰到 VS18 一律「Could not find a suitable toolset」→ bootstrap 直接失败
#      → b2.exe 根本不存在。实测日志：Failed to build Boost.Build engine.
#   2) 就算编出 b2，它的 msvc.jam 也只认识 msvc-14.2 / msvc-14.3。
# 所以这里显式把工具集喂给 bootstrap（engine 支持 `bootstrap.bat vc143`），并用 user-config
# 把 cl.exe 的绝对路径告诉 b2，绕开一切注册表/vswhere 探测。
#
# 为什么 build.bat 的 `boost` 关键字不能用：它 call :build_boost，而 build.bat 里没有这个标签，
# 所以历史上 CI 从来没有成功编出过 Boost 库 —— 这才是 Weasel 一直
# LNK1104 libboost_*-vc143-mt-s-x64-1_84.lib 的根因。
#
# 策略（依次尝试，编出 >=4 个库就停）：
#   A) vcvars 14.29.30133：bootstrap vc142/vc143 + b2 的多种 toolset/user-config 写法
#   B) vcvars 默认（14.51）：同上
#   C) 全失败 → 用 GitHub 上带顶层 CMakeLists.txt 的 boost-1.84.0 源码树走 CMake（x64 + x86 各编一遍）
# 最后把 -vc14x- 的库名复制成 -vc143-（auto-link 头按 cl 19.51 请求 vc143 的名字）。
# 全过程写进 build-output.log（会作为 Release 附件发布），失败原因一眼可见。
$ErrorActionPreference = 'Continue'
$ws = $env:GITHUB_WORKSPACE
if (-not $ws) { $ws = (Get-Location).Path }
$br = Join-Path $ws 'deps\boost_1_84_0'
$log = Join-Path $ws 'build-output.log'
$stageLib = Join-Path $br 'stage\lib'

function Say([string]$m) {
  $m | Out-File -FilePath $log -Append -Encoding utf8
  Write-Host $m
}
function Get-LibCount {
  if (Test-Path $stageLib) { return @(Get-ChildItem $stageLib -Filter '*.lib' -ErrorAction SilentlyContinue).Count }
  return 0
}
function Run-Bat([string]$bat) {
  $p = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', "`"$bat`"" -Wait -NoNewWindow -PassThru
  return $p.ExitCode
}
function Dump([string]$path, [int]$tail) {
  if (Test-Path $path) {
    Say "--- $(Split-Path $path -Leaf) 尾部 $tail 行"
    Get-Content $path -Tail $tail -ErrorAction SilentlyContinue | Out-File -FilePath $log -Append -Encoding utf8
  } else {
    Say "--- $(Split-Path $path -Leaf) 不存在"
  }
}

Say '===== Boost 依赖库构建 ====='
Say "workspace=$ws"
Say "boost=$br 存在=$(Test-Path $br)"
if (-not (Test-Path $br)) { Say 'FATAL: 没有 Boost 源码目录'; exit 0 }
Say "stage\lib=$stageLib 现有库数=$(Get-LibCount)"

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vs = ''
if (Test-Path $vswhere) { $vs = (& $vswhere -latest -products * -property installationPath | Select-Object -First 1) }
$vcvarsall = Join-Path $vs 'VC\Auxiliary\Build\vcvarsall.bat'
$msvcRoot = Join-Path $vs 'VC\Tools\MSVC'
Say "VS=$vs"
Say "vcvarsall=$vcvarsall 存在=$(Test-Path $vcvarsall)"
$toolsets = @()
if (Test-Path $msvcRoot) { $toolsets = @(Get-ChildItem $msvcRoot -Directory | Sort-Object Name -Descending | ForEach-Object { $_.Name }) }
Say "工具集: $($toolsets -join ', ')"

function Find-Cl([string]$ver) {
  $root = if ($ver) { Join-Path $msvcRoot $ver } else { $msvcRoot }
  return Get-ChildItem $root -Recurse -Filter cl.exe -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match 'Hostx64\\x64' } |
    Sort-Object FullName -Descending | Select-Object -First 1
}
function Find-BootstrapVer([string]$ver) {
  # engine 只支持到 vc143；14.2x/14.3x 用 vc142 或 vc143 都行（同一个 cl.exe，只是编译参数分支）
  if ($ver -like '14.2*') { return @('vc142', 'vc143') }
  return @('vc143', 'vc142')
}

$b2args = '--with-thread --with-serialization --with-wserialization --with-system --with-filesystem --with-date_time --with-chrono --with-atomic --with-regex link=static runtime-link=static threading=multi address-model=32,64 variant=release stage'

$vcConfigs = @()
if ($toolsets -contains '14.29.30133') { $vcConfigs += [pscustomobject]@{ Ver = '14.29.30133'; Cl = (Find-Cl '14.29.30133') } }
$vcConfigs += [pscustomobject]@{ Ver = ''; Cl = (Find-Cl '') }

foreach ($vc in $vcConfigs) {
  if ((Get-LibCount) -ge 4) { break }
  $verArg = if ($vc.Ver) { " -vcvars_ver=$($vc.Ver)" } else { '' }
  $vcTag = if ($vc.Ver) { $vc.Ver } else { '默认' }
  $clPath = if ($vc.Cl) { $vc.Cl.FullName } else { '' }
  Say "=== vcvars $vcTag （cl=$clPath）"

  # --- bootstrap：显式喂工具集，绕开 guess_toolset 的 VS 版本探测 ---
  foreach ($bsVer in (Find-BootstrapVer $vc.Ver)) {
    if (Test-Path (Join-Path $br 'b2.exe')) { break }
    $bat = Join-Path $ws 'ci-bootstrap.bat'
    $lines = @(
      '@echo off',
      "call `"$vcvarsall`" x64$verArg > `"$br\vcvars.log`" 2>&1",
      'if errorlevel 1 (echo VCVARS_FAILED & exit /b 21)',
      "cd /d `"$br`"",
      "call bootstrap.bat $bsVer > bootstrap.log 2>&1",
      'if not exist b2.exe exit /b 22',
      'exit /b 0'
    )
    Set-Content -Path $bat -Value $lines -Encoding ASCII
    $code = Run-Bat $bat
    Say "bootstrap.bat $bsVer 退出码=$code  b2.exe 存在=$(Test-Path (Join-Path $br 'b2.exe'))"
    if ($code -ne 0) { Dump (Join-Path $br 'bootstrap.log') 12 }
  }
  if (-not (Test-Path (Join-Path $br 'b2.exe'))) { Say 'b2.exe 仍未生成，跳过这个 vcvars 组合的 b2 尝试'; continue }

  # --- b2：user-config 指到绝对路径的 cl.exe，再退到自动探测 ---
  $uc = Join-Path $ws 'ci-user-config.jam'
  $tsVer = if ($vc.Ver -like '14.2*') { '14.2' } elseif ($vc.Ver -like '14.3*') { '14.3' } else { '' }
  $b2Runs = @()
  if ($clPath -and $tsVer) {
    "using msvc : $tsVer : `"$clPath`" ;" | Out-File -FilePath $uc -Encoding ascii
    $b2Runs += [pscustomobject]@{ Name = "toolset=msvc-$tsVer + user-config($tsVer)"; Ts = "msvc-$tsVer"; Uc = $uc }
    $b2Runs += [pscustomobject]@{ Name = "toolset=msvc-$tsVer"; Ts = "msvc-$tsVer"; Uc = '' }
  }
  if ($clPath) {
    "using msvc : : `"$clPath`" ;" | Out-File -FilePath $uc -Encoding ascii
    $b2Runs += [pscustomobject]@{ Name = 'toolset=msvc + user-config(无版本)'; Ts = 'msvc'; Uc = $uc }
  }
  $b2Runs += [pscustomobject]@{ Name = '自动 toolset'; Ts = ''; Uc = '' }

  foreach ($r in $b2Runs) {
    if ((Get-LibCount) -ge 4) { break }
    $tsArg = if ($r.Ts) { " toolset=$($r.Ts)" } else { '' }
    $ucArg = if ($r.Uc) { " --user-config=`"$($r.Uc)`"" } else { '' }
    $bat = Join-Path $ws 'ci-b2.bat'
    $lines = @(
      '@echo off',
      "call `"$vcvarsall`" x64$verArg > `"$br\vcvars.log`" 2>&1",
      'if errorlevel 1 (echo VCVARS_FAILED & exit /b 21)',
      "cd /d `"$br`"",
      "b2.exe$tsArg$ucArg -j4 $b2args > b2.log 2>&1",
      'exit /b %ERRORLEVEL%'
    )
    Set-Content -Path $bat -Value $lines -Encoding ASCII
    $code = Run-Bat $bat
    Say "b2 [$($r.Name)] 退出码=$code  库数=$(Get-LibCount)"
    if ((Get-LibCount) -lt 4) { Dump (Join-Path $br 'b2.log') 30 }
  }
}

if ((Get-LibCount) -lt 4) {
  Say '===== b2 全部尝试失败，退回 CMake 构建 Boost ====='
  # archives.boost.io 的源码包是老式布局（没有顶层 CMakeLists.txt，实测 CMake 直接报
  # "does not appear to contain CMakeLists.txt"）；GitHub 上 boostorg/boost 的 release 包
  # 才是带顶层 CMakeLists.txt 的 CMake 版源码树。头文件仍用老布局那棵树（Weasel 的 $(BOOST_ROOT) 指它）。
  $csrc = Join-Path $ws 'deps\boost-cmake-src'
  if (-not (Test-Path (Join-Path $csrc 'CMakeLists.txt'))) {
    New-Item -ItemType Directory -Force -Path (Join-Path $ws 'deps') | Out-Null
    $tgz = Join-Path $ws 'boost-cmake.tar.gz'
    try {
      Invoke-WebRequest 'https://github.com/boostorg/boost/releases/download/boost-1.84.0/boost-1.84.0.tar.gz' -OutFile $tgz -TimeoutSec 900
      tar -xzf $tgz -C (Join-Path $ws 'deps')
      Remove-Item $tgz -Force
      if ((Test-Path (Join-Path $ws 'deps\boost-1.84.0\CMakeLists.txt')) -and -not (Test-Path (Join-Path $csrc 'CMakeLists.txt'))) {
        Move-Item (Join-Path $ws 'deps\boost-1.84.0') $csrc -Force
      }
    } catch { Say "下载 CMake 版 Boost 失败：$($_.Exception.Message)" }
  }
  Say "CMake 源码树=$csrc 有顶层 CMakeLists=$(Test-Path (Join-Path $csrc 'CMakeLists.txt'))"

  $incs = 'thread;serialization;filesystem;date_time;chrono;atomic;regex;system'
  foreach ($arch in @(@{ A = 'x64'; V = 'x64'; Tag = 'x64' }, @{ A = 'x86'; V = 'x86'; Tag = 'x32' })) {
    if (-not (Test-Path (Join-Path $csrc 'CMakeLists.txt'))) { break }
    $cbd = Join-Path $ws ("deps\boost-cmake-" + $arch.A)
    $cmlog = Join-Path $ws ("cmake-boost-" + $arch.A + ".log")
    $bat = Join-Path $ws ("ci-cmake-boost-" + $arch.A + ".bat")
    $lines = @(
      '@echo off',
      "call `"$vcvarsall`" $($arch.V) > nul 2>&1",
      "cmake -S `"$csrc`" -B `"$cbd`" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded -DBUILD_SHARED_LIBS=OFF -DBOOST_INCLUDE_LIBRARIES=`"$incs`" -DCMAKE_POLICY_VERSION_MINIMUM=3.5 > `"$cmlog`" 2>&1",
      'if errorlevel 1 exit /b 31',
      "cmake --build `"$cbd`" --config Release -j 4 >> `"$cmlog`" 2>&1",
      'exit /b %ERRORLEVEL%'
    )
    Set-Content -Path $bat -Value $lines -Encoding ASCII
    Say "cmake $($arch.A) 退出码=$(Run-Bat $bat)"
    Dump $cmlog 25
    New-Item -ItemType Directory -Force -Path $stageLib | Out-Null
    $found = @(Get-ChildItem $cbd -Recurse -Filter '*.lib' -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'boost' })
    Say "cmake $($arch.A) 产出 .lib 数=$($found.Count)"
    foreach ($f in $found) {
      $id = ($f.BaseName -replace '^lib', '') -replace '^boost_', ''
      $id = ($id -split '-')[0]
      Copy-Item $f.FullName (Join-Path $stageLib ("libboost_{0}-vc143-mt-s-{1}-1_84.lib" -f $id, $arch.Tag)) -Force
    }
  }
}

# 把 -vc142-/-vc144-/-vc145- 复制成 -vc143-（auto-link 头按 cl 19.51 请求 vc143）
$made = 0
Get-ChildItem $stageLib -Filter '*.lib' -ErrorAction SilentlyContinue | ForEach-Object {
  if ($_.Name -notmatch 'vc143') {
    $new = $_.Name -replace '-vc14\d-', '-vc143-'
    if ($new -ne $_.Name) {
      $dst = Join-Path $stageLib $new
      if (-not (Test-Path $dst)) { Copy-Item $_.FullName $dst -Force; $made++ }
    }
  }
}
Say "生成 -vc143- 别名 $made 个"
Say "最终 stage\lib 库数=$(Get-LibCount)"
Get-ChildItem $stageLib -Filter '*.lib' -ErrorAction SilentlyContinue |
  Select-Object -First 40 -ExpandProperty Name | Out-File -FilePath $log -Append -Encoding utf8
Say '===== Boost 构建结束 ====='
exit 0
