# 常见问题（TROUBLESHOOTING）

## 输入法侧

### 按 `v` 没有任何反应

1. `WeaselServer.exe` 在跑吗？`Get-Process WeaselServer`
2. 两个 lua 目录一致吗？（`TESTING.md` §4 的第 4 条）
3. `build\rime_ice.schema.yaml` 里 `engine/processors` 有没有 `lua_processor@*menu_processor`？
   没有就跑 `patch-build-schema.ps1` 再重启服务。
4. `WeaselServer` 日志里有没有 lua 报错：
   ```powershell
   Get-ChildItem "$env:TEMP\rime.weasel\*.log" | Sort-Object LastWriteTime -Descending |
     Select-Object -First 1 | Get-Content | Select-String 'lua|ERROR' | Select-Object -Last 20
   ```
5. 是不是在**英文 / ASCII 模式**？v 功能在该模式下整体关闭，按 `v` 出字母 v（这是设计）。

### 打字变卡 / 一按某个键就卡死

基本可以断定是**在输入线程里做了阻塞的事**：读大文件、起进程（`io.popen`）、等锁。
本项目所有 lua 都已 `pcall` + 只读写小文本文件；如果你新加了逻辑，先按
`AGENT-HANDOFF.md` 的「硬约束」检查一遍。

### 收藏不在候选第 2 位

* 输入是不是**不足 3 个字符**？（规则要求 ≥ 3，避免逐字符读盘）
* 编码匹配是**前缀**匹配，检查编码有没有打错。
* 是不是 `menu_filter.lua` 里 `place()` 之后的 `quality` 重排被删了？
  候选表在 filter 之后还会按 quality 排序，不重排就会乱位。

### 打纯数字没有候选（比如 `138` 应该出收藏）

`menu_processor.lua` 的数字接管分支需要满足：输入为空或全是数字、且
「已输入 + 新按键」仍是某条**纯数字编码**的前缀。检查：

* 收藏里真的有 `138` 这条编码吗？
* `digit_prefix` 里是不是写成了 `#s < #k`？必须是 `#s <= #k`，否则打完整条编码的那一下会被漏掉。

### 回车把原始编码上屏了，而不是收藏内容

`menu_processor.lua` 的 `Return` 分支要求**输入与编码完全一致**（`fav_exact`）。
* `wsl` 会命中，`ws`（前缀）不会 —— 前者是「打完编码」，后者是「还没打完」。
* 该分支被人删掉的话，只有数字编码还能靠「整屏只有一个候选」的巧合回车上屏。

### 有些候选（如「显示更多」）鼠标点不动

**这是 Weasel 的机制，不是 bug**：候选窗口的鼠标点击 = 「提交这一条候选文字」，
不经过按键处理链，所以操作行只能用键盘（`m` / `+` / `d` / `x` / `q`）。

### 改了候选框参数后**一个候选都不显示**（打字时按键被吞）

**现象**：改完 `build\weasel.yaml`（比如 `style/layout/max_width`）重启服务后，正常打字
**看不到任何候选窗口**，按键像被吞掉；输入法日志里出现：

```
E ... config_data.cc Error parsing YAML "…\build\weasel.yaml" :
      yaml-cpp: error at line 356, column 12: end of map not found
```

**根因**：用 `Get-Content` / `Set-Content` 改这个文件。PowerShell 5.1 的这两个 cmdlet
**默认按 ANSI（本机 GBK）解码**，UTF-8 中文被读成乱码再写回，YAML 结构直接损坏。

**正确改法**（一定要这样写）：

```powershell
$p = 'D:\rime-sandbox\build\weasel.yaml'
$t = [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8)
$t = $t -replace '(?m)^(\s*max_width:)\s*\d+', '$1 530'
[IO.File]::WriteAllText($p, $t, (New-Object Text.UTF8Encoding($false)))   # false = 不写 BOM

# 立刻验证：中文没被改写、键值对上了
([IO.File]::ReadAllText($p, [Text.Encoding]::UTF8) -split "`n" | Select-String 'max_width')
```

**判别方法**：改完重启 `WeaselServer`，看日志里**没有** `Error parsing`：

```powershell
Get-ChildItem "$env:TEMP\rime.weasel\*.log" | Sort-Object LastWriteTime -Descending |
  Select-Object -First 1 | Get-Content | Select-String 'Error parsing'   # 必须无输出
```

> 同一份配置要一起改的地方：`weasel.custom.yaml`（`patch`）+ `build/weasel.yaml`
> + `%APPDATA%\Rime\build\weasel.yaml`（镜像）。`page_size` 对应
> `rime_ice.custom.yaml` + `build/rime_ice.schema.yaml`。
> 现在的值是 **`max_width: 530` + `page_size: 36`**（默认单行 9 个、按 `↓` 展开 4 行 × 9 列，
> 见 `ARCHITECTURE.md` §3.6）；回退 = `max_width` 回 `0`、`page_size` 回 `9`，重启服务。

### 按 `↓` 不展开成 4 行 × 9 列

按顺序查这四条：

1. **配置生效了吗**：`build\weasel.yaml` 要是 `max_width: 530`、`build\rime_ice.schema.yaml`
   要是 `menu/page_size: 36`（改完**必须重启 `WeaselServer`**，见上一节）。
2. **lua 是不是两份不一样**：`D:\rime-sandbox\lua\` 与 `%APPDATA%\Rime\lua\` 的
   `vmenu_core.lua` / `menu_filter.lua` / `menu_processor.lua` 必须 **MD5 一致**
   （`TESTING.md` §4 第 4 条）。
3. **是不是在 v 菜单里**：v 菜单内部方向键保持原版行为（不接管），只有**普通打字**时 `↓` 才展开。
4. **候选是不是只有一两条**：候选本来就少时「展开」看起来没变化（展开只是把上限从 9 提到 36）。

> 已知未解决：展开后**第 2–4 行仍带序号**（`10`、`11`……）。需求是「只第一行有 1–9」，
> 目前做不到（`menu/alternative_select_labels` 填 36 项会被 rime 拒绝、`page_size` 退回 9），
> 属开放问题，不是配置错。

### 改了 Lua 却不生效

1. lua 有**两份**：`D:\rime-sandbox\lua\` 与 `%APPDATA%\Rime\lua\`，必须 **MD5 一致**
   （`TESTING.md` §4 第 4 条）；只改一份就会出现「改了没生效」。
2. 改完 lua **必须重启 `WeaselServer`**（librime-lua 是启动时加载模块），并等 ≥ 6 秒
   再打字，否则方案还没加载完会丢按键。

### 按了 `v`→`5` 再按数字没反应

说明「快捷输入」没有生效，按顺序查：

1. **重启过 `WeaselServer` 没有**：lua 模块是启动时加载的，改完必须重启（见上一节第 2 条）。
2. **两处 lua 是不是 MD5 一致**：`D:\rime-sandbox\lua\` 与 `%APPDATA%\Rime\lua\` 的
   `vmenu_core.lua`（`mode_of` 里的 `vqi` → `quick`）、`lua_menu.lua`（`yield_quick`）、
   `menu_processor.lua`（`cur == "vqi"` 分支）三份都要在、都要一致。
   `lua_filter` / `lua_processor` / `lua_translator` **各自 require 一份模块**，
   缺一份就会出现「菜单显示出来了，但按数字没反应」。
3. **日志里有没有 lua 报错**：

   ```powershell
   Get-ChildItem "$env:TEMP\rime.weasel\*.log" | Sort-Object LastWriteTime -Descending |
     Select-Object -First 1 | Get-Content | Select-String 'lua|error'    # 期望无 lua 报错
   ```
4. **是不是输错层了**：`v` → `5` 之后候选应变成 9 项（计算 / 日期 / … / 部件拆字 / 返回），
   如果看到的还是主菜单 5 项，那是 `5` 没进去（`menu_processor` 的主菜单分支没生效）。

### 计算器选了「计算」之后没有候选

**正常现象**：雾凇的计算器 recognizer 是 `^cC.+` —— **`cC` 后面必须至少有一个字符**才出候选。
所以 `v`→`5`→`1` 之后要接着敲算式（如 `1+2*3`），候选第一项才是结果。

同理：「数字大写」填的是 `R`、「Unicode」填的是 `U`、「部件拆字」填的是 `u`，
按完都要自己补内容（`R1234`、`U4e2d`、`nvzi`）—— 它们的设计就是这样。

### 农历出来的不是我要的那一天

按 `v`→`5`→`6` 时会**把当天的 `YYYYMMDD` 一起填进输入框**（`os.date("%Y%m%d")`），
所以立刻显示的是**今天**的农历。想查别的日子，把后面那串数字改成那天的日期即可（如 `N20260101`）。

### 输入 `u` 之后不出部件拆字候选

部件拆字（0.2.3 起）用的是单字母前缀 `u`，recognizer 是 `^u[a-z]+$`：

| 现象 | 原因 / 办法 |
| --- | --- |
| 打 `u` 后不出现拆字候选 | **`u` 后面必须继续输入字母**（如 `unvzi`），只有 `u` 本身不触发 |
| 以前打 `uU` 能用，现在不行了 | 0.2.3 把前缀从 `uU` 改成了 `u`，**旧的 `uU` 写法已失效**（回退：`rime_ice.custom.yaml` 里把 `radical_lookup/prefix` 改回 `uU`、recognizer 改回 `^uU[a-z]+$`，重启服务） |
| 想打以 `u` 开头的英文词却出了拆字候选 | 这是单字母前缀的副作用，回车/直接上屏或切成英文模式即可 |

---

## 设置窗口侧

### `v`→`1` 按了没反应

```powershell
# 1) 常驻窗口和守护进程各有一个吗？（注意：命令里不要出现脚本全名，否则会匹配到自己）
$pat = 'vmenu-' + 'settings-gui.ps1'
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine.IndexOf($pat) -ge 0 } |
  ForEach-Object { "gui pid=$($_.ProcessId)" }
$wpat = 'vmenu-' + 'watcher.ps1'
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine.IndexOf($wpat) -ge 0 } |
  ForEach-Object { "watcher pid=$($_.ProcessId)" }
# 2) 标记文件是不是积压了（稳态下不该存在）
Test-Path 'D:\rime-sandbox\open-settings.flag'
```

* 两个都没有 → 双击 `clipboard-sync.bat`（或 `打开设置.bat`）。
* 有窗口进程但窗口不出来 → 结束它，等 3 秒让守护进程用新脚本重新拉起。
* 标记文件一直在 → 常驻窗口没在轮询（进程卡了或不存在）。

### 窗口弹出很慢（几秒）

说明每次都在**重新启动 PowerShell**（而不是让常驻进程显示窗口）。检查
`vmenu-settings-gui.ps1` 里：

* 单实例互斥体分支是否还在（已有实例应该「写标记文件 + `exit 0`」）；
* 进程启动时是否做了离屏 `Show()`+`Hide()` 预建；
* 主循环是否还在每 60 ms 轮询标记文件（而不是每次重开窗口）。

### 窗口里的列表是空的

* 演示目录 / `-RimeDir` 指对了吗？窗口标题里没有路径，但「设置与缓存」页会列出三个文件路径。
* 文件是不是被别的程序写成了带 BOM 或改成了别的编码？
* 设置窗口只在前台显示时刷新数据；点「重新载入」可以手动刷新。

### 关了窗口，再按 `v`→`1` 又弹出来（想彻底退出）

点 × **本来就是只隐藏**（这是秒开的设计）。彻底退出：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\windows\vmenu-watcher-stop.ps1
```

（它会停掉守护进程和常驻窗口；再按 `v`→`1` 就不会有窗口了，此时用
`打开设置.bat` 仍可临时开一个。）

### 中文变成乱码 / 界面文字全乱

编码问题：

* `vmenu-settings-gui.ps1` **必须带 BOM**（`EF BB BF`）——用 `edit` 工具改完常见会丢 BOM；
* `.bat` 必须 CRLF + 纯 ASCII；
* 数据文件必须 UTF-8 **不带** BOM。
详见 `FILE-FORMATS.md` §5。

**为什么丢了 BOM 会炸**：PS 5.1 对**没有 BOM 的 UTF-8 脚本按 ANSI 解析**，中文注释/字符串变乱码，
严重时「多字节字符吃掉后面的引号」→ 直接**语法错误**（脚本跑不起来）。

```powershell
# 判别（基线）：前三个字节必须是 239,187,191
$p = 'D:\VibeCoding\输入法\vmenu-settings-gui.ps1'
(([IO.File]::ReadAllBytes($p)[0..2]) -join ',')

# 修法：读成 UTF-8 字符串，再用「带 BOM 的 UTF-8」写回
$t = [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8)
[IO.File]::WriteAllText($p, $t, (New-Object Text.UTF8Encoding($true)))
'BOM: ' + (([IO.File]::ReadAllBytes($p)[0..2]) -join ',')   # 必须是 239,187,191

# 改完做语法检查（能抓到上面那种「吃引号」错误）
$e = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($p, [ref]$null, [ref]$e)
if ($e) { $e | ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Message)" } }  # 期望无输出
```

> 注意 `[IO.File]::ReadAllText($p, [Text.Encoding]::UTF8)` 里的 UTF8 是**读取用的**解码器，
> 写回时必须另外传 `UTF8Encoding($true/false)` 才能决定**要不要写 BOM** —— 别混用。

---

## 托盘图标右键菜单（「输入法设置」）

### 点了托盘「输入法设置」没反应

托盘那一项做的事就是**无参数运行 `WeaselDeployer.exe`**，所以先看这个文件是什么：

```powershell
$d = 'C:\Program Files\Rime\weasel-0.17.4'
Get-Item "$d\WeaselDeployer.exe", "$d\WeaselDeployer.real.exe" -ErrorAction SilentlyContinue |
  Select-Object Name, Length, LastWriteTime
```

| 症状 | 结论 / 做法 |
| --- | --- |
| `WeaselDeployer.exe` **不是 5632 字节**（是几百 KB） | 代理没装上（或已被小狼毫升级覆盖）→ 重跑 `tools\vmenu-tray-setup.ps1` |
| **没有** `WeaselDeployer.real.exe` | 同上：真身还没被改名 → 重跑安装脚本 |
| 两个文件都在、大小也对，点了却没窗口 | 代理会去启动 `vmenu-settings-gui.ps1`（默认路径 `D:\VibeCoding\输入法\vmenu-settings-gui.ps1`）；**脚本不在那儿时代理会退回原生设置对话框**，所以「完全没反应」通常是设置窗口进程起不来 → 按上面的「`v`→`1` 按了没反应」查常驻窗口与守护进程 |
| 想分清是「菜单文字没改」还是「行为没改」 | 回读 exe 里的菜单文字，期望 `旧标签 0 处 / 新标签 1 处`（命令见 `TESTING.md` §7.1 ③） |

### 重新部署会不会弄丢候选方格（单行 9 / 展开 4 行 × 9 列）

**不会。** 实测：经代理转发的 `WeaselDeployer.exe /deploy`（= 托盘菜单里的「重新部署 (R)」）
会重新生成 `D:\rime-sandbox\build\weasel.yaml` 与 `build\rime_ice.schema.yaml`，
日志只有 INFO 没有 Error，而 **`max_width: 530`、`page_size: 36` 都还在** —— 因为它们写在
`weasel.custom.yaml` / `rime_ice.custom.yaml` 的 `patch` 里，重新部署会重新应用。

### 升级 / 修复安装小狼毫之后，托盘项变回「输入法设定」了

**这是预期的**：升级会覆盖 `WeaselServer.exe`（菜单文字回到原版）与 `WeaselDeployer.exe`
（代理被真身盖掉）。重新跑一次安装脚本即可：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\vmenu-tray-setup.ps1
```

脚本是幂等的：备份已存在就沿用（**不会**用新 exe 覆盖第一份备份）、菜单文字已是新标签就跳过、
快捷方式已改名就跳过、当前 `WeaselDeployer.exe` 已经是代理就跳过改名；代理每次都会重新编译
并覆盖安装。

> ✅ **升级后重跑会自动处理新版部署器**（0.2.2 起）：脚本**先编译代理**，再用
> 「大小是否等于代理（5632 字节）」判断当前 `WeaselDeployer.exe` 是真身还是代理；
> 是真身就**先改名保存为 `WeaselDeployer.real.exe`（覆盖旧真身）**，然后才放入代理。
> 所以**不需要**再手动挪走 `.real.exe`。
> 重跑时的实际输出形如：
>
> ```
> WeaselServer.exe 备份已存在，沿用（不会被覆盖）
> 菜单项文字已经是「输入法设置」，跳过
> WeaselDeployer.exe 已经是代理，跳过改名
> 已安装代理 WeaselDeployer.exe（5632 字节）
> ```
>
> （若升级后跑，第三行会变成 `WeaselDeployer.exe（638976 字节，真身）→ WeaselDeployer.real.exe`。）
>
> 早期版本（0.2.1 及以前）用的是「`.real.exe` 是否存在」来判断，升级后重跑会**直接用代理覆盖
> 新版部署器**；该行为已修复，见 `CHANGELOG.md` 的 0.2.2「修复 · 托盘安装脚本的代理识别」。

### 已知限制 / 注意事项

1. **托盘那一项是「改名 + 改行为」，不是新增第 13 项**：菜单项写死在 `WeaselServer.exe`
   的资源（`IDR_MENU_POPUP`，资源号 105）里，服务端也只认 `WeaselDeployer.exe` 这一个入口，
   所以无法凭空加一个全新命令号。原生设置对话框的直接入口因此从托盘挪到了 vmenu 设置窗口里
   （「小狼毫原生设置」分组 → 「打开小狼毫原生设置」）。
2. **小狼毫升级 / 修复安装会覆盖** `WeaselServer.exe` 与 `WeaselDeployer.exe`，
   托盘项退回原样（`输入法设置` 变回 `输入法设定` 且指向原生对话框）；重跑一次安装脚本即可
   （新版部署器会被自动改名保存，见上一节）。
3. **`weasel.dll` / `weaselx64.dll` 里也有同样的菜单文字**（那是输入法**语言栏**那条右键菜单用的），
   本项目**没有改**：它们是注入到所有进程里的 IME 模块，改了要重启所有程序才生效，风险不值得。
   也就是说语言栏那条右键菜单仍是「输入法设定」，点它走的是原生对话框。
4. **改 `WeaselServer.exe` 前必须先停掉 `WeaselServer` 进程**（正在运行的 exe 被系统锁住，
   写不进去）；安装脚本会自动停 / 起。**脚本文件本身必须 UTF-8 带 BOM**（`.ps1` 与 `.cs` 都是），
   否则 PowerShell 5.1 / csc 会按 GBK 解析，中文提示变乱码（脚本里匹配用的「输入法设定」
   是用字符码 `[char]0x8F93…` 拼出来的，不受文件编码影响）。

---

## 服务与生命周期

### 重启电脑后 `v`→`1` 没反应

两个后台服务不会自启。双击一次 `clipboard-sync.bat` 即可。
（仓库里**故意没有**加开机自启：不会静默往用户机器写启动项。需要的话自己加一个启动项，
指向 `clipboard-sync.bat`。）

### `.bat` 文件被安全软件删掉

本机装了火绒 HIPS，「`.bat` 里 `start` 一个隐藏 PowerShell」是典型可疑行为。
`打开设置.bat` 因此改成「先写标记文件 + 拉起守护脚本」。如果它被删了：
直接用 `clipboard-sync.bat`（同一套动作），或者手动执行：

```powershell
Start-Process powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden',
  '-File','.\src\windows\vmenu-watcher.ps1','-RimeDir','D:\rime-sandbox') -WindowStyle Hidden
```

### 多个实例 / 抢互斥体

* 设置窗口：互斥体 `RimeVMenuSettingsGui`，第二个实例只会写标记文件然后退出（不会开第二个窗口）。
* 守护进程：互斥体 `RimeVMenuWatcher`，第二个实例直接退出。
* 想「全部推倒重来」：双击 `clipboard-sync.bat`（它先停旧实例再启动）。

---

## 自动化测试 / 写测试脚本时的坑

### UI Automation 看不到设置窗口的控件

`System.Windows.Automation` 对这个 WinForms 窗口**抓不到任何子控件**：
`FindAll(Descendants, TrueCondition)` 返回 **0 个元素**（TabItem / Button / List 全是 0）。

→ 结论：GUI 自动化**只能走「截图找行 + 真实鼠标」**，现成工具是
`tools/gui-dblclick-test.ps1`（见 `TESTING.md` §1）。别再花时间试 UIA 选择器。

### 自动点击点错了行（DPI 缩放）

测试进程如果不是 DPI-aware，`SetCursorPos` 传进去的坐标会被系统按 **1.5 倍**缩放，
点击落到下面几行（实测：想点第 1 行，结果点到了第 9 行）。

→ 修法：使用前先调 `SetProcessDPIAware()`（`shot-window.ps1` 里已有同样说明，
`gui-dblclick-test.ps1` 在 `Add-Type` 之后第一件事就是它）。

### 找不到模态弹框

「编辑第 N 条」这种模态弹框**不会出现在 `Process.MainWindowTitle` 里**，
`Get-Process | Where-Object MainWindowTitle` 找不到它。

→ 修法：用 `EnumWindows` + `GetWindowTextW` 枚举**顶层窗口标题**（含不可见的判断），
再按标题子串匹配。`gui-dblclick-test.ps1` 的 `[VmWin]::Find` / `[VmWin]::Titles` 就是这套。

### 清理脚本把自己的 pwsh 也杀了

**现象**：命令直接结束，`[exit code: 4294967295]`（-1）。原因是在命令行里**写出了脚本字面名**：

```powershell
# ❌ 危险：自己的命令行里含 'vmenu-settings-gui.ps1'，会被下面的匹配一起选中
Get-CimInstance Win32_Process | Where-Object CommandLine -like '*vmenu-settings*' |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
```

→ 修法两条，**都要**：

```powershell
# ✅ 1) 排除自己；2) 脚本名在运行时拼接，命令行里不出现完整字面名
$pat = 'vmenu-' + 'settings-gui.ps1'
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine.IndexOf($pat) -ge 0 } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
```

### 双击编辑测试会**真的改文件**

`gui-dblclick-test.ps1 -TypeInto <文本>` 会真的写回 `clipboard-cache.txt` / `favorites.dict.yaml`。
测前**先备份并记录 sha256**，测后还原并校验一致（做法见 `TESTING.md` §3 第 1、3 步）。

---

## 日志与现场

| 东西 | 位置 |
| --- | --- |
| Rime / lua 日志 | `%TEMP%\rime.weasel\rime.weasel.<host>.<user>.log.INFO.*.log` |
| 输入法文件 | `<RimeUserDir>`（本机 `D:\rime-sandbox`） |
| 编译后的方案 | `<RimeUserDir>\build\rime_ice.schema.yaml`（`menu/page_size` 在这里生效） |
| 用户补丁（改这里，不要改 `build`） | `<RimeUserDir>\rime_ice.custom.yaml`（`menu/page_size`、部件拆字前缀 `radical_lookup/prefix`）、`<RimeUserDir>\weasel.custom.yaml`（`style/layout/max_width`） |
| 两份 Lua 模块（必须 MD5 一致） | `<RimeUserDir>\lua\` 与 `%APPDATA%\Rime\lua\`（快捷输入 / 候选方格都在 `vmenu_core.lua` / `lua_menu.lua` / `menu_processor.lua` / `menu_filter.lua` 里） |
| Weasel 主题（编译后） | `<RimeUserDir>\build\weasel.yaml`（`style/layout/max_width` 在这里生效），镜像在 `%APPDATA%\Rime\build\weasel.yaml` |
| 托盘入口的三个 exe（都在 `C:\Program Files\Rime\weasel-0.17.4\`） | `WeaselServer.exe.vmenu-bak`（原始 exe 的备份，只在第一次安装时生成）、`WeaselDeployer.real.exe`（真正的部署器）、`WeaselDeployer.exe`（代理，本机 5632 字节） |
| 截好的验证图 | 项目目录下 `shots\`（发布用的图在仓库 `screenshots\`） |
