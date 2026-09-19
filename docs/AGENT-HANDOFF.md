# AGENT-HANDOFF · 给下一个 agent 的交接说明

> **先读这份，再动代码。** 这份文档假设你（下一个 agent）没有本次会话的上下文，
> 但可以直接在这台机器上操作。

---

## 0. 60 秒上手

1. 这是 **Windows 输入法扩展**项目，宿主是 **小狼毫 Weasel 0.17.4 + librime 1.13.1 + rime-ice**。
   它给输入法加了一套「按 `v` 打开的功能菜单」（现在 **5 项**：设置 / 剪贴板 / 快捷输入 / 常用语 /
   **原符号**）、常驻的 WinForms 设置窗口（支持双击编辑）、
   **候选方格（默认收起 9 个，按 `↓` 展开 4 行 × 9 列、序号在词前、方向键移动选中项）**，
   以及**托盘图标右键菜单里的「输入法设置 (S)」**
   （改 `WeaselServer.exe` 的菜单文字 + 用代理顶替 `WeaselDeployer.exe`，
   可一键撤销，见 §4「改托盘菜单入口」与 `ARCHITECTURE.md` §3.8、§3.6、§3.9）。
   ⚠️ 候选方格那几项**改的是 Weasel 源码、跑的是自己编的 DLL/exe**：
   源码分支 `weasel-grid-build`，完整记录见 [`GRID-CANDIDATE-DLL.md`](GRID-CANDIDATE-DLL.md)。
2. 输入法侧是 **librime-lua**（`src/lua/`），宿主侧是 **PowerShell 5.1 脚本 + bat**（`src/windows/`）。
   **需要编译的东西有两处**：① 托盘入口的 C# 代理（`src/windows/vmenu-deployer-wrapper.cs`，
   由安装脚本用系统自带的 `csc.exe` 自动编译，只需要.NET Framework 的 csc（无需 SDK））；
   ② **Weasel 本体**（`WeaselUI/HorizontalLayout.cpp` + `RimeWithWeasel/RimeWithWeasel.cpp` 三个补丁，
   **本机编不了**，走 GitHub Actions 出包，见 `GRID-CANDIDATE-DLL.md` §4）。
3. 改动之后通常要做这几件事，否则看不到效果：
   * 改了 **lua** → 把文件同步到两个 lua 目录（**MD5 必须一致**），然后**重启 `WeaselServer.exe`**；
   * 改了 **`.ps1`** → 结束对应的常驻进程，让 `vmenu-watcher.ps1` 用新脚本重新拉起。
   * 改了 **主题/方案的候选框键**（`page_size` 等）→ 改 `custom.yaml` **和**
     `build/*.yaml`，再重启 `WeaselServer`（`page_size` = `36`；列数变了还要同步
     `vmenu_core.lua` 的 `GRID_COLS`）。**`max_width` 已经不管换行了**（自编 DLL 按「每 9 个」换）。
   * 改了 **Weasel 源码补丁** → 推到 `weasel-grid-build` 触发 CI → 下载 `weasel-grid-dlls.zip`
     → `tools/deploy-grid-dlls.ps1`（**5 个文件**，含 System32/SysWOW64）→ 重启 `WeaselServer`
     + 重启测试用的应用 → 按 §1 确认**没被微信输入法抢权**；
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
| ★ 现在跑的是**自己编的** Weasel | 候选窗口的「单行 ⇄ 4 行 × 9 列 + 序号在词前 + 方向键移动选中项」**必须改源码重编**（配置和 Lua 都做不到，理由见 `GRID-CANDIDATE-DLL.md` §1）。源码在 fork 仓库分支 **`weasel-grid-build`**（本地克隆 `D:\weasel-build\weasel`），GitHub Actions 出包，release 资产名是 **`weasel-grid-dlls.zip`**（tag `weasel-grid-<run 号>`）。当前部署：`weasel.dll` 1033728 / `weaselx64.dll` 1178624 / `WeaselServer.exe` 2755584 字节 |
| ★★ 部署**必须换 5 个文件** | 安装目录的 `weasel.dll` / `weaselx64.dll` / `WeaselServer.exe` **加上** `C:\Windows\System32\weasel.dll`（x64）与 `C:\Windows\SysWOW64\weasel.dll`（x86）。**TSF 客户端 DLL 不在安装目录**：注册表 `HKLM\SOFTWARE\Classes\CLSID\{A3F4CDED-B1E9-41EE-9CA6-7B4D0DE6CB0A}\InprocServer32` 指向 System32（`WOW6432Node` 那支指向 SysWOW64）。只换安装目录 = 应用侧完全没变（实测 md5 对比确认）。脚本：`tools/deploy-grid-dlls.ps1` |
| ★ 托盘入口（**已被覆盖，功能倒退**） | 原来 `WeaselServer.exe` = 2243072 字节（菜单文字就地改成「输入法设置 (&S)」）+ `WeaselDeployer.exe` = **5632 字节 = vmenu 代理** + `WeaselDeployer.real.exe` = 638976 字节。**装了自编的 server 后，托盘「输入法设置」入口回到原版**（fork 没有带托盘补丁，`WeaselTrayIcon::CustomizeMenu` 是空实现）——打字 `v` 开菜单不受影响（那是 Lua）。要两全就把托盘补丁合进 `weasel-grid-build` 再编一次 |
| 托盘入口的备份 | `C:\Program Files\Rime\weasel-0.17.4\WeaselServer.exe.vmenu-bak`（2243072 字节 = 原始 exe；md5 `FBE1F6CEF85B852E510DF7E53CFC7CC3`）；DLL 备份见 `GRID-CANDIDATE-DLL.md` §6 |
| ★★ 重启服务会被抢活动权 | 本机有腾讯**微信输入法（WeType）**。重启 `WeaselServer.exe` 后 Windows 有时把 zh-CN 交给 WeType：表现是**打拼音出拉丁字母、没有候选窗**。`nihao→你好` **区分不出来**（WeType 也打拼音）。**唯一可靠判定**：枚举目标程序已加载模块 —— `(Get-Process notepad).Modules | ? ModuleName -match 'weasel\|wetype'`，**只加载 `weasel.dll`** 才是小狼毫。恢复：停掉 `wetype*` 进程 → 重启 `ctfmon` → 重启 `WeaselServer` → **新开**记事本。TSF 是进程内 DLL，改完 DLL 也要重启应用 |
| 托盘入口脚本 | 仓库 `tools/vmenu-tray-setup.ps1`；本机部署副本 `D:\VibeCoding\输入法\vmenu-tray-setup.ps1`（它的 `-WrapperCs` 默认指向 `D:\VibeCoding\输入法\vmenu-deployer-wrapper.cs`，本机与仓库副本一致） |
| 开始菜单快捷方式 | `C:\ProgramData\Microsoft\Windows\Start Menu\Programs\小狼毫输入法\【小狼毫】输入法设置.lnk`（由「输入法设定」改名而来） |
| Rime 用户目录 | 注册表 `HKCU\Software\Rime\Weasel` 的 `RimeUserDir` → **`D:\rime-sandbox`**（这是当前生效目录） |
| Lua 镜像目录 | `%APPDATA%\Rime\lua\` —— **必须与 `<RimeUserDir>\lua\` 保持 MD5 一致**（历史遗留的双目录结构，两边都要放） |
| 方案 | `rime_ice`（雾凇拼音），编译产物 `D:\rime-sandbox\build\rime_ice.schema.yaml` |
| 候选框换行 / 序号 | 换行**不再由主题决定**：换行由自编 DLL 的 `HorizontalLayout.cpp` 按「每 9 个换行、≤9 个绝不换行」硬编码（用户要求「不许丢候选、必须一行」）。`style/layout/max_width` 现在只是兜底（`1100`），**别再花时间调它**。`style/label_format` = 留空（原值 `"%s"`），因为序号改由 DLL 的 `GetLabelText` 覆写直接写标签槽；写在 `weasel.custom.yaml` + `build/weasel.yaml`（`%APPDATA%\Rime\build\weasel.yaml` 是**不生效的旧副本**） |
| 一页候选数 | 方案键 `menu/page_size` = **36**（= 9 × 4；历史上是 9 → 18 → 36），写在 `rime_ice.custom.yaml` + `build/rime_ice.schema.yaml` |
| 候选方格（**已实测**） | 收起 = **1 行 9 个**（候选窗深色区高 **64px**，宽度随内容变长、不换行）；按 `↓` 展开 = 最多 36 个（4 行 × 9 列，`zhe'g` → 高 **274px**）；**`↓↓` 不收起**，而是高亮跳到第 2 行（实测差分 **5938** 点，x[90..212] y[197..327]）；展开态 `→` 在同一行内右移（11374 点，x[90..294]）；**第一行按 `↑` 才收起**（高回到 64px）。方向键移动选中项是**自编 DLL 的补丁**（`RimeWithWeasel.cpp` 里调 `highlight_candidate_on_current_page`，就是鼠标悬停选词那条通路），**不是** Lua（Lua 没有这个 API）。`vmenu_core.lua` 的 `GRID_COLS = 9` / `GRID_ROWS = 4` / option `vmenu_grid` 必须与之一致 |
| 候选序号 | 由自编 DLL 的 `HorizontalLayout::GetLabelText` 覆写写在**标签槽**（唯一在候选词**左**边的位置），按 `this->id / 9 == id / 9` 判断「本候选是否在高亮那一行」：是高亮行给 1-9，其余行给两个空格保证左边缘对齐。**「只有第一行有 1-9」就是「高亮在第一行」的特例**。旧做法（`menu_filter.number_row1` 往候选注释里塞数字）已删除——注释渲染在词**后面**（实测「这个1 这股2」），而且是翻译阶段生成的，移动高亮不会重跑过滤器，永远不可能「按高亮行重新编号」。`menu/alternative_select_labels` 对 Weasel **无效**，别再试 |
| `+` 号下翻（用户要求） | 收起态一行只有 9 个，按 `+` 把可见窗口后移 9 个（第 10-18 个候选），数字仍是 1-9；`GRID_PAGES = 4` 页，第 4 次按回到第 0 页。实测三页候选互不重复（这个/这股/遮盖… → 这关/遮光/这该… → 折股/这鬼/折桂…）。实现：rime 里 `KP_Add → send: plus`，**默认 `plus` 是标点会直接上屏**（实测 `zhe` 变「着+」），所以由 `menu_processor.lua` 拦下 → `vmenu_core.page_next()`（页码用 `vmenu_page_0..3` 四个布尔 option 存，因为 option 只能存布尔）→ `menu_filter.lua` 按页切片。**`+` 在 v 菜单剪贴板列表里不翻页**（翻译器忽略 `vclip` 后缀，Lua 的 `is_more_key` 只对已撤掉的 `vsetc*` 生效） |
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
| 11 | 方向键**只在普通打字时**由 Lua 接管（`core.grid_key`），**v 菜单内一律放行**；新增方向键分支前先想清楚是在哪种模式 | 候选方格需要 `↓` = 展开 / 跳下一行、`↑` = 第一行收起 / 跳上一行；v 菜单要保持原版手感。早期版本的教训是「无脑接管会破坏手感」，现在是**有条件的接管**。✅ 「用方向键移动选中项」现在**做得到**了 —— 但**不在 Lua 里**，而是自编 DLL 的补丁（见约束 22 与 `GRID-CANDIDATE-DLL.md` §2.3） |
| 12 | 改 `build/*.yaml`（`weasel.yaml` / `rime_ice.schema.yaml`）**只用 `[IO.File]::ReadAllText/WriteAllText` + UTF-8** | PS 5.1 的 `Get-Content`/`Set-Content` 按 ANSI 解码，写坏 YAML 后**候选窗口完全不显示** |
| 13 | 候选框宽度/一页上限**不要去 Lua 里找办法**（但「这一屏放几个」必须在 Lua 里限制） | 一页条数是 schema 的 `menu/page_size`，输入法内无法运行时切换；候选**个数**在 `menu_filter` 里截断。**换行**以前是主题 `style/layout/max_width` 的渲染行为（按宽度折行，凑不准 9 列），现在由**自编 DLL** 硬编码成「每 9 个换行、≤9 个绝不换行」（`GRID-CANDIDATE-DLL.md` §2.1），`max_width` 只是兜底 |
| 14 | **改 `WeaselServer.exe` 前必须先停掉 `WeaselServer` 进程**，且只做 **UTF-16 等长替换** | 运行中的 exe 文件被系统锁住，写不进去；等长替换（`定`→`置`，2 个字节）不动偏移量 / 长度，不会破坏文件结构 |
| 15 | 托盘菜单**不要试图新增菜单项或新命令号**，只做「改文字 + 用代理顶替 `WeaselDeployer.exe`」 | 菜单项写死在 `WeaselServer.exe` 的资源里，服务端只认 `WeaselDeployer.exe` 这一个入口（`CustomizeMenu` 是空实现，新命令号不会被处理） |
| 16 | 托盘相关的 `.ps1` 与**代理源码 `.cs`** 都必须 **UTF-8 带 BOM**；脚本里匹配中文用字符码拼（`[char]0x8F93…`） | 否则 PS 5.1 / csc 按 GBK 解析，中文提示变乱码，字面量也匹配不上 |
| 17 | 需要跨 `lua_processor` / `lua_filter` 共享的状态**只能放 context option**（如 `vmenu_grid`、`vraw_mode`），不要用模块级变量 | 两个组件**各自 `require` 一份** lua 模块，模块级变量不共享（展开状态曾因此读不到） |
| 18 | **绝不调用 `ctx.select`**（也别指望 `selected_candidate_index` 之类字段） | `ctx.select` 不是「移动高亮」，而是**「选中并上屏」**：0.2.3 用它做「往下跳一行」，结果展开后按 `↓` 直接把候选打了出去；而且日志 `ok=true err=nil`，**`pcall` 挡不住也不报错**（0.2.4 已删掉该调用） |
| 19 | 不要用 `menu/alternative_select_labels` 去改展开后的行序号 | 实测对 Weasel **完全无效**：写进 patch 会被整份拒绝（`page_size` 掉回 9、lua 挂载点消失），写进 `build` 产物像素分布逐段不变 —— 第 10 个之后的数字是面板按索引画的。**正确做法见 §4「改候选方格」的 1–3 步** |
| 20 | 快捷输入类功能**优先复用 rime-ice 自带的 recognizer + translator**（只填前缀），不要自己实现计算/日期/农历 | 自研等于重造轮子并丢边界处理；`ARCHITECTURE.md` §3.9 有完整前缀表 |
| 21 | 往 `build\*.yaml` 里插行时，缩进与相邻同级键**完全一致**（`menu:` 的子键 = **2 个空格**） | 缩进错一层 → `Error parsing YAML ... illegal map value`，schema 整个失效：**一个候选都不出、打字直接出字母**（已踩） |
| 22 | **本机 librime-lua 没有「移动高亮」的 API** —— 探针实测：`ctx.select_candidate` / `ctx.set_selected_candidate_index` / `ctx.highlight` / `ctx.move_selection` / `ctx.menu` / `ctx.get_menu` / `ctx.selected_candidate_index` / `menu.*` / `composition.select` **全是 `nil`** | 所以**别在 Lua 里**试「用方向键移动选中项」。✅ 这件事已经用**自编 DLL** 做到了：`RimeWithWeasel.cpp` 的 `ProcessKeyEvent` 里在 `vmenu_grid` 打开时调 `HighlightCandidateOnCurrentPage()`（鼠标悬停选词的服务端通路），`↓`=+9 / `↑`=-9 / `←`=-1 / `→`=+1，越界不吞键、落回原生。见 `GRID-CANDIDATE-DLL.md` §2.3。探针脚本见 `TESTING.md` §8.3 |
| 23 | 换了 `weasel.dll` / `weaselx64.dll` / `WeaselServer.exe` 之后，**别只看安装目录** | 见 §1「部署必须换 5 个文件」：TSF 客户端 DLL 在 `System32` / `SysWOW64`；只换安装目录时，行为**一点变化都没有**，会误判成「补丁没生效」 |
| 24 | 改了 `weasel.dll` 之后**必须重启目标应用**（记事本等） | TSF 是**进程内** DLL，老进程里还是旧代码；只有 `WeaselServer.exe` 需要重启服务 |
| 25 | 「按键下翻候选」不要用 `shift+equals` 去模拟 `+` | 合成的 Shift 会触发 rime 的 `Shift_L: commit_code`，把编码**直接上屏**（看起来像「按 + 把列表关了」）。要发**小键盘加号** `VK_ADD (0x6B)`，rime 里它是 `KP_Add → send: plus`，正是 `is_more_key` 认的键 |
| 26 | **`ctx:set_option` 必须先读再写：值没变就一个 option 都别写** | context option 一变，rime 就判定候选表失效、**重新翻译整份候选**。本项目曾因此在**每个按键**上写 4–6 个 option（`page_reset` 循环写 `vmenu_page_0..3`、`grid_set` 写 `vmenu_grid`、`set_raw` 写 `vraw_mode`），实测**一次按键 2ms 内连刷约 30 条** `updated option`、日志 410/571 行是它 → 用户直接反馈「打字卡顿」。改完 410 → **2** 行（`PROGRESS.md` §1.17、`GRID-CANDIDATE-DLL.md` §5.4） |
| 27 | 带中文的 `.ps1` 要存成 **UTF-8 带 BOM**（或干脆全 ASCII） | `powershell -File`（5.1）按 ANSI 解析无 BOM 的 UTF-8 → 中文字节把引号吃掉，报 `Unexpected token '}'` / `The string is missing the terminator`。`tools/verify-grid.ps1` 就踩过（`pwsh` 7 下正常，所以容易漏） |
| 28 | PowerShell 函数里 **`return $array` 会被展平** | `tools/verify-grid.ps1` 曾返回「深底横带数组」，调用方拿到的是散开的整数 → 算出的高度**恒为 0**、四条几何断言误报 FAIL。返回 hashtable（或 `,$array`）才安全 |
| 29 | **验收候选窗必须在「会自己画候选」的程序里也测一遍** —— 记事本一类程序不支持「集成候选列表」，走的路径和其它程序**完全不同** | 小狼毫 WeaselTSF/CandidateList.cpp 把 ITfIntegratableCandidateListUIElement 暴露给应用后，Chrome / Edge / 微信 / Office / UWP 会**自己画候选**（只拿到 GetString() 的候选文本 → **没有标签槽序号、没有 9×4 方格**），只有记事本这类程序才 _pbShow = TRUE 退回我们的窗。症状是「只有记事本有数字」；修法见 GRID-CANDIDATE-DLL.md §2.4。**只在新开记事本里验收会 100% 漏掉这个 bug** |
| 30 | 改了 weasel.dll / weaselx64.dll 之后，**所有客户端程序都要重启**才会加载新代码 | TSF 是**进程内** DLL：WeaselServer.exe 只管服务端 UI（网格/序号/方向键），客户端 DLL 管按键与「要不要让应用自己画候选」。用户说「只有记事本有数字」时，第一件事就是让他在目标程序里**重开窗口**再试 |
| 31 | 本机**没有 ATL**（tlmfc/tlbase.h 不存在，swhere -requires VC.ATL 为空）→ WeaselTSF **本地编不出来** | 本地从零编还要先编 Boost（约 40 分钟）+ librime，**且仍会卡在 ATL**。要出 DLL 只能走 CI（需要 push），或对已部署 DLL 做等效的**二进制常量补丁**（改 __uuidof 那个 16 字节 IID 的最后一字节 → IsEqualIID 永不匹配；先确认该常量在目标 DLL 里只出现 1 次、且 server 里 0 次） |

---

## 3. 目录与「改哪里」

```
src/lua/           → 复制到 <RimeUserDir>\lua\ 和 %APPDATA%\Rime\lua\
  vmenu_core.lua      共享核心：路径、设置读写、剪贴板/常用语读写、命中判断、原符号标记，
                      以及候选方格状态（GRID_COLS=9 / GRID_ROWS=4 / option vmenu_grid /
                      grid_limit / grid_key；状态必须走 option，模块级变量在 filter 里读不到）
                      ⚠️ grid_key 只做「展开 / 收起」，**绝不调用 ctx.select**（那是上屏）
  menu_processor.lua  ★ 按键总管（必须排在 speller/selector 之前）：v 菜单（1-5）、vqi 子模式、
                        数字编码、回车调用；非 v 模式的方向键先交给 core.grid_key
                        （v 菜单内不接管；原来的主菜单第 5 项「文字设置」仍是保留代码）
  lua_menu.lua        ★ translator：产出所有菜单/列表候选（文案都在这里，要改文案就改它）
                        yield_menu yield 5 项（设置/剪贴板/快捷输入/常用语/原符号）；
                        yield_quick yield 9 项 + 返回（快捷输入的文案与顺序）
  menu_filter.lua     ★ filter：v 模式只留需要的候选；普通打字时把常用语插到第 2 位，
                        按 core.grid_limit(ctx) 截断候选个数（收起 9 / 展开 36），
                        并按 core.page_get(ctx) 做「+ 下翻」的切片
                        （⚠️ 序号**不再**写注释，改由自编 DLL 的标签槽实现，见 §4）

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

### 改候选方格（默认单行 9 个 / 按 `↓` 展开 4 行 × 9 列 / 序号在词前 / 方向键移动 / `+` 下翻）

> ⚠️ **换行规则、序号位置、方向键行为都在「自己编译的 Weasel」里**
> （`WeaselUI/HorizontalLayout.cpp` 与 `RimeWithWeasel/RimeWithWeasel.cpp` 三个补丁），
> **不在 Lua、也不在 YAML**。改这几项 = 改源码 → 推 `weasel-grid-build` → 等 CI（约 50 分钟）
> → `tools/deploy-grid-dlls.ps1` 换 **5 个文件**。完整配方见
> [`GRID-CANDIDATE-DLL.md`](GRID-CANDIDATE-DLL.md)（§2 补丁 / §4 编译部署 / §5 验收）。

还在 Lua / YAML 里的只有这几项：

* `menu/page_size`（**36** = 9 × 4）：一页候选上限，写在 `rime_ice.custom.yaml` + `build/rime_ice.schema.yaml`；
* `style/label_format` 留空（`" "`）：关掉 Weasel **原生**序号列（序号改由 DLL 的标签槽画，见 §1）；
* `src/lua/menu_filter.lua`：`core.grid_limit(ctx)` 决定「这一屏放几个」（9 / 36），
  `core.page_get(ctx)` 决定 `+` 下翻取哪 9 个；
* `src/lua/vmenu_core.lua`：`GRID_COLS = 9` / `GRID_ROWS = 4` / `GRID_PAGES = 4`，改了要跟上面同步。

**必须用 UTF-8 读写**，绝不能用 `Get-Content`/`Set-Content`（会把 YAML 写坏，
后果是候选窗口完全不显示）：

```powershell
function Set-YamlValue($p, $pattern, $value) {
  $t = [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8)
  $t = [regex]::Replace($t, $pattern, $value)
  [IO.File]::WriteAllText($p, $t, (New-Object Text.UTF8Encoding($false)))   # false = 无 BOM
}
# 一页上限（= 列数 × 行数；现在 36 = 9 列 × 4 行）
Set-YamlValue 'D:\rime-sandbox\build\rime_ice.schema.yaml' '(?m)^(\s*page_size:)\s*\d+' '$1 36'
# 原生序号列留空（关掉 Weasel 画的 1、2、3…；序号改由 DLL 的标签槽提供）
Set-YamlValue 'D:\rime-sandbox\build\weasel.yaml' '(?m)^(\s*label_format:).*$' '$1 ""'
# custom.yaml 里的 patch 也要同步；改了 lua 就把文件同步到两个 lua 目录（MD5 必须一致），再重启服务：
Get-Process WeaselServer -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Process 'C:\Program Files\Rime\weasel-0.17.4\WeaselServer.exe'
# 看日志确认没有 Error parsing
# ⚠️ 重启后确认没被微信输入法抢走活动权（见 §1 那条）——不然会误判成「改动没生效」
```

> `style/layout/max_width`（现在 `1100`）**已经不管换行**了：换行由 DLL 按「候选 > 9 时每 9 个」
> 硬编码，`max_width` 只是兜底。别再调它。

**改序号的完整顺序**（序号 = 「高亮那一行的 1–9，画在词前面」）：

1. 改**源码**：`WeaselUI/HorizontalLayout.cpp` 的 `GetLabelText` 覆写（§2.2），
   同步改 `.h` 里的声明；
2. 推到 `weasel-grid-build` → 等 CI → 下载 `weasel-grid-dlls.zip`；
3. `tools/deploy-grid-dlls.ps1`（**5 个文件**：安装目录三件套 + `System32` / `SysWOW64` 的 `weasel.dll`）
   → 重启 `WeaselServer` → **重启记事本**（TSF 是进程内 DLL）；
4. 确认活动输入法没被微信输入法抢走（§1），再验证。

验证（2026-09-18 实测）：**收起 64px（一行）**、`↓` 展开 **204px**（`zhe` 3 行 × 9 列）、
`↓↓` 高亮跳到第 2 行（差分 **12767** 点）、`→` 行内右移（**11374** 点）、第 1 行 `↑` 回到 **64px**、
`+` 下翻 4 页循环（第 4 次与第 0 页只差 **14** 点）。
**判定要用逐像素差分**（高亮底色是深棕 `0x594231`，亮度 / 亮像素数指标**看不出来**）；
一键脚本 `tools/verify-grid.ps1`，语义部分（数字在词前、按高亮行编号）用裁图 + `vision.js` 读字复核。

> ⚠️ **Lua 里没有「移动高亮」的 API**（`ctx.select_candidate` / `set_selected_candidate_index` /
> `highlight` / `move_selection` / `get_menu` / `selected_candidate_index` 全是 `nil`），
> 而 `ctx.select` 是**上屏**。方向键移动选中项**已经由自编 DLL 实现**（`GRID-CANDIDATE-DLL.md` §2.3），
> **别再试图在 Lua 里做**——只会把候选打出去。探针脚本见 `TESTING.md` §8.3。

> ⚠️ **不要**用 `menu/alternative_select_labels` 去改展开后的行序号 —— 实测对 Weasel **完全无效**：
> 写进 `rime_ice.custom.yaml` 的 patch 会被**整份拒绝**（`page_size` 掉回 9、lua 挂载点消失），
> 写进 `build` 产物 YAML 能过但序号列像素分布逐段不变（第 10 个之后的数字是面板按索引画的）。
> 正确做法见上面 1–4 步（DLL 的标签槽）。`build\rime_ice.schema.yaml` 里那行 36 项的
> `alternative_select_labels` 还留着，对显示没有影响。
>
> ⚠️ 直接在 `build\rime_ice.schema.yaml` 里插行时，**缩进必须与被插入的键同级**
> （这个文件里是 **2 个空格**）；写成 4 个空格会报
> `config_data.cc:78 Error parsing YAML ... illegal map value`，**schema 整个失效：
> 一个候选都不出、打字直接出字母**。改完必看 `%TEMP%\rime.weasel\*.log`。

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
| 按 `↓` / `↑` / `←` / `→` 行为不对 | 普通打字走 `core.grid_key`：`↓` = 收起时展开 / 已展开时**收回**（**0.2.4 起不再上屏**）、`↑` = 收回、`←`/`→` 放行给原生导航器；**v 菜单内方向键必须放行**。若在 v 菜单里乱跳，说明 `grid_key` 被套到了菜单模式上（`cur ~= "" and not core.mode_of(cur)` 这个条件被改坏了） |
| 展开后按 `↓` 把候选打出去了 | **0.2.3 的 bug，0.2.4 已修**：老代码用 `ctx:select(sel + 9)` 跳行，而 `ctx.select` 是**上屏**。检查两处 lua 的 `vmenu_core.lua` 是否 MD5 一致且重启过；搜文件里还有没有 `ctx:select` 的**调用**（注释提到它属正常）。不要再写回这套「跳行」逻辑 |
| 选了方向键却不动选中项 | **先确认跑的是自编的 `WeaselServer.exe`**（原版没有这个补丁）：`WeaselServer.exe` 字节数应为 2756096、md5 `FFA4285B058E81BDA32EC55F45A2D4DD`，`weasel.dll`/`weaselx64.dll` 应为 `60B0F018D85B7DE1322A332E31657D11` / `0B1307495A5766094CA6636242748677`（含集成 IID 的那一字节改动）；再确认 `System32`/`SysWOW64` 的 `weasel.dll` 也换过、测试程序重启过。都对了还不动 → 查 `vmenu_grid` option 是否置位（v 菜单里方向键本来就不接管） |
| 展开后第 2–4 行也有序号 | 说明跑的还是**原版 server**（序号机制现在是 DLL 的 `GetLabelText` 覆写）；另外确认主题 `style/label_format` 是留空。**不要**用 `alternative_select_labels`（对 Weasel 无效） |
| **改完 `build` 产物后打字直接出字母、一个候选都没有** | 插进去那行的缩进错了（`menu:` 的子键必须 2 个空格）→ 日志 `config_data.cc:78 Error parsing YAML ... illegal map value`，schema 整个失效；改回缩进再重启 |
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
- [ ] 改了候选框键（`page_size` / `label_format`）的话：`custom.yaml` 与 `build/*.yaml` 都改了、用 UTF-8 读写、日志没有 `Error parsing`、截图确认（收起约 64px 一行 / 展开按候选数 1–4 行）
- [ ] 改了**源码补丁**的话：`weasel-grid-build` 推成功、CI 出了 `weasel-grid-dlls.zip`、**5 个文件**都换了、服务和测试程序都重启过、活动输入法没被微信输入法抢走（跑 `tools/verify-grid.ps1`）
- [ ] 方向键 / `+` 仍是「`↓` 收起时展开、已展开时跳下一行；`←`/`→` 行内移动；第一行 `↑` 收回；`+` 下翻 4 页循环；**全程不上屏**」
- [ ] 序号仍是「**高亮那一行的 1–9、画在候选词前面**」（自编 DLL 的标签槽；裁图 + `vision.js` 读字复核）
- [ ] 改了快捷输入（`lua_menu.lua` / `menu_processor.lua` / `vmenu_core.lua`）的话：两个 lua 目录 MD5 一致、重启服务、每一项都真按键验一次上屏（`TESTING.md` §8.2 的表格）
- [ ] 没有用 `menu/alternative_select_labels` 去改行序号（实测对 Weasel 无效，还会让 patch 被整份拒绝）
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
  现在改成 **`530` + `36` + `grid_key` 接管**（默认收起 9 个、按 `↓` 展开 4 行 × 9 列，见第五 / 第六轮）。
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

### 已完成并验收（2026-09-13 第五轮 · 候选方格 + 部件拆字 + 序号）

* **候选窗口默认收起 9 个，按 `↓` 展开 4 行 × 9 列**：主题 `max_width = 530` +
  方案 `menu/page_size = 36`；`vmenu_core.lua` 的 `grid_limit` / `grid_key` 负责展开状态。
  （→ **0.2.5 起换行改由自编 DLL 按「每 9 个」硬编码，`max_width` 不再是关键值**；`page_size` 仍是 36。）
* **部件拆字前缀 `uU` → `u`**（两行配置，**没有新造功能**）：`unvzi`→好、`uriyue`→明；
  `v`→`5` 子菜单同步加了第 9 项「部件拆字」。**旧的 `uU` 写法失效**。
* **序号只留第一行（原「未解决」项，本轮已做完）**：主题 `style/label_format` 留空关掉原生序号，
  `menu_filter.number_row1` 给前 9 个候选的注释写 `1`–`9`，v 菜单也逐条写序号注释；
  截候选窗口图后读图确认**第一行有 1–9、第 2/3/4 行没有**，且注释不影响上屏
  （`shi`+空格 → 是、`shi`+`3` → 师）。
  证据图在本地 `D:\VibeCoding\输入法\shots\show-*.png`（**不入库**）。
  副作用：收起时 9 个候选被序号撑宽 → 排成 **2 行**（窗口高 74 → 145），第 2 行那两个也带数字。
  同轮踩坑：往 `build\rime_ice.schema.yaml` 插行时缩进写成 4 个空格（应为 2 个）→
  `Error parsing YAML ... illegal map value`、schema 失效、打字直接出字母。
* ~~待复测：`↓↓` 与 `↓`+`→`×9 选中同一个候选。~~ **✅ 第六轮复测：这条旧结论是误判**
  （当时第二次 `↓` 会直接把候选上屏，两次「比较」比的是被意外上屏的那个字）。
* 遗留小瑕疵：v 菜单「快捷输入」里的「返回」显示 `10`（按键是 `q`），只影响观感
  （`PROGRESS.md` §5 第 13 条）。

### 已完成并验收（2026-09-13 第六轮 · 修「展开后按 `↓` 会上屏」，0.2.4 / 提交 `13c572c`）

* **现象**：0.2.3 里 `shi` → `↓` 展开 → **再按 `↓`** → 候选窗口消失并**上屏当前候选**
  （3/3 复现，三次分别上屏「实」「💩」「使」——顺序不同是因为雾凇拼音的用户词库会学习）。
* **根因**：`grid_key` 用 `ctx:select(sel + 9)` 想「往下跳一行」，而 **`ctx.select` 是「选中并上屏」
  不是「移动高亮」**。日志 `ok=true err=nil` —— 没有异常，所以 `pcall` 挡不住、还被误判成「静默失败」。
* **探针（怎么得出上面的结论）**：在方向键分支里 `io.open` 写日志并打印 `type(ctx.xxx)`：
  `ctx.select` = function（= 上屏）；`ctx.select_candidate` / `set_selected_candidate_index` /
  `highlight` / `move_selection` / `menu` / `get_menu` / `selected_candidate_index` / `menu.*` /
  `composition.select` **全部 `nil`**。脚本见 `TESTING.md` §8.3。
* **修法**：`vmenu_core.grid_key` 重写 —— **彻底不再调用 `ctx.select`**：
  `↓` 收起时展开 / 已展开时**收回**；`↑` 收回；`←` / `→` 放行给原生导航器。
* **实测**：窗口高 **144 → 287 → 144 → 287 → 144**，**标题全程 `*shi`，没有任何候选被上屏** ✅。
  对照基准：数字键 `1` → 是、`2` → 师 ✅（证明候选顺序本身没问题）。
* **顺带更正的错误文档**：旧文档的「`ctx.selected_candidate_index` 1 基 / `ctx:select(i)` 0 基换算」
  是**错的**（该字段不存在，读到 `nil` 当 0 用）；已在 `CHANGELOG` / `ARCHITECTURE` / `TESTING` /
  `TROUBLESHOOTING` / `PROGRESS` / 本文件 + README + 使用说明里改掉。
* **仍未达成**：**方向键不能移动选中项**（`→` ×1 或 ×3 再空格仍上屏第 1 个）——
  没有 API，不是没写；不改小狼毫 C++ 源码做不到（`PROGRESS.md` §5 第 14 条，等用户拍板）。
  → **✅ 0.2.5（2026-09-18）已达成**：用户放开限制、用 CI 编了带补丁的 `WeaselServer.exe`，
  `↓`/`↑`/`←`/`→` 现在真的能移动高亮且不上屏（`GRID-CANDIDATE-DLL.md` §2.3）。
* 遗留死代码：`vmenu_core.lua` 的 `grid_sel()` 已无人调用（可删），它注释里还留着那条错误的「1 基 / 0 基」。
  → **✅ 0.2.5 已删除**。

### 下一步（按价值排序）

1. **决定「方向键移动选中项」怎么办**（`PROGRESS.md` §5 第 14 条）：接受现状（数字键选词）／
   放宽需求／改小狼毫 C++ 源码。**正在等用户拍板**，这是当前最大的未决项。
2. **确认开放问题 1**（「最右边的回车键也要还原」的确切含义，见 `PROGRESS.md` §5）——
   到现在**仍未确认**；如果是别的意思，改 `menu_processor.lua` 的 `Return` 分支即可。
3. **`vset*` 死代码怎么处理待定**：菜单第 5 项现在被快捷输入占用，它依然不可达
   （只有手打 `vset` 进得去）。删掉能省一大段文案与分支；留着保留「窗口挂了也能改设置」的兜底。
   需要人类拍板。
4. **v 菜单里「返回」被编成 `10` 的小瑕疵要不要顺手改**（`PROGRESS.md` §5 第 13 条）：
   在 `menu_filter.lua` 的 v 菜单编号循环里跳过 `vact` 类候选即可，改动很小。
5. **「快捷输入」是否做进设置窗口可配置**（顺序 / 显示哪几项），以及是否再加更多项
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
