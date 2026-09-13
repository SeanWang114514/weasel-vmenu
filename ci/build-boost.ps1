# 编 Boost 静态库（Weasel 链接只用到 thread/serialization/wserialization 等几个）。
#
# 为什么不能直接 b2：runner 上只有 VS 18，工具集是 14.29.30133 / 14.44.35207 / 14.51.36231，
# 而 Boost 1.84 的 b2 只认识 msvc-14.2 / msvc-14.3，自动探测碰到 14.5x 会直接失败；
# 另外 build.bat 里的 `boost` 关键字是坏的（它 call :build_boost，但文件里没有这个标签），
# 所以历史上 CI 从来没有成功编出过 Boost 库 —— 这才是 Weasel 一直
# LNK1104 libboost_*-vc143-mt-s-x64-1_84.lib 的根因。
#
# 策略（依次尝试，编出 >=4 个库就停）：
#   1) vcvars -vcvars_ver=14.29.30133 + toolset=msvc-14.2   ← b2 认识这套，最稳
#   2) 同上但不指定 toolset
#   3) vcvars 默认（最新工具集）+ 自动
#   4) vcvars 默认 + user-config 指定 cl.exe
#   5) 全失败 → 退回 CMake 构建（Boost 1.84 自带 CMakeLists）
# 最后把 -vc14x- 的库名复制成 -vc143-（auto-link 头按编译器 19.51 请求 vc143 的名字）。
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

$b2args = '--with-thread --with-serialization --with-wserialization --with-system --with-filesystem --with-date_time --with-chrono --with-atomic --with-regex link=static runtime-link=static threading=multi address-model=32,64 variant=release stage'

$attempts = @()
if ($toolsets -contains '14.29.30133') {
  $attempts += [pscustomobject]@{ Name = 'vcvars 14.29.30133 + toolset=msvc-14.2'; Ver = '14.29.30133'; Ts = 'msvc-14.2'; UserConf = $false }
  $attempts += [pscustomobject]@{ Name = 'vcvars 14.29.30133 + 自动 toolset'; Ver = '14.29.30133'; Ts = ''; UserConf = $false }
}
$attempts += [pscustomobject]@{ Name = 'vcvars 默认 + 自动 toolset'; Ver = ''; Ts = ''; UserConf = $false }
$attempts += [pscustomobject]@{ Name = 'vcvars 默认 + toolset=msvc + user-config'; Ver = ''; Ts = 'msvc'; UserConf = $true }

foreach ($a in $attempts) {
  if ((Get-LibCount) -ge 4) { break }
  if ($a.Ver -and -not ($toolsets -contains $a.Ver)) { Say "跳过（本机没有工具集 $($a.Ver)）：$($a.Name)"; continue }
  Say "--- 尝试：$($a.Name)"

  $verArg = if ($a.Ver) { " -vcvars_ver=$($a.Ver)" } else { '' }
  $tsArg = if ($a.Ts) { " toolset=$($a.Ts)" } else { '' }
  $ucArg = ''
  if ($a.UserConf) {
    $cl = Get-ChildItem $msvcRoot -Recurse -Filter cl.exe -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -match 'Hostx64\\x64' } | Select-Object -First 1
    if ($cl) {
      $uc = Join-Path $ws 'ci-user-config.jam'
      "using msvc : : `"$($cl.FullName)`" ;" | Out-File -FilePath $uc -Encoding ascii
      $ucArg = " --user-config=`"$uc`""
      Say "user-config -> cl: $($cl.FullName)"
    } else {
      Say '找不到 cl.exe，跳过这次尝试'
      continue
    }
  }

  $bat = Join-Path $ws 'ci-b2.bat'
  $lines = @(
    '@echo off',
    "call `"$vcvarsall`" x64$verArg > `"$br\vcvars.log`" 2>&1",
    'if errorlevel 1 (echo VCVARS_FAILED & exit /b 21)',
    "cd /d `"$br`"",
    'if not exist b2.exe call bootstrap.bat > bootstrap.log 2>&1',
    'if not exist b2.exe (echo BOOTSTRAP_FAILED & exit /b 22)',
    "b2.exe$tsArg$ucArg -j4 $b2args > b2.log 2>&1",
    'exit /b %ERRORLEVEL%'
  )
  Set-Content -Path $bat -Value $lines -Encoding ASCII
  $code = Run-Bat $bat
  Say "b2 退出码=$code  库数=$(Get-LibCount)"
  Dump (Join-Path $br 'vcvars.log') 10
  Dump (Join-Path $br 'bootstrap.log') 15
  Dump (Join-Path $br 'b2.log') 40
}

if ((Get-LibCount) -lt 4) {
  Say '===== b2 全部尝试失败，退回 CMake 构建 Boost ====='
  $cbd = Join-Path $ws 'deps\boost-cmake'
  $cmlog = Join-Path $ws 'cmake-boost.log'
  $incs = 'thread;serialization;filesystem;date_time;chrono;atomic;regex;system'
  $bat = Join-Path $ws 'ci-cmake-boost.bat'
  $lines = @(
    '@echo off',
    "call `"$vcvarsall`" x64 > `"$br\vcvars-cmake.log`" 2>&1",
    "cmake -S `"$br`" -B `"$cbd`" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded -DBUILD_SHARED_LIBS=OFF -DBOOST_INCLUDE_LIBRARIES=`"$incs`" -DCMAKE_POLICY_VERSION_MINIMUM=3.5 > `"$cmlog`" 2>&1",
    'if errorlevel 1 exit /b 31',
    "cmake --build `"$cbd`" --config Release -j 4 >> `"$cmlog`" 2>&1",
    'exit /b %ERRORLEVEL%'
  )
  Set-Content -Path $bat -Value $lines -Encoding ASCII
  Say "cmake 退出码=$(Run-Bat $bat)"
  Dump $cmlog 40

  New-Item -ItemType Directory -Force -Path $stageLib | Out-Null
  $found = @(Get-ChildItem $cbd -Recurse -Filter '*.lib' -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'boost' })
  Say "CMake 产出 .lib 数=$($found.Count)"
  foreach ($f in $found) {
    $id = ($f.BaseName -replace '^lib', '') -replace '^boost_', ''
    $id = ($id -split '-')[0]
    foreach ($arch in 'x64', 'x32') {
      Copy-Item $f.FullName (Join-Path $stageLib ("libboost_{0}-vc143-mt-s-{1}-1_84.lib" -f $id, $arch)) -Force
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
