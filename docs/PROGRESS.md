# 进度记录（PROGRESS）

> 这份文档记录**已经做完什么、怎么验证的、实测数据是多少**。
> 接手前请先读 [`AGENT-HANDOFF.md`](AGENT-HANDOFF.md)（环境事实与约束），
> 再看 [`ARCHITECTURE.md`](ARCHITECTURE.md)（设计原理）。

最后更新：2026-09-13（本机时间）

---

## 0. 一句话状态

**v 功能菜单已经全部可用并在真机上验证过**：菜单（4 项）、剪贴板、常用语（候选第 2 位 + 回车调用）、
原符号还原、可视化设置窗口（常驻、秒开、支持双击编辑）、多行候选框全部工作；
后台服务（剪贴板同步 + 守护 + 常驻窗口）运行中，实测 `v`→`1` 到窗口出现 **84–106 ms**。

未确认 / 待办事项见文末「开放问题」。

---

## 1. 需求 → 实现 → 验证

### 1.1 `v` 打开功能菜单（最早的需求）

| 项 | 内容 |
| --- | --- |
| 需求 | 按 `v` 出现菜单：剪贴板 / 收藏 / 原符号 / 设置 |
| 实现 | `menu_processor.lua` 在输入为空时接管 `v`；`lua_menu.lua`（translator）产出菜单行；`menu_filter.lua` 只保留当前模式需要的候选 |
| 验证 | 截图 `screenshots/ime-01-menu.png` |

菜单文案后来按用户要求**精简**过（见 1.5）。

**第二轮改动（本次）**：主菜单**去掉第 5 项**，只剩 4 项
`1 设置（图形窗口） / 2 剪贴板（历史） / 3 常用语（快捷内容） / 4 原符号（原版 v）`。
改动位置：`src/lua/menu_processor.lua` 主菜单分支（只处理 1–4，其余 `return 2` 放行）、
`src/lua/lua_menu.lua` 的 `yield_menu`（只 yield 4 项）。
`vset` / `vsetc` / `vsetf` / `vsetn` / `vsetx` 的代码**保留但不可再从菜单进入**（只有手打 `vset` 才进得去）。

### 1.2 剪贴板历史（`v`→`2`）+ 设置窗口里的剪贴板页

| 项 | 内容 |
| --- | --- |
| 实现 | `clipboard-sync.ps1` 在输入法**进程之外**每 1 s 同步剪贴板到 `clipboard-cache.txt`；Lua 只读写文本文件 |
| 关键根因 | **绝不能在 Rime 输入线程里启动子进程**（`io.popen` / `os.execute`）。早期版本在 Lua 里调 `io.popen` 读剪贴板，直接把 `v2` 卡死。这条是硬约束，见 `AGENT-HANDOFF.md` |
| 条数规则 | 默认 20，按 `m`/`+` 每次 +10，上限 50，超出丢最旧的 |
| 验证 | `screenshots/gui-01-clipboard.png`；`tools/run-vmenu-tests.ps1` 会跑 `m`/`+`/`-`/`=`/`d`/`x` 全流程并逐张截图 |

### 1.3 收藏（`v`→`3` + 设置窗口收藏页）

| 项 | 内容 |
| --- | --- |
| 存储 | `<RimeUserDir>\cn_dicts\favorites.dict.yaml`，正文在 `...` 之后：`内容<Tab>编码<Tab>词频` |
| 实现 | `vmenu_core.lua` 提供 `read_fav/write_fav/fav_match`；`lua_menu.lua` 生成 `vfav` 候选；设置窗口直接读写同一文件 |
| 验证 | `screenshots/ime-05-favorite-list.png`、`screenshots/gui-02-favorites.png` |

### 1.4 收藏「打字时出现在候选第 2 位」（用户需求）

| 项 | 内容 |
| --- | --- |
| 需求原文 | 「这个收藏要求在不按 v 的情况下输入的时候可以按前 3 个单词（就是编码部分）在候选词的 2 显示收藏的具体内容」 |
| 实现 | `vmenu_core.fav_hit(code)`：输入长度 ≥ 3 时，若输入是某条收藏编码的前缀（或完全相同）则命中；`menu_filter.lua` 在**普通打字**分支里把收藏做成 `Candidate("vfav", 0, #code, word, "收藏")` 插到**索引 2** |
| 关键细节 | 插入后把整张候选表的 `quality` 重排成严格递减（`1000000 - i`），否则后置的排序会打乱位置 |
| 性能 | 只有输入 ≥ 3 个字符才读文件，2 个字符以内不碰磁盘 |
| 验证 | 用示例数据打字 `you` → 候选第 2 位出现 `alice@example.com 收藏`（真实数据下同样命中，只是内容不同；本文档不记录真实内容）；按 `2` 上屏成功 |

### 1.5 纯数字编码（用户需求，本轮新增）

| 项 | 内容 |
| --- | --- |
| 需求原文 | 「纯数字输入的时候如果输入的数字在收藏栏里的话直接在候选词上显示 然后按下回车键即可调用 … 最右边的回车键也要还原」 |
| 问题根因 | 中文模式下**数字是选字键**，根本进不了编码，所以 `131` 这种收藏编码永远无法输入 |
| 实现 1 | `vmenu_core.digit_prefix(s)`：输入为空或全是数字、且 `s` 仍是某条**纯数字编码**的开头时返回 true；`menu_processor.lua` 在按键处理早期接管这个数字（`ctx:push_input(repr)`，返回 1） |
| 实现 2 | `vmenu_core.fav_exact(code)`：输入与某条编码**完全一致**才命中；`menu_processor.lua` 在 `repr == "Return"` 时 `env.engine:commit_text(word)` + `ctx:clear()`，让**回车直接调用收藏内容** |
| 验证（真按键 + 截图） | `138` → 候选直接显示 `13800138000 收藏`（`screenshots/ime-04-digit-favorite.png`）；`138`+回车 → 上屏 `13800138000`；`wsl`+回车 → 上屏收藏邮箱；`12345`+回车 → 原样 `12345`；`ni`+回车 → 原样 `ni`（不受影响） |
| 注意 | `fav_hit`（前 3 位命中，用于预览）与 `fav_exact`（完全一致，用于回车调用）是**两个函数**，别混用 |

### 1.6 设置窗口「太慢」（用户需求）

| 项 | 内容 |
| --- | --- |
| 需求原文 | 「这个设置的弹窗弹出太慢了 要 按 v1 后好久 才能弹出」 |
| 根因 1 | 旧设计每次 `v`→`1` 都**杀掉旧窗口 + 重新启动 PowerShell + 重新解析 700 多行脚本**，2–4 秒 |
| 根因 2 | 旧窗口进程还占着单实例互斥体，新进程只能静默 `exit 0`，表现为「按了没反应」 |
| 新设计 | 窗口进程**常驻**：启动时把窗口在屏幕外 `Show()` 一次再 `Hide()`（预建句柄 + 预跑布局），之后每 60 ms 轮询 `open-settings.flag`，看到就把窗口显示出来（居中 + `Activate` + `BringToFront` + `TopMost` 抖一下）。点 × 只隐藏不退出 |
| 输入法侧 | 只写标记文件（`vmenu_core.request_gui()`），**不启动任何进程** |
| 守护侧 | `vmenu-watcher.ps1` 变成监督者：没在跑就拉起来；自己也有单实例互斥体（`RimeVMenuWatcher`），重复启动无副作用 |
| 实测 | 标记文件 → 窗口在屏幕上：**45 / 56 / 63 / 71 / 72 ms**（稳态）；后台进程刚启动后的第一次显示：**106–180 ms**；真按 `v`→`1`：**84 / 94 / 103 / 106 ms**；不做离屏预建时约 348 ms |
| 验证工具 | `tools/v1-latency-test.ps1`、`tools/v1-e2e-test.ps1` |

### 1.7 菜单文案精简（用户需求）

| 项 | 内容 |
| --- | --- |
| 需求原文 | 「v 后的 123456 等的候选词太冗长了 说明精简一点 如收藏 剪贴板 设置等」 |
| 实现 | `lua_menu.lua` 全量改写：主菜单 `设置/剪贴板/收藏/原符号/文字设置`，注释压到 2–4 字；子菜单（`vset*`）同样精简 |
| 验证 | 截图 `screenshots/ime-01-menu.png` |

> 第二轮把主菜单压到 4 项（去掉 `文字设置`），第 3 项也从 `收藏` 改名为 `常用语`（见 1.8）。

### 1.8 「收藏」→「常用语」改名（用户需求，第二轮）

| 项 | 内容 |
| --- | --- |
| 范围 | **只改用户可见文本**：`v` 菜单第 3 项文本 `常用语` + 注释 `快捷内容`；`v`→`3` 的列表标题 / 空态 / 搜索提示（「还没有常用语」「没有匹配的常用语：」）；正常打字时候选第 2 位的注释（`menu_filter.lua` 里 `Candidate("vfav", 0, #code, fav.word, "常用语")`）；设置窗口标签页 `收藏内容` → `常用语` 及窗口内所有按钮 / 提示 / 确认框文本 |
| 刻意不改 | 内部命名与文件格式：`favorites.dict.yaml`、候选 `type` 前缀 `vfav`、`vset*` 模式、`vmenu-settings.txt` —— 改了会破坏已有数据与配置 |
| 验证 | 截图 `screenshots/ime-02-favorite-inline.png`（注释「常用语」）、`screenshots/ime-05-favorite-list.png`、`screenshots/gui-02-favorites.png` |

### 1.9 多行候选框（用户需求，第二轮）

| 项 | 内容 |
| --- | --- |
| 需求 | 「正常输入时按向下键能显示多个栏的框（多行候选）」 |
| 结论 1 | 候选窗口**换行**由 Weasel 主题键 `style/layout/max_width` 控制：`0` = 不换行（原行为）；`300` 实测 9 个候选排成每行约 5 个的多行网格；`620` 实测**不换行**（自然宽度还没超） |
| 结论 2 | 一页候选数由 schema 的 `menu/page_size` 控制：原来 `9`，现在 `18` → 候选框最多约 **4 行 × 5 列** |
| 落地 1 | `weasel.custom.yaml` 加 `patch: "style/layout/max_width": 300`，并把 `build/weasel.yaml` 的 `max_width` 改成 `300`（同时镜像到 `%APPDATA%\Rime\build\weasel.yaml`） |
| 落地 2 | `rime_ice.custom.yaml` 加 `patch: menu/page_size: 18`，并把 `build/rime_ice.schema.yaml` 的 `page_size` 改成 `18` |
| 方向键 | **一律不拦截**：`↓`/`↑`/`←`/`→` 全部交回 librime 原版 `navigator`。实测（librime 1.13.1，横向候选框）：`↓` = 选中下一个、`→` = 选中下一个、`↑` = 上一个，都不上屏 —— 用户要求的「保留按向右选候选」天然满足 |
| 回退 | `max_width` 改回 `0`、`page_size` 改回 `9`，重启 `WeaselServer` |
| 验证 | 截图 `screenshots/ime-06-multirow-candidates.png`：候选 9→18 条、每行约 5 个；按 `↓` 后高亮在**同一行内**移动（窗口内 y 197..257） |

> 这两个键**不在 Lua 里，也不能运行时切换** —— 想让候选框变高/变矮只能改这两处配置再重启服务。

### 1.10 设置窗口双击编辑（用户需求，第二轮）

| 项 | 内容 |
| --- | --- |
| 剪贴板页 | 双击某一行 → 弹出标题为 `编辑第 N 条` 的编辑框（单行文本框，打开时**全选原文**）；确定后写回 `clipboard-cache.txt`（`Save-Clipboard` + `Refresh-Clipboard`），状态栏显示「已修改第 N 条」；取消 / `Esc` 不改动 |
| 常用语页 | 双击某一行 → 复用原有的 `修改常用语` 弹框（等价于点「修改选中」） |
| 提示文字 | 两个列表的侧边提示都补了「双击某一条可以直接编辑 / 修改」 |
| 验证（端到端） | 双击第 1 行 → 弹出「编辑第 1 条」→ 输入 `test` + 回车 → `clipboard-cache.txt` 第 1 行确实变成 `test`；随后已还原真实数据并校验 sha256 一致 |
| 验证工具 | `tools/gui-dblclick-test.ps1`（新增，用法见 `TESTING.md`）；截图 `screenshots/gui-04-dblclick-edit.png` |

---

## 2. 时间线（本轮，2026-09-13 凌晨）

| 时间 | 事件 |
| --- | --- |
| 00:0x | 收藏候选第 2 位：改写 `menu_filter.lua`，实现 `fav_hit` + 插位 + quality 重排；验证 `wsl` / `131` |
| 00:1x | 数字编码：加 `digit_prefix` 接管，`131` 可输入；发现 `#s < #k` 写错导致最后一个数字漏掉，改成 `#s <= #k` 后通过 |
| 00:2x | 精简 `lua_menu.lua` 文案，截图确认 |
| 00:2x–00:3x | 设置窗口改为常驻 + 离屏预建；`vmenu-watcher.ps1` 改监督者；新增 `打开设置.bat`；修复 `$status.Text` → `$statusLabel.Text`（状态栏不更新） |
| 00:3x | 延迟实测 56–106 ms；发现原 `设置.bat` 从磁盘上消失（本机装有火绒 HIPS，疑似被安全软件清理，未确认），改用 `打开设置.bat` |
| 00:4x | 真机验证 `v`→`1`、菜单、收藏（截图） |
| 00:5x | 用户补充需求：数字编码 + 回车调用；实现 `fav_exact` + Return 处理并验证 |
| 01:0x | 为发布准备示例数据与截图（全部替换为假数据）；整理本仓库 |

### 2.1 第二轮（2026-09-13）

| 时间 | 事件 |
| --- | --- |
| — | 去掉主菜单第 5 项：改 `menu_processor.lua` 主菜单分支与 `lua_menu.lua` 的 `yield_menu`，菜单变 4 项 |
| — | 「收藏」→「常用语」改名（只改用户可见文本，内部标识不动） |
| — | 多行候选框：`weasel.custom.yaml` + `build/weasel.yaml` 的 `max_width` 改 300，`rime_ice.custom.yaml` + `build/rime_ice.schema.yaml` 的 `page_size` 改 18；重启服务后截图确认 18 条按每行约 5 个换行 |
| — | 方向键复核：确认 `↓`/`→` 都是「选下一个候选」且不上屏，决定 Lua **一律不拦截**方向键 |
| — | 设置窗口加双击编辑（剪贴板页 `编辑第 N 条`、常用语页复用 `修改常用语`），并补列表侧边提示 |
| — | 新增 `tools/gui-dblclick-test.ps1`（截图找行 + 真实鼠标双击），端到端验证「双击第 1 行 → 输入 → 文件第 1 行变化 → 还原并校验 sha256」 |
| — | 踩坑并记录：`Set-Content` 改 `build/weasel.yaml` 导致 YAML 损坏（候选窗口全不显示）；编辑工具吃掉 `.ps1` 的 BOM（见 §3 与 `TROUBLESHOOTING.md`） |
| — | 重新生成发布用截图（`ime-01`/`ime-05`/`ime-06`、`gui-01`〜`gui-04`） |

---

## 3. 已修复的坑（重要，别再踩）

| 现象 | 根因 | 修法 |
| --- | --- | --- |
| `v2` 一按就卡死输入法 | Lua 里 `io.popen` 在 **Rime 输入线程**里起进程 | 冻结设计：Lua 只写标记文件，进程由外部脚本管 |
| 收藏有时不在第 2 位 | 候选表在 filter 之后还会按 `quality` 排序 | 插位后把全表 quality 改成严格递减 |
| 打 `131` 一点反应都没有 | 中文模式数字是选字键，进不了编码 | `menu_processor` 在早期接管数字（`digit_prefix`） |
| 数字编码差最后一位 | `digit_prefix` 用了 `#s < #k` | 改成 `#s <= #k`（允许刚好打完整条编码） |
| 设置窗口状态栏不更新 | 写成 `$status.Text`（那是 `StatusStrip`） | 写 `$statusLabel.Text` |
| 窗口出现在 -48000,-48000 | 只 `CreateControl()` 不重新定位，`Show()` 不会重算位置 | 离屏 `Show()`+`Hide()` 预建，首次真正显示时显式居中 |
| 窗口跑到屏幕外后回不来 | 用户拖动 + 显示逻辑只在首次居中 | `Left/Top < -5000` 时强制重新居中 |
| 编辑 `.ps1` 后中文全乱 | `edit` 工具会去掉 BOM，PS 5.1 按 ANSI 解析 | 每次编辑后**补回 BOM**（`UTF8Encoding($true)`），见 `AGENT-HANDOFF.md` |
| 改完 `build\weasel.yaml` **一个候选都不显示**（打字时按键被吞） | 用 `Get-Content`/`Set-Content` 按 ANSI 解码 UTF-8 中文再写回，YAML 结构损坏；日志报 `yaml-cpp: error at line 356, column 12: end of map not found` | 改用 `[IO.File]::ReadAllText($p,[Text.Encoding]::UTF8)` + `WriteAllText(...UTF8Encoding($false))`，改完看日志确认没有 `Error parsing` |
| UIA 抓不到设置窗口的子控件 | WinForms 窗口对 `System.Windows.Automation` 不可见（`FindAll(Descendants)` 返回 0） | GUI 自动化一律走「截图找行 + 真实鼠标」，见 `tools/gui-dblclick-test.ps1` |
| 自动点击点到别的行 | 测试进程不 DPI-aware，`SetCursorPos` 的坐标被系统按 1.5 倍缩放 | 用前先 `SetProcessDPIAware()`（实测点到第 9 行而以为是第 1 行） |
| 找不到模态弹框 | 模态子窗口不出现在 `Process.MainWindowTitle` 里 | 用 `EnumWindows` + `GetWindowTextW` 枚举顶层窗口标题 |
| 自己的 pwsh 命令被自己杀掉 | 命令列里出现脚本字面名，被「按命令行匹配进程」的清理脚本一起匹配 | 脚本名在运行时拼接（`'vmenu-' + 'watcher.ps1'`），或用 `-ne $PID` 排除自己 |
| 记事本抢不到焦点 | Chrome 会持续抢前台，`SetForegroundWindow` 直接失败 | `AttachThreadInput` + `BringWindowToTop` + 先按一下 ALT 解锁前台锁（`tools/type-and-shot.ps1`） |

---

## 4. 当前部署状态（本机）

| 组件 | 状态 |
| --- | --- |
| `WeaselServer.exe` | 运行中（改 Lua 后重启过） |
| `clipboard-sync.ps1` | 1 个实例 |
| `vmenu-watcher.ps1` | 1 个实例（监督常驻窗口） |
| `vmenu-settings-gui.ps1` | 1 个实例（常驻，未打开时是隐藏窗口） |
| `open-settings.flag` | 稳态下**不存在** |
| Lua 双目录一致性 | `D:\rime-sandbox\lua\` 与 `%APPDATA%\Rime\lua\` 四个文件 MD5 必须一致 |
| `style/layout/max_width` | 300（`weasel.custom.yaml` + `build/weasel.yaml` + `%APPDATA%\Rime\build\weasel.yaml` 三处一致） |
| `menu/page_size` | 18（`rime_ice.custom.yaml` + `build/rime_ice.schema.yaml`） |

---

## 5. 开放问题（需要人类确认）

1. **「最右边的回车键也要还原」的确切含义未确认。**
   当时的判断：用户想表达「编码打完按回车就能调用收藏内容」（数字编码尤其需要），
   于是实现了 `fav_exact` + Return 提交，字母编码也一并支持（行为统一）。
   **如果用户本意是别的**（例如希望候选窗口最右侧的翻页/提示控件恢复原样，或者希望字母编码
   的回车仍然提交原始编码），改动点在 `src/lua/menu_processor.lua` 的 Return 分支，
   删除该分支即可回到原行为（数字编码仍会靠「整屏只有一个候选时回车上屏」生效）。
2. **`设置.bat` 为什么从磁盘消失未确认。** 本机装有火绒（Huorong HIPS），
   「.bat 里 `start` 一个隐藏 PowerShell」是典型可疑行为，疑似被安全软件清理。
   现在的启动脚本 `打开设置.bat` 改成「先写标记文件，再拉起守护脚本」，目前存活。
3. 设置窗口是 DPI 不感知的（Windows 放大，文字略软）。要做成真 DPI 感知，
   需要 `SetProcessDPIAware()` + 所有尺寸乘以 `DpiX/96`（改动集中在
   `vmenu-settings-gui.ps1` 的 `Layout-Tabs` 与常量区）。
4. 目前**没有开机自启**：重启电脑后需要再双击一次 `clipboard-sync.bat`。
   仓库里没有加自启脚本（不想在用户机器上静默写启动项）——需要的话可以加一个
   显式确认的 `install-autostart.ps1`。
5. **`vset*` 死代码是否删除待定。** 主菜单去掉第 5 项后，`vset` / `vsetc` / `vsetf` / `vsetn` /
   `vsetx` 这一整条纯键盘设置路径只有手打 `vset` 才进得去，对普通用户等于不可达。
   删掉可以省掉 `lua_menu.lua` 里一大段文案与 `menu_processor.lua` 的分支；
   留着则保留「窗口挂了也能改设置」的兜底能力。**需要人类拍板**。
6. **多行候选框的列数 / 每页条数是否再调。** 现在 `max_width=300` + `page_size=18`
   ≈ 4 行 × 5 列。实测 `max_width=620` 不换行、`300` 才换行，所以想改列数就调这个值
   （调小 = 每行更少、行更多），想改总条数就调 `page_size`。
   两者都是**改完要重启服务**的配置，没有运行时开关。是否需要给「想要几列」找个更好看的值，
   待人类看截图后定。
