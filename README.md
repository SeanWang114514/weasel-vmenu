# weasel-vmenu · 小狼毫输入法「v 功能菜单」

给小狼毫（Weasel / librime）加一套 **v 功能菜单**：可视化设置窗口、剪贴板历史、收藏快捷输入，
以及「原符号输入」还原。全部用 **librime-lua + PowerShell 5.1** 实现，不改输入法源码、不重新编译。

> **English TL;DR** — A Lua + PowerShell extension pack for the
> [Weasel](https://github.com/rime/weasel) IME on Windows (built and verified against
> Weasel 0.17.4 + librime 1.13.1 + [rime-ice](https://github.com/iDvel/rime-ice)):
> press `v` for a menu (`1` 设置 / `2` 剪贴板 / `3` 收藏 / `4` 原符号 / `5` 文字设置).
> Includes a **resident WinForms settings GUI** that opens in ~0.1 s, a clipboard-history
> quick picker, favourite snippets that appear as **candidate #2 while you type their code**
> (Enter invokes them), and the isolation/tooling to verify everything with screenshots.
> Source in `src/`, verification harness in `tools/`, docs in `docs/`.
> See [`docs/AGENT-HANDOFF.md`](docs/AGENT-HANDOFF.md) before changing anything.

---

## 1. 它是什么

按 `v` 打开功能菜单（候选栏里只有 5 个短词）：

| 候选 | 功能 | 说明 |
| --- | --- | --- |
| `1 设置` | 可视化设置窗口 | 常驻进程，`v`→`1` 后约 **0.1 秒**出现窗口 |
| `2 剪贴板` | 剪贴板快查 | 后台脚本同步系统剪贴板到文本文件，Lua 只读文件 |
| `3 收藏` | 收藏快查 | 可继续输入编码过滤 |
| `4 原符号` | 还原原版 `v` 模式 | 之后直接输入符号编码（`2` → 二 贰 ² ₂ Ⅱ …） |
| `5 文字设置` | 纯键盘设置 | 和图形窗口共用同一批配置文件 |

除菜单外还有两条「不用按 v」的能力：

* **收藏候选第 2 位**：正常打字时键入收藏编码的**前 3 位**，内容直接出现在候选第 2 位。
* **编码打完 + 回车 = 直接调用**：输入与某条收藏编码**完全一致**时，回车把收藏内容上屏
  （字母编码、纯数字编码都支持）。

## 2. 界面

### 输入法候选栏

| 截图 | 说明 |
| --- | --- |
| ![v 菜单](screenshots/ime-01-menu.png) | 按 `v`：5 个短候选（设置 / 剪贴板 / 收藏 / 原符号 / 文字设置） |
| ![收藏候选](screenshots/ime-02-favorite-inline.png) | 打字时输入编码前 3 位 `you`，候选第 2 位就是收藏内容 `alice@example.com`（注释「收藏」） |
| ![回车调用](screenshots/ime-03-favorite-enter.png) | 编码打完按回车，内容直接上屏 |
| ![数字编码收藏](screenshots/ime-04-digit-favorite.png) | **纯数字编码**：输入 `138` → 候选直接显示 `13800138000`，回车调用 |
| ![收藏快查](screenshots/ime-05-favorite-list.png) | `v`→`3` 收藏快查列表 |

### 可视化设置窗口（三个标签页）

| 截图 | 说明 |
| --- | --- |
| ![剪贴板历史](screenshots/gui-01-clipboard.png) | 剪贴板历史：复制到剪贴板 / 删除选中 / 清空全部（二次确认）/ 重新载入 / 置顶，双击某条也能复制 |
| ![收藏内容](screenshots/gui-02-favorites.png) | 收藏内容：添加 / 修改 / 删除 / 清空（二次确认）/ 上移 / 下移；改动**立即**对输入法生效 |
| ![设置与缓存](screenshots/gui-03-settings.png) | 设置与缓存：列表默认条数（20–50）、缓存清理、文件位置一览 |

> README 里的截图全部使用**示例数据**（`alice@example.com`、`13800138000` 等），
> 不包含任何真实剪贴板或收藏内容。

## 3. 安装

### 3.1 依赖

| 组件 | 版本（本仓库验证过的） |
| --- | --- |
| [Weasel 小狼毫](https://github.com/rime/weasel) | 0.17.4（librime 1.13.1） |
| 方案 | [rime-ice 雾凇拼音](https://github.com/iDvel/rime-ice)（`rime_ice` schema，带 `lua/` 目录） |
| PowerShell | Windows PowerShell 5.1（不需要 PowerShell 7） |

### 3.2 部署 Lua 侧

1. 把 `src/lua/*.lua` 复制到 **Rime 用户目录**的 `lua/` 下：

   ```
   <RimeUserDir>\lua\vmenu_core.lua
   <RimeUserDir>\lua\menu_processor.lua
   <RimeUserDir>\lua\menu_filter.lua
   <RimeUserDir>\lua\lua_menu.lua
   ```

   `<RimeUserDir>` 可以用注册表读到（本机是 `D:\rime-sandbox`）：

   ```powershell
   (Get-ItemProperty 'HKCU:\Software\Rime\Weasel').RimeUserDir
   ```

2. 在方案里注册 Lua 组件。**这一步必须落到编译后的 `build\rime_ice.schema.yaml`**：
   Weasel 的部署器只从 `*.custom.yaml` 读取 `engine/processors|translators|filters`、
   `punctuator/symbols`、`recognizer/patterns` 这些**结构性**配置，而且当
   librime 的 `DetectModifications` 判定「无改动」时会**直接中止整个部署**。
   本仓库的 `src/windows/patch-build-schema.ps1` 就是把这几个键的语义直接写回
   `build/rime_ice.schema.yaml`，再重启服务（可重复运行）：

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\patch-build-schema.ps1 -RimeDir "D:\rime-sandbox"
   ```

   需要写入的关键片段（详见 `docs/ARCHITECTURE.md`）：

   ```yaml
   engine:
     processors:
       - lua_processor@*menu_processor   # 必须排在 speller / selector 之前
     translators:
       - lua_translator@*lua_menu        # 生成 v 菜单 / 剪贴板 / 收藏 / 设置的行
     filters:
       - lua_filter@*menu_filter         # v 模式过滤 + 收藏插到候选第 2 位
   ```

3. 重启 `WeaselServer.exe`（Lua 是运行时加载的，改完必须重启服务才生效）：

   ```powershell
   Get-Process WeaselServer | Stop-Process -Force
   Start-Process 'C:\Program Files\Rime\weasel-0.17.4\WeaselServer.exe'
   ```

### 3.3 部署 Windows 侧（后台服务 + 设置窗口）

把 `src/windows/` 整个目录放到任意位置（脚本用 `%~dp0` / 同目录互相调用），然后：

```powershell
# 双击即可：先停掉旧实例，再启动两个服务，并顺手打开设置窗口
.\clipboard-sync.bat
```

它会启动：

| 脚本 | 作用 |
| --- | --- |
| `clipboard-sync.ps1` | 每 1 秒把系统剪贴板同步进 `<RimeUserDir>\clipboard-cache.txt`（去重、上限 50、新的在前） |
| `vmenu-watcher.ps1` | 守护**常驻**的设置窗口进程（`vmenu-settings-gui.ps1`）；单实例互斥 |
| `vmenu-settings-gui.ps1` | WinForms 设置窗口本体，常驻后台，每 60 ms 看一次 `open-settings.flag` |

**启动方式**有三种，任选：

* 输入法里 `v` → `1`（最快，约 0.1 秒）；
* 双击 `打开设置.bat`（先写标记文件，再拉起守护脚本）；
* 双击 `clipboard-sync.bat`（重启服务并打开窗口）。

设置窗口右上角 **× 只是隐藏**，进程留在后台（所以下次还是秒开）。
彻底退出：运行 `vmenu-watcher-stop.ps1`，或在任务管理器里结束标题为
「小狼毫 v 功能 · 可视化设置」的 powershell 进程。

## 4. 配置与文件格式

| 文件（相对 `<RimeUserDir>`） | 内容 |
| --- | --- |
| `clipboard-cache.txt` | 剪贴板历史，UTF-8 **无 BOM**，一行一条，最新在最前 |
| `cn_dicts/favorites.dict.yaml` | 收藏，正文在 `...` 之后：`内容<Tab>编码<Tab>词频` |
| `vmenu-settings.txt` | `clip_page=20`（列表默认显示条数，20–50） |
| `open-settings.flag` | 「打开设置窗口」标记文件，平时不存在（被守护进程秒删） |

详细格式说明见 [`docs/FILE-FORMATS.md`](docs/FILE-FORMATS.md)；
示例数据见 [`examples/`](examples/)。

### 收藏的匹配规则（重要）

| 你输入 | 结果 |
| --- | --- |
| 编码 `you`，键入 `you`（= 前 3 位） | 候选第 2 位出现收藏内容，按 `2` 上屏 |
| 编码 `you` 打完，按 **回车** | 收藏内容直接上屏 |
| 编码 `138`（纯数字），键入 `138` | 数字本来会被当成「选字键」，由 `menu_processor` 接管后进入编码；候选即收藏内容 |
| 输入 `12345`（不是任何编码） | 完全按原样输入，回车也是原样 |
| 英文 / ASCII 模式 | v 功能整体关闭，收藏也不会插进候选 |

## 5. 目录结构

```
weasel-vmenu/
├── README.md                     ← 你在这里
├── CHANGELOG.md                  ← 版本与里程碑
├── docs/
│   ├── PROGRESS.md               ← 进度记录：做了什么、怎么验证、实测数据
│   ├── AGENT-HANDOFF.md          ← 给下一个 agent 的交接说明（先读这个再改代码）
│   ├── ARCHITECTURE.md           ← 架构、数据流、设计约束与不变量
│   ├── FILE-FORMATS.md           ← 各配置/数据文件格式
│   ├── TESTING.md                ← 截图验证与自动化测试工具
│   └── TROUBLESHOOTING.md        ← 常见问题
├── src/
│   ├── lua/                      ← 输入法侧（复制到 <RimeUserDir>\lua\）
│   └── windows/                  ← 后台服务 / 设置窗口 / 启动脚本（含 .bat）
├── tools/                        ← 验证工具（截图、聚焦、按键、延迟测试）
├── examples/                     ← 示例数据与示例配置
└── screenshots/                  ← README 里用到的截图（全部为示例数据）
```

## 6. 测试

```powershell
# 1) v 功能菜单全流程截图（需要记事本 + 已启动服务）
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run-vmenu-tests.ps1

# 2) v→1 的端到端延迟（真按键，测到窗口出现在屏幕上为止）
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\v1-e2e-test.ps1

# 3) 只测标记文件 → 窗口出现（不含按键）
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\v1-latency-test.ps1 -Runs 3
```

实测（本机 2560×1440 / 150%）：

| 指标 | 数值 |
| --- | --- |
| 标记文件 → 窗口出现在屏幕上（稳态） | **45 / 56 / 63 / 71 / 72 ms** |
| 真按 `v` → `1` → 窗口出现 | **84 / 94 / 103 / 106 ms**（改动前是 2–4 秒） |
| 后台进程刚启动后的第一次显示 | 106–180 ms（窗口在启动时已离屏预建；不做预建约 348 ms） |

详见 [`docs/TESTING.md`](docs/TESTING.md)。

## 7. 已知限制

* **候选栏里的操作行点不动**：小狼毫的鼠标点击 = 「提交这一条候选文字」，不经过按键处理链，
  所以「显示更多」这类操作行必须用键盘（`m` / `+`）。这是 Weasel 的机制，不是本项目的 bug。
* 收藏的「打字命中」需要编码 **≥ 3 位**（不足 3 位的编码请用 `v`→`3`）；纯数字编码需要把编码打完。
* 常驻设置窗口是一个 PowerShell + WinForms 进程，约占 150 MB 内存 —— 这是「秒开」的代价。
* 设置窗口是 DPI 不感知的，在 150% 缩放下由 Windows 整体放大，布局正确但文字略软。
* 剪贴板多行内容会被压平成一行（缓存格式一行一条）。
* 本项目只针对 **Weasel + rime-ice** 验证过；其它方案需要自己补 `engine/*` 注册与
  `recognizer/patterns`（见 `docs/ARCHITECTURE.md`）。

## 8. 许可

[MIT](LICENSE)。`src/lua/` 里的 `vmenu_*.lua` 为本项目新增；
`menu_processor.lua` / `menu_filter.lua` / `lua_menu.lua` 以 rime-ice 的 Lua 惯例编写。
