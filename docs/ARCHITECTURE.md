# 架构（ARCHITECTURE）

## 1. 总览

```
                  ┌─────────────────────────── 输入法进程（WeaselServer / librime）───────────────────────────┐
   按键 ────────► │ menu_processor.lua (lua_processor)                                                     │
                  │   ├─ 输入为空 + v          → push_input("v")            → 进入 v 菜单                  │
                  │   ├─ v + 1..5            → 写标记文件 / 切到 vclip / vfav / v / vqi                    │
                  │   ├─ 方向键 ↓↑←→          → 普通打字走网格导航（grid_key），其它键交回原版             │
                  │   ├─ 全数字编码：数字→并进编码；组不成前缀→数字直接上屏；
                  │   │              `-`/`=`/`+`→上屏数字再插符号；回车→整条常用语（§3.3.1）      │
                  │   └─ Return + 编码完全匹配 → engine:commit_text(常用语内容)                            │
                  │                                                                                        │
                  │ lua_menu.lua (lua_translator)  ── 产出候选行：vmenu / vclip / vfav / vqi / vset / vact  │
                  │ menu_filter.lua (lua_filter)   ── v 模式下只留所需候选；普通打字时把常用语插到候选第 2 位│
                  │ vmenu_core.lua (require)       ── 路径、设置、剪贴板/常用语读写、命中判断、原符号标记    │
                  └───────────────┬───────────────────────────────────────────────┬────────────────────────┘
                                  │ 只读写文本文件（绝不启动进程）                 │ 写 open-settings.flag
                                  ▼                                               ▼
        clipboard-cache.txt / favorites.dict.yaml / vmenu-settings.txt     open-settings.flag
                                  ▲                                               │ 轮询 60 ms
                                  │ 每 1 s 同步系统剪贴板                          ▼
                  ┌───────────────┴───────────────┐            ┌─────────────────────────────────────────┐
                  │ clipboard-sync.ps1（独立进程） │            │ vmenu-settings-gui.ps1（常驻 WinForms） │
                  └───────────────────────────────┘            │  ← vmenu-watcher.ps1 负责「永远有一个」 │
                                                               └─────────────────────────────────────────┘
```

**核心思想**：输入法进程只做「按键 → 候选」和「读写文本文件」，
**任何进程创建、窗口管理、网络、耗时 IO 都放到外面的 PowerShell 服务里**。
这是被一次严重卡死事故换来的设计（见 §5 约束 1）。

## 2. 组件职责

| 组件 | 类型 | 职责 | 关键约束 |
| --- | --- | --- | --- |
| `vmenu_core.lua` | 共享模块 | 路径解析（`rime_api.get_user_data_dir()`）、设置读写、剪贴板/常用语读写、`fav_hit` / `fav_exact` / `digit_prefix`、原符号标记、**候选方格状态与二维导航**（`grid_limit` / `grid_key`，见 §3.6） | 所有对外函数可被 `pcall` 包裹；不启动进程；**模块级变量在 processor/filter 之间不共享**，状态只能走 context option |
| `menu_processor.lua` | `lua_processor@*` | 按键总管。**必须排在 `speller` / `selector` 之前**，否则数字会被当成选字键、`v` 会被当普通字母。主菜单 `1`–`5`、`vqi` 子模式（§3.9）、非 v 模式的 `+`（下翻）与方向键 → `grid_key`（§3.6；移动高亮的补丁在自编 DLL 里） | 只拦自己认识的键，其余一律 `return 2` |
| `lua_menu.lua` | `lua_translator@*` | 所有菜单/列表候选的文案与数据（菜单文案要改就改这里），含主菜单第 5 项「快捷输入」与 `yield_quick` 的 9 项 | 候选 `type` 用于 filter 分流：`vmenu`/`vclip`/`vfav`/`vqi`/`vset`/`vact`（`vset` 自第二轮起已不可从菜单进入，属保留代码） |
| `menu_filter.lua` | `lua_filter@*` | ① v 模式：只保留当前模式需要的候选类型；② 普通打字：命中常用语时插入候选第 2 位，全数字输入时把「数字本身」做成第 1 位候选；③ 普通打字时按方格状态限制候选个数（收起 9 / 展开 36），并按 `core.page_get(ctx)` 做 `+` 下翻的窗口切片（见 §3.6、§3.3.1） | 插位后必须重排 `quality`（严格递减）；**序号不在这个文件里**（已改由自编 DLL 的标签槽画） |
| `vmenu-settings-gui.ps1` | 常驻 WinForms | 三个标签页的可视化设置；轮询标记文件；改动即时写文件；列表支持**双击编辑**；「设置与缓存」页底部还有 **`小狼毫原生设置`** 分组 + `打开小狼毫原生设置` 按钮（打开小狼毫自带的设置对话框） | DPI 不感知 → 所有坐标在 `Layout-Tabs` 里按「实际客户区」现算，不能用 Dock/Anchor/写死坐标 |
| `vmenu-deployer-wrapper.cs` | 代理（C#） | 顶替安装目录下的 `WeaselDeployer.exe`：**无参数** → 打开 vmenu 设置窗口（`vmenu-settings-gui.ps1 -ShowNow`）；**带参数** → 原样转发给 `WeaselDeployer.real.exe`（见 §3.8） | 用 `csc.exe /target:winexe /r:System.Windows.Forms.dll` 编译；源文件必须 UTF-8 **带 BOM**；找不到窗口脚本时退回原生对话框 |
| `vmenu-tray-setup.ps1` | 部署工具 | 托盘菜单入口的**安装 / 撤销**：改 `WeaselServer.exe` 里的菜单文字、安装代理、开始菜单快捷方式改名 | 幂等；`-Revert` 可还原；`WeaselServer.exe.vmenu-bak` 只在第一次安装时生成 |
| `vmenu-watcher.ps1` | 监督者 | 保证「常驻窗口永远有一个」；自身单实例 | 不杀进程、不做别的判断 |
| `clipboard-sync.ps1` | 独立进程 | 系统剪贴板 → 文本文件（去重、上限、新的在前） | 必须在输入法进程之外 |
| `patch-build-schema.ps1` | 部署工具 | 把结构性配置写回 `build\rime_ice.schema.yaml` | 幂等、可重复运行 |

## 3. 数据流（逐功能）

### 3.1 按 `v` 打开菜单

1. 输入为空时按下 `v`：`menu_processor` → `ctx:push_input("v")`，返回 1（已处理）。
2. `lua_menu` 看到输入 `v` → 产出 **5 个** `vmenu` 候选
   （设置 / 剪贴板 / 快捷输入 / 常用语 / 原符号）。
3. `menu_filter` 看到 `core.mode_of("v") == "menu"` → 只保留 `vmenu` + `vact`，其余全丢。
4. 按 `1`..`5`：`menu_processor` 的 `cur == "v"` 分支写标记文件（设置窗口）或改写输入
   （`vclip` / `vfav` / 原符号模式 / `vqi` 快捷输入，见 §3.9）；**其余按键 `return 2` 放行** ——
   原来的第 5 项「文字设置」已从菜单去掉（`vset*` 只有手打 `vset` 才进得去），现在第 5 项是快捷输入。

### 3.2 剪贴板（`v`→`2`）

* 数据源是 `clipboard-cache.txt`（外部进程写，Lua 只读）。
* 显示条数由 `vmenu-settings.txt` 的 `clip_page` 决定，默认 20，范围 20–50。
* 列表里：`m`/`+` 每次多看 10 条，`-`/`=` 翻页，`d` 进删除模式，`x` 清空（二次确认页），`q` 返回。
* 分页、删除、清空都是**改写输入码**（`vsetc` + `m` 的个数等）实现的无状态重算，
  输入码本身就是状态，因此不需要额外变量。
  （`vsetc` 这类输入码仍在使用；原来的菜单入口 `v`→`5`→`1` 已随第 5 项一起去掉，
  现在只有 `v`→`2` 和手打 `vset` 两条路。）

### 3.3 常用语（`v`→`3` / 打字命中 / 回车调用）

> 「常用语」就是原来的「收藏」：**只有用户可见文本改了**，代码里的 `fav_*` / `vfav` /
> `favorites.dict.yaml` 等内部标识一个都没动。

| 场景 | 代码路径 | 规则 |
| --- | --- | --- |
| 搜索取用 | `vfav` 模式 + `fav_match` 过滤 | 编码或内容前缀匹配 |
| **打字预览** | `menu_filter` 普通分支 + `fav_hit(code)` | 输入长度 **≥ 3**，且输入是某条编码的前缀 → 常用语内容做成 `vfav` 候选插到索引 2（注释文本 `常用语`） |
| **回车调用** | `menu_processor` 的 `Return` 分支 + `fav_exact(code)` | 输入与某条编码**完全一致**（不分大小写）→ `engine:commit_text(word)` + `ctx:clear()` |
| 纯数字编码 | `digit_prefix(code)` + 数字接管分支 | 输入为空或全数字，且「已输入 + 新按键」仍是一条**纯数字编码**的前缀 → 把数字并进编码；**组不成前缀就把数字当普通字符上屏**（`commit_text(code)` + `clear()`），于是 `13` 后面按 `-` `=` `+` `.` 得到的是「数字 + 符号」而不是「数字变成候选态」（第二十轮，见 §3.3.1） |

`fav_hit`（前缀，用于预览）与 `fav_exact`（完全一致，用于回车）**故意分开**：
预览要「早」（3 位就出现），回车要「准」（不能抢走正常的原始输入）。

#### 3.3.1 纯数字输入不再「变成候选态」（第二十轮）

用户诉求（原话）：「输入数字的时候会变成候选状态 也就是无法在输入如 13的时候直接按"-"等按键
在后面插入一个"-" 但是要保留数字作为常用语的编码（如常用语 13122500717 在输入131的时候会在
候选词中显示 但是有且只有在输入回车后才会输入完整的常用语 输入1等词的时候不会输入而是正常地
加在后面）」。

原因是两条老机制叠在一起：① `menu_filter` 把「数字编码本身」也做成了候选（第 1 位），
② `punctuator` 在**有候选菜单**时，`-` 会先提交**当前高亮的候选**再插入符号
（`Punctuator::ProcessKeyEvent`：`if (ctx->IsComposing()) { commit 选中项 }`），
于是 `13` + `-` 变成「13」上屏 + 「-」，看起来就是「数字被当成候选吃掉了」。

现在的分工（`menu_processor.lua` 新增分支放在 **raw 模式之后、翻页分支之前**）：

| 输入 | 按键 | 结果 |
| --- | --- | --- |
| 空 或 全数字 | 数字，且 `已输入+数字` 仍是某条**纯数字编码**的前缀 | 并进编码（`ctx:push_input`），继续待在输入框里等回车 |
| 空 | 其它数字（组不成任何编码前缀，例如现库里没有 `2…` 开头的编码） | `return 2` 放行 → 正常打字 |
| 全数字 | `-` `=` `+`（含小键盘 `KP_Subtract/Equal/Add`） | **先上屏数字本身**，再插入符号 → `13` + `-` = `13-`（`commit_text(code .. sym)` + `clear()`） |
| 全数字 | `Enter` | **仍然是唯一**能上屏整条常用语的键（`fav_exact`） |
| 全数字 | 其它数字（组不成前缀） | 数字当普通字符上屏 → `1313`、`1312` 就老老实实是 `1313`、`1312` |

* 配套的「数字候选」由 `menu_filter.lua` 的 `digit_cand(code)` 提供：全数字输入时它**永远排第 1 位**
  （`quality = 1000000`），于是「回车/点它」= 上屏数字本身；常用语排在它后面（第 2 位）。
  没有这条候选时，输入框里只有常用语一条候选，`13` 看起来就像「已经被选成候选」了。
* 翻页键同时收窄了适用范围：`-` / `=` 只在**列表型 v 功能**或**纯拼音输入**（`^[a-z']+$`）时才当翻页，
  数字编码输入时它们走上面的「上屏数字 + 插入符号」分支。
* 实测（干净记事本，逐条）：`13`+`-` → `13-`；`131`+回车 → `13122500717`；`1313` → `1313`；
  `13`+`.` → `13。`；`13`+`Shift+=` → `13+`；`13`+`=` → `13=`；`1312` → `1312`；
  单个 `1`（前缀 `131` 的起点）留在输入框、回车才上屏；`wsl`+回车 → 收藏邮箱（未受影响）。

### 3.4 原符号模式（`v`→`5`）

`v`→`4` 把输入改回 `v` 并写模块级标记 + context option（`vraw_mode`）双写，
之后 `menu_processor` 直接 `return 2`，让 `speller`/`punctuator` 按原版行为处理，
于是 `v` 后面接 `2` 得到「二 贰 ² ₂ Ⅱ …」。输入清空即退出该模式。

### 3.5 设置窗口（`v`→`1`）

```
输入法（Lua）                          常驻窗口进程（PowerShell/WinForms）
─────────────                          ─────────────────────────────────────
request_gui()  ──写──► open-settings.flag ──轮询 60 ms──► Take-Flag()（读到即删）
                                                          └─► Show-SettingsWindow()
                                                              ├ 首次或跑到屏幕外：居中到主屏工作区
                                                              ├ Show() + Activate() + BringToFront()
                                                              ├ TopMost 抖一下（绕过前台锁）
                                                              └ 状态栏写「已打开 · HH:mm:ss」
```

* 进程启动时把窗口**离屏 `Show()` 一次再 `Hide()`**：句柄、字体、布局全部预建，
  用户第一次按 `v`→`1` 也是毫秒级（实测 106 ms；不做预建时是 ~350 ms）。
* 点 × = 只隐藏（`FormClosing` 里 `$e.Cancel = $true` + `Hide()`），所以下次仍秒开。
* 单实例互斥体 `RimeVMenuSettingsGui`；已有实例时新进程**只写标记文件然后退出**，
  于是「双击 bat 再开一个」不会开出第二个窗口，而是把已有窗口叫到前台。
* `vmenu-watcher.ps1` 每 500 ms 数一次「命令行含 `vmenu-settings-gui.ps1` 的 powershell 进程」，
  为 0 就拉起来（若标记文件已存在则带 `-ShowNow`）。

### 3.6 候选框渲染（收起 ⇄ 4 行 × 9 列 + 网格导航）

**候选框的宽度与一页上限由「主题 + 方案」决定**，不能运行时切换；
**但要「这一屏放几个候选」由 Lua 决定** —— 两者配合才是「默认收起 9 个、按 `↓` 展开 4 行 × 9 列」。

| 决定什么 | 键 / 代码 | 文件 | 现在的值 |
| --- | --- | --- | --- |
| 一行放几个 / 是否换行 | **自编 DLL**（不再是主题键） | `weasel-grid-build` 分支的 `WeaselUI/HorizontalLayout.cpp` | 候选 **> 9** 时每 9 个换行；**≤ 9 绝不换行**（窗口随内容变长） |
| 候选框最宽多少 | **`style/layout/max_width`（第二十轮起真的生效了）** | 主题 `weasel.custom.yaml` → `style.max_width` → `HorizontalLayout.cpp` 的 `row_budget` | `1100`。英文/长候选（如 `gith` 9 条 × 272px = 2448）不再把框拉到整屏宽：**先丢尾部最多 3 条**，仍放不下就把格宽压到 `row_budget / draw_cols`，超出的字画成 `…`（**候选文本不动，上屏仍是完整的**） |
| 一页最多几条 | `menu/page_size` | 方案：`rime_ice.custom.yaml` →（编译产物）`build/rime_ice.schema.yaml` | `36`（= 9 × 4，原来 `18`） |
| 原生序号列画不画 | `style/label_format` | Weasel 主题：同一个 `weasel.custom.yaml` | `" "`（留空 = 不画原生序号；原值 `"%s"`）。序号改由自编 DLL 的标签槽画 |
| 这一屏实际放几个 | `grid_limit(ctx)` | `src/lua/menu_filter.lua`（正常打字分支） | 收起 **9**、展开 **36** |
| 序号数字 | `HorizontalLayout::GetLabelText` 覆写 | **自编 DLL**（`weasel-grid-build` 分支） | 按 `this->id/9 == id/9` 判断高亮行：高亮行给列号 `1`–`9`（**画在候选词前面**），其余行两个空格对齐 |
| 展开状态 / 下翻页码 | context option `vmenu_grid` / `vmenu_page_0..3` | `src/lua/vmenu_core.lua` | `↓` 展开、第 1 行 `↑` 收起；`+` 下翻换下一批 9 个（4 页循环） |

* 组合效果（2026-09-18 实测）：收起 = **一行**（`zhe` 实测高 **64px**，宽随内容变长）；
  `↓` 展开 = 最多 **4 行 × 9 列**（`zhe` 只有 3 行候选 → **204px**）；展开后 `↓`/`↑` 是**上下跳行**、
  `←`/`→` 行内移动；**高亮回到第 1 行按 `↑` 才收回**。
* `page_size` 与 `label_format` 在 `build/*.yaml` 里生效，改完**必须重启 `WeaselServer`**；
  换行 / 序号 / 方向键则要改源码 → CI → 部署 **5 个文件**（见 `GRID-CANDIDATE-DLL.md`）。
* ⚠️ 改这两个文件必须用 UTF-8 读写（`[IO.File]::ReadAllText/WriteAllText`）。
  PS 5.1 的 `Get-Content`/`Set-Content` 默认按 ANSI 解码，会把 YAML 写坏，
  表现为**候选窗口完全不显示**（见 `TROUBLESHOOTING.md`）。

**方向键 / `+` 下翻（0.2.5 起由自编 DLL + Lua 共同负责）**：`menu_processor.lua` 在**非 v 模式、
且输入非空**时，先拦 `plus`（下翻）再交给 `core.grid_key(ctx, repr)`；
真正「移动高亮」的是**自编 DLL** 的 `RimeWithWeasel.cpp` 补丁（复用鼠标悬停选词的服务端通路，
不会上屏）：

| 按键 | 实际行为 | 实测 |
| --- | --- | --- |
| `↓`（收起时） | **展开**成 4 行 × 9 列（Lua 置位 `vmenu_grid`） | ✅ 64 → 204px |
| `↓`（已展开） | 高亮**跳到下一行**（DLL：+9），**不收起** | ✅ 差分 12767 点（x[90..212] y[197..327]），高度不变 |
| `↑`（高亮在第 1 行） | **收回**成一行（Lua 清 `vmenu_grid`；DLL 的 -9 越界，不吞键） | ✅ 204 → 64px |
| `↑`（高亮在第 2–4 行） | 高亮**跳到上一行**（DLL：-9） | ✅ |
| `←` / `→` | 高亮**在同一行内左右移动**（DLL：-1 / +1） | ✅ 11374 点（x[90..294]） |
| `+`（小键盘） | **下翻**：收起态换下一批 9 个（页码 option），4 页循环 | ✅ 三页候选互不重复；第 4 次与第 0 页只差 14 点 |
| 其它任何键 | 自动收回 + 页码复位（Lua），按键原样放行 | ✅ 自动收回 |

> ⚠️ **Lua 侧仍然没有「移动高亮」的 API**（`ctx.select_candidate` / `set_selected_candidate_index` /
> `highlight` / `move_selection` / `get_menu` / `selected_candidate_index` 全是 `nil`），
> `ctx.select` 是**上屏**。所以这套导航**只能在 DLL 里做** —— 别试图把 `ctx.select` 当跳行用。

**三个必须知道的实现约束**（前两个踩过，第三个是 0.2.4 的实测结论）：

1. **`lua_filter` 与 `lua_processor` 各自 `require` 一份 lua 模块，模块级变量不共享** ——
   「是否展开」必须放在 **context option**（`vmenu_grid`）里传递，和 `vraw_mode` 一个思路。
2. ⚠️ **绝不能调用 `ctx.select`**：它不是「移动高亮」，而是**「选中并上屏」**。
   0.2.3 用它做「往下跳一行」（`ctx:select(sel + 9)`），结果展开后第二次按 `↓` 就把候选打出去了
   （日志里 `ok=true err=nil`，没有异常 —— 所以 `pcall` 根本挡不住，会伪装成「静默生效」）。
3. **本机 librime-lua 没有「移动高亮」的 API**（探针实测）：
   `ctx.select_candidate` / `set_selected_candidate_index` / `highlight` / `move_selection` /
   `menu` / `get_menu` / `selected_candidate_index` / `menu.*` / `composition.select` **全是 `nil`**。
   ~~早期文档里「`selected_candidate_index` 是 1 基、`ctx:select(i)` 是 0 基，在 `grid_sel()` 里换算」
   是**错的**~~ —— 那个字段不存在，换算读到的永远是 `nil`（当成 0 用），这也是当时
   误判「跳行只是差一位」的原因。

**v 菜单内部不接管方向键**（`cur` 命中 `mode_of()` 时跳过 `grid_key`），保持原菜单手感。

**序号：数字在候选词前面、画在高亮那一行（0.2.5 起）**：

1. **自编 DLL 覆写 `WeaselUI/HorizontalLayout.cpp` 的 `GetLabelText`**：一格候选的渲染顺序是
   「标签 → 候选词 → 注释」，只有**标签槽**在词的左边；按 `this->id / 9 == id / 9` 判断
   「本候选是否在高亮那一行」，是高亮行给列号 `1`–`9`，其余行给两个空格保证左边缘对齐。
2. **主题 `style/label_format` 留空**（`" "`）→ Weasel **不再画原生序号列**。
   这一步仍是「去掉第 2–4 行 `10`、`11`……」的必要条件：rime 的
   `menu/alternative_select_labels` 对 Weasel **无效**（实测：写进 patch 会被整份拒绝、
   `page_size` 掉回 9；写进 `build` 产物 YAML 能过但序号列的像素分布逐段完全相同）。
3. **`menu_filter.lua` 里不再有任何序号代码**（旧的 `number_row1` 与 v 菜单逐条编号**已删除**）。

> 历史（为什么换实现）：旧做法把序号写进候选**注释**，渲染出来是「这个**1** 这股**2**」——数字在词的
> **后面**；而且注释是**翻译阶段**生成的，**移动高亮不会重跑过滤器**，序号永远钉在第一行，
> 做不到「按高亮行重新编号」。标签槽是**每次绘制**都重算的，天然跟随高亮。
> 副作用（好的一面）：v 菜单「快捷输入」第 10 条以前显示 `10`，现在不会再出现。

> 取证：`D:\weasel-build\shots\` 下的候选窗裁图（只截候选窗口区域，按惯例**不入库** `screenshots/`），
> 用 `node ...\claude-vision-skill\vision.js <png> "逐字输出图中所有文字"` 读出 `1 这个 2 这股 …`。

#### 3.6.1 v 功能菜单：一行 4 个 + `+` / `-` 翻页 + `↓` 展开（第十八轮；第二十轮静态菜单已改成「全部排一行」，见下）

用户诉求（原话）：「v 的功能改为支持用加减号进行选择 然后一行显示 4 个 同时参考正常输入的下键
拓展按键进行拓展显示」，并补充「当所有的功能的候选词实在太多的时候 允许减少 1-3 个候选词
以保证页面可实行完整 同时拓展栏也要有相应的缩减 以保证对齐」。

| 决定什么 | 键 / 代码 | 文件 | 现在的值 |
| --- | --- | --- | --- |
| v 功能一行几个 | `ctx.grid_cols`（服务端下发） | `RimeWithWeasel.cpp` `_VMenuCols` → `include/WeaselIPCData.h` `Context::grid_cols` → `WeaselUI/HorizontalLayout.cpp` | v 功能 **4**、普通打字 **9**（缺省 0 = 9，老服务端不发这行也照旧） |
| 序号按哪种算法 | `ctx.grid_2d`（服务端下发） | `RimeWithWeasel.cpp` `_VMenuSeqLabels` → `Context::grid_2d` → `HorizontalLayout::grid_2d_` | **1** = 按「行 × 列」（列表型 v 功能 + 普通打字）；**0** = 按 `1..N` 顺序（静态 v 菜单） |
| 一屏几条 / 翻页步长 | `core.grid_limit(ctx, code)` | `src/lua/vmenu_core.lua` | v 列表 **4 / 16**（= 4 列 × 1 / 4 行），静态 v 菜单 **36**（全部一次给），普通打字 **9 / 36** |
| `+` / `-` 干什么 | `core.page_next / page_prev` | `src/lua/menu_processor.lua` | **列表型 v 功能**与普通打字：按「这一屏的条数」翻页；`-` 回上一屏。静态 v 菜单不接（条目本来就全显示） |
| `↓` / `↑` 干什么 | `core.grid_key` | `src/lua/menu_processor.lua` + 服务端箭头补丁 | 列表型 v 功能：`↓` 展开 4 行 × 4 列 = 16 个、`↑` 在第一行收回；静态 v 菜单不接（保持原菜单手感） |
| 一行放不下怎么办 | `visible_cols_` + `row_budget` | `WeaselUI/HorizontalLayout.cpp` | ① **每行少放 1–3 列**（最少 1 列），被省掉的**尾部格子里什么都不画**（空矩形 = 点不到），列槽位保留；② 丢到 3 条还放不下 → **压窄每格**（`col_width = row_budget / draw_cols`，下限 `120 + candidate_spacing`），多出来的字画 `…`。**静态 v 菜单不参与这两步** |

**为什么「少放几列」而不是「重新折行」**：重排会让收起态那一行与展开后的每一行**列位置对不上**
（用户明确要求「拓展栏也要有相应的缩减 以保证对齐」）。现在的做法是：

```
一行 4 列，实际画 2 列（格子还是 4 个，后 2 个是空矩形）
收起态： [1][2][ ][ ]                 ← 第 1 行
展开后： [1][2][ ][ ]                 ← 第 1 行（列 x 坐标与收起态逐像素相同）
         [5][6][ ][ ]                 ← 第 2 行
         [9][10][ ][ ]
         [13][14][ ][ ]
```

* 判据：`cols >= 4` 时按 `min_cols = cols - 3` 兜底，循环 `while (draw_cols > min_cols && draw_cols * col_width > grid_budget) --draw_cols;`，
  `grid_budget = GetSystemMetrics(SM_CXSCREEN) - offsetX - 2*real_margin_x - 16`。
* 实测（剪贴板 20 条，条目很长时）：收起 `1433x49` 只画 2 列、展开 `1433x191` 是 4 行 × 2 列
  （可见项 = 1/2、5/6、9/10、13/14 —— 4 个一行换行的槽位里每行只画前 2 个）；条目短时（第 2 屏）
  一行**画满 4 个**：`1424x49`，OCR 读出 `1 Paraformer-zh 5/20`、`2 不要显示这个内部代码 6/20`、
  `3 paraformer-zh-small int8 7/20`、`4 先再网页跑通了再打包 8/20`。
* ⚠️ 已知特性：被省掉的格子**仍然能被数字键选中**（服务端/librime 的选词是按下标算的，
  前端只是没画）。表现：收起态只画 2 个时按 `3` 会上屏第 3 条（看不见）。这是「不重排」的代价，
  比「按了 3 却选到第 1 行第 3 个」要可预测得多。

**静态 v 菜单的序号是顺序的**（这是 `ctx.grid_2d = 0` 的唯一用途）：v 主菜单 5 项、v3 快捷输入 7 项，
数字键是 **1..N 顺序选**（`menu_processor.lua` 自己处理），所以序号也必须顺序画。
**第二十轮起它们不再折行，而是全部排在同一行**（用户：「让v功能的页面的候选词在同一行显示」）：

* 静态 v 菜单（`grid_2d == 0`）在 `HorizontalLayout` 里走 `static_menu` 分支：**列数 = 候选条数**、
  强制单行、格宽用**内容自然宽度**（`grid_uniform = false`，不再等宽居中），也**不参与**下面的丢格/压宽。
  实测：v 主菜单 `849x49` 一行 5 项（原来是 4 列 `861x95` 两行）、
  v3 快捷输入 `997x49` 一行 7 项（原来是 2 列 `707x189` 四行）。
* 普通打字仍是「≤9 绝不换行、>9 每 9 个换行」的等宽网格（`shi` 收起 `663x49` 9 格、
  `↓` 展开 4 行 × 9 列），列的 x 坐标与展开后逐像素对齐 —— **这是不能回归的约束**。

> ⚠️⚠️ **绝不能在 `lua_filter` 里调用 `ctx:set_option()`**（第十八轮付出血的代价）：
> 第一版把「这次是不是列表型 v 功能」写进 option `vmenu_list` 由过滤器刷新，
> 结果服务端**每次按键都栈溢出崩溃**（事件日志 `WeaselServer.exe` / `ntdll.dll` / `0xc00000fd`，
> `%TEMP%\rime.weasel\WeaselServer.exe.<pid>.dmp`）。原因：`set_option` 会通知引擎重跑候选管线，
> 管线又进过滤器、过滤器又 `set_option` —— 无限递归。
> 现在这份判断由**服务端自己按输入前缀算**（`_VMenuListCode`：`vclip*` / `vfav*` / `vsetc*` / `vsetf*`），
> 不经过 option；`menu_processor.lua`（**processor**，在管线之前跑）里该改 option 的照旧。

**列表型 v 功能（剪贴板 `v`→`2` / 常用语 `v`→`4`）是「固定格宽」的另一套排版**（第十九轮）：
服务端下发 `ctx.grid_cols = 2` 时，客户端 `HorizontalLayout` 走 `fixed_cells` 分支 ——

* 一屏固定 **2 列 × 3 行 = 6 条**（`vmenu_core.LIST_LIMIT`），**永远展开**，`↑` 在第 1 行被吞掉；
* 格宽钉死为 **`min(屏宽 20%, 可用宽度/列数)`**（`kVMenuFixedCellPercent = 20`），
  面板宽度因此与内容无关（剪贴板三页实测都是 `707x144`；`v`→`4` 两条也是 `707x49`）；
* 每格 = `[序号槽][候选词][右对齐的注释]`，候选词可用宽度 = 格右缘 − 注释 − 间距，
  放不下的文字由 DirectWrite 画成 `…`（`SetLayoutWordWrapping(NO_WRAP)` +
  `SetLayoutEllipsisTrimming`）——**只裁绘制，候选文本不动，上屏仍是完整内容**；
  **剪贴板的注释已按用户要求删除**（原来是「剪贴板 n/30」），所以剪贴板那些格子的
  候选词宽度 = 整格，一格能看约 9 个汉字；常用语仍带注释，写的是触发键；
* 数字键与正常打字同构：只选**高亮那一行**的第 N 个（`row = current/2; target = row*2 + digit`），
  `+` / `-` 按 6 翻页。
* ⚠️ 两个必须记住的坑：换行时**光标必须在算本行第一个候选的 rect 之前**就回到行首
  （否则那一格的宽度是 0），以及固定格宽下**光标只能走到本格文字区右缘**
  （否则注释 rect 被顶出格子，`max_width_of_rows` 跟着涨 → 面板宽度抖动）。
  详见 `docs/GRID-CANDIDATE-DLL.md` §7.5。
* **快捷输入（`v`→`3`）曾经在 0.2.17 接进这套固定格**（用户当时要求「和粘贴板相似的2*3格式」）；
  第二十轮用户改口「让 v 功能的页面的候选词在同一行显示」，于是服务端 `_VMenuCols` 对它
  **不再返回 2**，v3 与 v 主菜单一起排成一行（`997x49`）。
  **剪贴板（`v`→`2`）与常用语（`v`→`4`）保持这 2 × 3 的固定格**（`grid_2d = 1` 的列表型），
  用户明确没有要求改它们 —— 实测仍是 `706x143` / `706x49`。

#### 3.6.3 候选框宽度上限（第二十轮）：长英文候选不再把框拉长

用户诉求（原话）：「在输入GitHub等词的时候会出现如图候选词框过长的问题 并且不止一个有这个问题
删除1-3个候选词不是让你拉长候选词框的」。

* `row_budget = min(_style.max_width, grid_budget)`，其中 `_style.max_width` 就是主题键
  `style/layout/max_width`（当前 `1100`）—— 这份补丁以前完全没用它，框宽只看屏宽。
* 顺序：先 `--draw_cols`（最多丢 3 条，`min_cols = avail_cols - 3`、至少 1 列）；
  丢到 3 条仍超 → `col_width = max(row_budget / draw_cols, 120 + candidate_spacing)`，
  置 `cells_shrunk`，命中它的格子和固定格一样走 `…` 裁剪（**只裁绘制，候选文本不动**）。
* 实测 `gith`：9 条 × 272px = 2448 → 丢 3 条后 6 × 272 = 1632 > 1100 → 格宽压到 183 →
  面板 **1122x49**（旧行为 `1656x49`，几乎顶满 `1707` 的逻辑屏宽）。视觉复核一行 6 个：
  `1 GitHub · 2 GitHub Pages · 3 GitHub Actions · 4 GitHub Copilot · 5 GitHub Copilot… · 6 GitHub Codes…`。
* 代价（已知，与 §3.6.1 那条同源）：被丢掉的第 7–9 条**仍能被数字键选中**（服务端按下标算选词）。
* 想更宽/更窄就改主题 `style/layout/max_width`（`D:\rime-sandbox\weasel.custom.yaml`），
  改完必须重启 `WeaselServer`。诊断这类问题时曾临时在 `HorizontalLayout.cpp` 里加
  `VMENU_LAY_DEBUG`（把 `cols/c2d/cand/static/uni/colw/budget/roww/draw/maxw/screen/off/rm/scale`
  写进 `D:\rime-sandbox\vmenu-layout.log`）—— 定位完**已删除**，要复现就照这个字段表临时加回。

### 3.7 设置窗口里的双击编辑

```
用户双击列表某一行
  ├─ $clipList.Add_DoubleClick ─► Edit-Clipboard -Index ([int]$clipList.SelectedItems[0].Tag)
  └─ $favList.Add_DoubleClick  ─► Edit-Favorite  -Index ([int]$favList.SelectedItems[0].Tag)
```

| | 剪贴板页 `Edit-Clipboard` | 常用语页 `Edit-Favorite` |
| --- | --- | --- |
| 弹框标题 | `编辑第 N 条` | `修改常用语`（`Index = -1` 时是 `添加常用语`） |
| 输入框 | 单行文本框，**打开时全选原文** | 内容 + 编码两个框 |
| 确定后 | `Save-Clipboard` → `Refresh-Clipboard` | `Save-Favorites` → `Refresh-Favorites` |
| 状态栏 | `已修改第 N 条` | `已修改：<内容>` |
| 取消 / `Esc` | 直接 `return`，不写文件 | 直接 `return`，不写文件 |

* 两个列表项都在 `Tag` 里存了**数据索引**，所以双击取的是真实索引，不受排序/过滤影响。
* 常用语页的「修改选中」按钮复用同一个 `Edit-Favorite`，所以双击与按钮行为完全一致。
* 弹框是模态的（`ShowDialog($form)`），因此它是**顶层窗口**而不是子窗口 ——
  自动化测试里必须用 `EnumWindows` 找它，`Process.MainWindowTitle` 看不到（见 `TESTING.md`）。

### 3.8 托盘图标右键菜单的接管（「输入法设置 (S)」）

在**托盘图标右键菜单**里点第一项「输入法设置 (S)」，打开的也是 §3.5 那个常驻窗口。
这**不是新加的菜单项**（菜单有 12 项，仍然是 12 项），而是「**改一句菜单文字 + 顶替被调用的程序**」
两件可逆的事。

**为什么只能这么做**（源码核对结论）：

| 事实 | 说明 |
| --- | --- |
| 菜单是 `WeaselServer.exe` 里的**菜单资源** | `IDR_MENU_POPUP`（资源号 105）；菜单项的文字与命令号都写死在资源里 |
| **没有配置文件能新增菜单项** | `weasel.yaml` / `weasel.custom.yaml` 只能改候选窗口样式，改不了托盘菜单 |
| 服务端只做一件事 | 源码 `WeaselServer/WeaselServerApp.cpp` 的 `SetupMenuHandlers()`：**启动安装目录下的 `WeaselDeployer.exe` 并带参数** |
| 没有可用的扩展钩子 | `WeaselTrayIcon` 里的 `void CustomizeMenu(HMENU) {}` 是**空实现**，没有配置钩子；再加一个「**全新命令号**」的菜单项服务端不会处理（点了没反应） |

命令号（`include/resource.h`）与服务端动作的对应关系：

| 菜单项 | 命令号 | 服务端实际执行的 |
| --- | --- | --- |
| 输入法设置 (S) | `ID_WEASELTRAY_SETTINGS` = **40008** | `WeaselDeployer.exe`（**无参数**） |
| 重新部署 (R) | `ID_WEASELTRAY_DEPLOY` = 40002 | `WeaselDeployer.exe /deploy` |
| 用户词典管理 (D) | `ID_WEASELTRAY_DICT_MANAGEMENT` = 40010 | `WeaselDeployer.exe /dict` |
| 用户资料同步 (N) | `ID_WEASELTRAY_SYNC` = 40012 | `WeaselDeployer.exe /sync` |
| 其余项（帮助文档 / 参加讨论 / 检查新版本 / 程序文件夹 / 用户文件夹 / 日志文件夹 / 重启算法服务 / 退出算法服务…） | 40001–40016 中的其它值 | 打开网址 / 打开文件夹 / 检查更新 / 退出 |

> `include/resource.h` 里的其它命令号：`ID_WEASELTRAY_QUIT=40001`、`CHECKUPDATE=40003`、
> `FORUM=40004`、`HOMEPAGE=40005`、`INSTALLDIR=40006`、`USERCONFIG=40007`、`WIKI=40009`、
> `ENABLE_ASCII=40013` / `DISABLE_ASCII=40014`、`RERUN_SERVICE=40015`、`LOGDIR=40016`。

**接管链路**：

```
托盘右键「输入法设置 (S)」
  └─ 命令号 40008（ID_WEASELTRAY_SETTINGS）
      └─ WeaselServer.exe 启动  <InstallDir>\WeaselDeployer.exe  （无参数）
          └─ 这个位置现在是代理（vmenu-deployer-wrapper.cs 编译，本机 5632 字节）
              ├─ 无参数（托盘「输入法设置」）
              │    └─ powershell -NoProfile -ExecutionPolicy Bypass -File
              │         vmenu-settings-gui.ps1 -ShowNow
              │         ├─ 窗口没在跑 → 新实例启动并显示（标题「小狼毫 v 功能 · 可视化设置」）
              │         └─ 已在跑     → 写 open-settings.flag，常驻实例把窗口亮出来（§3.5）
              │       （找不到窗口脚本时退回原生对话框，避免「点了没反应」）
              └─ 带参数 /deploy /dict /sync
                   └─ 原样转发给 WeaselDeployer.real.exe（真正的部署器，工作目录 = 安装目录）
```

**安装脚本做的两件可逆的事**（`tools/vmenu-tray-setup.ps1`）：

1. **就地改菜单文字**：`输入法设定 (&S)` → `输入法设置 (&S)`。UTF-16 **等长替换**，
   只改最后 1 个汉字 `定`(U+5B9A) → `置`(U+7F6E)（2 个字节），字节偏移 `0x220E40`，
   不动任何偏移量 / 长度；改前确认命中 1 处，改完回读校验「旧标签 0 处 / 新标签 1 处」。
   exe 无数字签名，改它不破坏签名。
2. **安装代理**：真正的 `WeaselDeployer.exe` → `WeaselDeployer.real.exe`，
   再把 `vmenu-deployer-wrapper.cs` 编译出的代理放到 `WeaselDeployer.exe` 的位置。

**撤销链路**：

```
vmenu-tray-setup.ps1 -Revert
  ├─ 停 WeaselServer（运行中的 exe 被系统锁住，写不进去）
  ├─ 用 WeaselServer.exe.vmenu-bak 还原 WeaselServer.exe
  ├─ WeaselDeployer.real.exe 改名回 WeaselDeployer.exe
  ├─ 开始菜单「【小狼毫】输入法设置.lnk」名字还原
  ├─ 起 WeaselServer
  └─ 回读校验（期望 旧标签 1 处 / 新标签 0 处）
```

> 独立的一条：开始菜单里的 `【小狼毫】输入法设定.lnk` 会被改名为 `【小狼毫】输入法设置.lnk`；
> 它指向的也是 `WeaselDeployer.exe`，所以现在同样打开 vmenu 窗口。
> 原生设置对话框（标题 `【小狼毫】方案选单设定`）的入口因此挪到了设置窗口的
> 「小狼毫原生设置」分组里（等价于直接运行 `WeaselDeployer.real.exe`）。

### 3.9 `v` → 3 快捷输入（借用雾凇拼音的前缀）

> 历史：这一项最初挂在 `v`→`5`、共 9 项（含「星期」「日期时间」「部件拆字」）。
> 第十一轮 `v`→`3`/`v`→`5` 互换后，**现在是 `v`→`3`**（`v`→`5` 是原符号），
> 第十五轮精简为 **7 项**并把数字换成「项目字母」快捷键，第十九/二十轮排版改成一行（§3.6.1）。

**一句话**：子菜单里选中一项后，**把该功能的触发前缀直接写进输入框，然后把键盘完全交回原方案** ——
计算 / 日期 / 农历 / 数字大写 / Unicode 这些能力**本来就是雾凇拼音自带的**
（`recognizer/patterns` + `lua_translator`），本项目只是把前缀喂进去，**没有自己实现任何一个**。

**为什么不用自己实现**：rime-ice 已经带了 `calc_translator.lua`（计算）、`date_translator.lua`
（日期 / 时间）、`lunar.lua`（农历）、`number_translator.lua`（数字大写）、
`unicode.lua`（Unicode），每个都配好了 recognizer。
自己写一遍等于重造轮子，而且拿不到它们的边界处理（时区、大写规则、农历闰月…）。
把前缀填进去 = 直接复用，代价为零。

**链路**：

```
按 v        → lua_menu: yield_menu() 产出 5 个 vmenu 候选（第 3 项：快捷输入 / 计算·日期）
按 3        → menu_processor: cur == "v" 且 repr == "3" → replace_input(ctx, "vqi")   return 1
              （replace_input = ctx:clear() + ctx:push_input(前缀)，与 vclip / vfav 同一套）
顶层       → vmenu_core: mode_of("vqi…") = "quick"；want_type("quick") = "vqi"
              → lua_menu: yield_quick(seg) 产出 7 项
              → menu_filter: 只留 type == "vqi" 的候选（不会被原方案候选混进来）
按 1..7 或按项目字母 → menu_processor: cur == "vqi" → replace_input(ctx, 真前缀)        return 1
按 q       → menu_processor: replace_input(ctx, "v")（回主菜单）                        return 1
之后       → 输入框里只剩前缀，我们不再拦截任何键：原方案的 recognizer 命中，lua_translator 出候选
```

**7 项 → 快捷键 → 前缀 → 来源 → 实测**（数字映射按**屏幕上的渲染顺序**，见下面的坑）：

| 数字 | 字母 | 菜单文字 | 填入的前缀 | 来源 | 实测上屏 |
| --- | --- | --- | --- | --- | --- |
| 1 | `c` | 计算 | `cC` | `calc_translator.lua`（recognizer `^cC.+`） | `1+2*3` → **7**；`9*9` → **81** |
| 2 | `r` | 日期 | `rq` | `date_translator.lua` | **2026-09-13** |
| 3 | `s` | 时间 | `sj` | 同上 | **02:30**（`HH:MM`） |
| 4 | `n` | 农历输入 | `N` + 当天 `%Y%m%d` | `lunar.lua`（recognizer `^N[0-9]{1,8}`） | **丙午马年八月初三** |
| 5 | `h` | 数字货币转写 | `R` | `number_translator.lua`（recognizer `^R[0-9]+`） | 输入 `1234` → **一千二百三十四** |
| 6 | `u` | Unicode | `U` | `unicode.lua`（recognizer `^U[a-f0-9]+`，需要 `unicode` tag） | 输入 `4e2d` → **中** |
| 7 | `q` | 返回 | `v`（回主菜单） | — | — |

> 部件拆字**不再从这个菜单进**（第十五轮精简掉了），它直接打字：`u` + 部件拼音（`unvzi` → 好）。
> 「星期」「日期时间」也不再单独列项（想用就直接打 rime-ice 的前缀 `xq` / `dt`）。

**三个易踩的点**：

1. **`cC` 单独不出候选**：recognizer 是 `^cC.+`，**必须继续输入至少一个字符**（如 `1+2*3`），
   候选第一项才是结果。
2. **农历会把当天日期一起填进去**（`os.date("%Y%m%d")`）：所以按 `6` 立刻就能看到今天的农历；
   想查别的日子，把后面的数字改成那天的 `YYYYMMDD` 即可。
3. **`R` / `U` 后面要自己补内容**（`R1234`、`U4e2d`），它们的设计就是这样。

**部件拆字的前缀改动**（0.2.3）：rime-ice 原本的触发键是 `uU`（要打 `uUnvzi`），
本项目在 `rime_ice.custom.yaml` 里把它改成单字母 `u`（两行配置），
于是「直接打字」和「`v`→`5`→`9`」两条路都能用：`u`+`nvzi` → **好**，`u`+`riyue` → **明**。
相关结构（原有，未改）：`affix_segmentor@radical_lookup` + `table_translator@radical_lookup`
（`dictionary: radical_pinyin`）+ `reverse_lookup_filter@radical_reverse_lookup`。

> 副作用：**旧的 `uU` 写法失效**；以 `u` 开头的英文词也会被当成拆字。

**生效条件**：改完 lua **必须重启 `WeaselServer`**（Lua 模块有缓存），且
`D:\rime-sandbox\lua\` 与 `%APPDATA%\Rime\lua\` 两处文件要 **MD5 一致**
（`lua_filter` / `lua_processor` / `lua_translator` 各 require 一份，不一致会出现「菜单有、按键没反应」这类怪现象）。

### 3.10 v 功能的**显示层**：内部编码 → 中文名（服务端 `_VMenuLabel`）

v 功能的输入编码（`v` / `vclip` / `vqi` / `vfav` / `vset*`）是给 Lua 判断分支用的**内部约定**，
不该出现在用户眼前。但**行内预编辑显示的就是 composition 的 preedit**，而 librime 的 Lua API
没有「改 preedit」的接口 —— 所以只能在**服务端把上下文交给前端之前**改写，位置有两条：

| 通路 | 代码位置 | 谁在用 |
| --- | --- | --- |
| 字符串协议（逐行消息） | `RimeWithWeasel.cpp` `_Respond()` 里 `ctx.preedit=` / `ctx.preedit.cursor=` | 自己画候选窗的客户端，**TSF 全走这条**（Chrome / 记事本 等） |
| 结构体 | `RimeWithWeasel.cpp` `_GetContext()` → `weasel_context.preedit.str`（由 `_UpdateUI()` 调） | **非 TSF** 客户端（服务端面板 `m_ui`，如 WinForms 程序） |

映射表（`_VMenuLabel()`，任一不满足就原样下发）：

| 输入 | 显示 | 条件 |
| --- | --- | --- |
| `v` | 功能菜单 | 首字母必须 `v` |
| `vclip…` | 剪贴板 | 且 `vraw_mode` 为**假** |
| `vqi…` | 快捷输入 | 且 `vraw_mode` 为**假** |
| `vfav…` | 常用语 | 且 `vraw_mode` 为**假** |
| `vset…` | 设置 | 且 `vraw_mode` 为**假** |
| 其它（`shi`、`cC1+2*3`、原符号的 `v…`） | 原样 | — |

要点：

* **原符号模式必须排除**（`vraw_mode`，菜单第 5 项）—— 那里 `v` 开头是用户自己敲的符号编码，
  改掉会让用户看不见自己在打什么。
* 命中时**不下发高亮范围**（`ctx.preedit.cursor` 写「长度,长度,长度」），否则会拿旧编码的偏移
  去高亮新文案。
* 中文文案写成宽字符 `\uXXXX` + `wtou8()`：工程无 `/utf-8`，中文窄字符串会被按 GBK 编码输出。
* 同一套判断也决定**退格**行为：v 功能里按 Backspace = 整条输入作废（Lua 侧 `is_v_func()`），
  输入一空，显示层自然什么都不剩。
* **空格（0.2.21）**：v 功能里按空格先问 `ctx:get_selected_candidate()` —— 有真候选 → `return 2`
  放行给 rime 的 `Editor::Confirm`（上屏**高亮那条**，与普通选词手感一致，正常路径零改动）；
  拿不到候选 → **吞掉空格**；pcall 异常 → 退回原行为。
  根因（用户报障「v2按空格会有概率出现vclip」）：候选为 nil 时
  `Context::ConfirmCurrentSelection` 回退成「确认原始输入」→ `ctx->Commit()` →
  `Composition::GetCommitText` 对没有候选的段直接取 `input_.substr(...)`，于是字面量 `vclip`
  被打进文档。「有概率」= 按下瞬间撞上 nil 候选窗口（菜单重建 / 高亮越界 / 剪贴板缓存被
  clipboard-sync 重写）的概率。修在 `menu_processor.lua`「退格整条取消」分支之后。

## 4. 结构性配置（`build/rime_ice.schema.yaml`）

```yaml
engine:
  processors:
    - lua_processor@*menu_processor     # 必须早于 speller / selector
    # …（rime-ice 原有 processors）
  translators:
    - lua_translator@*lua_menu          # 菜单/列表候选
    # …（rime-ice 原有 translators）
  filters:
    - lua_filter@*menu_filter           # 放在其它 filter 之后也可以，见「quality 重排」
    # …（rime-ice 原有 filters）
```

`src/windows/patch-build-schema.ps1` 会用「解析 YAML → 改这几个键 → 写回」的方式保证幂等；
**不要**指望 `WeaselDeployer` 重新编译（见 `AGENT-HANDOFF.md` §1 的部署器坑）。

> 另外两组键写在**用户补丁**里（不是结构性配置，改完 `重建部署.bat` / 重启服务即可）：
> `menu/page_size: 36`（候选方格，见 §3.6）与 `radical_lookup/prefix: u` +
> `recognizer/patterns/radical_lookup: "^u[a-z]+$"`（部件拆字，见 §3.9）。
> `radical_lookup` 的 `affix_segmentor` / `table_translator`（`dictionary: radical_pinyin`）/
> `reverse_lookup_filter` 是 rime-ice **原有**结构，本次只改了前缀与 recognizer。

## 5. 设计约束与理由

| 约束 | 理由（真实事故） |
| --- | --- |
| 输入法进程内**不启动子进程** | 早期在 Lua 里用 `io.popen` 读剪贴板 → 输入法整个卡死 |
| filter **同时**保证 yield 顺序与 `quality` 递减 | 曾经出现「常用语跑到第 1/3 位」，因为候选表在 filter 之后还会按 quality 排 |
| 处理器里的每个分支都用 `pcall` 包住 | 任何异常都退化为「不处理」，绝不会让用户打不出字 |
| 普通打字路径**不碰磁盘** | 常用语命中要求 ≥ 3 字符才读文件，避免逐字符 IO |
| 窗口坐标运行时按客户区现算 | 进程 DPI 不感知，写死坐标会被系统缩放平移，按钮跑到窗口外 |
| 标记文件而不是 IPC/子进程 | 输入线程里做任何阻塞或创建进程都会拖慢打字 |
| 状态栏写 `$statusLabel.Text` | `$status` 是 `StatusStrip` 本身，写它什么都不会显示 |
| 方向键 / `+` **只在普通打字时**由我们接管（Lua 拦 `plus` 与方向键、**自编 DLL** 移动高亮），v 菜单内一律交回原版 `navigator` | `↓` = 收起时展开 / 已展开时跳下一行，`↑` = 第一行时收回 / 否则跳上一行，`←`/`→` = 行内移动，`+` = 下翻下一批 9 个。⚠️ **移动高亮只能在 DLL 里做**：Lua 没有这个 API，且 `ctx.select` 是**上屏**不是移动（见 §3.6、`GRID-CANDIDATE-DLL.md`） |
| **绝不调用 `ctx.select`**（以及任何想「移动高亮」的字段） | 它是「选中并上屏」：0.2.3 用它跳行，结果展开后按 `↓` 直接把候选打出去；而且 `ok=true err=nil`，`pcall` 挡不住、也不报错（0.2.4 已删掉这处调用） |
| 一页上限 / 原生序号列由「方案 + 主题」两个键决定（`menu/page_size`、`style/label_format`）；**换行规则、序号位置、方向键移动**由**自编 DLL 的三个补丁**决定；「这一屏放几个」与「`+` 下翻取哪 9 个」由 Lua 决定 | 换行 / 序号 / 方向键都在 `WeaselServer.exe` 里，配置与 Lua 都改不动（见 `GRID-CANDIDATE-DLL.md`）；候选**个数**可以在 filter 里截断 |
| **不要**用 rime 的 `menu/alternative_select_labels` 去改展开后的行序号 | 实测对 Weasel **完全无效**：写进 patch 会被整份拒绝（`page_size` 掉回 9、lua 挂载点消失），写进 `build` 产物 YAML 能过但序号列像素分布逐段不变（第 10 个之后的数字是面板按索引画的）。正确做法 = `label_format` 留空 + 注释写序号，见 §3.6 |
| 「是否展开」只能放在 **context option**（`vmenu_grid`）里，不能用模块级变量 | `lua_filter` 与 `lua_processor` 各自 `require` 一份模块，变量不共享（`vraw_mode` 同理） |
| ~~`ctx.selected_candidate_index`（1 基）与 `ctx:select(i)`（0 基）的换算只写在一处（`grid_sel`）~~ **这条约束是错的** | 实测那个字段**根本不存在**（探针 `nil`，旧代码一直把 `nil` 当 0 用）；`ctx.select` 则是「选中并上屏」。正确约束见上面两条：**别用 `ctx.select`**、**本机没有移动高亮的 API** |
| 快捷输入**不自己实现**计算 / 日期 / 农历 / 大写 / Unicode，只把前缀填进输入框 | 这些能力 rime-ice 自带且 recognizer 已配好，自己实现等于重造轮子还会丢边界处理（见 §3.9） |
| 改 `build/*.yaml` 只用 `[IO.File]::ReadAllText/WriteAllText`（UTF-8） | PS 5.1 的 `Get-Content`/`Set-Content` 按 ANSI 解码，写坏 YAML 后候选窗口完全不显示 |
| 改 `WeaselServer.exe` **必须先停 `WeaselServer`**，且只做 **UTF-16 等长替换** | 运行中的 exe 被系统锁住写不进去；等长替换不动偏移量 / 长度，不会破坏文件结构（详见 §3.8） |
| 托盘菜单**不去想「新增一项」**，只做「改名 + 顶替 `WeaselDeployer.exe`」 | 菜单项写死在 `WeaselServer.exe` 的资源里，服务端只认 `WeaselDeployer.exe` 这一个入口，新命令号不会被处理（详见 §3.8） |

## 6. 状态与持久化

| 状态 | 存在哪 | 谁写 |
| --- | --- | --- |
| 当前模式（菜单/剪贴板/常用语/快捷输入/原符号） | **输入码本身**（`v`、`vclip`、`vfav`、`vqi`、`vset…`）+ `vraw_mode` option | `menu_processor` |
| 剪贴板历史 | `clipboard-cache.txt` | `clipboard-sync.ps1`（也允许设置窗口改） |
| 常用语 | `cn_dicts/favorites.dict.yaml`（内部沿用旧名） | 设置窗口 / 用户手改 |
| 列表默认条数 | `vmenu-settings.txt` | 设置窗口 |
| 候选框是否展开 | **context option `vmenu_grid`**（进程内，随输入上下文销毁，不落盘） | `vmenu_core.grid_key`（`menu_processor` 调用） |
| 一页上限 / 原生序号列 | **不是这里的状态**：`menu/page_size`（方案）+ `style/label_format`（主题）；换行 / 序号 / 方向键则在**自编 DLL** 里 | 部署时改配置 + 重启服务；改源码补丁则走 CI + 换 5 个文件（`GRID-CANDIDATE-DLL.md`） |
| 打开窗口请求 | `open-settings.flag` | Lua 写、常驻窗口读后即删 |

没有任何常驻内存状态需要跨进程同步 —— 所有文件都是「最后写入者胜」，
设置窗口与输入法各自「读—改—写」，并通过 `.tmp` + rename 原子替换避免半截文件。
