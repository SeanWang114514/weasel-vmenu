# 架构（ARCHITECTURE）

## 1. 总览

```
                  ┌─────────────────────────── 输入法进程（WeaselServer / librime）───────────────────────────┐
   按键 ────────► │ menu_processor.lua (lua_processor)                                                     │
                  │   ├─ 输入为空 + v          → push_input("v")            → 进入 v 菜单                  │
                  │   ├─ v + 1/2/3/4         → 写标记文件 / 切到 vclip,vfav,v（原符号）                    │
                  │   ├─ 方向键 ↓↑←→          → 一律 return 2，交回 librime 原版 navigator                 │
                  │   ├─ 纯数字编码前缀        → push_input(数字)，否则交给选字键                          │
                  │   └─ Return + 编码完全匹配 → engine:commit_text(常用语内容)                            │
                  │                                                                                        │
                  │ lua_menu.lua (lua_translator)  ── 产出候选行：vmenu / vclip / vfav / vset / vact        │
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
| `vmenu_core.lua` | 共享模块 | 路径解析（`rime_api.get_user_data_dir()`）、设置读写、剪贴板/常用语读写、`fav_hit` / `fav_exact` / `digit_prefix`、原符号标记 | 所有对外函数可被 `pcall` 包裹；不启动进程 |
| `menu_processor.lua` | `lua_processor@*` | 按键总管。**必须排在 `speller` / `selector` 之前**，否则数字会被当成选字键、`v` 会被当普通字母 | 只拦自己认识的键，其余一律 `return 2` |
| `lua_menu.lua` | `lua_translator@*` | 所有菜单/列表候选的文案与数据（菜单文案要改就改这里） | 候选 `type` 用于 filter 分流：`vmenu`/`vclip`/`vfav`/`vset`/`vact`（`vset` 自第二轮起已不可从菜单进入，属保留代码） |
| `menu_filter.lua` | `lua_filter@*` | ① v 模式：只保留当前模式需要的候选类型；② 普通打字：命中常用语时插入候选第 2 位 | 插位后必须重排 `quality`（严格递减） |
| `vmenu-settings-gui.ps1` | 常驻 WinForms | 三个标签页的可视化设置；轮询标记文件；改动即时写文件；列表支持**双击编辑**；「设置与缓存」页底部还有 **`小狼毫原生设置`** 分组 + `打开小狼毫原生设置` 按钮（打开小狼毫自带的设置对话框） | DPI 不感知 → 所有坐标在 `Layout-Tabs` 里按「实际客户区」现算，不能用 Dock/Anchor/写死坐标 |
| `vmenu-deployer-wrapper.cs` | 代理（C#） | 顶替安装目录下的 `WeaselDeployer.exe`：**无参数** → 打开 vmenu 设置窗口（`vmenu-settings-gui.ps1 -ShowNow`）；**带参数** → 原样转发给 `WeaselDeployer.real.exe`（见 §3.8） | 用 `csc.exe /target:winexe /r:System.Windows.Forms.dll` 编译；源文件必须 UTF-8 **带 BOM**；找不到窗口脚本时退回原生对话框 |
| `vmenu-tray-setup.ps1` | 部署工具 | 托盘菜单入口的**安装 / 撤销**：改 `WeaselServer.exe` 里的菜单文字、安装代理、开始菜单快捷方式改名 | 幂等；`-Revert` 可还原；`WeaselServer.exe.vmenu-bak` 只在第一次安装时生成 |
| `vmenu-watcher.ps1` | 监督者 | 保证「常驻窗口永远有一个」；自身单实例 | 不杀进程、不做别的判断 |
| `clipboard-sync.ps1` | 独立进程 | 系统剪贴板 → 文本文件（去重、上限、新的在前） | 必须在输入法进程之外 |
| `patch-build-schema.ps1` | 部署工具 | 把结构性配置写回 `build\rime_ice.schema.yaml` | 幂等、可重复运行 |

## 3. 数据流（逐功能）

### 3.1 按 `v` 打开菜单

1. 输入为空时按下 `v`：`menu_processor` → `ctx:push_input("v")`，返回 1（已处理）。
2. `lua_menu` 看到输入 `v` → 产出 **4 个** `vmenu` 候选（设置 / 剪贴板 / 常用语 / 原符号）。
3. `menu_filter` 看到 `core.mode_of("v") == "menu"` → 只保留 `vmenu` + `vact`，其余全丢。
4. 按 `1`..`4`：`menu_processor` 的 `cur == "v"` 分支写标记文件（设置窗口）或改写输入
   （`vclip` / `vfav` / 原符号模式）；**其余按键 `return 2` 放行** ——
   第 5 项「文字设置」已从菜单去掉，`vset*` 只有手打 `vset` 才进得去。

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
| 纯数字编码 | `digit_prefix(code)` + 数字接管分支 | 输入为空或全数字，且「已输入 + 新按键」仍是一条**纯数字编码**的前缀 → 把数字并进编码 |

`fav_hit`（前缀，用于预览）与 `fav_exact`（完全一致，用于回车）**故意分开**：
预览要「早」（3 位就出现），回车要「准」（不能抢走正常的原始输入）。

### 3.4 原符号模式（`v`→`4`）

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

### 3.6 候选框渲染（多行候选 + 方向键）

**候选框的形状完全由「主题 + 方案」决定**，与 Lua 无关，也不能运行时切换。

| 决定什么 | 键 | 文件 | 现在的值 |
| --- | --- | --- | --- |
| 是否换行 / 每行几个 | `style/layout/max_width` | Weasel 主题：`weasel.custom.yaml` →（编译产物）`build/weasel.yaml` | `300`（`0` = 不换行） |
| 一页几条 | `menu/page_size` | 方案：`rime_ice.custom.yaml` →（编译产物）`build/rime_ice.schema.yaml` | `18`（原来 `9`） |

* 组合效果：一页 18 条，按 `300` 宽度折行，约 **4 行 × 5 列**。
  实测 `620` **不换行**（自然宽度还没超），`300` 才换行 —— 想改列数就调这个值。
* 两个键都是 `build/*.yaml` 里的值真正生效，改完**必须重启 `WeaselServer`**；
  回退 = `max_width` 回 `0`、`page_size` 回 `9`。
* ⚠️ 改这两个文件必须用 UTF-8 读写（`[IO.File]::ReadAllText/WriteAllText`）。
  PS 5.1 的 `Get-Content`/`Set-Content` 默认按 ANSI 解码，会把 YAML 写坏，
  表现为**候选窗口完全不显示**（见 `TROUBLESHOOTING.md`）。

**方向键**：`↓` / `↑` / `←` / `→` **Lua 一律不拦截**（`menu_processor.lua` 里明确注释了这一点），
全部交回 librime 原版 `navigator`。实测（librime 1.13.1，横向候选框）：
`↓` = 选中下一个候选，`→` = 选中下一个候选，`↑` = 上一个，都不上屏。
之所以不自己实现方向键：一旦 Lua 吞掉这些按键，既会破坏原版手感，也会在多行候选框下
和 Weasel 自己的换行/翻页逻辑打架。

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
| **Lua 一律不拦截方向键**（`↓↑←→` 不写进任何分支） | 原版 `navigator` 已经是对的（`↓`/`→` = 下一个候选），自己接管会和 Weasel 的换行/翻页逻辑打架 |
| 候选框行列数只由「主题 + 方案」两个键决定，**不放进 Lua** | 换行是 Weasel 主题 `style/layout/max_width` 的渲染行为，一页条数是 schema 的 `menu/page_size`，Lua 里没有任何接口能改 |
| 改 `build/*.yaml` 只用 `[IO.File]::ReadAllText/WriteAllText`（UTF-8） | PS 5.1 的 `Get-Content`/`Set-Content` 按 ANSI 解码，写坏 YAML 后候选窗口完全不显示 |
| 改 `WeaselServer.exe` **必须先停 `WeaselServer`**，且只做 **UTF-16 等长替换** | 运行中的 exe 被系统锁住写不进去；等长替换不动偏移量 / 长度，不会破坏文件结构（详见 §3.8） |
| 托盘菜单**不去想「新增一项」**，只做「改名 + 顶替 `WeaselDeployer.exe`」 | 菜单项写死在 `WeaselServer.exe` 的资源里，服务端只认 `WeaselDeployer.exe` 这一个入口，新命令号不会被处理（详见 §3.8） |

## 6. 状态与持久化

| 状态 | 存在哪 | 谁写 |
| --- | --- | --- |
| 当前模式（菜单/剪贴板/常用语/原符号） | **输入码本身**（`v`、`vclip`、`vfav`、`vset…`）+ `vraw_mode` option | `menu_processor` |
| 剪贴板历史 | `clipboard-cache.txt` | `clipboard-sync.ps1`（也允许设置窗口改） |
| 常用语 | `cn_dicts/favorites.dict.yaml`（内部沿用旧名） | 设置窗口 / 用户手改 |
| 列表默认条数 | `vmenu-settings.txt` | 设置窗口 |
| 候选框行列数 | **不是这里的状态**：主题 `style/layout/max_width` + schema `menu/page_size` | 部署时改配置 + 重启服务 |
| 打开窗口请求 | `open-settings.flag` | Lua 写、常驻窗口读后即删 |

没有任何常驻内存状态需要跨进程同步 —— 所有文件都是「最后写入者胜」，
设置窗口与输入法各自「读—改—写」，并通过 `.tmp` + rename 原子替换避免半截文件。
