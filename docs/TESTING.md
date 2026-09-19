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
| v 菜单 | `esc,v` | **5 个**短候选（设置 / 剪贴板 / 快捷输入 / 常用语 / 原符号） |
| v 菜单第 3 项 | `esc,v,3` | 打开**快捷输入**子菜单（9 项 + 返回；原来的「文字设置」已去掉，`vset*` 保留但菜单不可达） |
| v 菜单第 4 项 | `esc,v,4` | 打开**常用语**列表（候选注释「常用语 wsl」这类） |
| v 菜单第 5 项 | `esc,v,5` | **原符号**：输入回到 `v`，之后走原版 `v` 候选（`vac / van / var …`） |
| 快捷输入 · 计算（字母键） | `esc,v,3,c` 再敲 `1+2*3`，空格上屏 → **7** |
| 快捷输入 · 计算（数字键） | `esc,v,3,1` 再敲 `1+2*3`，空格上屏 → **7** |
| 快捷输入 · 数字货币转写 | `esc,v,3,h` 再敲 `123`，空格上屏 → **一百二十三** |
| 快捷输入 · Unicode | `esc,v,3,u` 再敲 `4e2d`，空格上屏 → **中** |
| 快捷输入 · 农历输入 | `esc,v,3,n`，空格上屏 → 今天的农历（如 丙午马年八月初九） |
| 快捷输入 · 日期 / 时间 | `esc,v,3,r` → 今天日期；`esc,v,3,s` → 当前时间 |
| 快捷输入 · 子菜单宽度 | `esc,v,3` 后整条候选必须完整可见（**≤1000px**；超 1500px 说明注释写长了，屏幕会裁掉尾部） |
| v2 退格取消 | `esc,v,2` 后按 **Backspace** → 候选窗关闭、**什么都不上屏**（网页里 textarea 长度保持 0） |
| v2 退格取消（带筛选词） | `esc,v,2` 再打几个字母筛选，按 Backspace 同样整个作废 |
| v2 正常上屏（回归） | `esc,v,2` 后按 `1` → 上屏第一条剪贴板 |
| 剪贴板管理列表不受影响（回归） | 设置窗口 → 剪贴板管理：退格仍是删一个字，不是清空 || 直输原前缀（不删） | `cC`+`1*2`→2 · `R`+`123`→一百二十三 · `U`+`4e2d`→中 · `rq`→日期 · `sj`→时间 | 候选第一项 = **7**（`9*9` → **81**） |
| 快捷输入 · 日期/时间/星期/日期时间 | `esc,v,5,2`（`3` / `4` / `5`） | 今天的日期 / `HH:MM` / `星期日` / ISO 时间戳 |
| 快捷输入 · 农历 | `esc,v,5,6` | 今天的农历（按 `6` 时已把当天 `YYYYMMDD` 填进去） |
| 快捷输入 · 数字大写 / Unicode | `esc,v,5,7` 再敲 `1234` / `esc,v,5,8` 再敲 `4e2d` | **一千二百三十四** / **中** |
| 快捷输入 · 部件拆字 | `esc,v,5,9` 再敲 `nvzi` | **好** |
| 部件拆字（不经菜单） | `u` 再敲 `nvzi`（或 `riyue`） | **好** / **明**；旧的 `uU` 写法已失效 |
| 常用语列表 | `esc,v,3` | 常用语快查列表 |
| 设置窗口 | `esc,v,1` | 窗口出现在屏幕上（< 300 ms） |
| 候选方格（收起） | 打一段拼音刷出 ≥ 10 条候选 | 收起时只有 **9** 个（因序号注释排成 **2 行**，窗口高 144），带 1–9 序号 |
| 候选方格（展开） | 候选窗口里按 1 次 `↓` | 展开成 **36 个 = 4 行 × 9 列**（高 287）✅，只有第一行有 1–9 |
| 候选方格（再按 `↓`） | 展开后再按 1 次 `↓` | **收回**成 9 个（高 287 → 144）✅，**不上屏**（0.2.4 修的 bug） |
| 候选方格（收回） | 展开后按 `↑` | 收回（高 287 → 144）✅ |
| 方向键移动选中项 | 展开后 `↓` / `↑` / `←` / `→` 再按空格 | ✗ **做不到**：四个方向键都不移动选中项，空格总是上屏第 1 个（对照：数字键 `1`→是、`2`→师 ✅）。原因是没有 API，见 §8.3 |
| 序号不影响上屏 | `shi`+空格 / `shi`+`3` | 分别上屏 是 / 师（序号只是注释，不进上屏文字） |
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
#    5a. 用 UTF-8 读回确认中文没被改写、值也对（绝不要用 Get-Content/Set-Content 去改）
$t = [IO.File]::ReadAllText("D:\rime-sandbox\build\weasel.yaml", [Text.Encoding]::UTF8)
$t.Contains('max_width: 530')                        # ⚠️ 0.2.5 起换行改由自编 DLL 控制，这项不再是判定条件
[regex]::IsMatch($t, 'label_format:\s*"\s*"')        # 期望 True（留空 = 不画原生序号，序号改由自编 DLL 的标签槽提供）
# 确认跑的是自编的网格版 server（原版 2243072 字节，没有换行 / 序号 / 方向键补丁）：
(Get-Item 'C:\Program Files\Rime\weasel-0.17.4\WeaselServer.exe').Length   # 期望 2755584
[IO.File]::ReadAllText("D:\rime-sandbox\build\rime_ice.schema.yaml", [Text.Encoding]::UTF8).Contains('page_size: 36')  # 期望 True
#    5b. 重启 WeaselServer 后看日志里没有 YAML 解析错误
#        （在 build 产物里手插一行时最容易踩：缩进必须与被插入的键同级 —— 本文件里是 2 个空格；
#         写成 4 个空格会报 config_data.cc Error parsing YAML ... illegal map value，
#         症状是 schema 整个失效：一个候选都不出、打字直接出字母）
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
| 候选方格（0.2.3 起） | 打 `shi` → 候选窗口 **797 × 74**（单行 9 个）；按 `↓` → **797 × 285**（4 行 × 9 列）；第一行按 `↑` → 回到 797 × 74 |

> 「进程刚启动后的第一次显示」会明显偏大（180 ms）：守护进程拉起窗口进程、WinForms
> 初始化、首次布局都在这一次里完成。稳态（窗口进程已常驻）是 45–72 ms。

---

## 6. 本次迭代（0.2.0）的验收结论

| # | 验收项 | 结论 |
| --- | --- | --- |
| 1 | `v` 菜单项数 | 只有 **4 项**（`1 设置 / 2 剪贴板 / 3 常用语 / 4 原符号`）；按 `5` 无反应；手打 `vset` 仍能进设置根菜单（**0.2.2 起第 5 项改为「快捷输入」，见 §8**） |
| 2 | 「收藏」→「常用语」 | 菜单项、`v`→`3` 列表标题/空态/搜索提示、候选第 2 位注释、设置窗口标签页与按钮文案全部显示「常用语」；`favorites.dict.yaml` / `vfav` / `vset*` / `vmenu-settings.txt` 未改 |
| 3 | 多行候选框 | `max_width: 300` 时一页 18 条候选换行排成每行约 5 个（约 4 行 × 5 列）；按 `↓` 高亮在**同一行内**移动（窗口内 y 197..257）；`620` 实测不换行（**0.2.3 起这套参数已换成 `530` / `36` + 按 `↓` 展开，见 §8**） |
| 4 | 方向键行为 | **第二轮（横向单行候选框时期）**：`↓` = 选中下一个候选、`→` = 选中下一个候选、`↑` = 上一个，都**不上屏**（librime 1.13.1）。**0.2.3 起普通打字时方向键改由 `grid_key` 接管**（`↓` / `↑` = 展开 / 收回）。**0.2.5 起移动选中项由自编 DLL 补丁实现**（`↓`+9 / `↑`-9 / `←`-1 / `→`+1，不上屏），`+` 下翻，见 §8.3 与 `GRID-CANDIDATE-DLL.md` |
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
| 5 | 代理透传 `/deploy` | 真的执行了部署：`D:\rime-sandbox\build\weasel.yaml` 与 `build\rime_ice.schema.yaml` 在 02:14:52/53 被重新生成，日志只有 INFO 无 Error；**`max_width: 300`、`page_size: 18` 都还在**（它们在 `weasel.custom.yaml` / `rime_ice.custom.yaml` 的 patch 里）→ **重新部署不会弄丢多行候选框**（0.2.3 起这两个值是 **`530` / `36`**，见 §8） |
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
#       「WeaselDeployer.exe 已经是代理，跳过改名」（0.2.2 起按「大小是否等于代理」判断；
#         若当前是升级后的真身，会先改名成 .real.exe 再装代理）
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
[IO.File]::ReadAllText('D:\rime-sandbox\build\weasel.yaml', [Text.Encoding]::UTF8).Contains('max_width: 530')          # 期望 True（0.2.3 起；原来是 300）
[IO.File]::ReadAllText('D:\rime-sandbox\build\rime_ice.schema.yaml', [Text.Encoding]::UTF8).Contains('page_size: 36') # 期望 True（0.2.3 起；原来是 18）
Get-ChildItem "$env:TEMP\rime.weasel\*.log" | Sort-Object LastWriteTime -Descending |
  Select-Object -First 1 | Get-Content | Select-String 'Error'    # 期望无输出

# ⑥ 设置窗口新按钮（人眼验收）：打开设置窗口 → 「设置与缓存」页 → 点「打开小狼毫原生设置」
#    期望弹出标题为「【小狼毫】方案选单设定」的对话框
```

> 托盘项**不用真的去点**：这一项做的事就是「无参数运行 `WeaselDeployer.exe`」（脚本 + 资源回读都已确认
> 命令号 = 40008 且服务端对它的处理就是启动这个 exe），所以第 4 条用直接运行来验收。

---

## 8. 本次迭代（0.2.2 / 0.2.3 / 0.2.4）的验收结论：快捷输入 · 候选方格 · 部件拆字 · 序号

### 8.1 复现方法：怎么「看见」一次上屏

真按键 + 读窗口标题，全程不用人眼（记事本的标题 = 文档第一行内容）：

```powershell
# 通用形式：esc 归位 → v 开菜单 → 5 进快捷输入 → <数字> 选功能 →（可选）继续输入 → space 上屏
# `type-and-shot.ps1` 的按键表里没有 + 和 *（它们是 shift 组合），所以示例用减法；
# 想测 + / * 就手动敲，或先按 shift 再按 equals。
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\type-and-shot.ps1 `
  -Target notepad -Keys 'esc,v,5,1,8,minus,3,space' -Out .\shots\v5-calc.png
# 输出：AFTER=<算式结果>   SHOT=…

# 日期 / 时间 / 星期 / 日期时间 / 农历（选完就能上屏）
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\type-and-shot.ps1 -Target notepad -Keys 'esc,v,5,2,space' -Out .\shots\v5-date.png
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\type-and-shot.ps1 -Target notepad -Keys 'esc,v,5,3,space' -Out .\shots\v5-time.png
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\type-and-shot.ps1 -Target notepad -Keys 'esc,v,5,4,space' -Out .\shots\v5-week.png
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\type-and-shot.ps1 -Target notepad -Keys 'esc,v,5,5,space' -Out .\shots\v5-dt.png
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\type-and-shot.ps1 -Target notepad -Keys 'esc,v,5,6,space' -Out .\shots\v5-lunar.png

# 数字大写 / Unicode / 部件拆字（前缀后面自己补内容）
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\type-and-shot.ps1 -Target notepad -Keys 'esc,v,5,7,1,2,3,4,space' -Out .\shots\v5-rmb.png    # AFTER=一千二百三十四
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\type-and-shot.ps1 -Target notepad -Keys 'esc,v,5,8,4,e,2,d,space' -Out .\shots\v5-uni.png    # AFTER=中
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\type-and-shot.ps1 -Target notepad -Keys 'esc,v,5,9,n,v,z,i,space' -Out .\shots\v5-rad.png    # AFTER=好

# 部件拆字「不经菜单」的那条路（0.2.3 把前缀从 uU 改成了 u）
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\type-and-shot.ps1 -Target notepad -Keys 'esc,u,n,v,z,i,space' -Out .\shots\rad-u.png       # AFTER=好
```

> 注意（个人手动按键版）：`esc` → `v` → `5` → 数字（可选继续输入算式）→ 空格上屏，
> 然后读记事本窗口标题即可，例如 `v` `5` `1` 再敲 `1+2*3` 得到 `7`。

### 8.2 快捷输入 9 项的实测结果（0.2.2 / 0.2.3）

| # | 菜单文字 | 填入的前缀 | 实测上屏结果 |
| --- | --- | --- | --- |
| 1 | 计算 | `cC` | `1+2*3` → **7**；`9*9` → **81**（按 `1` 后必须继续输入算式） |
| 2 | 日期 | `rq` | **2026-09-13** |
| 3 | 时间 | `sj` | **02:30**（`HH:MM`） |
| 4 | 星期 | `xq` | **星期日** |
| 5 | 日期时间 | `dt` | **2026-09-13T02:30:14+0800** |
| 6 | 农历 | `N` + 当天 `%Y%m%d` | **丙午马年八月初三** |
| 7 | 数字大写 | `R` | 输入 `1234` → **一千二百三十四** |
| 8 | Unicode | `U` | 输入 `4e2d` → **中** |
| 9 | 部件拆字 | `u` | 输入 `nvzi` → **好** |
| q | 返回 | （清空输入） | 回到空输入状态 |

部件拆字的另外两条对照（0.2.3）：`u` + `riyue` → **明**；`v`→`5`→`2`（日期）不受影响。
**旧的 `uU` 前缀已失效**（`uU` 单独不再触发拆字）。

### 8.3 候选方格 + 方向键的实测（0.2.3 → 0.2.4 修复后）

| 操作 | 候选窗口（高度，物理像素） | 结果 |
| --- | --- | --- |
| 打 `shi` | 144 | 收起：9 个候选排成 **2 行**（序号注释撑宽所致），带序号 1–7 + 8、9 |
| 按 1 次 `↓` | 287 | **4 行 × 9 列** ✅ |
| 序号（读图） | — | **只有第一行有 1–9，第 2–4 行没有序号**（截候选窗口图后用视觉 API 读图确认；四行最左边都是候选文字本身） |
| 再按 1 次 `↓` | 144 | ✅ **收回**（0.2.3 这里会**上屏**，见下） |
| 再按 `↓` 又按 `↑` | 287 → 144 | ✅ 展开 / 收回往复正常 |
| 全程上屏状态 | — | **标题一直是 `*shi`**，没有任何候选被上屏 ✅ |
| 方向键移动选中项 | — | ✗ 不移动：`→` ×1 或 ×3 再空格，上屏的仍是**「是」（第 1 个）**；展开后 `↓↓` + `→` 亦然 |
| 数字键基准对照 | — | ✅ `1` → **是**、`2` → **师**（证明「候选顺序」本身没问题，是方向键不动） |
| 注释不影响上屏 | — | `shi`+空格 → 是、`shi`+`3` → 师；`v`→`5`→`2` → 2026-09-13、`v`→`3` → 常用语 |

> **0.2.3 的 bug（0.2.4 已修）**：展开后按 `↓` 会**把当前候选上屏**。
> 原因是 `grid_key` 用了 `ctx:select(sel + 9)`，而 `ctx.select` **是「选中并上屏」不是「移动高亮」**；
> 日志里 `ok=true err=nil`，没有任何异常（`pcall` 挡不住，会伪装成「静默生效」）。
> 修法：`grid_key` 重写为**只做展开 / 收起**，彻底不再调用 `ctx.select`。
> **「用方向键移动选中项」仍然做不到**（不是没写，是没有 API）：探针实测
> `ctx.select_candidate` / `set_selected_candidate_index` / `highlight` / `move_selection` /
> `menu` / `get_menu` / `selected_candidate_index` / `menu.*` / `composition.select` **全是 `nil`**。
> 在「不改小狼毫 C++ 源码」的前提下无法实现；**选词请用数字键**（只覆盖前 10 个候选）。

**探针怎么复现**（改 `grid_key` 前后都建议跑一次）：在 `src\lua\vmenu_core.lua` 的方向键分支里
挂一个日志文件，把「字段类型」和「调用结果」都写下来，然后重启 `WeaselServer`、打字并按方向键，
再读日志：

```lua
-- 临时探针（用完删掉）：写 type(ctx.xxx) 与调用结果
local function probe(ctx)
  local f = io.open("D:\\rime-sandbox\\probe.log", "a")
  if not f then return end
  for _, k in ipairs({"select", "select_candidate", "set_selected_candidate_index",
                      "highlight", "move_selection", "menu", "get_menu",
                      "selected_candidate_index"}) do
    f:write(k, " = ", tostring(type(ctx[k])), "\n")
  end
  local ok, err = pcall(function() ctx:select(9) end)
  f:write("ctx:select(9) -> ok=", tostring(ok), " err=", tostring(err), "\n")
  f:close()
end
```

实测输出：只有 `select = function`，其余**全部 `nil`**；`ctx:select(9)` 返回 **`ok=true err=nil`**
但候选被上屏了（这就是当年误判「静默失败」的原因）。
也说明：**`pcall` 不能用来判断「API 是否真的做了我们以为的事」**，只能挡异常。

**另一条实测更正**：早期文档写的「`ctx.selected_candidate_index` 是 1 基、`ctx:select(i)` 是 0 基」**是错的** ——
该字段在本机不存在（`nil`），旧代码的换算一直把 `nil` 当 0 用。

前置条件（缺一不可）：**部署了自编的网格版 5 个文件**（`GRID-CANDIDATE-DLL.md` §4.2，含
`System32`/`SysWOW64` 的 `weasel.dll`）、`WeaselServer` 在跑且**小狼毫是活动输入法**
（微信输入法会抢，判定见 `AGENT-HANDOFF.md` §1）、测试程序是部署后**新开**的进程。
`build\weasel.yaml` 的 `style/label_format` **留空**（本机 `" "`、示例 `""`）、
`build\rime_ice.schema.yaml` 的 `menu/page_size: 36`：

```powershell
# label_format 与 page_size 都在各自文件里；换行/序号/方向键在 DLL 里，不查 YAML
$t = [IO.File]::ReadAllText('D:\rime-sandbox\build\weasel.yaml', [Text.Encoding]::UTF8)
[regex]::IsMatch($t, 'label_format:\s*"\s*"')      # 期望 True（等于空或一个空格：不画原生序号）
[IO.File]::ReadAllText('D:\rime-sandbox\build\rime_ice.schema.yaml', [Text.Encoding]::UTF8).Contains('page_size: 36')  # 期望 True
```

序号机制（缺任一处都会退回「第 2–4 行也有 10、11……」）：
**自编 DLL 的 `GetLabelText` 覆写**（把序号写进标签槽、按高亮行 1–9）+ 主题 `label_format` 留空
（关掉原生序号列）。改 lua 记得同步两处 lua 目录（MD5 一致）再重启；改源码补丁则走
CI + `tools/deploy-grid-dlls.ps1`（5 个文件）。

### 8.4 待复测 / 未解决（不要当成已通过）

| 项 | 现状 |
| --- | --- |
| ~~**`↓↓` vs `↓` + `→`×9**~~ | **✅ 已复测：旧结论是误判。** 第二次 `↓` 当时会直接上屏，两次「比较」比的其实是被意外上屏的那个字。0.2.4 修好后这一对照已无意义（现在 `↓` 是展开 / 收起开关） |
| **用方向键移动选中项** | **做不到（不是没写）**：本机 librime-lua 没有「移动高亮」的 API，`ctx.select` 是上屏不是移动。要做只能改小狼毫 C++ 源码 —— 用户正在决定是否放宽这条限制。**选词请用数字键**（只覆盖前 10 个候选） |
| **v5 的截图** | 本轮**没有**截图：抓屏时机撞上用户正在用电脑，已把两张新图从 `screenshots/` 删掉，因此文档不引用 v5 截图 |
| **v 菜单「返回」显示 `10`** | v 菜单的序号是逐条写的，快捷输入子菜单有 10 条（9 项 + 返回），所以「返回」前面显示 `10`（实际按键 `q`）。只影响观感，未处理 |
| ~~展开后第 2–4 行的序号~~ | **✅ 已解决**（`label_format` 留空 + 注释写序号），验收见 §8.3；`menu/alternative_select_labels` 已确认对 Weasel 无效，不要再试 |
| ~~展开后再按 `↓` 会上屏~~ | **✅ 已修复（0.2.4）**：`grid_key` 重写为只做展开 / 收起，不再调用 `ctx.select`；实测 144 → 287 → 144 → 287 → 144 且全程没有候选被上屏 |
| **`grid_sel()` 死代码** | `vmenu_core.lua` 里的 `grid_sel()` 已无人调用（`grid_key` 重写后），可删；它的注释还留着那条**错误**的「1 基 / 0 基」说法 |

## 11. 截图验收的两个坑（2026-09-19 实测，别再踩）

1. **DPI 缩放会让自写的抓图错位。** 显示器 2560x1440 @150% 时，DPI 不感知的进程读到的窗口坐标是
   **虚拟坐标**（`GetSystemMetrics` 报 1707x960），自己按窗口 rect 调 `Graphics.CopyFromScreen`
   抓出来的是**别的地方**（本次抓到过记事本菜单栏）。可靠做法二选一：
   - 抓**固定大区域**（如 `0,0` 起 `1400x700`），让读图的人自己找候选窗；
   - 直接用 `tools/type-and-shot.ps1` 的默认区域（`40,40,1200,560`，正好覆盖放在 `60,40` 的记事本
     和它下面的候选窗），本次所有 v 菜单截图都是这么来的。
2. **候选窗尺寸可当「当前是什么」的快速判据**（候选窗是客户端进程的 `ATL:` 类窗口）：
   `842x49` = v 主菜单；`583x49` = 横排列表（常用语 / 剪贴板）；`987x49` = 快捷输入；
   `3921x49` = 剪贴板长列表（会横向溢出屏幕，见 PROGRESS §1.27 ⑥）；高度 `191` = 方格或原版 `v` 候选。
   配合 `EnumWindows` + `GetClassName` 找 `ATL:` 前缀即可，无需读标题（标题里没有文字）。

## 12. ⚠️ 发按键之前必须先证明「前台就是目标窗口」（2026-09-19 付出血的教训）

**事故**：验收脚本用「`ShowWindow` + `MoveWindow` + 在窗口中心点一下」抢焦点，然后无条件开始发
按键（含 `Ctrl+A` / `Delete`）。实测那一次的 `GetForegroundWindow()` 打印出来是 **`点完之后焦点在
目标窗口 = False`** —— 点击被另一个**盖在上面的**窗口接走了，于是整轮按键（十来次击键 + 两次
`Ctrl+A`+`Delete`）全部打进了**用户自己的窗口**。脚本却继续跑完并输出了「测试结果」。

**规矩（写死在 `tst/preedit-label-verify2.ps1` / `tst/pad-preedit-verify.ps1` 里，复制脚本时别删）**：

1. 发按键前先 `SetWindowPos(hwnd, HWND_TOPMOST, …)` 把目标窗口**置顶**，测完 `HWND_NOTOPMOST` 还原
   —— 否则目标窗口可能一直压在别的窗口下面，点击打到别处。
2. 点之前查 **`GetAncestor(WindowFromPoint(点击点), GA_ROOT) == hwnd`**；不等 → 打印
   `<挡住它的窗口标题>` 并**直接退出，一个键都不发**。
3. 点之后再查 **`GetForegroundWindow() == hwnd`**；不等 → 同样退出。
4. **每一次**发按键之前再查一次（焦点可能在截图/OCR 期间被抢走），不等就退出。
5. 退出码区分原因（1 = 找不到窗口 / 2 = 被遮挡 / 3 = 点击后焦点不对 / 4 = 中途丢焦点），
   方便一眼看出是「没测」还是「测失败」——**绝不允许把「没测成」写成「通过」**。

> 另外：`Ctrl+A` / `Delete` 这类**破坏性**按键只在第 2–4 步都通过之后才允许发。任何自动化都不要对
> **用户的**窗口（记事本、聊天输入框、浏览器标签）发按键 —— 只对脚本自己起的测试窗口和
> 专用测试页 `tools/ime-web-test.html` 发。

**行内预编辑（preedit）怎么取证**：`vclip` 这类内部编码显示在**行内预编辑**里，占位符
（`placeholder`）会和它叠在同一行，所以先把 textarea 填上几个字符（脚本里先打 `abc` + 回车上屏）
再截图。取图用 `ime-ocr-boxes.ps1` 拿到**每行文字 + 坐标**（比 `ime-ocr.ps1` 的纯文本更好用：
能确认「读到的字确实在输入框那一行」，而不是候选窗里的同名文字）。

## 13. 第十八轮的取证工具（v 功能 4 列 / 加减号翻页 / `↓` 展开）

三件套都在 `D:\weasel-build\tst\`（**不入库**，属临时工具；思路与脚本要点记在这里）：

| 脚本 | 用途 | 要点 |
| --- | --- | --- |
| `measure-panel2.ps1` | 一次跑完「点窗口 → 发一串键 → 每步量候选窗尺寸 → 抓全屏图」 | `-Title` 找窗口、`-Keys` 逗号分隔的键、`-Down`/`-Up` 在键序列后各按一次 ↓/↑、`-Out` 输出前缀；**每一步按键前**都重查 `RootAt(点) == hwnd` 与 `GetForegroundWindow() == hwnd`（见 §12），不满足就 `ABORT` 且一个键都不发 |
| `crop-panel.ps1` | 把全屏图按**虚拟矩形**裁成候选窗特写（可 `-Zoom`） | 内部 `×1.5` 换算成真实像素（见 §11 第 1 条），所以调用时直接填 `GetWindowRect` 那种虚拟坐标 |
| `dump-windows.ps1` | 列出所有可见窗口（类名/标题/rect/pid） | 用来确认「谁挡住了点击点」「候选窗到底在不在屏幕上」 |

**这一轮踩到的取证坑（补 §11）**：

* **截图是真实像素，窗口 rect 是虚拟像素**。2560×1440 @150% 下自写的 DPI 不感知进程
  `SM_CXSCREEN = 1707`、`SM_CYSCREEN = 960`，但 `CopyFromScreen` 抓的是**真实**像素 1:1。
  所以：抓全屏必须抓 `2560x1440`（抓 `1714x920` 会把右边切掉 —— 第 4 列的序号「4」正好在被切掉的
  区域里，害我一度以为「屏幕外多画了一个 4」）。
* **面板尺寸就是最好的判据**（这一轮的对照表）：

  | 场景 | 尺寸 |
  | --- | --- |
  | v 主菜单（4 + 1，两行） | `861x95` |
  | v3 快捷输入（4 + 3） | `808x96` |
  | v 剪贴板收起（长条目，只画 2 列） | `1433x49` |
  | v 剪贴板 `↓` 展开（4 行 × 2 列） | `1433x191` |
  | v 剪贴板第 2 屏（短条目，画满 4 列） | `1424x49` |
  | 普通打字 `shi` 收起 / 展开 | `660x49` / `660x189` |

* **别把「服务端崩了」当成「按键没生效」**。这一轮服务端因为 `lua_filter` 里 `set_option` 而
  **每次按键栈溢出崩溃**（`0xc00000fd`），现象是「记事本里打字毫无反应」「候选窗不出现」，
  看起来像焦点/按键问题。**判断方法**：看 `%TEMP%\rime.weasel\` 里有没有新的
  `WeaselServer.exe.<pid>.dmp`、以及 `Get-WinEvent Application` 里的 `APPCRASH`（出错模块 + 异常代码）。
  WeaselServer 每次按键重启 → `Get-Process WeaselServer` 的 `StartTime` 一直在变。
### 13.1 「收起那一行 vs 展开后第一行」是否对齐：怎么量（可直接照抄）

「对齐」不能靠看图，要**落在数字上**。这套比对只取「两张图都落在候选窗内部」的一条横带
（面板真实 y ≈ 207..270，取 **212..263** 绝对安全；取 200..280 会把面板外的文档文字也算进来，
第一版就是这么误判出 17% 差异的）：

| 量什么 | 方法 | 本轮结果（v 剪贴板，画 2 列 / 普通打字 9 列） |
| --- | --- | --- |
| 对照（方法本身可不可信） | 同一状态跑两次、截图互相比 | **0 / 110760 px 差异 = 0%**（渲染是确定性的）✅ |
| 逐像素差异 | `align-strict.ps1`：裁同一条带逐点比，阈值 18 | 普通打字 **20 / 50960 = 0.039%**（等于「没差别」）；v 剪贴板 **2066 / 110760 = 1.865%**，且**全部落在真实 x < 165**（第 1 格最前面一小段） |
| 文字列位置 | 逐列数「白色像素」（亮度 > 170，避开高亮底色干扰）取连续段 | 普通打字：**21 段左边缘全部一致，最大偏差 0 px**；v 剪贴板：**真实 x ≥ 271 起的文字段完全相同**（第 2 格标签 1169 / 正文 1204 两态一致） |
| 高亮格矩形 | 数「蓝色底」（`B > R + 8`）的 x 范围 | **两态都是 x 99..1146**（列宽与格子边界逐像素相同） |
| 面板是否完整在屏幕内 | 像素扫描找候选窗右边界 | 真实右边界 **2240**（屏宽 2560）→ 右边距 **320 px**，不会溢出（`grid_budget` 里留了 16 px 余量） |

> ⚠️ 已知的一处**外观**差异（不是几何差异）：v 剪贴板第 1 格最前面约 44 真实像素（标签槽那一段）
> 在收起态比展开态「淡」一些（亮像素 493 vs 1073）；文字段从 x ≥ 271 起完全一致、
> 高亮格矩形两态相同 —— 也就是**列 / 格 / 词的位置没错位**，只是那一小段的前景色渲染不同。
> 以后若要追，先看 `WeaselUI/HorizontalLayout.cpp` 画「高亮格标签」时的颜色与顺序。

> 工具（都在 `D:\weasel-build\tst\`，不入库）：`align-strict.ps1`（逐像素比 + 差异 x 段起点）、
> `align-profile.ps1`（白色文字段左边缘）、`panel-real-rect.ps1`（像素扫描找面板真实矩形）。

## 14. 第十九轮（固定格宽 / `…` 截断）的取证方法：**先拿客户端日志，再谈像素**

这一轮的现象是「候选词显示不全、注释不出现、面板宽度抖」，看截图只能猜。
真正两分钟定位的是一个**临时**探针：在客户端 `WeaselUI.cpp`（`UI::Update`）与
`WeaselPanel.cpp`（`_DrawCandidates` 的 TEXT / CMT 两处）里 `fopen` 追加一行日志：

```
pid=14608 UPDATE abbrev=30 n=6
    i=0 cch=33 text=# 雾凇拼音  ![demo](./others/asse.   ← 客户端**实际拿到**的文本
pid=14608 DRAW i=2 TEXT rect=52,89,52,127 w=0 cch=33 t=502 <!DOCTYPE html> <html lan.
                     ↑ 行首那格宽度 = 0（就是 bug 本体）
```

**永久经验**：`_DrawCandidates` 用的是 `m_layout->GetCandidate*Rect(i)`，
**rect 是排版算的、文字是上下文给的** —— 「文字显示不全」先分清是
①上下文文本本来就短（本轮发现是主题 `candidate_abbreviate_length: 30` 在**客户端**缩写，
只影响显示，上屏仍是全文），还是 ②排版给的 rect 太窄（本轮两个 bug）。
日志比截图快一个数量级。**排查完必须删掉**（本轮已删，`Test-Path client-draw.log = False`）。

**本轮可直接照抄的验收命令**（`D:\weasel-build\tst\probe-fixed.ps1`，
按一串键 → 量候选窗矩形 → 截图 + 裁面板 → 可选 `↓`/`↑`/数字 → `WM_GETTEXT` 读回上屏，
**全程不碰剪贴板**）：

```powershell
# 1) 先杀旧记事本再开新的：客户端 DLL 是进程内加载，不重启看不到新 DLL
Get-Process notepad | Stop-Process -Force; Start-Process notepad.exe -ArgumentList '"D:\weasel-build\tst\IME LAYOUT TEST.txt"'
# 2) 剪贴板：2 列 × 3 行、面板恒宽（应 707x144，三页都一样）
pwsh -NoProfile -File probe-fixed.ps1 -Keys 'v,2'            -Out c1
pwsh -NoProfile -File probe-fixed.ps1 -Keys 'v,2,equal'      -Out c2
pwsh -NoProfile -File probe-fixed.ps1 -Keys 'v,2,equal,equal'-Out c3
# 3) 选择逻辑与按键：↓ 后数字选「高亮那一行」；↑ 不许收起
pwsh -NoProfile -File probe-fixed.ps1 -Keys 'v,2' -Down -Digit 2 -Out c4   # 期望上屏 URL（第 4 条）
pwsh -NoProfile -File probe-fixed.ps1 -Keys 'v,2' -Up           -Out c5   # 期望仍是 707x144
# 4) 常用语 / 原符号 / 回归
pwsh -NoProfile -File probe-fixed.ps1 -Keys 'v,4' -Digit 1 -Out f1        # 期望上屏第 1 条常用语
pwsh -NoProfile -File probe-fixed.ps1 -Keys 'v,5' -Down -Up    -Out r1    # 690x49 → 852x191 → 690x49
pwsh -NoProfile -File probe-fixed.ps1 -Keys 's,h,i'            -Out s1    # 660x49（无回归）
```

**几何怎么量**（不要靠看图）：

| 量什么 | 命令 | 本轮结果 |
| --- | --- | --- |
| 高亮格（蓝块）宽度 | 逐像素找 `B > R + 15` 的 x 范围 | 高亮格 540 物理 = **360 虚拟 ≈ 屏宽 20%** ✅ |
| 文字块 / 注释块位置 | `ink.ps1 -In <crop> -Y0 a -Y1 b -Cells @(20,720,1400)` | 每格「文字块 → 右对齐注释块」，注释右缘两列各自对齐 ✅ |
| 末尾有没有 `…` | `inkmap.ps1 -In <crop> -X0 470 -X1 545 -Y0 112 -Y1 150 -ColStep 1 -RowStep 1` | 基线处 **3 个小点** ✅ |
| 面板宽度稳不稳 | `probe-fixed.ps1` 打印的 `panel WxH` | 剪贴板三页 **707x144 / 707x143 / 707x143** ✅ |

