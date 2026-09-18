# 候选窗口「按键展开」——改 Weasel 源码重编 DLL 的完整记录

> 本文记录**唯一一处必须改输入法本体源码**才能做到的功能：候选窗口的
> 「默认单行 9 个 ⇄ 按 `↓` 展开 4 行 × 9 列、序号画在词前、方向键移动选中项」。
>
> 除了本文这些改动，插件的其它功能全部靠 Lua + YAML 实现（见 `ARCHITECTURE.md`）。
>
> 源码仓库：[`SeanWang114514/weasel-vmenu`](https://github.com/SeanWang114514/weasel-vmenu)
> 分支 **`weasel-grid-build`**（= 插件仓库的 `main` 之外的第二个分支），
> 本地克隆在 `D:\weasel-build\weasel`。

---

## 1. 为什么必须改 DLL

最初的想法是「不动源码，只用主题 + Lua 凑出来」，实测**做不到**，原因是这两件事都发生在
`WeaselServer.exe` 里，YAML 和 Lua 都碰不到：

| 想要的效果 | 由谁决定 | 只改配置能不能做到 |
|---|---|---|
| 候选窗口换行成 4 行 × 9 列 | `WeaselUI/HorizontalLayout.cpp` 的排版算法（按累计宽度折行） | ❌ `max_width` 只能整体截断，列数 = 宽度 / 格宽，**不是**「每 9 个换行」 |
| 方向键移动选中项 | `RimeWithWeasel/RimeWithWeasel.cpp` 的按键预处理 | ❌ Lua 没有「移动高亮」的 API（见 `AGENT-HANDOFF.md` 约束 22） |
| 序号画在候选**词的前面** | `WeaselUI/*Layout.cpp` 的标签槽 → 候选词 → 注释 三段式顺序 | ❌ 注释永远在词后面；`label_format` 只能套模板，不能「按高亮行重新编号」 |

**关键事实**：候选窗口是 **`WeaselServer.exe` 画出来的**，不是 TSF 客户端 DLL。
所以排版补丁和按键补丁**都链接进 `WeaselServer.exe`**；`weasel.dll` / `weaselx64.dll`
只负责「把按键和上下文送到 server」，这次改动对它们是透明的。

但**部署时三个文件都要换**，原因见 §4。

---

## 2. 三个补丁

### 2.1 排版：每 9 个换行，≤9 个绝不换行

文件：`WeaselUI/HorizontalLayout.cpp`（`DoLayout`）

原版按「累计宽度有没有超过 `max_width`」决定换行，于是
「9 列」会随字体、字号、候选长度漂移，永远凑不准。改成**按个数**换行：

```cpp
const int kGridCols = 9;
const bool grid_multi_row = (candidates_count > kGridCols);
const bool vmenu_line_break =
    grid_multi_row && i > 0 && (i % kGridCols) == 0;
```

* 候选 **≤ 9**：完全不换行 → 窗口宽度随内容变长（用户要求「不许丢候选、必须一行」）。
* 候选 **> 9**：每 9 个换行 → 展开 36 个正好 4 行 × 9 列。

> `style/layout/max_width` 因此**不再参与**网格排版（现在设成 `1100` 只是兜底），
> 不要再花时间调它。

### 2.2 序号：写进「标签槽」，按高亮行 1–9，词前

文件：`WeaselUI/HorizontalLayout.cpp` + `.h`（覆写 `GetLabelText`）

一格候选的渲染顺序是 **标签 → 候选词 → 注释**，只有**标签槽**在词的左边。
所以序号必须走标签槽：

```cpp
std::wstring HorizontalLayout::GetLabelText(const std::vector<Text>& labels,
                                            int id,
                                            const wchar_t* format) const {
  const int kGridCols = 9;
  const int hl_row = this->id / kGridCols;   // 高亮在第几行（0 基）
  const int row = id / kGridCols;
  if (row == hl_row) return std::to_wstring(id % kGridCols + 1) + L" ";
  return L"  ";                              // 其它行给两个空格，保证左边缘对齐
}
```

为什么**不能**用注释（`menu_filter.lua` 里那个 `number_row1` 已经删掉）：

1. 注释渲染在词的**后面**，实测是「这个**1** 这股**2**」——与「数字在词前」相反；
2. 注释是**翻译阶段**由过滤器生成的，移动高亮**不会重跑过滤器**，所以注释里的序号
   永远钉在第一行，不可能「按高亮行重新编号」；
3. 标签槽是**每次绘制**都重算的，天然跟随高亮。

`this->id` 是当前高亮候选的索引（`Layout` 构造时取 `_context.cinfo.highlighted`）。

> 本机主题把 `style/label_format` 设成 `" "`（只有空格、**没有 `%s`**），模板会把标签
> 文字整个吃掉，所以这里**故意不走模板**，直接返回数字。

行为对照（`zhe'g`，视觉实测）：

| 状态 | 第一行 | 第 2–4 行 |
|---|---|---|
| 收起（9 个） | `1 这个 2 这股 3 遮盖 …` | —（只有一行） |
| 展开、高亮在第 1 行 | 同上 | 无序号 |
| 展开、按 `↓↓` 高亮到第 2 行 | 无序号 | `1 这关 2 遮光 …`（**重新编号**） |

### 2.3 按键：网格态下方向键移动选中项

文件：`RimeWithWeasel/RimeWithWeasel.cpp`（`ProcessKeyEvent` 内）

```cpp
if (!(keyEvent.mask & ibus::Modifier::RELEASE_MASK) &&
    rime_api->get_option(session_id, "vmenu_grid")) {
  int delta = 0;
  if (keyEvent.keycode == ibus::Down)  delta = +9;   // 下一行
  else if (keyEvent.keycode == ibus::Up)   delta = -9;
  else if (keyEvent.keycode == ibus::Left) delta = -1;
  else if (keyEvent.keycode == ibus::Right)delta = +1;
  if (delta) {
    RIME_STRUCT(RimeContext, ctx);
    rime_api->get_context(session_id, &ctx);
    int current = ctx.menu.highlighted_candidate_index;
    int count   = ctx.menu.num_candidates;
    int target  = current + delta;
    if (target >= 0 && target < count) {
      HighlightCandidateOnCurrentPage((size_t)target, ipc_id, eat);
      m_active_session = ipc_id;
      return TRUE;                                   // 吞掉，不给原生导航器
    }
  }
}
```

* 只在 option `vmenu_grid` 打开时生效 → **普通打字的手感完全不变**。
* 越界时**不吞键**，落回 `rime_api->process_key`（比如第 1 行按 `↑`，交给 Lua 做「收起」）。
* 复用的 `HighlightCandidateOnCurrentPage` 就是**鼠标悬停选词**走的那条服务端通路
  （`WeaselTSF/CandidateList.cpp` → `WeaselIPC` → `WeaselServerImpl.cpp`），
  所以它不会上屏、只移动高亮。

> ⚠️ `include/KeyEvent.h` 里 `Keycode::Down` 与 `ibus::Down` 是**同一个枚举**，
> 键盘映射不用担心（`WeaselTSF/KeyEvent.cpp` 把 `VK_DOWN` → `ibus::Down`）。

---

## 3. Lua 侧（跟着 DLL 一起才是完整体验）

DLL 只提供「能不能」；「什么时候」由 Lua 通过 context option `vmenu_grid` 控制。

| 文件 | 作用 |
|---|---|
| `vmenu_core.lua` | `GRID_COLS = 9` / `GRID_ROWS = 4` / `GRID_OPTION = "vmenu_grid"`；`grid_key()`：`↓` 收起时置位、已展开不动作；`↑` 第 1 行清位（收起）；`←/→` 放行 |
| `menu_filter.lua` | 收起放 `min(9, n)` 个、展开放 `min(36, n)` 个；**下翻**页码切片（见 §3.1） |
| `menu_processor.lua` | 新一次输入时复位 `vmenu_grid` 与下翻页码；`+` → 下翻；方向键交给 `grid_key` |

**状态必须放 context option**：`lua_processor` 与 `lua_filter` **各自 require 一份** Lua
模块，模块级变量不共享（`vraw_mode` 也是同一套路）。

### 3.1 `+` 号下翻（用户要求「保留 + 号下翻选择预选词」）

收起态一行只有 9 个，第 10 个以后够不着。按 `+` 把可见窗口整体后移 9 个：

* `vmenu_core.lua`：`PAGE_OPTION = "vmenu_page"` + `GRID_PAGES = 4`。option 只能存布尔，
  所以用 `vmenu_page_0..3` 四个开关表示页码 0–3；`page_next()` 到头回到第 0 页。
* `menu_filter.lua`：收起态取 `buf[page*9+1 .. page*9+9]`（翻过头回第 0 页，绝不留空窗口）。
* `menu_processor.lua`：`repr == "plus"`（rime 里 `KP_Add → send: plus`）→ `page_next()` 并吞掉键。

实测（`zhe'g`，视觉读出）：

| 页 | 候选 |
|---|---|
| 第 0 页 | 这个 这股 遮盖 组合柜 赵河沟 这给 鹧鸪 这跟 这更 |
| 按 `+` 第 1 页 | 这关 遮光 这该 这罐 这瓜 这锅 这根 这歌 折光 |
| 按 `+` 第 2 页 | 折股 这鬼 折桂 浙赣 蜇过 折干 综合岗 综合股 综合馆 |

**注意**：`+` 在 rime 原生绑定里是**标点**，会「提交当前候选 + 插入 `+`」（实测
`zhe` 直接上屏成「着+」）。这条 Lua 接管是唯一能把它变成下翻的地方；
`=`（`equal`）本来就被 rime 绑成 `Page_Down`，不用动。

---

## 4. 编译（GitHub Actions）与部署

### 4.1 为什么用 CI 而不是本机

本机没有 VS2022/v143 + ATL + boost 的完整环境，而 Weasel 需要
`weasel.sln`（VS2026 打开、平台工具集 v143）+ 预编译 boost。CI 的坑与解法：

| 坑 | 现象 | 解法 |
|---|---|---|
| ATL 库路径 | `atls.lib` 找不到 | `Directory.Build.props` 追加 `$(VCToolsInstallDir)atlmfc\lib\$(PlatformShortName)` |
| boost 下载 | 每轮重编 30 分钟 | 缓存 `boost-184-all-b2-v2-${{ runner.os }}`；`ci/build-boost.ps1` 结尾必须 `exit 0` |
| `-Include` 不递归 | 发布包里**漏掉 `WeaselServer.exe`**（run#22 的真实事故） | 打包改用 `-Filter`，并加「缺文件就告警」 |
| 工具集选择 | v18.9.2 下 `b2` 报错 | `ci/select-toolset.ps1`（同样 `exit 0` 收尾） |

产物发布成 release：tag = `weasel-grid-<run 号>`，资产有
**`weasel-grid-dlls.zip`**（三个文件：`weasel.dll` x86 / `weaselx64.dll` x64 / `WeaselServer.exe`）
和 `build-output.log`（完整编译日志）。

> ⚠️ 资产名**不是** `weasel-grid-<N>.zip`（那个是 GitHub 自动打的源码包）。
> 下载地址：
> `https://github.com/SeanWang114514/weasel-vmenu/releases/download/weasel-grid-<N>/weasel-grid-dlls.zip`

**查 CI 进度不要循环打 GitHub API**（未认证 60 次/小时会打爆），两个可靠办法：

```powershell
# a) 看 tag 有没有出现（出现 = 构建完成并已发布）
git ls-remote --tags vmenu | Select-String 'weasel-grid-\d+$'

# b) 看 Actions 页面里有没有 "In progress"（不需要 API）
(Invoke-WebRequest 'https://github.com/SeanWang114514/weasel-vmenu/actions/workflows/build-weasel.yml').Content -match 'In progress'
```

### 4.2 部署（**三个文件 + 两个系统目录，缺一不可**）

```powershell
# 0. 备份（先建时间戳目录）
$bak = "D:\weasel-build\dll-backup\$(Get-Date -Format yyyyMMdd-HHmmss)"
New-Item -ItemType Directory -Force -Path $bak | Out-Null
Copy-Item 'C:\Program Files\Rime\weasel-0.17.4\weasel*.dll','C:\Program Files\Rime\weasel-0.17.4\WeaselServer.exe' $bak -Force

# 1. 停服务（运行中的 exe 被锁，写不进去）
Get-Process WeaselServer -ErrorAction SilentlyContinue | Stop-Process -Force

# 2. 安装目录的三个文件
Copy-Item <解压目录>\weasel.dll      'C:\Program Files\Rime\weasel-0.17.4\' -Force
Copy-Item <解压目录>\weaselx64.dll   'C:\Program Files\Rime\weasel-0.17.4\' -Force
Copy-Item <解压目录>\WeaselServer.exe 'C:\Program Files\Rime\weasel-0.17.4\' -Force

# 3. ★ TSF 客户端 DLL 不在安装目录！★
Copy-Item <解压目录>\weaselx64.dll 'C:\Windows\System32\weasel.dll'  -Force
Copy-Item <解压目录>\weasel.dll    'C:\Windows\SysWOW64\weasel.dll'  -Force

# 4. 起服务 + 重启要测试的程序（TSF 是进程内 DLL，老进程里还是旧代码）
Start-Process 'C:\Program Files\Rime\weasel-0.17.4\WeaselServer.exe'
```

**第 3 步是最容易漏、漏了还查不出来的地方**：注册表
`HKLM\SOFTWARE\Classes\CLSID\{A3F4CDED-B1E9-41EE-9CA6-7B4D0DE6CB0A}\InprocServer32`
指向 `C:\Windows\System32\weasel.dll`（x64）与 `WOW6432Node\...` → `SysWOW64\weasel.dll`（x86），
**不是**安装目录。md5 对得上才说明换对了。

现成脚本：`tools/deploy-grid-dlls.ps1`（三个文件 + 两个系统目录 + 备份 + 重启）。

### 4.3 ⚠️ 重启服务会把输入法「交出去」

本机装了腾讯微信输入法（WeType）。`WeaselServer` 重启后 Windows 有时把 zh-CN 的
活动输入法交给 WeType，表现为：**打拼音出拉丁字母、没有候选窗**，而
`nihao→你好` 这种测试**区分不出来**（WeType 也打拼音）。

**判定当前活动输入法**：枚举目标程序的已加载模块。

```powershell
$np = Get-Process notepad | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
$np.Modules | Where-Object { $_.ModuleName -match 'weasel|wetype' } | Select-Object ModuleName
```

**只加载 `weasel.dll`** 才是小狼毫。

**恢复办法**（无需改注册表，WeType 会在需要时自己起来）：

```powershell
Get-Process | Where-Object { $_.Name -match '^wetype' } | Stop-Process -Force
Stop-Process -Name ctfmon -Force          # 会自动重启
Get-Process WeaselServer | Stop-Process -Force
Start-Process 'C:\Program Files\Rime\weasel-0.17.4\WeaselServer.exe'
# 然后关掉旧记事本、开一个新的（新进程才会加载新 DLL）
```

### 4.4 已知的功能倒退（部署前必须知道）

我们编的 `WeaselServer.exe` **没有**带上插件仓库的托盘补丁
（`WeaselTrayIcon::CustomizeMenu` 在原版是空实现）。后果：

* 托盘右键的「输入法设置」入口**回到原版**（服务端 `SetupMenuHandlers` 里那几个命令号
  不再指向 `WeaselDeployer.exe` 代理）；
* 打字 `v` 打开功能菜单**不受影响**（那是 Lua 的）。

要两全，得把插件仓库的托盘补丁**一起合进 `weasel-grid-build`** 再编一次。

---

## 5. 验收（视觉 + 像素，缺一不可）

### 5.1 自动化脚本

`tools/verify-grid.ps1` 一次跑完全部断言（需要已部署 + 小狼毫是活动输入法）：

```powershell
powershell -ExecutionPolicy Bypass -File tools\verify-grid.ps1
```

它做的事：开记事本 → 打字 → 分别截图 → 量**候选窗深色区的高度** + 逐像素差分 →
打印每条断言 PASS/FAIL 与证据，最后给出汇总（`exit $fail`，可直接进 CI）。

> ⚠️ 两个已经踩过的脚本坑（2026-09-18 修）：
> 1. **函数里 `return` 数组会被 PowerShell 展平** —— 旧版返回「深底横带数组」，
>    调用方拿到的是散开的整数，算出的高度**恒为 0**，四条几何断言全部误报 FAIL。
>    现在改成返回 hashtable（`WinRegion`）；
> 2. **第一张截图必须真点一下窗口**（不加 `-NoClick`），否则记事本没有焦点、按键全丢，
>    后面的差分自然全是 0。
> 3. 文件必须存成 **UTF-8 带 BOM**：否则 `powershell -File`（5.1）会把中文按 ANSI 解析、
>    直接语法报错（`Unexpected token '}'`）。

### 5.2 视觉复核（最重要的一步）

**像素能证明「变了」，证明不了「对不对」**，一定要把候选窗裁出来让视觉模型读字：

```powershell
# 裁候选窗 + 二值化反相 + 放大，然后交给视觉模型（浅字深底必须反相，否则读成空白）
node "C:\Users\Administrator\.codex\skills\claude-vision-skill\vision.js" "<png 绝对路径>" "逐字输出图中所有文字"
```

> 本机 modlens 视觉桥**不稳定**（返回空白 / 把我的提示词当成图 / `503 busy`），
> 用上面这个 `vision.js` 更可靠。

### 5.3 判定要点

| 断言 | 判定方法 | 实测结果（run#24 构建，2026-09-18 夜） |
|---|---|---|
| 收起态**只有一行** | 候选窗深色区高约 64px | ✅ 64px（含顶部编码行） |
| 按 `↓` 展开 | 高度变成 3–4 行的量级 | ✅ 64 → **274px**（`zhe'g` 4 行） |
| `↓↓` **不收起** | 第 2 次 `↓` 后高亮移动、窗口高度不变 | ✅ 274 → 274px，差分 **5938** 点 |
| `→` 在同一行内右移 | 差分集中在行内、y 范围不变 | ✅ **2085** 点 |
| 第 1 行按 `↑` **收起** | 高度回到 64px | ✅ 64px |
| 序号在**词前** | 视觉读出 `1 这个 2 这关 …` | ✅ 三个状态 + 重启后第一次输入都读出「数字在词的左边」 |
| **按高亮行重新编号** | `↓↓` 后视觉读出第 2 行是 `1 这更 2 遮光 3 这该 …`，第 1/3/4 行「无数字」 | ✅ |
| `+` 下翻 | 换掉一批候选、第 4 次回到第 0 页、编码不上屏 | ✅ 页0/1 差 **1739** 点、页1/2 差 **1528** 点、第 4 次差 **0** 点 |
| v 菜单没被破坏 | 按 `v` 仍出 5 项 | ✅（人工看图） |

**踩过的判定坑**：候选高亮色是深棕 `0x594231`（亮度≈71），用「亮度 / 亮像素数」当指标
**完全看不出来**；必须用**逐像素差分（Σ|ΔRGB| > 30）**。

### 5.4 顺带查出来的性能问题：不要在每次按键写 option

用户反馈「打字卡顿」，定位方法就是**数日志**：

```powershell
$log = Get-ChildItem "$env:LOCALAPPDATA\Temp\rime.weasel\*.log" | Sort LastWriteTime -Desc | Select -First 1
(Get-Content $log).Count
@(Get-Content $log | Select-String 'updated option').Count      # ← 这个数字大得离谱就是它
```

* 实测：一份 571 行的日志里 **410 行**是 `updated option`，而且**一次按键**在 2ms 内连刷约 30 条
  （级联：`set_option` → 候选表失效、重跑过滤器 → 过滤器又 `set_option` → …）。
* 根因是 Lua 侧的坏习惯：`page_reset()` 每个按键都循环写 `vmenu_page_0..3`、
  `grid_set()` 每次都写 `vmenu_grid`、`set_raw()` 每次都写 `vraw_mode`。
* 修法：**值没变就不写**（改完同样操作的刷屏量：410 → **2**，且都不是我们的 option）。
* 教训：新写的任何 `ctx:set_option` 都必须**先读再写**，否则每个按键都会让 rime 重翻译一整份候选。

---

## 6. 回退

本机备份（改名回原位即可）：

| 内容 | 路径 |
|---|---|
| 安装目录三件套（旧） | `D:\weasel-build\dll-backup\20260918-182645\` |
| System32 / SysWOW64 的 `weasel.dll`（旧） | `D:\weasel-build\dll-backup\20260918-182933-system32\` |
| 原版 `WeaselServer.exe` | `D:\weasel-build\weasel\...` 构建前的 `C:\Program Files\Rime\weasel-0.17.4\WeaselServer.exe.vmenu-bak`（md5 `FBE1F6CEF85B852E510DF7E53CFC7CC3`） |
| 部署前整机备份 | `D:\weasel-build\backup-weasel-0.17.4-20260913-102918\` |

回退顺序与部署相反（停服务 → 覆盖 5 个文件 → 起服务 → 重启应用）。

**永远不要碰 `rime.dll`**（librime 本体，改它没有任何需求支撑，出问题无法回退）。

---

## 7. 未做 / 待确认

| 项 | 说明 |
|---|---|
| 托盘入口 | 见 §4.4，编出的 server 丢了这个入口 |
| v 菜单列表里的 `+` | v 菜单剪贴板列表（输入 `vclip`）**不吃**任何后缀（翻译器忽略），所以那里的 `+` 不会翻页；Lua 的 `is_more_key` 只对**已从菜单撤掉**的 `vsetc*` 管理列表生效。「下翻」目前只在**普通打字**的候选列表里实现 |
| `+` 的页数 | 固定 4 页（`GRID_PAGES = 4`），与展开态 36 个候选对齐；要更多页就加 `vmenu_page_4…` 开关 |
| 「最右边的回车键也要还原」 | 用户提过但含义未定（原始 0.17.4 主题？），未动 |
| language bar 名称 | 仍是 DLL 里的资源字符串，没改 |
