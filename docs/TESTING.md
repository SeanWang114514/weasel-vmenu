# 测试与验证（TESTING）

## 0. 原则

1. **真按键 + 截图**：不靠「读代码觉得对」。每个结论都要有一张图或一次真按键的输出。
2. **看 `AFTER=` 判据**：`tools/type-and-shot.ps1` 会打印目标窗口标题（记事本标题=文档内容），
   这比截图更硬。
3. **测延迟要测到「窗口真的在屏幕上」**：`MainWindowHandle != 0` 不够（曾经窗口停在
   -48000,-48000 也被判定为「已显示」），必须同时 `GetWindowRect` 的 `Left/Top > -1000`。
4. **改完 lua 先重启服务再测**，并等 ≥ 6 秒（方案没加载完就打字会丢按键）。
5. **回归矩阵**（每次改动都要过一遍）：

| 用例 | 按键 | 期望 |
| --- | --- | --- |
| 普通拼音 | `n,i` | 候选 你/尼/泥…，不受影响 |
| 纯数字（非编码） | `1,2,3,4,5,enter` | 原样 `12345` |
| 字母编码 + 回车 | `w,s,l,enter` | 收藏内容上屏 |
| 字母编码 + 候选第 2 位 | `w,s,l,2` | 收藏内容上屏 |
| 纯数字编码 | `1,3,8` | 候选直接显示常用语内容 |
| v 菜单 | `esc,v` | **4 个**短候选（设置 / 剪贴板 / 常用语 / 原符号） |
| v 菜单第 5 项 | `esc,v,5` | **不再有反应**（第 5 项已去掉；`vset*` 保留但菜单不可达） |
| 常用语列表 | `esc,v,3` | 常用语快查列表 |
| 设置窗口 | `esc,v,1` | 窗口出现在屏幕上（< 300 ms） |
| 多行候选框 | 打一段拼音刷出 ≥ 6 条候选 | 候选超过一行宽度（`max_width=300`）时自动折行，一页最多 18 条 |
| 候选框方向键 | 候选窗口里按 `↓` / `→` | 选中下一个候选（**不上屏**）；`↑` = 上一个；Lua 不拦截 |
| 托盘「输入法设置」 | 直接运行 `WeaselDeployer.exe`（无参数 —— 这就是那个菜单项真正做的事） | 设置窗口出现；已在跑时被常驻实例亮出来（见 §7） |

---

## 1. 工具（`tools/`）

### `type-and-shot.ps1` —— 主力工具

```powershell
# 干净记事本 → 抢焦点 → 真按键 → 截图
Get-Process notepad -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Process notepad; Start-Sleep -Seconds 2
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\type-and-shot.ps1 `
  -Target notepad -Keys 'esc,w,s,l,enter' -Out .\shots\x.png `
  -ShotX 0 -ShotY 40 -ShotW 1700 -ShotH 560
# 输出：FOCUSED=<窗口标题>  AFTER=<按完之后的标题=文档内容>  SHOT=<文件>
```

* 抢焦点用 `AttachThreadInput` + `BringWindowToTop` + 先按一下 ALT 解锁前台锁
  —— 这台机器上 Chrome 会不断抢前台，普通 `SetForegroundWindow` 拿不到。
* `-NoClick` 可以不做「点击编辑区」这一步（默认会点一下确保焦点在文本框）。

### 延迟测试

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\v1-latency-test.ps1 -Runs 3
# gui pid = … / run 1: window visible after 72 ms / min = 56 ms max = 72 ms avg = 65 ms

powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\v1-e2e-test.ps1 -Out .\shots\e2e.png
# hidden before test = True
# v then 1 : settings window visible after 84 ms
# flag consumed = True
```

`v1-latency-test.ps1` 先写 `hide` 把窗口藏起来，再写时间戳，之后每 5 ms 轮询；
`v1-e2e-test.ps1` 真的按 `v` 和 `1`（会先聚焦记事本）。

### `gui-dblclick-test.ps1` —— 设置窗口「双击编辑」验证

GUI 自动化在这个项目里**不能走 UI Automation**（原因见 §2「测试工具本身的坑」），
只能「截图找行 + 真实鼠标双击」：

```powershell
# 剪贴板页第 1 行双击 → 期望弹出「编辑第 1 条」
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\gui-dblclick-test.ps1 `
  -Row 1 -Out .\shots\dblclick.png

# 先点一下窗口内坐标切到常用语标签页，再双击第 1 行（期望「修改常用语」）
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\gui-dblclick-test.ps1 `
  -PreX 300 -PreY 200 -Row 1 -Expect '修改常用语'

# 端到端：双击后往弹框输入 ASCII 并回车（会真的改文件！）
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\gui-dblclick-test.ps1 -Row 1 -TypeInto test
```

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `-Match` | `小狼毫 v 功能` | 窗口标题子串 |
| `-Row` | `1` | 要双击第几行文本（在列表区域内从上往下数） |
| `-ListTop` / `-ListLeft` / `-ListRight` / `-ListBottom` | `200` / `150` / `1400` / `800` | 列表区域（默认 `ListTop=200` 是为了跳过表头） |
| `-PreX` / `-PreY` | `-1`（不做） | 先点一下窗口内坐标，例如切标签页 |
| `-Expect` | `编辑第` | 期望弹框标题的前缀 |
| `-TypeInto` | 空 | 往弹框输入这段 ASCII 并回车（**会真的写文件**，测完记得还原） |
| `-Out` | 空 | 保存一张双击前的窗口截图 |
| `-DryRun` | 关 | 只找到行、不真的双击 |

**退出码**：`0` = 弹框如期出现（或 `-DryRun` 正常完成）；`1` = 失败（没找到行 / 弹框没出现）；
`2` = 找不到窗口。

**实测几何**（150% 缩放、窗口 1464×989、窗口左上角在屏幕 549,189）：
表头 y≈176..206，数据行高 30 px，**第 1 行中心 y≈210、第 2 行 ≈240、第 3 行 ≈270**。
`ListTop=200` 刚好跳过表头。

### 其它

| 工具 | 用途 |
| --- | --- |
| `run-vmenu-tests.ps1` | 18 步菜单流程逐张截图（`shots\vmenu\`） |
| `shot-window.ps1 -Match ' v '` | 只抓设置窗口（DPI-aware） |
| `window-keys-shot.ps1 -Match ' v ' -Keys 'ctrl+tab'` | 抢前台 + 发组合键 + 抓窗口（切设置窗口标签页用） |
| `list-windows.ps1 -MinWidth 600` | 列出可见窗口：`pid / hwnd / 物理坐标 / 标题` |
| `ime-test.ps1` | 老版按键+截图（记事本会移到 80,60） |
| `focus-notepad.ps1` | 只抢焦点 |
| `vmenu-tray-setup.ps1` | 托盘菜单入口「输入法设置」的**安装 / 撤销**（`-Revert`），以及 exe 菜单文字的回读校验（见 §7） |

---

## 2. 截图取证的坑

| 坑 | 说明 |
| --- | --- |
| **候选栏比 1200 px 宽** | 3 条长收藏的候选栏能到 1300 px。抓宽一点（`-ShotW 1700`），否则右边被截断 |
| **别把桌面截进去** | 截图会带进桌面侧边栏/其它窗口。裁到内容区域：见下面的「暗像素包围盒」办法 |
| **DPI** | 本进程 `SetProcessDPIAware()` 后是**物理坐标**（2560×1440）；不感知的话是虚拟坐标（1707×960）。`GetWindowRect` 抓到的是物理的，别和虚拟混用 |
| **窗口可能停在屏幕外** | 判断「可见」必须同时看句柄和 rect（见原则 3） |
| **前台窗口不是你要的那个** | 抓图前先 `window-keys-shot.ps1`（它内部会抢前台并校验 `FOREGROUND_OK=True`） |

### 自动定位候选栏（裁图用）

候选行在截图里是一大片深色像素，扫一遍就能得到包围盒：

```powershell
Add-Type -AssemblyName System.Drawing
$bmp = [Drawing.Bitmap]::FromFile($raw)
$minX=99999;$maxX=-1;$minY=99999;$maxY=-1
for ($y=150; $y -lt 330; $y++) { for ($x=0; $x -lt $bmp.Width; $x++) {
  $c=$bmp.GetPixel($x,$y); if (($c.R+$c.G+$c.B)/3 -lt 150) {
    if($x -lt $minX){$minX=$x}; if($x -gt $maxX){$maxX=$x}
    if($y -lt $minY){$minY=$y}; if($y -gt $maxY){$maxY=$y} } } }
"bbox: x $minX..$maxX  y $minY..$maxY"   # 例：x 83..1340  y 161..259
```

然后用 `Graphics.DrawImage` 裁出 `(x-20, y-20, w+40, h+40)`。

### 测试工具本身的坑（改测试脚本前必读）

| 坑 | 现象 | 做法 |
| --- | --- | --- |
| **UI Automation 看不到设置窗口的子控件** | `System.Windows.Automation` 的 `FindAll(Descendants, TrueCondition)` 返回 **0 个元素**（TabItem / Button / List 全是 0） | 这个 WinForms 窗口的 GUI 自动化**只能走「截图 + 真实鼠标」**，见 `gui-dblclick-test.ps1`。别再试 UIA 选择器 |
| **进程不 DPI-aware 时坐标会被放大 1.5 倍** | `SetCursorPos` 传进去的坐标被系统按 150% 缩放，点击落到下面几行（实测点到第 9 行而以为是第 1 行） | 使用前先调 `SetProcessDPIAware()`（`shot-window.ps1` 里也有同样说明） |
| **模态弹框不出现在 `Process.MainWindowTitle` 里** | `Get-Process \| Where MainWindowTitle` 找不到弹框 | 用 `EnumWindows` + `GetWindowTextW` 枚举顶层窗口标题（`gui-dblclick-test.ps1` 的 `[VmWin]::Find`） |
| **脚本会把自己杀掉** | 在命令行里写出脚本字面名，再用 `Get-CimInstance Win32_Process \| Where CommandLine -like '*vmenu-settings*'` 去杀进程 → 连自己一起杀，表现为 `[exit code: 4294967295]` | 排除 `$PID`，并把脚本名在运行时拼接（`'vmenu-' + 'settings-gui.ps1'`） |

---

## 3. 怎么生成「不含真实数据」的截图

发布用的截图**必须**是示例数据。做法（本项目实际用过）：

1. 复制 `examples/favorites.example.dict.yaml` 覆盖真实的常用语文件，
   **先备份并记录 SHA256**：
   ```powershell
   Copy-Item $real $bak -Force
   "backup sha256 = $((Get-FileHash $bak -Algorithm SHA256).Hash)"
   Copy-Item examples\favorites.example.dict.yaml $real -Force
   ```
2. 抓图（输入法侧用示例编码，如 `you` / `138`）。
3. **还原并校验**：
   ```powershell
   Copy-Item $bak $real -Force
   (Get-FileHash $real -Algorithm SHA256).Hash -eq (Get-FileHash $bak -Algorithm SHA256).Hash  # 必须 True
   ```
4. 设置窗口的截图用**独立的演示目录**（例如 `C:\rime-demo`），不要动真实目录：
   ```powershell
   # 先停掉监督者和常驻窗口，避免两个实例抢互斥体
   powershell -NoProfile -ExecutionPolicy Bypass -File .\src\windows\vmenu-watcher-stop.ps1
   Start-Process powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden',
     '-File','.\src\windows\vmenu-settings-gui.ps1','-RimeDir','C:\rime-demo','-ShowNow') -WindowStyle Hidden
   # 抓图 → 结束后再双击 clipboard-sync.bat 把真实服务拉回来
   ```

---

## 4. 静态检查

```powershell
# 1) PowerShell 语法（PS 5.1）
$errs = $null
[void][System.Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($f), [ref]$errs)
if ($errs.Count) { $errs | ForEach-Object { "line $($_.Token.StartLine): $($_.Message)" } }
# 更严格的写法（能抓到「无 BOM 的 UTF-8 被按 ANSI 解析」导致的多字节吃引号错误）：
$e = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$e)
if ($e) { $e | ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Message)" } }   # 期望无输出

# 2) BOM 检查（含中文的 .ps1 必须带 BOM）
(([IO.File]::ReadAllBytes($p)[0..2]) -join ',')      # 期望 239,187,191

# 2b) 托盘代理源码同样必须带 BOM（csc 按 GBK 读无 BOM 的源码，中文提示会变乱码）
(([IO.File]::ReadAllBytes('.\src\windows\vmenu-deployer-wrapper.cs')[0..2]) -join ',')   # 期望 239,187,191

# 3) bat 编码检查（必须 CRLF + 纯 ASCII）
$b=[IO.File]::ReadAllBytes($bat); ($b | Where-Object {$_ -gt 127}).Count   # 期望 0

# 4) 两个 lua 目录一致性
foreach ($f in 'vmenu_core.lua','menu_processor.lua','lua_menu.lua','menu_filter.lua') {
  (Get-FileHash "D:\rime-sandbox\lua\$f" -Algorithm MD5).Hash -eq
  (Get-FileHash "$env:APPDATA\Rime\lua\$f" -Algorithm MD5).Hash
}   # 全部期望 True

# 5) 改完候选框配置（build/*.yaml）后的两件必做的事
#    5a. 用 UTF-8 读回确认中文没被改写（绝不要用 Get-Content/Set-Content 去改）
[IO.File]::ReadAllText("D:\rime-sandbox\build\weasel.yaml", [Text.Encoding]::UTF8).Contains('max_width: 300')
#    5b. 重启 WeaselServer 后看日志里没有 YAML 解析错误
Get-ChildItem "$env:TEMP\rime.weasel\*.log" | Sort-Object LastWriteTime -Descending |
  Select-Object -First 1 | Get-Content | Select-String 'Error parsing'   # 必须无输出
```

---

## 5. 实测记录（本机 2560×1440 @150%，Weasel 0.17.4）

| 指标 | 数值 |
| --- | --- |
| 标记文件 → 窗口在屏幕上（稳态） | 45 / 56 / 63 / 71 / 72 ms（avg 65 ms） |
| 真按 `v` → `1` → 窗口出现 | 84 / 94 / 103 / 106 ms |
| 后台进程刚启动后的第一次显示 | 106–180 ms（离屏预建前约 348 ms） |
| 改动前（每次重启 PowerShell + 解析 700 行脚本） | 2000–4000 ms |
| 打字命中常用语（`wsl`） | 无感（≥ 3 字符才读一次小文件） |
| 多行候选框 | `max_width=300` 换行、`620` 不换行；`page_size=18` → 约 4 行 × 5 列 |

> 「进程刚启动后的第一次显示」会明显偏大（180 ms）：守护进程拉起窗口进程、WinForms
> 初始化、首次布局都在这一次里完成。稳态（窗口进程已常驻）是 45–72 ms。

---

## 6. 本次迭代（0.2.0）的验收结论

| # | 验收项 | 结论 |
| --- | --- | --- |
| 1 | `v` 菜单项数 | 只有 **4 项**（`1 设置 / 2 剪贴板 / 3 常用语 / 4 原符号`）；按 `5` 无反应；手打 `vset` 仍能进设置根菜单 |
| 2 | 「收藏」→「常用语」 | 菜单项、`v`→`3` 列表标题/空态/搜索提示、候选第 2 位注释、设置窗口标签页与按钮文案全部显示「常用语」；`favorites.dict.yaml` / `vfav` / `vset*` / `vmenu-settings.txt` 未改 |
| 3 | 多行候选框 | `max_width: 300` 时一页 18 条候选换行排成每行约 5 个（约 4 行 × 5 列）；按 `↓` 高亮在**同一行内**移动（窗口内 y 197..257）；`620` 实测不换行 |
| 4 | 方向键行为 | `↓` = 选中下一个候选、`→` = 选中下一个候选、`↑` = 上一个，都**不上屏**（librime 1.13.1，横向候选框） |
| 5 | 设置窗口双击编辑（剪贴板页） | 双击第 1 行 → 弹出「编辑第 1 条」→ 输入 `test` + 回车 → `clipboard-cache.txt` **第 1 行确实变成 `test`** → 随后还原真实数据并**校验 sha256 一致** |
| 6 | 设置窗口双击编辑（常用语页） | 双击某一行 → 弹出 `修改常用语`（与点「修改选中」等价） |
| 7 | 截图 | `screenshots/` 下 `ime-01`/`ime-05`/`ime-06`、`gui-01`〜`gui-04` 全部为示例数据 |

复现命令（验收项 5、6）：

```powershell
# 5) 剪贴板页：双击第 1 行 → 弹框 → 输入并回车（会真的改文件，先备份！）
$p = 'D:\rime-sandbox\clipboard-cache.txt'
Copy-Item $p "$p.bak" -Force
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\gui-dblclick-test.ps1 `
  -Row 1 -Expect '编辑第' -TypeInto test -Out .\shots\gui-04-dblclick-edit.png
(Get-Content $p -Encoding UTF8)[0]                 # 期望：test
Copy-Item "$p.bak" $p -Force
(Get-FileHash $p -Algorithm SHA256).Hash -eq (Get-FileHash "$p.bak" -Algorithm SHA256).Hash   # 期望 True

# 6) 常用语页：先点标签页，再双击第 1 行
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\gui-dblclick-test.ps1 `
  -PreX 300 -PreY 200 -Row 1 -Expect '修改常用语'
```

---

## 7. 本次迭代（0.2.1）的验收结论：托盘菜单「输入法设置」

| # | 验收项 | 结论 |
| --- | --- | --- |
| 1 | 改完**回读** `WeaselServer.exe` | 新标签 `输入法设置 (&S)` 命中 **1 处**、旧标签 `输入法设定 (&S)` **0 处** |
| 2 | 该菜单项的**命令号** | 从 `IDR_MENU_POPUP`（资源 105）读出 = **40008**，与源码 `include/resource.h` 的 `ID_WEASELTRAY_SETTINGS` 一致 |
| 3 | 菜单文本片段顺序 | `输入法设置 (&S)` / `用户词典管理 (&D)` / `用户资料同步 (&N)` / … 与用户截图一致 |
| 4 | 触发方式 = 该菜单项真正做的事（**直接运行 `WeaselDeployer.exe`（无参数）**） | 设置窗口没在跑 → 新实例启动、窗口出现（标题 `小狼毫 v 功能 · 可视化设置`）；已在跑 → 常驻实例把窗口亮出来（走 `open-settings.flag` 那条路） |
| 5 | 代理透传 `/deploy` | 真的执行了部署：`D:\rime-sandbox\build\weasel.yaml` 与 `build\rime_ice.schema.yaml` 在 02:14:52/53 被重新生成，日志只有 INFO 无 Error；**`max_width: 300`、`page_size: 18` 都还在**（它们在 `weasel.custom.yaml` / `rime_ice.custom.yaml` 的 patch 里）→ **重新部署不会弄丢多行候选框** |
| 6 | 设置窗口新按钮 | 点「打开小狼毫原生设置」→ 弹出标题 `【小狼毫】方案选单设定`（截图 `screenshots/gui-05-native-settings.png` 是设置窗口里的「小狼毫原生设置」分组与按钮） |

### 7.1 安装 / 幂等 / 撤销的测试方法与命令

```powershell
# ① 安装（幂等；脚本会自己停 / 起 WeaselServer，并重新编译代理）
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\vmenu-tray-setup.ps1
# 结尾几行就是判据：
#   校验：exe 里 旧标签=0 处 / 新标签=1 处
#   文件：WeaselDeployer.exe=5632 字节，WeaselDeployer.real.exe=… 字节（本机 638976）
#   服务：WeaselServer PID=…

# ② 幂等：紧接着再跑一次
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\vmenu-tray-setup.ps1
# 期望：「WeaselServer.exe 备份已存在，沿用（不会被覆盖）」
#       「菜单项文字已经是「输入法设置」，跳过」
#       `.real.exe` 已存在时不再重复改名；代理每次都会重新编译并覆盖安装
```

```powershell
# ③ 独立回读（不依赖脚本输出）：按 UTF-16 数标签出现次数
$exe = 'C:\Program Files\Rime\weasel-0.17.4\WeaselServer.exe'
$b   = [IO.File]::ReadAllBytes($exe)
$old = [Text.Encoding]::Unicode.GetBytes(([char]0x8F93)+([char]0x5165)+([char]0x6CD5)+([char]0x8BBE)+([char]0x5B9A)+' (&S)')  # 输入法设定 (&S)
$new = [Text.Encoding]::Unicode.GetBytes(([char]0x8F93)+([char]0x5165)+([char]0x6CD5)+([char]0x8BBE)+([char]0x7F6E)+' (&S)')  # 输入法设置 (&S)
function Count-All($hay, $needle) {
  $n = 0
  for ($i = 0; $i -le $hay.Length - $needle.Length; $i++) {
    if ($hay[$i] -ne $needle[0]) { continue }
    $ok = $true
    for ($j = 1; $j -lt $needle.Length; $j++) { if ($hay[$i + $j] -ne $needle[$j]) { $ok = $false; break } }
    if ($ok) { $n++ }
  }
  $n
}
"旧标签 = $(Count-All $b $old) 处 / 新标签 = $(Count-All $b $new) 处"   # 期望：旧标签 = 0 处 / 新标签 = 1 处
```

（同一套计数逻辑脚本内部也有：`Find-All` + `Test-Label`。标签用字符码拼出来是为了不受文件编码影响。）

```powershell
# ④ 撤销（会真的还原两个 exe 与开始菜单快捷方式名字）
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\vmenu-tray-setup.ps1 -Revert
# 期望输出：
#   已还原 WeaselServer.exe（来自 …\WeaselServer.exe.vmenu-bak）
#   已把 WeaselDeployer.real.exe 改名回 WeaselDeployer.exe
#   校验：exe 里 旧标签=1 处，新标签=0 处
# 撤销后想再装回来，重跑 ① 即可

# ⑤ 代理透传（验收 5 的复现；会真的重新部署）
& 'C:\Program Files\Rime\weasel-0.17.4\WeaselDeployer.exe' /deploy
Get-Item 'D:\rime-sandbox\build\weasel.yaml','D:\rime-sandbox\build\rime_ice.schema.yaml' | Select-Object Name, LastWriteTime
[IO.File]::ReadAllText('D:\rime-sandbox\build\weasel.yaml', [Text.Encoding]::UTF8).Contains('max_width: 300')          # 期望 True
[IO.File]::ReadAllText('D:\rime-sandbox\build\rime_ice.schema.yaml', [Text.Encoding]::UTF8).Contains('page_size: 18') # 期望 True
Get-ChildItem "$env:TEMP\rime.weasel\*.log" | Sort-Object LastWriteTime -Descending |
  Select-Object -First 1 | Get-Content | Select-String 'Error'    # 期望无输出

# ⑥ 设置窗口新按钮（人眼验收）：打开设置窗口 → 「设置与缓存」页 → 点「打开小狼毫原生设置」
#    期望弹出标题为「【小狼毫】方案选单设定」的对话框
```

> 托盘项**不用真的去点**：这一项做的事就是「无参数运行 `WeaselDeployer.exe`」（脚本 + 资源回读都已确认
> 命令号 = 40008 且服务端对它的处理就是启动这个 exe），所以第 4 条用直接运行来验收。
