# 变更记录（CHANGELOG）

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。
本项目在真机（Windows 11 + Weasel 0.17.4 + librime 1.13.1 + rime-ice）上验证。

## [0.2.6] — 2026-09-19

候选方格翻页收尾，**第一次在本机编出 `WeaselServer.exe`**（不再依赖 CI）：
`+` / `-`（主键盘与小键盘）以及「最后一行继续按 `↓`」都会**整屏翻 36 个** →
「新一屏第 1 行 = 原来的第 5 行，以此类推」；翻页后**高亮自动回到同一纵列的最上方**
（`col = 原高亮 % 9`，服务端 `highlight_candidate_on_current_page`）；`+` 再 `-` 能
**像素级回到原页**。部署只换服务端 exe（md5 `1D87C729A92FCD8336A62C814CBD7B87`），
TSF 客户端 DLL 未动 → 所有程序立即生效、不用各自重启。完整记录见
[`docs/GRID-CANDIDATE-DLL.md`](docs/GRID-CANDIDATE-DLL.md) §2.5 与
[`docs/PROGRESS.md`](docs/PROGRESS.md) §1.19。

## [0.2.5] — 2026-09-18

候选方格这一轮**改了 Weasel 源码并用 GitHub Actions 重新编译**（这是本项目第一次改动输入法本体）：
序号改到**候选词前面**、**按高亮行重新编号**，方向键真的能**移动选中项**，`+` 号能**下翻**下一批候选。
完整记录见 [`docs/GRID-CANDIDATE-DLL.md`](docs/GRID-CANDIDATE-DLL.md)。

### 修复 · 「只有记事本有数字，其他软件都没有」（用户实测发现的真问题）

* **症状**：记事本里序号/方格一切正常；Chrome、微信、Office 等**全是原样**（没有数字、没有方格）。
* **根因**（`WeaselTSF/CandidateList.cpp` 逐行确认）：小狼毫把
  `ITfIntegratableCandidateListUIElement`（「集成候选列表」）暴露给了应用程序 →
  Chrome / Edge / 微信 / Office / UWP / 搜索框这类**会自己画候选**的程序接管了列表，
  而它们只能拿到 `GetString()` 的**候选文本**：标签槽里的 1–9 序号、9×4 方格**都不存在**；
  记事本不支持集成 → `_pbShow = TRUE` → 用**我们自己的候选窗** → 所以只有它有数字。
* **修法**（源码两处 + 已部署的二进制等效补丁，详见
  [`docs/GRID-CANDIDATE-DLL.md`](docs/GRID-CANDIDATE-DLL.md) §2.4）：
  `QueryInterface` 不再暴露该接口；`StartUI()` 里把 `_pbShow` 强制置 TRUE 再建窗。
  本机**没装 ATL**（`atlmfc` 不存在）编不出 DLL，于是对已部署的 DLL 做了等效的
  **一字节常量补丁**：把编进 DLL 的 IID 常量最后一位 `0x7B → 0x7A`，`IsEqualIID()` 永远不匹配。
* **实测证据**（Chrome + `file://` 测试页）：补丁前只有 `zhe'g` + 应用自画列表；
  补丁后读出 `1 这个 2 这关 3 这股 4 组合柜 5 赵河沟 6 遮盖 7 这给 8 鹧鸪 9 这跟`（数字在词**左边**），
  按 `↓` 展开后**只有第 1 行**带 1–9，第 2/3/4 行「开头无数字」✅。
* **注意**：TSF 客户端 DLL 是**进程内**的，改完要**重启那些程序**才生效（只重启 `WeaselServer.exe` 不够）。

### 修复 · 打字卡顿（实测定位并修掉）

* **现象**：用户反馈「打字有卡顿」。
* **定位（看 `%LOCALAPPDATA%\Temp\rime.weasel\*.log`）**：一份 571 行的日志里 **410 行**是
  `engine.cc:133 updated option: ...`，而且**一次按键**能在 2 毫秒内连刷约 30 条 ——
  典型级联：`set_option` → rime 判定候选表失效、重跑过滤器 → 过滤器又 `set_option` ……
* **根因**：本项目的 Lua 在**每个按键**上无条件写 option：`page_reset()` 循环写
  `vmenu_page_0..3` 四个开关，`grid_set()` 每次都写 `vmenu_grid`，`set_raw()` 每次都写
  `vraw_mode`。而 context option 一变，rime 就会把整份候选**重新翻译**一遍。
* **修法**（`src/lua/vmenu_core.lua`）：**值没变就一个 option 都不写** ——
  `page_set` 先比当前页、只改真正要变的那两个开关；`grid_set` / `set_raw` 都先比再写。
* **实测对比**：同样敲 `zhe'g` + `↓` + `↓↓` + `→→`，
  修前 410/571 行是 option 刷屏，修后 **2 行**（且都是 rime 自己的 `_auto_commit` / `emoji`）；日志无报错。

### 新增 · `+` 号下翻（用户要求「保留 + 号下翻选择预选词」）

* **现象**：收起态一行只有 9 个候选，第 10 个以后够不着；而按小键盘 `+` 的默认行为是
  **当标点用**——实测 `zhe` 会被**直接上屏**成「着+」。
* **实现**：rime 里 `KP_Add → send: plus`，由 `src/lua/menu_processor.lua` 拦下 →
  `vmenu_core.page_next()`（页码存成 `vmenu_page_0..3` 四个布尔 option，因为 context option 只能存布尔）
  → `menu_filter.lua` 收起态按 `page*9+1 … page*9+9` 切片。共 4 页，第 4 次按回到第 0 页；
  新一次输入复位。
* **实测**：三页候选互不重复（`这个/这股/遮盖…` → `这关/遮光/这该…` → `折股/这鬼/折桂…`），
  第 4 次与第 0 页的像素差分只有 **14 点**（抗锯齿噪声）✅，全程编码未上屏。

### 变更 · 候选序号：从「注释」搬进「标签槽」，数字在词前、按高亮行 1–9

* **问题（视觉实测）**：旧实现把序号写进候选**注释**（`menu_filter.number_row1`），
  Weasel 一格候选的渲染顺序是「标签 → 候选词 → 注释」，于是渲染成 **`这个1 这股2`** ——
  数字在词的**后面**；而且注释是**翻译阶段**由过滤器生成的，**移动高亮不会重跑过滤器**，
  序号永远钉在第一行，**不可能**「按高亮行重新编号」。
* **修法**：在 `WeaselUI/HorizontalLayout.cpp` 覆写 `GetLabelText`，按
  `this->id / 9 == id / 9` 判断「本候选是否在高亮那一行」：是高亮行给列号 `1`–`9`，
  其余行返回两个空格（宽度接近，保证各行候选词**左边缘对齐**）。标签槽是**每次绘制**都重算的，
  所以移动高亮时序号自动跟着重新编号。主题 `label_format` 是 `" "`（不含 `%s`），
  覆写因此**故意绕过模板**。
* 同时**删除** `menu_filter.lua` 里的注释序号（`number_row1` 与 v 菜单那段编号），
  以及 `vmenu_core.lua` 里已无人调用的死代码 `grid_sel()`（它的注释还留着一条错误说明）。
* **副作用（好的一面）**：v 菜单「快捷输入」子菜单第 10 条（返回）以前显示 `10`，现在不会再出现。

### 新增 · 候选窗口「按键展开」的自编 DLL（三个 C++ 补丁）

* `WeaselUI/HorizontalLayout.cpp`：删掉「按宽度折行」，改成**按个数**——
  `candidates_count > 9` 时每 9 个换行，**≤ 9 个绝不换行**（窗口宽度随内容变长、绝不丢候选）。
  `style/layout/max_width` 因此**不再参与**网格排版。
* `WeaselUI/HorizontalLayout.cpp` + `.h`：`GetLabelText` 覆写（见上）。
* `RimeWithWeasel/RimeWithWeasel.cpp`：`ProcessKeyEvent` 里当 option `vmenu_grid` 打开时，
  把方向键转成「移动高亮」——复用**鼠标悬停选词**的那条服务端通路
  （`HighlightCandidateOnCurrentPage`），`↓` +9 / `↑` -9 / `←` -1 / `→` +1；越界**不吞键**、
  落回原生处理（例如第 1 行按 `↑` 交给 Lua 收起）。
* **实测**：收起 64px（一行）→ `↓` 展开 204px（`zhe` 3 行 × 9 列）→ `↓↓` 高亮跳到第 2 行
  （差分 12767 点，x[90..212] y[197..327]）→ `→` 行内右移（11374 点，x[90..294]）→
  第 1 行 `↑` 回到 64px ✅；**全程 `zhe` 未被上屏**。

### 新增 · 构建/部署/验收的完整方法与工具

* **CI**：fork 分支 `weasel-grid-build` → GitHub Actions（VS2026，约 50 分钟/次）→ release
  `weasel-grid-<run 号>`，资产 **`weasel-grid-dlls.zip`**（+ `build-output.log`）。
  踩过的坑：ATL 的 `atls.lib` 路径、boost 缓存、`-Include` 不带 `-Recurse` 导致发布包**漏掉
  `WeaselServer.exe`**（run#22 的真实事故）。
* **部署要换 5 个文件**（`tools/deploy-grid-dlls.ps1`）：安装目录三件套 **加上**
  `C:\Windows\System32\weasel.dll`（x64）与 `C:\Windows\SysWOW64\weasel.dll`（x86）——
  **TSF 客户端 DLL 不在安装目录**（注册表 `CLSID\{A3F4CDED-…}\InprocServer32` 指向系统目录），
  只换安装目录时行为**一点变化都没有**（md5 对比确认）。
* **新增 `tools/verify-grid.ps1`**：一次跑完收起 / 展开 / `↓↓` 不收起 / 行内移动 / `↑` 收起 /
  `+` 下翻的**像素断言**，并打印汇总；语义部分（数字在词前、按高亮行编号）用裁图 + `vision.js` 复核。
* **文档**：新增 `docs/GRID-CANDIDATE-DLL.md`；同步 `docs/AGENT-HANDOFF.md`（环境事实表、
  约束 11/13/22 更正、新增约束 23–25）、`docs/PROGRESS.md`（§1.16、§2.6、§4、§5）、`README.md`。

### 已知限制 / 倒退（部署前必须知道）

* **托盘「输入法设置」入口失效**：自编的 `WeaselServer.exe` 没带托盘补丁
  （`WeaselTrayIcon::CustomizeMenu` 是空实现），托盘右键那一项回到原版行为；
  打字 `v` 打开功能菜单**不受影响**（那是 Lua）。要两全就把托盘补丁合进 `weasel-grid-build` 再编一次。
* **v 菜单剪贴板列表（`vclip`）里的 `+` 不会下翻**：翻译器忽略 `vclip` 后面的字符，
  `is_more_key` 只对入口已撤掉的 `vsetc*` 生效。`+` 下翻目前只在**普通打字**的候选列表里有效。
* **激活风险**：重启 `WeaselServer` 后腾讯微信输入法（WeType）有时抢走 zh-CN 活动权
  （表现：打拼音出字母、没有候选窗）。判定只能靠枚举目标程序已加载模块（只认 `weasel.dll`），
  `nihao→你好` **区分不出来**。恢复法见 `GRID-CANDIDATE-DLL.md` §4.3。

## [0.2.4] — 2026-09-13

修复 **0.2.3 的候选方格导航 bug**：展开后**再按一次 `↓` 会把当前候选直接上屏**。
顺带更正文档里一条**错误的实现约束**（`selected_candidate_index` 的「1 基 / 0 基换算」）。

### 修复 · 展开后再按 `↓` 会把候选上屏

* **现象（0.2.3）**：`shi` → 按 1 次 `↓` 展开（窗口高 287）→ **再按 1 次 `↓`** →
  候选窗口消失，并且**把当前选中的候选打出去了**（3/3 复现；三次分别上屏「实」「💩」「使」，
  顺序不同是因为雾凇拼音的用户词库会学习、候选顺序一直在变）。
  真实影响：想从第 1 行连按 `↓` 走到第 3 行，第二次就把词打出去了。
* **根因（实测探针）**：本机 librime-lua **没有**「只移动高亮」的 API。`grid_key` 里原本用
  `ctx:select(sel + 9)` 想「往下跳一行」，而 `ctx.select` **不是移动高亮，而是「选中并上屏」** ——
  展开后调 `ctx:select(9)` 等于直接把第 10 个候选提交出去。日志里 `ok=true`、`err=nil`，
  没有任何异常，所以之前被 `pcall` 掩盖成了「静默生效」。
* **探针清单**（`type(ctx.xxx)` 逐个打印，实测结果）：`ctx.select` = **function（= 上屏）**；
  `ctx.select_candidate` / `ctx.set_selected_candidate_index` / `ctx.highlight` / `ctx.move_selection` /
  `ctx.menu` / `ctx.get_menu` / `ctx.selected_candidate_index` / `menu.*` / `composition.select`
  **全部 = nil（不存在）**。
* **修法**：`src/lua/vmenu_core.lua` 的 `grid_key` 重写，**彻底不再调用 `ctx.select`**：
  * `↓`（收起时）→ **展开**成 4 行 × 9 列；
  * `↓`（已展开）→ **收回**（不再上屏）；
  * `↑`（展开时）→ **收回**；
  * `←` / `→` → 直接放行给原生导航器（我们不再碰）。
* **实测（每一步都看候选窗口高度 + 记事本里的上屏标题）**：
  基线 **144** → `↓` **287** → `↓` **144** → `↓` **287** → `↑` **144**，
  **全程标题一直是 `*shi`，没有任何候选被上屏** ✅。
* **⚠️ 仍然做不到的事（重要，别当成已完成）**：「展开后用 `↑` / `↓` / `←` / `→` 移动选中项」。
  用数字键做基准对照实测：`1` → **是**、`2` → **师**（数字键选词正常 ✅）；
  但 `→` 按 1 次或 3 次再按空格，**上屏的仍是「是」（第 1 个）**，展开后 `↓↓` + `→` 也一样 ——
  **四个方向键都不会移动选中项**，原生导航器在这条处理链里没有生效。
  结论：在**不改小狼毫 C++ 源码**的前提下**做不到**（原因是没有 API，不是没写）。
  现状：方向键只负责「展开 / 收起」，**选词请用数字键**（只覆盖前 10 个候选）。
* **文档更正**：0.2.3 文档里那条「`ctx.selected_candidate_index` 是 1 基、`ctx:select(i)` 是 0 基，
  在 `grid_sel()` 里换算」**是错的** —— 那个字段在本机**根本不存在**（探针读到 `nil`），
  换算一直把 `nil` 当成 0 用，这也是当初误判「跳行只是差一位」的原因。
  正确的约束是：**别用 `ctx.select`（它是上屏不是移动高亮），本机没有移动高亮的 API**。
* 遗留清理：`vmenu_core.lua` 里的 `grid_sel()` 现在是**死代码**（已无人调用），可以删。

## [0.2.3] — 2026-09-13

候选窗口改成「**默认单行、按 `↓` 展开 4 行 × 9 列**」（**序号只留第一行 1–9**），
部件拆字的前缀从 `uU` 改成单字母 `u`。

### 新增 · 候选窗口「收起 ⇄ 4 行 × 9 列」

* 需求原文：「默认是直着的显示 然后按向下后才变成 9 乘 4 的竖向方格 然后在最顶端按下向上回到一行
  按向下变成 9 乘 4 同时保留左右选择预选词的功能」。
* 主题 `style/layout/max_width` 由 `300` 改成 **`530`**（逻辑像素；屏幕 150% 缩放下实测**一行正好 9 个**）；
  schema `menu/page_size` 由 `18` 改成 **`36`**（= 9 × 4）。
* `src/lua/vmenu_core.lua`：新增展开状态与方向键二维导航
  （`M.GRID_COLS = 9`、`M.GRID_ROWS = 4`、`M.GRID_OPTION = "vmenu_grid"`、`grid_limit` / `grid_key`）。
  **当时的代码意图**是：
  * `↓`：收起时**展开**（选中项不动）；已展开时往下跳一行（`ctx:select(sel + 9)`）；
  * `↑`：选中项在**第一行**（下标 < 9）时**收回**；否则往上跳一行（`sel - 9`）；
  * `←` / `→`：行内左右移动（「按右键选候选」的习惯保留）；
  * 任何**别的按键**（继续打字、上屏、数字选词）自动收回。
  ⚠️ **这个「跳行」的思路是错的**：`ctx.select` 是「选中并上屏」而不是「移动高亮」，
  于是展开后再按 `↓` 会把候选打出去（**0.2.4 已重写为「展开 / 收起」开关**，见上面 `[0.2.4]`）。
* `src/lua/menu_filter.lua`：正常打字时按状态限制候选个数 —— 收起 **9** 个、展开 **36** 个
  （Weasel 按 `max_width: 530` 自动排成 4 行 × 9 列）。
* `src/lua/menu_processor.lua`：非 v 模式下方向键先交给 `grid_key`；v 菜单内部保持原样。
* **两个坑（都踩过）**：
  * `lua_filter` 与 `lua_processor` **各自 `require` 一份 lua 模块，模块级变量不共享** ——
    所以「是否展开」只能放在 **context option**（`vmenu_grid`）里传递，与 `vraw_mode` 同一思路；
  * ~~`ctx.selected_candidate_index` 是 **1 基**，而 `ctx:select(i)` 是 **0 基**，已换算。~~
    ⚠️ **这条是错的**（0.2.4 实测推翻）：那个字段在本机**不存在**（探针读到 `nil`），
    换算一直把 `nil` 当成 0 用。正确约束见 `[0.2.4]`。
* 实测（候选窗口物理像素；数字取自 `shots\` 取证截图，等于窗口整块区域）：

| 操作 | 候选窗口 | 结果 |
| --- | --- | --- |
| 打 `shi` | 717 × 145 | 收起：9 个候选排成 **2 行**（序号注释把候选撑宽了） |
| 按 1 次 `↓` | 793 × 285 | **4 行 × 9 列** ✅ |
| 再按 1 次 `↓` | 窗口消失 | ✗ 直接上屏（**0.2.4 已修**：现在第二次 `↓` = 收回） |
| `↓` 然后 `↑` | 回到 145 | 收回 ✅ |
| 再打任何字 | — | 自动收回 |

* ⚠️ **已知 bug（0.2.3 存在，0.2.4 已修）：展开后再按 `↓` 会把当前候选直接上屏。**
  当时的复现：`shi` → `↓`（展开）→ 再 `↓` → 候选窗口消失并上屏（三次分别上屏「实」「💩」「使」，
  候选顺序不同是因为雾凇拼音的用户词库会学习）。根因与修法见上面 `[0.2.4]`。
* ~~**已知未完成**：第 2–4 行的序号。~~ **✅ 本次已解决**（见下面「修复 · 第 2–4 行的序号」）。
  原来 rime 按候选下标发号，第 10 个之后会显示 `10`、`11`……，而需求是「下面几行不用序号，
  只需要第一行有 1–9」。第一版尝试是 `menu/alternative_select_labels` 填 36 项 ——
  **实测对 Weasel 无效**（详见下一节）。
* ~~**待复测**：「`↓↓` 与 `↓` + `→`×9 选中同一个候选」。~~ **✅ 已复测：这条旧结论是误判。**
  第二次 `↓` 会直接把候选上屏，所以当时两次「比较」比的其实是被意外上屏的那个字。参见上面的已知 bug。

### 修复 · 第 2–4 行的序号（0.2.3 的遗留项，已实测确认）

**根因（实测）**：`menu/alternative_select_labels` 对 Weasel 的渲染**完全无效**。两种写法都试过 ——

* 写进 `rime_ice.custom.yaml` 的 patch（36 项、10 项两种长度）→ **整份补丁被 rime 拒绝**
  （`page_size` 掉回 9、lua 挂载点消失，等于候选被压制功能失效）；
* 直接写进部署产物 `build/rime_ice.schema.yaml`（36 项，前 9 项 `1`–`9`、后面 27 项分别试过
  空串和零宽空格 U+200B）→ YAML 能过、窗口也正常，但**序号列的像素分布逐段完全相同**
  （1013 px，与改之前一模一样）。

结论：**第 10 个之后的数字不是 rime 给的标签**，所以拿 `alternative_select_labels` 永远去不掉。
（那一行 36 项的配置目前还留在 `build/rime_ice.schema.yaml` 第 142 行，对显示没有影响。）

**最终做法（三段配合，都已生效）**：

1. 主题加 `"style/label_format"` 并留空 —— 关掉**全部**原生序号。
   本机现在写的是 `" "`（一个空格）：实测部署产物 `build/weasel.yaml` 里**原样保留了 `" "`**
   （没有被 trim 成 `""`），效果和空串一样都是「不画序号」；仓库示例
   `examples/weasel.custom.example.yaml` 里用的是 `""`，两种都行。
   顺手确认 `max_width: 530` 未受影响（同一个文件第 541 / 554 行）。
2. `src/lua/menu_filter.lua` 新增 `number_row1(cand, i)`：**只给前 9 个候选**（正好第一行）的
   **comment** 写 `1`–`9`。注释只用于显示、**不进上屏文字** ——
   实测 `shi`+空格 → 是、`shi`+3 → 师。
   （正常打字的两条出口都调用了它：无命中收藏时按 `grid_limit` 截断后编号、命中收藏插到第 2 位后编号。）
3. 同一个文件的 **v 菜单分支**也把序号写进 comment（注释里本来就有数字的，如快捷输入的
   「按 1 · …」，不重复加），否则关掉原生序号后 v 菜单就看不出按几 ——
   实测 `v`→`5`→`2` → 2026-09-13、`v`→`3` → 常用语，说明注释没影响上屏。

**视觉证据**：候选窗口单独截图后用视觉 API 读图确认 —— 4 行候选里**第一行最左边是 1 位数字序号，
第 2/3/4 行没有序号**，四行最左边是候选文字（屎 / 识 / 施 一类）。
图在 `D:\VibeCoding\输入法\shots\show-2-grid.png`、`show-1-single.png`、`show-3-vmenu.png`、
`show-4-quick.png`（**只截了候选窗口那一小块**，没有桌面内容；按惯例**不放**进仓库 `screenshots/`）。

**一个副作用（已确认，非预期但无害）**：序号是**按候选下标 1–9** 写的，而且注释占用宽度 ——
所以**收起状态**下 9 个候选不再是「正好一行」，而是**排成 2 行**（候选窗口高从 74 变成 **145**），
第 2 行那两个（第 8、9 个）**也带数字**。需求里的「下面几行不用序号」只针对**展开后的 4 行**
（第 2–4 行 = 第 10–36 个候选，没有注释）—— 那一部分已达成。

**新踩的坑（改 build 产物时）**：直接改 `build/rime_ice.schema.yaml` 插入行时，
缩进必须和 `page_size` **同一级**（这个文件里是 **2 个空格**）。一度写了 4 个空格，日志立刻报
`config_data.cc:78 Error parsing YAML ... illegal map value`，**schema 整个失效：一个候选都不出、
打字直接出字母**。排查先看 `%TEMP%\rime.weasel\*.log`。

> 小瑕疵（未处理）：v 菜单的序号是逐条写的，而快捷输入子菜单有 10 条（9 项 + 返回），
> 所以「返回」那条前面会显示 `10`（实际按键是 `q`）。只影响观感。

### 变更 · 部件拆字触发键 `uU` → `u`

小狼毫自带的 rime-ice **本来就有**部件拆字（词典 `radical_pinyin`），但触发键是 `uU`，要打 `uUnvzi`。
本次**不新造功能**，只把前缀改成单个 `u`（两行配置，写在 `rime_ice.custom.yaml`）：

```yaml
radical_lookup/prefix: u
"recognizer/patterns/radical_lookup": "^u[a-z]+$"
```

相关结构（原有，未改）：`affix_segmentor@radical_lookup` + `table_translator@radical_lookup`
（`dictionary: radical_pinyin`）+ `reverse_lookup_filter@radical_reverse_lookup`；
词典条目形如 `好	nv'zi	3824`。

* 实测：`u` + `nvzi` → **好**；`u` + `riyue` → **明**；`v`→`5`→`9` + `nvzi` → **好**；
  `v`→`5`→`2`（日期）不受影响。
* **副作用**：**旧的 `uU` 写法失效**；以 `u` 开头的英文词也会被当成拆字。

### 变更 · `v` → 5 子菜单补第 9 项「部件拆字」

* `lua_menu.lua` 的 `yield_quick` 末尾新增 `部件拆字`（注释 `按 9 · 如 nvzi = 女+子`），
  选中后填入 `u`（`menu_processor.lua` 加 `if repr == "9" then replace_input(ctx, "u") return 1 end`）。

### 其它

* `examples/weasel.custom.example.yaml`：`max_width` 改成 `530`、旧注释里那句「实测 300 时…
  每行约 5 个」改写成 530 的实测值，并补上 `"style/label_format"`（序号改由候选注释显示）
  与「第一行 1-9、下面几行干净」的说明；
  `examples/rime_ice.custom.example.yaml`：`menu/page_size: 36` + 部件拆字补丁。
* `src/lua/menu_filter.lua`：除了 `number_row1` 与 v 菜单编号，还更新了文件头的注释
  （说明「序号走注释」的原因），并保持**两处 lua 目录 MD5 一致**后重启 `WeaselServer` 生效。

## [0.2.2] — 2026-09-13

`v` 菜单新增第 5 项**快捷输入**（9 项：计算 / 日期 / 时间 / 星期 / 日期时间 / 农历 / 数字大写 /
Unicode / 部件拆字 —— 最后一项随 0.2.3 的部件拆字改动加入），
并修掉托盘安装脚本在「小狼毫升级后重跑」时会覆盖新版部署器的问题。

### 新增 · `v` → 5「快捷输入」

* 主菜单第 5 项：`快捷输入`（注释 `计算 · 日期`）→ 子模式 `vqi`，子菜单 8 项 + `返回`。
* **机制（重要）**：选中一项后**把该功能的触发前缀直接写进输入框**
  （Lua 的 `ctx:clear()` + `push_input()`，就是原来 `vclip` / `vfav` 那一套 `replace_input`），
  之后所有按键**完全交回原方案**（我们不再拦截），于是雾凇拼音自带的 `recognizer/patterns` +
  `lua_translator` 自然生效 —— **不需要自己实现计算 / 日期 / 农历 / 大写 / Unicode**。
* 实现位置（三个文件，都已同步到仓库 `src/lua/`）：
  * `src/lua/vmenu_core.lua`：`M.mode_of()` 加 `if code:sub(1,3) == "vqi" then return "quick" end`；
    `M.want_type()` 加 `if m == "quick" then return "vqi" end`（vqi 菜单里只留菜单候选）。
  * `src/lua/lua_menu.lua`：主菜单加 `yield(item(seg, "vmenu", "快捷输入", "计算 · 日期"))`；
    新增 `yield_quick(seg)`；入口分派加 `if mode == "quick" then yield_quick(seg) return end`。
  * `src/lua/menu_processor.lua`：主菜单 `if repr == "5" then replace_input(ctx, "vqi") return 1 end`；
    新增 `cur == "vqi"` 分支（数字 1–9 填前缀、`q` 清空返回、其余放行）。
    原来的「第 5 项已去掉」注释改成「第 5 项：快捷输入」；`vset*` 代码仍然保留但菜单进不去。

9 项与实测上屏结果（第 9 项「部件拆字」是随 0.2.3 的部件拆字改动一起加进子菜单的）：

| 数字 | 菜单文字 | 填入的前缀 | 来源 | 实测上屏 |
| --- | --- | --- | --- | --- |
| 1 | 计算 | `cC` | `calc_translator.lua`（recognizer `^cC.+`） | `1+2*3` → **7**；`9*9` → **81** |
| 2 | 日期 | `rq` | `date_translator.lua` | **2026-09-13** |
| 3 | 时间 | `sj` | 同上 | **02:30**（`HH:MM`） |
| 4 | 星期 | `xq` | 同上 | **星期日** |
| 5 | 日期时间 | `dt` | 同上 | **2026-09-13T02:30:14+0800** |
| 6 | 农历 | `N` + 当天 `%Y%m%d` | `lunar.lua`（recognizer `^N[0-9]{1,8}`） | **丙午马年八月初三** |
| 7 | 数字大写 | `R` | `number_translator.lua`（recognizer `^R[0-9]+`） | 输入 `1234` → **一千二百三十四** |
| 8 | Unicode | `U` | `unicode.lua`（recognizer `^U[a-f0-9]+`，需要 `unicode` tag） | 输入 `4e2d` → **中** |
| 9 | 部件拆字 | `u` | `radical_pinyin` 词典（recognizer `^u[a-z]+$`） | 输入 `nvzi` → **好** |

* 三个特别注意：「计算」按下 `1` 之后**必须继续输入算式**（recognizer 是 `^cC.+`，光有 `cC` 不出候选）；
  「农历」按 `6` 时会把**当天的 `YYYYMMDD` 一起填进去**（`os.date("%Y%m%d")`），所以立刻能看到今天的农历；
  「数字大写」「Unicode」「部件拆字」按完还要自己补内容（`R1234`、`U4e2d`、`nvzi`）。
* 生效条件：改完 lua **必须重启 `WeaselServer`**（Lua 模块有缓存），并且
  `D:\rime-sandbox\lua\` 与 `%APPDATA%\Rime\lua\` 两处要保持 **MD5 一致**（本次已同步、已重启，日志无 lua 报错）。
* 本轮**没有可用的截图**：抓屏时机撞上用户正在用电脑（会带上用户自己的桌面内容），
  两张新图已从 `screenshots/` 删掉，所以文档里不引用 v5 的截图。

### 修复 · 托盘安装脚本的「代理识别」

* 原逻辑是 `if (-not (Test-Path $realDep)) { Move-Item … }` —— `WeaselDeployer.real.exe` 已存在时
  不再改名，于是小狼毫升级后重跑会用代理**直接覆盖新版** `WeaselDeployer.exe`（新版真身丢失）。
* 新逻辑：**先编译代理**，再用「大小是否等于代理（5632 字节）」判断当前 `WeaselDeployer.exe`
  是真身还是代理；不是代理就先 `Move-Item` 改名成 `WeaselDeployer.real.exe`（**覆盖旧真身**），
  然后才把代理放进去。
* 实测重跑输出：`WeaselServer.exe 备份已存在，沿用` / `菜单项文字已经是「输入法设置」，跳过` /
  `WeaselDeployer.exe 已经是代理，跳过改名` / `已安装代理 WeaselDeployer.exe（5632 字节）`；
  之后无参数启动仍然打开 vmenu 设置窗口。

### 修正 · 上一版文档里的一处限制说明

* 0.2.1 的文档写着「升级后重跑时新版 `WeaselDeployer.exe` 会被代理直接覆盖、`.real.exe` 可能仍是旧版」——
  该行为已在本版修掉：现在重跑会**自动把新版真身改名保存**为 `.real.exe`，不需要先手动挪走。

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
  ⚠️ **这一条只在「不接管方向键」时成立**：0.2.3 起普通打字时方向键由 `grid_key` 接管
  （`↓`/`↑` = 展开 / 收回），而 **0.2.4 确认 librime-lua 没有「移动高亮」的 API**，
  所以现在 **`←`/`→` 不再移动选中项**（选词请用数字键，见 `[0.2.4]`）。
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
