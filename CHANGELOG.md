# 变更记录（CHANGELOG）

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。
本项目在真机（Windows 11 + Weasel 0.17.4 + librime 1.13.1 + rime-ice）上验证。

## [0.2.1] — 2026-09-13

托盘图标右键菜单第一项变成 **「输入法设置 (S)」**，点它打开 vmenu 可视化设置窗口；
小狼毫自带的设置对话框改从设置窗口里的「小狼毫原生设置」分组打开。

### 新增 · 托盘菜单「输入法设置」

* 托盘右键菜单第一项：`输入法设定 (S)` → **`输入法设置 (S)`**，点击打开 vmenu 可视化设置窗口
  （就是输入法里按 `v` → `1` 打开的那个 WinForms 窗口）。

**机制（源码核对结论）**：托盘右键菜单是 **`WeaselServer.exe` 里的菜单资源** `IDR_MENU_POPUP`
（资源号 105），菜单项的**文字与命令号写死在资源里**，**没有任何配置文件能新增菜单项**
（`weasel.yaml` / `weasel.custom.yaml` 只能改候选窗口样式，改不了托盘菜单）。
服务端对这些命令号的处理只有一件事（源码 `WeaselServer/WeaselServerApp.cpp` 的
`SetupMenuHandlers()`）：**启动安装目录下的 `WeaselDeployer.exe` 并带参数**：

| 命令号（`include/resource.h`） | 服务端执行 |
| --- | --- |
| `ID_WEASELTRAY_SETTINGS` = 40008 | `WeaselDeployer.exe`（**无参数**） |
| `ID_WEASELTRAY_DEPLOY` = 40002 | `WeaselDeployer.exe /deploy` |
| `ID_WEASELTRAY_DICT_MANAGEMENT` = 40010 | `WeaselDeployer.exe /dict` |
| `ID_WEASELTRAY_SYNC` = 40012 | `WeaselDeployer.exe /sync` |

其余项是打开网址 / 打开文件夹 / 检查更新 / 退出。

所以本项目做**两件可逆的事**：

1. **就地改菜单文字**：`WeaselServer.exe` 里的 `输入法设定 (&S)` → `输入法设置 (&S)`。
   这是 **UTF-16 等长替换，只改最后 1 个汉字**（`定`(U+5B9A) → `置`(U+7F6E)，2 个字节），
   字节偏移 `0x220E40`，**不动任何偏移量 / 长度**；脚本改前确认命中 1 处，
   改完回读校验「旧标签 0 处 / 新标签 1 处」。该 exe **没有数字签名**（`NotSigned`，
   同目录 `WeaselDeployer.exe` 也未签名），所以改它不会破坏签名。
2. **安装部署器代理**：把真正的 `WeaselDeployer.exe` 改名为 `WeaselDeployer.real.exe`，
   用 `src/windows/vmenu-deployer-wrapper.cs` 编译出的小代理顶替它
   （`csc.exe /target:winexe /r:System.Windows.Forms.dll`，安装脚本自动编译）：
   不带参数 → 打开 vmenu 设置窗口（`powershell -File vmenu-settings-gui.ps1 -ShowNow`；
   窗口脚本自己有单实例互斥体，已在跑就写 `open-settings.flag` 让常驻实例亮出来）；
   带参数 → 原样转发给 `WeaselDeployer.real.exe`，**重新部署 / 用户词典管理 /
   用户资料同步三个功能完全不受影响**。

* 脚本 `tools/vmenu-tray-setup.ps1`（安装，幂等；`-Revert` 撤销）；
  备份 `C:\Program Files\Rime\weasel-0.17.4\WeaselServer.exe.vmenu-bak` 只在第一次安装时生成。

### 新增 · 设置窗口里的「小狼毫原生设置」分组

* 设置窗口「设置与缓存」页底部新增分组 **`小狼毫原生设置`** 与按钮 **`打开小狼毫原生设置`**，
  用来打开小狼毫自带的设置对话框（标题 `【小狼毫】方案选单设定`，配色 / 字体等）。
* 因为托盘那一项现在被 vmenu 占用了，原生对话框的入口改到这里
  （也可以直接运行 `WeaselDeployer.real.exe`）。
* 实测截图：`screenshots/gui-05-native-settings.png`。

### 变更 · 开始菜单快捷方式改名

* `【小狼毫】输入法设定.lnk` → **`【小狼毫】输入法设置.lnk`**。它指向的也是
  `WeaselDeployer.exe`，所以现在同样打开 vmenu 设置窗口。

### 修复 / 踩坑（详见 `docs/TROUBLESHOOTING.md`）

* **托盘菜单不能靠配置文件新增项**：菜单项写死在 `WeaselServer.exe` 的资源里；
  `WeaselTrayIcon` 里那个 `void CustomizeMenu(HMENU) {}` 是**空实现**，没有可用的配置钩子；
  新增一个「**全新命令号**」的菜单项服务端不会处理（点了没反应）。所以只能「改名 + 改行为」。
* **改 `WeaselServer.exe` 前必须先停掉 `WeaselServer` 进程**：正在运行的 exe 文件被系统锁住，
  写不进去；脚本会自动停 / 起。
* **必须是等长替换**：`定` → `置` 都是 1 个 UTF-16 码元，字节偏移与长度都不变，
  不会破坏文件里任何偏移量。
* **脚本文件本身必须 UTF-8 带 BOM**（`.ps1` 与 `.cs` 都是）：否则 PowerShell 5.1 / csc 会按
  GBK 解析，中文提示变乱码（脚本里匹配用的「输入法设定」是用字符码 `[char]0x8F93…` 拼出来的，
  不受文件编码影响）。

### 已知限制（本节新增）

* 托盘那一项是**改名 + 改行为**，不是新增第 13 项：原生设置对话框的直接入口从托盘挪到了
  vmenu 设置窗口里（服务端只认 `WeaselDeployer.exe` 这一个入口，无法凭空加一个全新命令号）。
* 小狼毫**升级 / 修复安装**会覆盖 `WeaselServer.exe` 与 `WeaselDeployer.exe`，托盘项会退回原样
  （`输入法设置` 变回 `输入法设定` 且指向原生对话框）；重新跑一次 `tools/vmenu-tray-setup.ps1`
  即可（幂等：备份已存在就沿用，菜单文字已是新标签就跳过，代理每次重新编译覆盖安装）。
  注意：脚本只在**没有** `WeaselDeployer.real.exe` 时才做改名，升级后重跑时它通常还在，
  于是本次的 `WeaselDeployer.exe` 会被代理**直接覆盖**，`.real.exe` 可能仍是升级前的旧版。
* `weasel.dll` / `weaselx64.dll` 里也有同样的菜单文字（那是输入法**语言栏**那条右键菜单用的），
  **本次没有改**：它们是注入到所有进程里的 IME 模块，改了要重启所有程序才生效，风险不值得。

## [0.2.0] — 2026-09-13

菜单瘦身、术语改名、**多行候选框**、设置窗口**双击编辑**，以及配套的验证工具与踩坑记录。

### 变更 · 主菜单去掉第 5 项

* `v` 菜单现在只有 **4 项**：`1 设置（图形窗口）` / `2 剪贴板（历史）` / `3 常用语（快捷内容）` /
  `4 原符号（原版 v）`。
* 原来的第 5 项「文字设置」（`vset`）已从菜单删除。`vset` / `vsetc` / `vsetf` / `vsetn` / `vsetx`
  的 Lua 代码**保留但不可再从菜单进入**（只有手打 `vset` 才进得去）。
* 改动位置：`src/lua/menu_processor.lua` 的主菜单分支（只处理 `1`–`4`，其余放行）、
  `src/lua/lua_menu.lua` 的 `yield_menu`（只 yield 4 项）。

### 变更 · 「收藏」→「常用语」（只改用户可见文本）

* `v` 菜单第 3 项文本 `常用语`、注释 `快捷内容`；
* `v`→`3` 列表的标题 / 空态 / 搜索提示改为「常用语 …」「还没有常用语」「没有匹配的常用语：」；
* 正常打字时**候选第 2 位的注释**从 `收藏` 改为 `常用语`
  （`src/lua/menu_filter.lua` 的 `Candidate("vfav", 0, #code, fav.word, "常用语")`）；
* 设置窗口标签页 `收藏内容` → `常用语`，以及窗口内所有按钮 / 提示 / 确认框文本
  （`src/windows/vmenu-settings-gui.ps1`）。
* **未改（刻意保留）**：内部命名与文件格式 —— `favorites.dict.yaml`、候选 `type` 前缀 `vfav`、
  `vset*` 模式、`vmenu-settings.txt` 全部沿用旧名，避免破坏已有数据与配置。

### 新增 · 多行候选框

* 候选窗口换行由 Weasel 主题键 **`style/layout/max_width`** 控制：`0` = 不换行（原行为），
  实测 `300` 时 9 个候选会排成每行约 5 个的多行网格；`620` 实测**不换行**（自然宽度还没超）。
* 一页候选数由方案键 **`menu/page_size`** 控制：原来 `9`，现在改为 **`18`**，
  于是候选框最多约 **4 行 × 5 列**。
* 落地两处（`build/*.yaml` 是实际生效的编译产物，必须一起改）：
  * `weasel.custom.yaml` 加 `patch: "style/layout/max_width": 300`，
    并把 `build/weasel.yaml` 的 `max_width` 改成 `300`（同时镜像到 `%APPDATA%\Rime\build\weasel.yaml`）；
  * `rime_ice.custom.yaml` 加 `patch: menu/page_size: 18`，
    并把 `build/rime_ice.schema.yaml` 的 `page_size` 改成 `18`。
* 回退：`max_width` 改回 `0`、`page_size` 改回 `9`，重启 `WeaselServer`。
* **方向键一律不拦截**：`↓`/`↑`/`←`/`→` 全部交回 librime 原版 `navigator`。
  实测（librime 1.13.1，横向候选框）：`↓` = 选中下一个候选，`→` = 选中下一个候选，
  `↑` = 上一个，都不上屏 —— 用户要求的「保留按向右选候选」因此天然满足。
* 实测截图：`screenshots/ime-06-multirow-candidates.png`（9→18 条、每行约 5 个；
  按 `↓` 后高亮位置在同一行内移动，窗口内 y 197..257）。

### 新增 · 设置窗口双击编辑

* 剪贴板页：双击某一行 → 弹出标题为 `编辑第 N 条` 的编辑框（单行文本框，打开时**全选原文**），
  确定后写回 `clipboard-cache.txt`（`Save-Clipboard` + `Refresh-Clipboard`），
  状态栏显示「已修改第 N 条」；取消 / `Esc` 不改动。
* 常用语页：双击某一行 → 复用原有的 `修改常用语` 弹框（等价于点「修改选中」）。
* 两个列表的侧边提示文字都补了「双击某一条可以直接编辑 / 修改」。
* 端到端已验证：双击第 1 行 → 弹出「编辑第 1 条」→ 输入 `test` + 回车 →
  `clipboard-cache.txt` 第 1 行确实变成 `test`（随后已还原真实数据并校验 sha256 一致）。

### 新增 · 测试工具 `tools/gui-dblclick-test.ps1`

* 用「截图找行 + 真实鼠标双击」验证上面的双击编辑：UIA 看不到这个 WinForms 窗口的子控件，
  只能走这条路（详见 `docs/TESTING.md`）。
* 参数：`-Match`（窗口标题子串，默认 `小狼毫 v 功能`）、`-Row`、
  `-ListTop` / `-ListLeft` / `-ListRight` / `-ListBottom`（列表区域，默认 `ListTop=200`）、
  `-PreX` / `-PreY`（先点一下，例如切标签页）、`-Expect`（弹框标题前缀，默认 `编辑第`）、
  `-TypeInto`（往弹框输入 ASCII 并回车）、`-Out`（保存截图）、`-DryRun`。退出码 0 / 1 / 2。
* 实测几何（150% 缩放、窗口 1464×989、窗口左上角在屏幕 549,189）：表头 y≈176..206，
  数据行高 30 px，第 1 行中心 y≈210、第 2 行 ≈240、第 3 行 ≈270。

### 修复 / 踩坑（详见 `docs/TROUBLESHOOTING.md`）

* **改 `build/weasel.yaml` 不能用 `Get-Content` / `Set-Content`**：PS 5.1 默认按 ANSI/GBK 解码，
  会把 UTF-8 中文读成乱码再写回，YAML 结构损坏。现象是 `WeaselServer` 日志出现
  `Error parsing YAML "…build\weasel.yaml" : yaml-cpp: error at line 356, column 12: end of map not found`，
  **候选窗口完全不显示**（打字时按键被吞、看不到任何候选）。必须用
  `[IO.File]::ReadAllText($p,[Text.Encoding]::UTF8)` + `[IO.File]::WriteAllText(...)`，
  改完再看日志确认没有 `Error parsing`。
* **编辑工具会吃掉 `.ps1` 的 UTF-8 BOM**：PS 5.1 对无 BOM 的 UTF-8 脚本按 ANSI 解析，
  中文变乱码，甚至因「多字节字符吃掉后面的引号」直接语法错误。判别：
  `[IO.File]::ReadAllBytes($p)[0..2]` 必须是 `239,187,191`；改完用
  `[System.Management.Automation.Language.Parser]::ParseFile()` 做语法检查。
* 记入踩坑的还有：UIA 看不到 WinForms 子控件；测试进程不 `SetProcessDPIAware()` 时
  坐标被按 1.5 倍缩放（点错行）；模态弹框不出现在 `Process.MainWindowTitle` 里（要用
  `EnumWindows` + `GetWindowTextW`）；按命令行匹配杀进程会连自己一起杀掉；
  改 Lua 后必须重启 `WeaselServer` 且两个 lua 目录要 MD5 一致。

### 已知限制（本节新增）

* 多行候选框**不能运行时切换**，只能改主题 + 方案两个键并重启服务。
* `vset*` 已成死代码（保留但菜单不可达），是否删除待定（见 `docs/PROGRESS.md`）。

## [0.1.0] — 2026-09-13

首次整理成仓库。以下是**已经实现并在真机上验证过**的能力。

### 新增 · v 功能菜单

* 按 `v` 打开功能菜单：`1 设置 / 2 剪贴板 / 3 收藏 / 4 原符号 / 5 文字设置`
  （`lua_processor@*menu_processor` + `lua_translator@*lua_menu` + `lua_filter@*menu_filter`）。
* 候选文案精简：主菜单 5 个短词，子菜单同样压缩（用户明确要求「说明精简一点」）。
* `v`→`4` 还原原版 `v` 符号输入（`v` 后接 `2` → 二 贰 ² ₂ Ⅱ …）。
* 英文 / ASCII 模式下 v 功能整体关闭。

### 新增 · 剪贴板历史

* 后台进程 `clipboard-sync.ps1` 每 1 秒把系统剪贴板同步到 `clipboard-cache.txt`
  （去重、最新在前、上限 50、多行压平成一行）。
* 输入法内 `v`→`2` 快查：`m`/`+` 每次多看 10 条、`-`/`=` 翻页、`d` 删除模式、`x` 清空（二次确认）、`q` 返回。
* 设置窗口里可复制 / 删除 / 清空 / 重新载入 / 置顶
  （0.1.0 时「双击条目即复制」；0.2.0 起双击改为**编辑**，复制请用「复制到剪贴板」按钮）。

### 新增 · 收藏

* 收藏存 `cn_dicts/favorites.dict.yaml`（`内容<Tab>编码<Tab>词频`），输入法与设置窗口读写同一文件。
* **打字预览**：输入编码**前 3 位**时，收藏内容出现在**候选第 2 位**（`fav_hit` + `menu_filter`）。
  插位后整表 `quality` 重排为严格递减，保证位置稳定。
* **回车调用**：输入与某条编码**完全一致**时按回车，内容直接上屏（`fav_exact` +
  `env.engine:commit_text`）。
* **纯数字编码**：中文模式下数字本来是选字键，`menu_processor` 通过 `digit_prefix`
  在输入为空/全数字且仍是某条数字编码前缀时接管该数字，于是 `138` 这类编码可以输入并出候选。
* `v`→`3` 收藏快查，可继续输入编码过滤。

### 新增 · 可视化设置窗口（WinForms）

* 三个标签页：剪贴板历史 / 收藏内容 / 设置与缓存（列表默认条数 20–50、缓存清理、文件位置）。
* **常驻进程 + 离屏预建**：`v`→`1` 到窗口出现在屏幕上实测 **84–106 ms**
  （改动前每次都要重启 PowerShell 并重新解析 700 多行脚本，2–4 秒）。
* 点 × 只隐藏不退出；重复启动（双击 bat）只会把已有窗口叫到前台。
* `vmenu-watcher.ps1` 变成监督者（单实例互斥体），保证常驻窗口永远有一个。

### 新增 · 部署与验证工具

* `patch-build-schema.ps1`：把 `engine/processors|translators|filters` 等结构性配置
  直接写回 `build\rime_ice.schema.yaml`（本机部署器不会重新编译 schema），可重复运行。
* `tools/`：真按键 + 抢焦点 + 截图（`type-and-shot.ps1`）、窗口抓图（`shot-window.ps1`）、
  组合键 + 抓图（`window-keys-shot.ps1`）、窗口枚举（`list-windows.ps1`）、
  延迟测试（`v1-latency-test.ps1` / `v1-e2e-test.ps1`）、菜单流程截图（`run-vmenu-tests.ps1`）。

### 修复

* `v`→`2` 一按就卡死输入法：根因是 Lua 在 Rime 输入线程里 `io.popen` 读剪贴板。
  现在**输入法进程内绝不启动子进程**，只写标记文件/文本文件，进程由外部脚本管理。
* 设置窗口状态栏不更新：写成 `$status.Text`（`StatusStrip` 本身）而不是 `$statusLabel.Text`。
* 窗口出现在屏幕外（-48000,-48000）：只 `CreateControl()` 不重新定位，`Show()` 不会重算位置。
* 数字编码最后一位丢失：`digit_prefix` 用了 `#s < #k`，改为 `#s <= #k`。
* 状态栏文案、收藏页提示、列表列头等文案统一为「简短说明 + 按键提示」。

### 已知限制

* 候选栏里的操作行（如「显示更多」）**点不动** —— Weasel 的鼠标点击等于提交候选，不经过按键链。
  这是宿主行为，非本项目缺陷。
* 收藏打字命中要求编码 ≥ 3 位；纯数字编码要把编码打完。
* 常驻设置窗口约占 150 MB 内存（秒开的代价）。
* 设置窗口 DPI 不感知，150% 缩放下文字略软。
* 后台服务不会开机自启，重启后需要双击一次 `clipboard-sync.bat`。

### 未确认

* 用户需求「最右边的回车键也要还原」的确切含义（见 `docs/PROGRESS.md` §5 开放问题 1）。
  当前按「回车即可调用收藏内容」实现，字母/数字编码统一。
