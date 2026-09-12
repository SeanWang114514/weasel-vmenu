# 架构（ARCHITECTURE）

## 1. 总览

```
                  ┌─────────────────────────── 输入法进程（WeaselServer / librime）───────────────────────────┐
   按键 ────────► │ menu_processor.lua (lua_processor)                                                     │
                  │   ├─ 输入为空 + v          → push_input("v")            → 进入 v 菜单                  │
                  │   ├─ v + 1/2/3/4/5         → 写标记文件 / 切到 vclip,vfav,v（原符号）/vset            │
                  │   ├─ 纯数字编码前缀        → push_input(数字)，否则交给选字键                          │
                  │   └─ Return + 编码完全匹配 → engine:commit_text(收藏内容)                              │
                  │                                                                                        │
                  │ lua_menu.lua (lua_translator)  ── 产出候选行：vmenu / vclip / vfav / vset / vact        │
                  │ menu_filter.lua (lua_filter)   ── v 模式下只留所需候选；普通打字时把收藏插到候选第 2 位  │
                  │ vmenu_core.lua (require)       ── 路径、设置、剪贴板/收藏读写、命中判断、原符号标记      │
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
| `vmenu_core.lua` | 共享模块 | 路径解析（`rime_api.get_user_data_dir()`）、设置读写、剪贴板/收藏读写、`fav_hit` / `fav_exact` / `digit_prefix`、原符号标记 | 所有对外函数可被 `pcall` 包裹；不启动进程 |
| `menu_processor.lua` | `lua_processor@*` | 按键总管。**必须排在 `speller` / `selector` 之前**，否则数字会被当成选字键、`v` 会被当普通字母 | 只拦自己认识的键，其余一律 `return 2` |
| `lua_menu.lua` | `lua_translator@*` | 所有菜单/列表候选的文案与数据（菜单文案要改就改这里） | 候选 `type` 用于 filter 分流：`vmenu`/`vclip`/`vfav`/`vset`/`vact` |
| `menu_filter.lua` | `lua_filter@*` | ① v 模式：只保留当前模式需要的候选类型；② 普通打字：命中收藏时插入候选第 2 位 | 插位后必须重排 `quality`（严格递减） |
| `vmenu-settings-gui.ps1` | 常驻 WinForms | 三个标签页的可视化设置；轮询标记文件；改动即时写文件 | DPI 不感知 → 所有坐标在 `Layout-Tabs` 里按「实际客户区」现算，不能用 Dock/Anchor/写死坐标 |
| `vmenu-watcher.ps1` | 监督者 | 保证「常驻窗口永远有一个」；自身单实例 | 不杀进程、不做别的判断 |
| `clipboard-sync.ps1` | 独立进程 | 系统剪贴板 → 文本文件（去重、上限、新的在前） | 必须在输入法进程之外 |
| `patch-build-schema.ps1` | 部署工具 | 把结构性配置写回 `build\rime_ice.schema.yaml` | 幂等、可重复运行 |

## 3. 数据流（逐功能）

### 3.1 按 `v` 打开菜单

1. 输入为空时按下 `v`：`menu_processor` → `ctx:push_input("v")`，返回 1（已处理）。
2. `lua_menu` 看到输入 `v` → 产出 5 个 `vmenu` 候选（设置 / 剪贴板 / 收藏 / 原符号 / 文字设置）。
3. `menu_filter` 看到 `core.mode_of("v") == "menu"` → 只保留 `vmenu` + `vact`，其余全丢。
4. 按 `1`..`5`：`menu_processor` 的 `cur == "v"` 分支改写输入（`vclip` / `vfav` / `vset`）
   或写标记文件（设置窗口）。

### 3.2 剪贴板（`v`→`2`、`v`→`5`→`1`）

* 数据源是 `clipboard-cache.txt`（外部进程写，Lua 只读）。
* 显示条数由 `vmenu-settings.txt` 的 `clip_page` 决定，默认 20，范围 20–50。
* 列表里：`m`/`+` 每次多看 10 条，`-`/`=` 翻页，`d` 进删除模式，`x` 清空（二次确认页），`q` 返回。
* 分页、删除、清空都是**改写输入码**（`vsetc` + `m` 的个数等）实现的无状态重算，
  输入码本身就是状态，因此不需要额外变量。

### 3.3 收藏（`v`→`3` / 打字命中 / 回车调用）

| 场景 | 代码路径 | 规则 |
| --- | --- | --- |
| 搜索取用 | `vfav` 模式 + `fav_match` 过滤 | 编码或内容前缀匹配 |
| **打字预览** | `menu_filter` 普通分支 + `fav_hit(code)` | 输入长度 **≥ 3**，且输入是某条编码的前缀 → 收藏内容做成 `vfav` 候选插到索引 2 |
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
| filter **同时**保证 yield 顺序与 `quality` 递减 | 曾经出现「收藏跑到第 1/3 位」，因为候选表在 filter 之后还会按 quality 排 |
| 处理器里的每个分支都用 `pcall` 包住 | 任何异常都退化为「不处理」，绝不会让用户打不出字 |
| 普通打字路径**不碰磁盘** | 收藏命中要求 ≥ 3 字符才读文件，避免逐字符 IO |
| 窗口坐标运行时按客户区现算 | 进程 DPI 不感知，写死坐标会被系统缩放平移，按钮跑到窗口外 |
| 标记文件而不是 IPC/子进程 | 输入线程里做任何阻塞或创建进程都会拖慢打字 |
| 状态栏写 `$statusLabel.Text` | `$status` 是 `StatusStrip` 本身，写它什么都不会显示 |

## 6. 状态与持久化

| 状态 | 存在哪 | 谁写 |
| --- | --- | --- |
| 当前模式（菜单/剪贴板/收藏/设置/原符号） | **输入码本身**（`v`、`vclip`、`vfav`、`vset…`）+ `vraw_mode` option | `menu_processor` |
| 剪贴板历史 | `clipboard-cache.txt` | `clipboard-sync.ps1`（也允许设置窗口改） |
| 收藏 | `cn_dicts/favorites.dict.yaml` | 设置窗口 / 用户手改 |
| 列表默认条数 | `vmenu-settings.txt` | 设置窗口 / `v`→`5`→`3` |
| 打开窗口请求 | `open-settings.flag` | Lua 写、常驻窗口读后即删 |

没有任何常驻内存状态需要跨进程同步 —— 所有文件都是「最后写入者胜」，
设置窗口与输入法各自「读—改—写」，并通过 `.tmp` + rename 原子替换避免半截文件。
