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
$t = $t -replace '(?m)^(\s*max_width:)\s*\d+', '$1 300'
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
> 回退 = `max_width` 回 `0`、`page_size` 回 `9`，重启服务。

### 改了 Lua 却不生效

1. lua 有**两份**：`D:\rime-sandbox\lua\` 与 `%APPDATA%\Rime\lua\`，必须 **MD5 一致**
   （`TESTING.md` §4 第 4 条）；只改一份就会出现「改了没生效」。
2. 改完 lua **必须重启 `WeaselServer`**（librime-lua 是启动时加载模块），并等 ≥ 6 秒
   再打字，否则方案还没加载完会丢按键。

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
| Weasel 主题（编译后） | `<RimeUserDir>\build\weasel.yaml`（`style/layout/max_width` 在这里生效），镜像在 `%APPDATA%\Rime\build\weasel.yaml` |
| 截好的验证图 | 项目目录下 `shots\`（发布用的图在仓库 `screenshots\`） |
