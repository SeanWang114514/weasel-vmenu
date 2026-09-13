# AGENT-HANDOFF · 给下一个 agent 的交接说明

> **先读这份，再动代码。** 这份文档假设你（下一个 agent）没有本次会话的上下文，
> 但可以直接在这台机器上操作。

---

## 0. 60 秒上手

1. 这是 **Windows 输入法扩展**项目，宿主是 **小狼毫 Weasel 0.17.4 + librime 1.13.1 + rime-ice**。
   它给输入法加了一套「按 `v` 打开的功能菜单」（现在 **5 项**：设置 / 剪贴板 / 常用语 / 原符号 /
   **快捷输入**）、常驻的 WinForms 设置窗口（支持双击编辑）、
   **候选方格（默认单行 9 个，按 `↓` 展开 4 行 × 9 列）**，
   以及**托盘图标右键菜单里的「输入法设置 (S)」**
   （改 `WeaselServer.exe` 的菜单文字 + 用代理顶替 `WeaselDeployer.exe`，
   可一键撤销，见 §4「改托盘菜单入口」与 `ARCHITECTURE.md` §3.8、§3.6、§3.9）。
2. 输入法侧是 **librime-lua**（`src/lua/`），宿主侧是 **PowerShell 5.1 脚本 + bat**（`src/windows/`）。
   **唯一需要编译的东西**是托盘入口的 C# 代理（`src/windows/vmenu-deployer-wrapper.cs`），
   由安装脚本用系统自带的 `csc.exe` 自动编译，只需要.NET Framework 的 csc（无需 SDK）。
3. 改动之后通常要做这几件事，否则看不到效果：
   * 改了 **lua** → 把文件同步到两个 lua 目录（**MD5 必须一致**），然后**重启 `WeaselServer.exe`**；
   * 改了 **`.ps1`** → 结束对应的常驻进程，让 `vmenu-watcher.ps1` 用新脚本重新拉起。
   * 改了 **主题/方案的候选框键**（`max_width` / `page_size`）→ 改 `custom.yaml` **和**
     `build/*.yaml`，再重启 `WeaselServer`（现在的值是 `530` / `36`；列数变了还要同步
     `vmenu_core.lua` 的 `GRID_COLS`）。
   * 改了 **托盘入口**（`tools/vmenu-tray-setup.ps1` / `src/windows/vmenu-deployer-wrapper.cs`）
     → 重跑一次 `tools/vmenu-tray-setup.ps1`（它会重新编译并覆盖代理、按需改菜单文字）。
4. 验证一律用**截图 + 真按键**（`tools/` 里现成的脚本），不要靠「读代码觉得对」。
5. 当前状态与开放问题见 [`PROGRESS.md`](PROGRESS.md) 第 4、5 节。

---

## 1. 本机环境事实（写死的事实，别再试探）

| 事实 | 值 |
| --- | --- |
| 系统 | Windows 10/11（本机用户名/主机名从略：`$env:USERNAME` / `$env:COMPUTERNAME`） |
| Python / Node | 本机有 Node v24（用于读 DSH 会话文件等）；主脚本语言是 **Windows PowerShell 5.1**（**没有** pwsh 7） |
| Weasel | `C:\Program Files\Rime\weasel-0.17.4\`（`WeaselServer.exe`、`WeaselDeployer.exe`） |
| 托盘入口的三个 exe | 同目录：`WeaselServer.exe` = 2243072 字节（菜单文字已就地改成「输入法设置 (&S)」）；`WeaselDeployer.exe` = **5632 字节 = vmenu 代理**；`WeaselDeployer.real.exe` = 638976 字节 = 真正的部署器 |
| 托盘入口的备份 | `C:\Program Files\Rime\weasel-0.17.4\WeaselServer.exe.vmenu-bak`（2243072 字节 = 原始 exe；只在第一次安装时生成，撤销时用它还原） |
| 托盘入口脚本 | 仓库 `tools/vmenu-tray-setup.ps1`；本机部署副本 `D:\VibeCoding\输入法\vmenu-tray-setup.ps1`（它的 `-WrapperCs` 默认指向 `D:\VibeCoding\输入法\vmenu-deployer-wrapper.cs`，本机与仓库副本一致） |
| 开始菜单快捷方式 | `C:\ProgramData\Microsoft\Windows\Start Menu\Programs\小狼毫输入法\【小狼毫】输入法设置.lnk`（由「输入法设定」改名而来） |
| Rime 用户目录 | 注册表 `HKCU\Software\Rime\Weasel` 的 `RimeUserDir` → **`D:\rime-sandbox`**（这是当前生效目录） |
| Lua 镜像目录 | `%APPDATA%\Rime\lua\` —— **必须与 `<RimeUserDir>\lua\` 保持 MD5 一致**（历史遗留的双目录结构，两边都要放） |
| 方案 | `rime_ice`（雾凇拼音），编译产物 `D:\rime-sandbox\build\rime_ice.schema.yaml` |
| 候选框换行 | 主题键 `style/layout/max_width` = **530**（`0` = 不换行；150% 缩放下**一行正好 9 个**），写在 `weasel.custom.yaml` + `build/weasel.yaml` + `%APPDATA%\Rime\build\weasel.yaml` |
| 一页候选数 | 方案键 `menu/page_size` = **36**（= 9 × 4；历史上是 9 → 18 → 36），写在 `rime_ice.custom.yaml` + `build/rime_ice.schema.yaml` |
| 候选方格 | **默认单行 9 个**，按 `↓` 展开 36 个（4 行 × 9 列）、`↑` 在第一行时收回；`vmenu_core.lua` 的 `GRID_COLS = 9` / `GRID_ROWS = 4` / option `vmenu_grid` 必须与上面两个键配套改 |
| `v`→`5` 快捷输入 | 已生效：子模式 `vqi`，9 项（计算 / 日期 / 时间 / 星期 / 日期时间 / 农历 / 数字大写 / Unicode / 部件拆字）+ 返回；机制是「填前缀 + 完全放行」，见 `ARCHITECTURE.md` §3.9 |
| 部件拆字前缀 | **单字母 `u`**（`rime_ice.custom.yaml`：`radical_lookup/prefix: u` + `recognizer/patterns/radical_lookup: "^u[a-z]+$"`）；旧写法 `uU` 已失效 |
| 用户补丁文件（改这里） | `<RimeUserDir>\rime_ice.custom.yaml`（`menu/page_size`、部件拆字前缀）、`<RimeUserDir>\weasel.custom.yaml`（`max_width`）；仓库里同步维护 `examples/rime_ice.custom.example.yaml` / `examples/weasel.custom.example.yaml` |
| 屏幕 | 物理 2560×1440，缩放 150%（虚拟 1707×960） |
| 安全软件 | 火绒 HIPS 在运行（会盯「bat 起隐藏 PowerShell」这类行为） |
| 本项目工作目录 | `D:\VibeCoding\输入法`（脚本、截图、备份都在这里） |

### 部署器的一个坑（一定要知道）

`WeaselDeployer` / `WeaselServer /deploy` 在**这台机器上不会重新编译 schema**：
librime 的 `DetectModifications` 判定「无改动」后会**直接中止整个部署**。
所以 `engine/processors|translators|filters`、`punctuator/symbols`、`recognizer/patterns`
这些**结构性**配置的改动，必须用 `src/windows/patch-build-schema.ps1`
把语义**直接写回** `build\rime_ice.schema.yaml`，再重启服务。脚本可重复运行。

### 托盘菜单的机制（别再试「新增一项」）

* 托盘右键菜单是 **`WeaselServer.exe` 里的菜单资源** `IDR_MENU_POPUP`（资源号 105），
  菜单项的文字与命令号**写死在资源里**；`weasel.yaml` / `weasel.custom.yaml` 只能改候选窗口样式，
  **改不了托盘菜单**。
* 服务端对这几个命令号**只做一件事**（`WeaselServer/WeaselServerApp.cpp` 的 `SetupMenuHandlers()`）：
  启动安装目录下的 `WeaselDeployer.exe` 并带参数 —— `ID_WEASELTRAY_SETTINGS`(40008) 无参数、
  `ID_WEASELTRAY_DEPLOY`(40002) `/deploy`、`ID_WEASELTRAY_DICT_MANAGEMENT`(40010) `/dict`、
  `ID_WEASELTRAY_SYNC`(40012) `/sync`；其余项是打开网址 / 打开文件夹 / 检查更新 / 退出。
* `WeaselTrayIcon` 里的 `void CustomizeMenu(HMENU) {}` 是**空实现**，没有可用配置钩子；
  新增一个「全新命令号」的菜单项服务端不会处理（点了没反应）。
* → 本项目走的是「**就地改菜单文字** + **用代理顶替 `WeaselDeployer.exe`**」，完整细节
  （含安装 / 撤销链路）见 `ARCHITECTURE.md` §3.8。

---

## 2. 硬约束（违反会出事故）

| # | 约束 | 原因 |
| --- | --- | --- |
| 1 | **绝不在 Rime 输入线程里启动子进程**（Lua 里禁用 `io.popen` / `os.execute`） | 早期版本在 Lua 里读剪贴板，直接卡死输入法。Lua 只能读写文本文件 |
| 2 | Lua 里的对外函数一律用 `pcall` 兜底，异常时 `return 2`（放行） | 输入法绝不能因为扩展报错而不能打字 |
| 3 | 普通打字路径**不读写文件**（`fav_hit` 只在输入 ≥ 3 字符时才读） | 打字流畅度优先 |
| 4 | 候选顺序：filter 的 yield 顺序是权威，但**必须同时把 `quality` 改成严格递减** | 否则后置排序会打乱「常用语在第 2 位」 |
| 5 | 改完 lua **必须重启 `WeaselServer.exe`** | librime-lua 是启动时加载模块 |
| 6 | 两个 lua 目录必须同步（MD5 一致） | 双目录结构，不同步会出现「改了没生效」 |
| 7 | `.ps1` 里**要么纯 ASCII，要么带 BOM** | PS 5.1 把无 BOM 的 UTF-8 当 ANSI 解析，中文注释/字符串会炸解析 |
| 8 | `.bat` 必须 **CRLF + 纯 ASCII** | cmd.exe 按活动代码页逐块解码，多字节字符跨块会错位 |
| 9 | 按命令行匹配进程来杀进程的脚本，**必须排除自己**（`$PID`）或运行时拼接脚本名 | 自己的 pwsh 命令行里含脚本字面名 → 自杀（实测把自己打断过） |
| 10 | 不要永久修改系统输入法选择 / 不要静默写开机启动项 | 用户环境优先；需要自启时先问 |
| 11 | 方向键**只在普通打字时**由 Lua 接管（`core.grid_key`），**v 菜单内一律放行**；新增方向键分支前先想清楚是在哪种模式 | 候选方格需要 `↓` = 展开 / 跳行、`↑` = 收回 / 跳行（原版只有「下一个候选」）；v 菜单要保持原版手感。早期版本的教训是「无脑接管会破坏手感」，现在是**有条件的接管** |
| 12 | 改 `build/*.yaml`（`weasel.yaml` / `rime_ice.schema.yaml`）**只用 `[IO.File]::ReadAllText/WriteAllText` + UTF-8** | PS 5.1 的 `Get-Content`/`Set-Content` 按 ANSI 解码，写坏 YAML 后**候选窗口完全不显示** |
| 13 | 候选框宽度/一页上限**不要去 Lua 里找办法**（但「这一屏放几个」必须在 Lua 里限制） | 换行是 Weasel 主题 `style/layout/max_width` 的渲染行为，一页条数是 schema 的 `menu/page_size`，输入法内无法运行时切换；候选**个数**则可以在 `menu_filter` 里截断 |
| 14 | **改 `WeaselServer.exe` 前必须先停掉 `WeaselServer` 进程**，且只做 **UTF-16 等长替换** | 运行中的 exe 文件被系统锁住，写不进去；等长替换（`定`→`置`，2 个字节）不动偏移量 / 长度，不会破坏文件结构 |
| 15 | 托盘菜单**不要试图新增菜单项或新命令号**，只做「改文字 + 用代理顶替 `WeaselDeployer.exe`」 | 菜单项写死在 `WeaselServer.exe` 的资源里，服务端只认 `WeaselDeployer.exe` 这一个入口（`CustomizeMenu` 是空实现，新命令号不会被处理） |
| 16 | 托盘相关的 `.ps1` 与**代理源码 `.cs`** 都必须 **UTF-8 带 BOM**；脚本里匹配中文用字符码拼（`[char]0x8F93…`） | 否则 PS 5.1 / csc 按 GBK 解析，中文提示变乱码，字面量也匹配不上 |
| 17 | 需要跨 `lua_processor` / `lua_filter` 共享的状态**只能放 context option**（如 `vmenu_grid`、`vraw_mode`），不要用模块级变量 | 两个组件**各自 `require` 一份** lua 模块，模块级变量不共享（展开状态曾因此读不到） |
| 18 | `ctx.selected_candidate_index`（**1 基**）与 `ctx:select(i)`（**0 基**）的换算只写一处（`grid_sel`） | 混用会差一位，表现为「跳行跳错一个」（已踩） |
| 19 | 不要用 `menu/alternative_select_labels` 去改展开后的行序号 | 填的标签数与 `page_size` 不匹配时 rime 会**拒绝整份补丁**并把 `page_size` 退回 9（已踩，见 `PROGRESS.md` §5 第 11 条） |
| 20 | 快捷输入类功能**优先复用 rime-ice 自带的 recognizer + translator**（只填前缀），不要自己实现计算/日期/农历 | 自研等于重造轮子并丢边界处理；`ARCHITECTURE.md` §3.9 有完整前缀表 |

---

## 3. 目录与「改哪里」

```
src/lua/           → 复制到 <RimeUserDir>\lua\ 和 %APPDATA%\Rime\lua\
  vmenu_core.lua      共享核心：路径、设置读写、剪贴板/常用语读写、命中判断、原符号标记，
                      以及候选方格状态与二维导航（GRID_COLS=9 / GRID_ROWS=4 / option vmenu_grid /
                      grid_limit / grid_key；状态必须走 option，模块级变量在 filter 里读不到）
  menu_processor.lua  ★ 按键总管（必须排在 speller/selector 之前）：v 菜单（1-5）、vqi 子模式、
                        数字编码、回车调用；非 v 模式的方向键先交给 core.grid_key
                        （v 菜单内不接管；原来的主菜单第 5 项「文字设置」仍是保留代码）
  lua_menu.lua        ★ translator：产出所有菜单/列表候选（文案都在这里，要改文案就改它）
                        yield_menu yield 5 项（设置/剪贴板/常用语/原符号/快捷输入）；
                        yield_quick yield 9 项 + 返回（快捷输入的文案与顺序）
  menu_filter.lua     ★ filter：v 模式只留需要的候选；普通打字时把常用语插到第 2 位，
                        并按 core.grid_limit(ctx) 截断候选个数（收起 9 / 展开 36）

src/windows/       → 放到任意目录（脚本间用 %~dp0 互相调用，必须保持同目录）
  vmenu-settings-gui.ps1  ★ 常驻设置窗口（WinForms）：三个标签页 + 标记文件轮询 + 离屏预建
                            + 列表双击编辑（Edit-Clipboard / Edit-Favorite）
  vmenu-watcher.ps1       监督者：窗口没在跑就拉起来（单实例互斥体 RimeVMenuWatcher）
  vmenu-watcher-stop.ps1  停止监督者 + 常驻窗口
  clipboard-sync.ps1      剪贴板 → clipboard-cache.txt
  clipboard-sync-stop.ps1 停止剪贴板同步
  patch-build-schema.ps1  把结构性配置写回 build\rime_ice.schema.yaml
  vmenu-deployer-wrapper.cs  ★ 托盘「输入法设置」的代理源码（C#，安装脚本用 csc 编译成
                             WeaselDeployer.exe 顶替真身；必须 UTF-8 带 BOM）
  clipboard-sync.bat      一键重启两个服务并打开设置窗口
  打开设置.bat             先写标记文件，再拉起监督者（最快的备用入口）
  重建部署.bat             patch-build-schema + 重启服务

tools/             → 验证工具（见第 5 节）+ 托盘入口安装脚本
  vmenu-tray-setup.ps1    托盘菜单入口「输入法设置」的安装（幂等）/ 撤销（-Revert），
                          并回读校验 exe 里的菜单文字
examples/          → 示例数据（常用语、剪贴板缓存、设置文件、custom.yaml）
screenshots/       → README 用图（**全部是示例数据**，不要往这里放真实剪贴板内容）
```

---

## 4. 怎么改、怎么让它生效

### 改 Lua（输入法行为、菜单文案、命中规则）

```powershell
# 1) 在 src/lua/ 改完，同步到两个目录
$a = 'D:\rime-sandbox\lua'; $b = "$env:APPDATA\Rime\lua"
foreach ($f in 'vmenu_core.lua','menu_processor.lua','lua_menu.lua','menu_filter.lua') {
  Copy-Item (Join-Path $a $f) (Join-Path $b $f) -Force
}
# 2) 重启输入法服务
Get-Process WeaselServer -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
Start-Process 'C:\Program Files\Rime\weasel-0.17.4\WeaselServer.exe'
Start-Sleep -Seconds 7      # 等它把方案加载完，太早打字会丢按键
# 3) 看日志有没有 lua 报错（有的话一定是 lua 语法/API 用错）
Get-ChildItem "$env:TEMP\rime.weasel\*.log" | Sort-Object LastWriteTime -Descending |
  Select-Object -First 1 | Get-Content | Select-String 'lua|ERROR' | Select-Object -Last 20
```

### 改设置窗口（`vmenu-settings-gui.ps1`）

```powershell
# 结束常驻窗口（注意：命令里不要出现脚本全名，否则会匹配到自己的进程）
$pat = 'vmenu-' + 'settings-gui.ps1'
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine.IndexOf($pat) -ge 0 } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
# 3 秒内 vmenu-watcher.ps1 会用新脚本把它拉起来
# ★ 编辑后必须补回 BOM：
$p = 'D:\VibeCoding\输入法\vmenu-settings-gui.ps1'
$t = [IO.File]::ReadAllText($p)
[IO.File]::WriteAllText($p, $t, (New-Object Text.UTF8Encoding($true)))
'BOM: ' + (([IO.File]::ReadAllBytes($p)[0..2]) -join ',')   # 必须是 239,187,191
```

### 改结构性配置（processors / translators / filters / punctuator）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\windows\patch-build-schema.ps1 -RimeDir D:\rime-sandbox
# 然后重启 WeaselServer（或直接双击 src\windows\重建部署.bat）
```

### 改候选方格（默认单行 9 个 / 按 `↓` 展开 4 行 × 9 列）

**宽度与一页上限不在 Lua 里**（两个键，两处 `custom.yaml` + `build/*.yaml` 都要改）；
**但「这一屏放几个」在 Lua 里**（`menu_filter` 按 `core.grid_limit(ctx)` 截断），列数改了要一起同步。
**必须用 UTF-8 读写**，绝不能用 `Get-Content`/`Set-Content`（会把 YAML 写坏，
后果是候选窗口完全不显示）：

```powershell
function Set-YamlValue($p, $pattern, $value) {
  $t = [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8)
  $t = [regex]::Replace($t, $pattern, $value)
  [IO.File]::WriteAllText($p, $t, (New-Object Text.UTF8Encoding($false)))   # false = 无 BOM
}
# 一行放几个（越小行越多）：0 = 不换行；530 在 150% 缩放下正好一行 9 个
# （历史数据：620 实测不换行、300 时一行约 5 个）
Set-YamlValue 'D:\rime-sandbox\build\weasel.yaml' '(?m)^(\s*max_width:)\s*\d+' '$1 530'
# 一页上限（= 列数 × 行数；现在 36 = 9 列 × 4 行）
Set-YamlValue 'D:\rime-sandbox\build\rime_ice.schema.yaml' '(?m)^(\s*page_size:)\s*\d+' '$1 36'
# custom.yaml 里的 patch 也要同步改；列数变了还要改 src\lua\vmenu_core.lua 的 GRID_COLS，
# 并把 lua 同步到两个目录，再重启服务：
Get-Process WeaselServer -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Process 'C:\Program Files\Rime\weasel-0.17.4\WeaselServer.exe'
# 看日志确认没有 Error parsing；回退 = max_width 0 + page_size 9（回到原版一条长候选栏）
```

验证要用**截图 + 候选窗口尺寸**：打一段拼音刷出 ≥ 10 条候选 → 期望单行 9 个（797 × 74），
按 `↓` → 4 行 × 9 列（797 × 285），第一行按 `↑` → 收回（`TESTING.md` §8.3）。

> ⚠️ 别用 `menu/alternative_select_labels` 去改展开后的行序号：标签数与 `page_size` 不匹配时
> rime 会**拒绝整份补丁**并把 `page_size` 退回 9（已踩过，见 `PROGRESS.md` §5 第 11 条）。

### 改快捷输入（`v`→`5` 的 9 项）

三处代码，改完**同步两个 lua 目录 + 重启 `WeaselServer`**：

| 想改什么 | 改哪里 |
| --- | --- |
| 菜单文字 / 注释 / 顺序 | `src/lua/lua_menu.lua` 的 `yield_quick`（`item(seg, "vqi", 文字, 注释)`） |
| 某项填进去的前缀 | `src/lua/menu_processor.lua` 的 `cur == "vqi"` 分支（`replace_input(ctx, "cXx")`） |
| 「返回」行为 / 其它按键 | 同上分支末尾：`q` → `ctx:clear()`，其余 `return 2` 放行 |
| 模式识别（例如加新前缀） | `src/lua/vmenu_core.lua` 的 `mode_of()` / `want_type()`（`vqi` ↔ `quick`） |

原则：**只填前缀，不要自己实现功能**（计算 / 日期 / 农历 / 数字大写 / Unicode / 部件拆字都是
rime-ice 自带的，前缀表见 `ARCHITECTURE.md` §3.9）。新加的项要确认对应 recognizer 存在，
否则「按了数字没候选」。

### 改托盘菜单入口（「输入法设置」）

```powershell
# 改完 vmenu-deployer-wrapper.cs / vmenu-tray-setup.ps1 后，重跑安装脚本即可
# （它自动停/起 WeaselServer、重新编译代理、覆盖 WeaselDeployer.exe、按需改菜单文字）
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\vmenu-tray-setup.ps1
# 期望结尾：校验：exe 里 旧标签=0 处 / 新标签=1 处

# 撤销（还原 WeaselServer.exe、把 .real.exe 改回 WeaselDeployer.exe、快捷方式名字还原）
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\vmenu-tray-setup.ps1 -Revert

# 验收「托盘那一项做的事」：无参数运行部署器位置上的程序 = 打开 vmenu 设置窗口
& 'C:\Program Files\Rime\weasel-0.17.4\WeaselDeployer.exe'

# 验收转发链（会真的重新部署：build\weasel.yaml / build\rime_ice.schema.yaml 会被重新生成）
& 'C:\Program Files\Rime\weasel-0.17.4\WeaselDeployer.exe' /deploy
```

* 脚本参数：`-Revert`、`-InstallDir`（默认 `C:\Program Files\Rime\weasel-0.17.4`）、
  `-GuiScript`（默认 `D:\VibeCoding\输入法\vmenu-settings-gui.ps1`）、
  `-WrapperCs`（默认 `D:\VibeCoding\输入法\vmenu-deployer-wrapper.cs`）。
* 备份**只在第一次安装时**生成（`WeaselServer.exe.vmenu-bak`），`-Revert` 用它还原 exe；
  备份已存在时脚本不会覆盖它。
* **脚本怎么判断当前 `WeaselDeployer.exe` 是真身还是代理（0.2.2 起）**：先编译代理，再用
  「大小是否等于代理（5632 字节）」比较；不是代理就先 `Move-Item` 改名成
  `WeaselDeployer.real.exe`（**覆盖旧真身**），然后才放入代理。所以「小狼毫升级后重跑」
  **会**自动把新版部署器改名保存，不会丢（旧版的「`.real.exe` 存在就跳过改名」已废弃）。
* 改完 `.cs` / `.ps1` 记得确认 BOM（`TESTING.md` §4 第 2、2b 条）。

---

## 5. 验证工具（全部在 `tools/`，都是 ASCII-only 的 PS 5.1 脚本）

| 工具 | 用途 | 例子 |
| --- | --- | --- |
| `type-and-shot.ps1` | **抢焦点 + 真按键 + 截图**（`AttachThreadInput` + ALT 解锁，能打赢 Chrome 抢焦点） | `-Target notepad -Keys 'esc,w,s,l,enter' -Out shots\x.png -ShotX 0 -ShotY 40 -ShotW 1700 -ShotH 560` |
| `ime-test.ps1` | 老版按键+截图（会把记事本移到 80,60） | `-Keys 'esc,v,1' -Out shots\x.png` |
| `run-vmenu-tests.ps1` | 把 18 个菜单流程步骤各截一张图 | 无参数 |
| `v1-latency-test.ps1` | 标记文件 → 窗口出现在屏幕上的延迟（轮询 5 ms） | `-Runs 3` |
| `v1-e2e-test.ps1` | **真按 `v` `1`** → 窗口出现的端到端延迟 | `-Out shots\e2e.png` |
| `gui-dblclick-test.ps1` | **设置窗口双击编辑**：截图找行 + 真实鼠标双击 → 等弹框标题 | `-Row 1 -Out shots\dblclick.png`；`-PreX 300 -PreY 200 -Row 1 -Expect '修改常用语'`；`-Row 1 -TypeInto test`（会真的改文件，先备份） |
| `shot-window.ps1` | 按窗口标题抓单个窗口（DPI-aware） | `-Match ' v ' -Out shots\w.png` |
| `window-keys-shot.ps1` | 抢前台 + 发组合键（如 `ctrl+tab`）+ 抓窗口 | `-Match ' v ' -Keys 'ctrl+tab' -Out x.png` |
| `list-windows.ps1` | 列出可见窗口（pid / hwnd / 物理坐标 / 标题） | `-MinWidth 600` |
| `focus-notepad.ps1` | 只抢焦点 | 无参数 |
| `vmenu-tray-setup.ps1` | **托盘菜单入口安装 / 撤销**（改 exe 菜单文字 + 装代理 + 快捷方式改名），结尾打印回读校验 | 无参数安装；`-Revert` 撤销 |

### 截图取证的正确姿势

1. 先 `Get-Process notepad | Stop-Process -Force`，再 `Start-Process notepad`（干净文档，标题显示内容）。
2. `type-and-shot.ps1` 会返回 `FOCUSED=` / `AFTER=`（记事本标题=已输入内容）/ `SHOT=`，
   **`AFTER=` 就是判据**：例如 `AFTER=*13800138000` 表示号码真的上屏了。
3. 需要看清楚候选栏时，用 `-ShotW 1700` 抓宽一点（候选栏可能超过 1200 px），
   再用 `System.Drawing` 裁到正文区域，避免把桌面/其它窗口截进去。
4. 想确认「窗口真的可见」，必须同时判 `MainWindowHandle != 0` **且** `GetWindowRect` 的
   `Left/Top > -1000`（曾经出现过窗口停在 -48000,-48000 却被判为「已显示」）。
5. **设置窗口的 GUI 自动化不要用 UI Automation**：`FindAll(Descendants, TrueCondition)`
   对它是 0 个元素。只能「截图找行 + 真实鼠标」，并且进程要先 `SetProcessDPIAware()`
   （否则坐标被 1.5 倍缩放，点到别的行）。模态弹框要用 `EnumWindows` + `GetWindowTextW` 找
   （它不进 `Process.MainWindowTitle`）。现成实现：`tools/gui-dblclick-test.ps1`。

---

## 6. 排查手册（症状 → 检查点）

| 症状 | 先查什么 |
| --- | --- |
| 按 `v` 没反应 | `WeaselServer` 是否在跑；两个 lua 目录是否一致；`WeaselServer` 日志里有没有 lua 报错；`patch-build-schema.ps1` 是否写入过 `lua_processor@*menu_processor` |
| `v`→`1` 没反应 | `vmenu-watcher` 和常驻窗口进程是否各有一个（见 §3 的检查命令）；`open-settings.flag` 是否被消费（稳态下不该存在） |
| 窗口弹得慢 | 常驻进程还在吗？如果每次都要重新起 PowerShell，看 `-ShowNow` 分支和离屏预建那两段是否被改坏 |
| 常用语不在第 2 位 | `menu_filter.lua` 的 `place()` 是否还把整表 `quality` 改成递减；`fav_hit` 是否被改成「精确匹配」 |
| 打数字没候选 | `menu_processor.lua` 的 `digit_prefix` 分支是否还在（注意 `#s <= #k`，写成 `<` 会漏最后一位） |
| 回车把原始编码上屏而不是常用语 | `menu_processor.lua` 的 `Return` 分支是否还在；`fav_exact` 是否要求**完全一致** |
| 保存的中文变乱码 | 对应文件是不是 BOM/编码问题（`.ps1` 带 BOM、数据文件不带 BOM、`.bat` 纯 ASCII + CRLF） |
| **打字完全看不到候选框** | `build\weasel.yaml` 是不是被 `Get-Content`/`Set-Content` 写坏了（日志里找 `Error parsing`）；用 UTF-8 读写改回 |
| 候选框不展开（还是只有一行） | `build\weasel.yaml` 的 `max_width` 是不是 `530`、`build\rime_ice.schema.yaml` 的 `page_size` 是不是 `36`（改完要重启 `WeaselServer`）；`vmenu_core.lua` 的 `GRID_COLS` 是否与之一致；两个 lua 目录是否 MD5 一致 |
| 按 `↓` / `↑` / `←` / `→` 没反应或行为怪 | 普通打字走 `core.grid_key`（`↓` 展开 / 跳行、`↑` 收回 / 跳行、左右移动）；**v 菜单内方向键必须放行**。若在 v 菜单里乱跳，说明 `grid_key` 被套到了菜单模式上（`cur ~= "" and not core.mode_of(cur)` 这个条件被改坏了） |
| 展开后第 2–4 行还有序号 | **已知未解决**（rime 按下标发号；`alternative_select_labels` 会被拒），不是配置错，见 `PROGRESS.md` §5 第 11 条 |
| 菜单里按 `5` 没反应 | `vqi` 分支 / `mode_of` 的 `vqi`→`quick` 是否还在；是否同步了两个 lua 目录并重启过 `WeaselServer`；日志有没有 lua 报错 |
| `v`→`5`→数字之后没有候选 | ①「计算」要在 `cC` 后继续敲算式（`^cC.+`）；②「数字大写 / Unicode / 部件拆字」要自己补内容（`R1234`/`U4e2d`/`nvzi`）；③对应 recognizer 是否在 `build\rime_ice.schema.yaml` 里 |
| 打 `u` 不出部件拆字 | `u` 后面必须继续输入字母（`^u[a-z]+$`）；另外 0.2.3 起前缀是单 `u`，旧的 `uU` 写法已失效 |
| 双击列表某一项没反应 | 是不是没点到行？列表区域默认 `ListTop=200`（跳过表头）；用 `gui-dblclick-test.ps1 -DryRun` 先确认找得到行 |
| 点托盘「输入法设置」没反应 | `WeaselDeployer.exe` 是不是 **5632 字节**的代理、`WeaselDeployer.real.exe` 在不在；不在就重跑 `tools\vmenu-tray-setup.ps1`。窗口起不来则按「`v`→`1` 没反应」查常驻窗口 |
| 托盘菜单第一项又变回「输入法设定」 | 多半是小狼毫升级 / 修复安装覆盖了 exe：重跑 `tools\vmenu-tray-setup.ps1` 即可（脚本会先编译代理、按大小判断当前 `WeaselDeployer.exe` 是不是代理，是真身就先改名保存为 `.real.exe`，不会丢掉新版部署器） |
| 重新部署后候选方格参数没了 | **正常情况不会**：`max_width` / `page_size` 写在 `custom.yaml` 的 patch 里，重新部署会重新应用；真没了就查 `build\weasel.yaml` 与 `rime_ice.custom.yaml` 的值 |
| 打字变卡 | 是不是在普通打字路径里读了文件或起了进程（约束 1、3） |

---

## 7. 安全改动清单（每次改完都过一遍）

- [ ] Lua：`pcall` 兜底、普通路径不读盘、不启动进程
- [ ] 同步两个 lua 目录并校验 MD5
- [ ] 重启 `WeaselServer` 并等 ≥ 6 秒
- [ ] 看日志没有新的 lua/ERROR
- [ ] 用 `type-and-shot.ps1` 真按键验证，并**看图**确认候选栏内容
- [ ] 回归：`ni`（普通拼音候选正常）、`12345`（纯数字正常）、`wsl`/`138`（常用语命中）、`v` 菜单（**5 项**）、`v`→`3` 列表、`v`→`5` 快捷输入（至少验一项上屏）
- [ ] 改了 `.ps1` 的话补回 BOM 并检查解析（`Parser::ParseFile`）
- [ ] 改了候选框键（`max_width`/`page_size`）的话：`custom.yaml` 与 `build/*.yaml` 都改了、`vmenu_core.lua` 的 `GRID_COLS` 同步了、用 UTF-8 读写、日志没有 `Error parsing`、截图 + 候选窗口尺寸确认（单行 9 / 展开 4 行 × 9 列）
- [ ] 改了快捷输入（`lua_menu.lua` / `menu_processor.lua` / `vmenu_core.lua`）的话：两个 lua 目录 MD5 一致、重启服务、每一项都真按键验一次上屏（`TESTING.md` §8.2 的表格）
- [ ] 没试过用 `menu/alternative_select_labels` 去改行序号（会被 rime 拒绝整份补丁）
- [ ] 改了托盘入口（`vmenu-tray-setup.ps1` / `vmenu-deployer-wrapper.cs`）的话：两个文件都 **UTF-8 带 BOM**、重跑安装脚本、结尾校验是「旧标签 0 处 / 新标签 1 处」、`WeaselDeployer.exe` = 5632 字节的代理且 `.real.exe` 仍在
- [ ] 动 `WeaselServer.exe` 之前确认 **`WeaselServer` 已停**（脚本会自己停/起），并且只做**等长替换**
- [ ] 托盘入口改完顺手回归三件不受影响的事：重新部署 / 用户词典管理 / 用户资料同步（至少跑一次 `/deploy`，看日志没有 Error 且 `max_width`/`page_size` 还在）
- [ ] 双击编辑的测试跑完**把数据还原**并校验 sha256
- [ ] 截图/示例数据里**不出现真实剪贴板、邮箱、手机号**

---

## 8. 当前状态 / 已完成 / 下一步

### 已完成并验收（2026-09-13 第二轮）

* `v` 菜单 **4 项**（`1 设置` / `2 剪贴板` / `3 常用语` / `4 原符号`）；第 5 项「文字设置」已去掉。
* 「收藏」→「常用语」改名（**只改用户可见文本**；`favorites.dict.yaml` / `vfav` / `vset*` /
  `vmenu-settings.txt` 等内部标识沿用旧名）。
* **多行候选框**（第二轮的做法，**第五轮已被换掉**）：主题 `style/layout/max_width = 300` +
  方案 `menu/page_size = 18` → 一页 18 条、约 4 行 × 5 列；回退 = `0` + `9`。
  方向键 `↓↑←→` 当时一律交回 librime `navigator`（`↓`/`→` = 下一个候选，不上屏）；
  现在改成 **`530` + `36` + `grid_key` 接管**（默认单行 9 个、按 `↓` 展开 4 行 × 9 列，见第五轮）。
* 设置窗口**双击编辑**：剪贴板页弹「编辑第 N 条」、常用语页弹「修改常用语」；
  已端到端验收（双击第 1 行 → 输入 `test` → 文件第 1 行变化 → 还原后 sha256 一致）。
* 新测试工具 `tools/gui-dblclick-test.ps1`（截图找行 + 真实鼠标双击），
  用法与实测几何见 `TESTING.md` §1；退出码 0 / 1 / 2。

### 已完成并验收（2026-09-13 第三轮 · 托盘菜单）

* **托盘图标右键菜单第一项 = 「输入法设置 (S)」**（`WeaselServer.exe` 里的菜单文字已就地改成
  `输入法设置 (&S)`：UTF-16 等长替换，回读 新标签 1 处 / 旧标签 0 处，命令号 **40008**；
  该 exe 无数字签名）。
* **`WeaselDeployer.exe` 位置已换成代理**（5632 字节），真身 = `WeaselDeployer.real.exe`
  （638976 字节）；无参数 → 打开 vmenu 设置窗口，`/deploy`、`/dict`、`/sync` → 原样转发。
  透传已实测：`build\weasel.yaml` / `build\rime_ice.schema.yaml` 重新生成、日志只有 INFO、
  `max_width: 300` 与 `page_size: 18` 都还在（**重新部署不会弄丢多行候选框**；
  这两个值在第五轮改成了 `530` / `36`，结论不变）。
* 设置窗口「设置与缓存」页新增分组 `小狼毫原生设置` + 按钮 `打开小狼毫原生设置`
  （弹出标题 `【小狼毫】方案选单设定`），实测截图 `screenshots/gui-05-native-settings.png`。
* 开始菜单 `【小狼毫】输入法设定.lnk` → `【小狼毫】输入法设置.lnk`。
* 安装 / 撤销脚本 `tools/vmenu-tray-setup.ps1`（幂等 / `-Revert`），备份
  `WeaselServer.exe.vmenu-bak`；验收方法与命令见 `TESTING.md` §7。
* 明确**没做**：`weasel.dll` / `weaselx64.dll` 里的语言栏菜单文字（见开放问题）。

### 已完成并验收（2026-09-13 第四轮 · `v`→`5` 快捷输入）

* **主菜单第 5 项 = 「快捷输入」**（注释 `计算 · 日期`）→ `vqi` 子模式，9 项 + 返回：
  计算 `cC` / 日期 `rq` / 时间 `sj` / 星期 `xq` / 日期时间 `dt` / 农历 `N`+当天 / 数字大写 `R` /
  Unicode `U` / 部件拆字 `u`（原来的「文字设置」保持去掉状态）。
* **机制**：选中后**把前缀直接写进输入框**（`replace_input`），之后按键**完全交回原方案** ——
  复用雾凇拼音自带的 `recognizer/patterns` + `lua_translator`，**没有自己实现任何一项**。
* 真按键验收：`1+2*3`→7、`9*9`→81、日期 `2026-09-13`、时间 `02:30`、星期 `星期日`、
  `2026-09-13T02:30:14+0800`、农历 `丙午马年八月初三`、`R1234`→一千二百三十四、`U4e2d`→中。
  表格与复现命令见 `TESTING.md` §8。**本轮没有截图**（抓屏会带上用户桌面内容，新图已删除）。
* 同一轮修好 `tools/vmenu-tray-setup.ps1` 的**代理识别**（改成按大小判断，见下面第 8 条）。

### 已完成并验收（2026-09-13 第五轮 · 候选方格 + 部件拆字）

* **候选窗口默认单行 9 个，按 `↓` 展开 4 行 × 9 列**：主题 `max_width = 530` +
  方案 `menu/page_size = 36`；`vmenu_core.lua` 的 `grid_limit` / `grid_key` 负责状态与二维导航
  （`↓` 展开 / 下跳一行，`↑` 第一行时收回 / 否则上跳一行，`←`/`→` 行内移动，其它键自动收回）。
* 实测：`shi` → 797 × 74；`↓` → 797 × 285；第一行 `↑` → 797 × 74；再打字自动收回。
* **部件拆字前缀 `uU` → `u`**（两行配置，**没有新造功能**）：`unvzi`→好、`uriyue`→明；
  `v`→`5` 子菜单同步加了第 9 项「部件拆字」。**旧的 `uU` 写法失效**。
* 明确**未解决**：展开后第 2–4 行仍带序号（需求是只第一行有 1–9）；
  `menu/alternative_select_labels` 填 36 项会被 rime 拒绝（`page_size` 退回 9）。
* 待复测：`↓↓` 与 `↓`+`→`×9 选中同一个候选（4 组对照里 1 组不一致）。

### 下一步（按价值排序）

1. **确认开放问题 1**（「最右边的回车键也要还原」的确切含义，见 `PROGRESS.md` §5）——
   到现在**仍未确认**；如果是别的意思，改 `menu_processor.lua` 的 `Return` 分支即可。
2. **`vset*` 死代码怎么处理待定**：菜单第 5 项现在被快捷输入占用，它依然不可达
   （只有手打 `vset` 进得去）。删掉能省一大段文案与分支；留着保留「窗口挂了也能改设置」的兜底。
   需要人类拍板。
3. **展开后第 2–4 行的序号（未解决，见 `PROGRESS.md` §5 第 11 条）**：
   试过的 `alternative_select_labels` 方案会被 rime 拒绝，需要另想办法（或改成自定义 filter，
   风险较高）。
4. **「快捷输入」是否做进设置窗口可配置**（顺序 / 显示哪几项），以及是否再加更多项
   （见 `PROGRESS.md` §5 第 9、10 条）。
5. DPI 感知：给 `vmenu-settings-gui.ps1` 加 `SetProcessDPIAware()` 并把所有尺寸乘 `DpiX/96`，
   解决 150% 下文字略软。
6. 开机自启（用户明确要求时）：加 `install-autostart.ps1`（写入启动项前必须显式确认）。
7. 剪贴板条目支持多行（现在被压平成一行）；需要改缓存格式 + 读写两侧。
8. 常用语编码不足 3 位时也能在打字时命中（现在只能用 `v`→`3`）；代价是要在 1–2 个字符时也读文件，
   需要先做性能测量。
9. ~~托盘入口在「小狼毫升级后重跑」时的健壮性~~ **✅ 已完成（第四轮）**：
   脚本改成先编译代理、按大小（5632 字节）判断当前 `WeaselDeployer.exe` 是真身还是代理，
   不是代理就先改名成 `.real.exe`（覆盖旧真身）再装代理；实测重跑输出符合预期。
10. **`weasel.dll` / `weaselx64.dll` 的语言栏菜单文字是否也改**（见 `PROGRESS.md` §5 开放问题 7）：
    本次没做 —— 注入所有进程的 IME 模块，改了要重启所有程序才生效。
