# 变更记录（CHANGELOG）

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。
本项目在真机（Windows 11 + Weasel 0.17.4 + librime 1.13.1 + rime-ice）上验证。

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
