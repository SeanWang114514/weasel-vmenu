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

## 2. 四个补丁

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

### 2.4 集成：不让「应用程序自己画候选」抢走我们的窗（用户实测「只有记事本有数字」的根因）

**症状**：用户反馈「**只有记事本有数字，其他软件都没有**」。记事本里序号/方格一切正常，
Chrome、微信、Office 等全是原样的浅色系统列表。

**根因**（在源码里逐行确认）：`WeaselTSF/CandidateList.cpp`

```cpp
if (IsEqualIID(riid, IID_ITfUIElement) || ... ) { *ppvObj = ...; }
else if (IsEqualIID(riid, IID_IUnknown) ||
         IsEqualIID(riid, __uuidof(ITfIntegratableCandidateListUIElement))) {
  *ppvObj = (ITfIntegratableCandidateListUIElement*)this;   // ← 把「集成候选列表」接口给了应用
}
...
pUIElementMgr->BeginUIElement(this, &_pbShow, &uiid);        // 应用在这里说「我自己画」
if (_pbShow) { _ui->style() = _style; _MakeUIWindow(); }     // _pbShow == FALSE → 我们根本不建窗
...
void CCandidateList::UpdateUI(...) {
  if (_pbShow == FALSE) _UpdateUIElement();                  // 把候选登记给应用去画
  if (status.composing) Show(_pbShow); else Show(FALSE);     // _pbShow == FALSE → 我们的窗永不显示
}
```

小狼毫把 `ITfIntegratableCandidateListUIElement` 暴露了出去，于是**支持「集成候选列表」的程序
（Chrome / Edge / 微信 / Office / UWP / 搜索框）会自己画候选**；它们只能拿到
`CCandidateList::GetString()` 给的**候选文本** —— 标签槽里的 1–9 序号、我们的 9×4 方格
**全都不存在**。记事本不支持集成，`_pbShow = TRUE`，于是退回**我们自己的候选窗**，
所以只有它有数字。

**修法（两处，都已落进分支）**：

1. **源码**：`CandidateList.cpp` 的 `QueryInterface` 里**不再暴露**
   `ITfIntegratableCandidateListUIElement`（只保留 `ITfUIElement` /
   `ITfCandidateListUIElement` / `ITfCandidateListUIElementBehavior`）；
   并在 `StartUI()` 里把 `_pbShow` **强制置 TRUE** 再 `_MakeUIWindow()` 作保险
   （`_pbShow` 同时决定 `UpdateUI()` 里的 `Show(_pbShow)`，不强制就会「建了但永不显示」）。
2. **已部署的二进制补丁（本机没装 ATL，编不出来时的等效做法）**：
   `__uuidof(...)` 会把 IID 以 **16 字节常量**编进 DLL；把该常量**最后一个字节**
   `0x7B → 0x7A`，`IsEqualIID()` 就永远匹配不上，等价于「不再暴露集成接口」。
   实测：x86 `weasel.dll` 偏移 **729804**、x64 `weaselx64.dll` 偏移 **825488**，
   该 GUID `4F-F5-A6-C7-80-B1-6F-41-B2-BF-7B-F2-E4-68-3D-7B` 在各自 DLL 里**只出现 1 次**，
   而 `WeaselServer.exe` 里**一次都没有** —— 所以改动只影响这一处判断，不碰别的功能。

**注意（必须告诉用户）**：TSF 客户端 DLL 是**进程内**的，改完**要让那些程序重启**才会加载新代码；
只重启 `WeaselServer.exe` 不够（这一点和「网格/序号在服务端」正好相反）。

**验收证据**（2026-09-18 夜，Chrome + `file://` 测试页）：

| 状态 | 视觉读图结果 |
|---|---|
| 补丁后收起态 | `1 这个 2 这关 3 这股 4 组合柜 5 赵河沟 6 遮盖 7 这给 8 鹧鸪 9 这跟`（数字均在词的**左边**）✅ |
| 补丁后按 `↓` | 第 1 行 `1…9` 带序号；第 2/3/4 行「**开头无数字**」✅（正是「只有第一行带序号」的规格） |
| 补丁前 | 同样的操作在 Chrome 里读到的只有 `zhe'g` + 应用自画的候选列表，**没有任何数字** |

---

### 2.5 补丁 5/6：翻页 +「第 5 行 → 第 1 行」+「光标停在同一纵列的最上方」（本机首编 Server，2026-09-19）

**需求（用户原话）**：「在候选词最底部继续翻页然后将第5行的词显示在第一行 以此类推 光标在同一纵列的最上方」
「还有保留+号下翻选择预选词的功能」。

| 项 | 内容 |
| --- | --- |
| 翻页量 | 展开态一页 36 个（`menu_filter.lua`：`start = page*lim`，`start >= 总数`归零）→ 翻一页 = 原第 5 行变新第 1 行（上一轮已上线） |
| Server 拦截（`RimeWithWeasel.cpp::ProcessKeyEvent`） | `vmenu_grid` 展开态下拦截 `+`/`-`（`keycode==0x2b/0x2d`（主键盘，ToUnicodeEx 产物）或 `KP_Add/KP_Subtract`）和「最后一行再按 `↓`（`delta>0 && Down` 且 `target>=count` 越界）」→ ① 记 `col = 高亮 % 9`；② 交给 `rime_api->process_key`（Lua 处理器选项翻页）；③ `highlight_candidate_on_current_page(col)` 放回同列第一行；④ `_Respond/_UpdateUI`，`return handled` |
| 为什么不越界拦截 | 箭头键目标**没越界**时维持 2.3 的纯移动高亮（窗口不换）；`↑` 在第一行 / `←` 在最左 仍放行给 rime（`↑` 收起） |
| Lua 配合 | `vmenu_core.lua grid_key`：已展开还能收到 `↓` ＝ 越界放行 → `page_next`（不再空吞） |
| ★ 本机编 Server 的完整解锁链 | ① `VC.ATL`（14.51）真正装上（UAC 禁用 → `Start-Process -Verb RunAs`）；② `rime.dll` 导出 → `rime.def`（修列序抓名字）→ `lib /machine:x64` 得 `rime.lib`；③ Boost 静态库 `libboost_*-vc143-mt-s-x64-1_84.lib`（`ci/build-boost.ps1` 的 user-config 显式写 cl 路径；编完把名字补 `-x64-` 段）；④ RC 缺 `afxres.h` → 写本地 `include/afxres.h` shim（gitignore）。`msbuild /t:WeaselServer /p:Platform=x64` → `output\WeaselServer.exe` |
| 部署 | 只换 `C:\Program Files\Rime\weasel-0.17.4\WeaselServer.exe`（停进程→替换→重启）。md5 新旧：`FFA4285B…`(2756096) → `1D87C729A92FCD8336A62C814CBD7B87`(2684416)。备份 `dll-backup\20260919-0050-pre-samecol\` |
| 作用域 | **服务端全局**：不改 TSF 客户端 DLL → 所有程序**立竿见影、无需重启各自程序**（与 2.4 相反） |
| 验收（fresh Notepad + modlens 读图 + 像素） | `shi`→`↓`→`→→`（第 3 列 `十`）→`+`：第 1 行 = 37–45 且高亮 = 第 3 列第 1 行 `3 狮` ✅；`++−` 与 `+` 后像素 diff=0 ✅；第 4 行按 `↓` 翻页、高亮仍在第 3 列第 1 行 ✅ |

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

### 4.1 为什么当年用 CI 而不是本机（**第十八轮起本机也能编，见 §7.4 与 `AGENT-HANDOFF.md` 约束 32**）

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
| **Chrome（原本自己画候选的程序）也有序号** | 补丁 4 后视觉读出 `1 这个 … 9 这跟`，`↓` 后只有第 1 行带 1–9 | ✅ 见 §2.4 |
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

## 7.1 ✅ 已部署（第九轮，2026-09-19）：候选方格「统一列宽」严格对齐

**用户诉求**：「还有下方的预选词要对齐 最好要完全对齐 并且每个预选词都用同一个长度
（如果实在太长 可以允许压缩到少几个预选词（行列对齐））」

**根因**：`WeaselUI/HorizontalLayout.cpp::DoLayout` 原来**按每个候选的真实宽度逐个累加** `w`
（`w += size.cx * textFontValid` …），于是每格宽度不同：第 1 行带序号（「数字 + 空格」比「两个空格」
宽约 8px）整体右移，第 2–4 行各格之间又随词长参差 → 逐列**累积漂移**（实测最大 93px）。

**最终实现**（本地 `weasel-grid-build` 分支，已编进部署的 DLL；旧 commit `f0c47b6` 是第一版，有 bug）：

1. 循环前量出**统一列宽** `col_width` = 所有候选里最宽的一格（统一序号槽宽 `grid_label_w`
   + `hilite_spacing` + 词 + 注释）+ `candidate_spacing`；
2. 每格走完后把光标**按列号**钉死：
   `w = offsetX + real_margin_x + ((i % cols) + 1) * col_width - _style.candidate_spacing`；
3. 序号槽宽度 `grid_label_w` 对所有行统一（高亮行画 `1 `–`9 `，其余行两个空格占位）；
4. 高亮块 `_candidateRects[i]` = **完整一格**（等宽）；「把最后一个候选拉到窗口右缘」那句加
   `!grid_uniform` 保护；
5. **收起态（单行 9 个）也等宽** —— 用户要「每个预选词都用同一个长度」；若一行 `9 × col_width`
   超出屏幕（有超长候选）则退回自然宽度，并按屏幕宽度反算每行最多几列（下限 3）。

**踩过的坑（第一版补丁的 bug，务必别再犯）**：第一版用循环里 `w` 的快照 `vmenu_cell_start` 来
「补齐」列宽。**换行时 `w` 被重置成新行行首，而 `vmenu_cell_start` 还是上一行末尾的值** →
第 2/3/4 行只有**第 1 格**在正确位置，第 2–9 格被推到面板外（实测第 2–4 行各只有 1 个文字簇；
肉眼看就是每行只剩第一个词）。
**结论：在有「按行重置」的布局里，跨行位置必须由「行号/列号」算出来，不能沿用累加值。**

**验收（视觉 + 像素，工具 `tools/measure-grid-align.ps1`）**：

| 图 | 逐列结果 |
| --- | --- |
| 旧 DLL `shots/c2_exp.png` | 第 1 行对第 4 行偏移 `8,16,25,32,43,59,67,80,93` → **最大 93px** ❌ |
| 新 DLL `shots/i2_exp.png` | `0,0,0,1,0,3,0,0,5` → **最大 5px**，且这 5px 出自高亮**粗体**字的墨迹 ✅ |
| 收起态 vs 展开态第 1 行 | 词起点完全相同 `135,241,347,454,559,670,771,877,988` ✅（展开时面板宽度不再跳变） |

量法：自动学出面板底色（暗像素里出现最多的颜色）→ 切行（阈值 = 面板内每行亮像素底噪 + 20，
否则 4 行会被并成 1 行）→ 按**簇宽度**区分「序号(窄)/候选词(宽)」并丢掉左右描边 →
逐列比词起点 x，同时报告列距极差与「第 1 行对末行」的逐列漂移。

**本机编译链**（这一轮打通，细节见 `PROGRESS.md` §1.20 ⑧）：ATL 已装；Boost 用
`ci/build-boost.ps1` 的 `--user-config` 法编静态库 —— **x64/x86 必须各自指向自己的 cl.exe**
（`Hostx64\x64\cl.exe` / `Hostx64\x86\cl.exe`），只改 `address-model=32` 而不换 cl，b2 会
**复用同名目标文件**，编出来的「x86 库」其实是 x64（dumpbin 看机器类型仍是 `8664`）；
`rime.lib` 由 `rime.dll` 导出表生成（抓**名字列**）；RC 段缺 `afxres.h` 用本地 shim（已 gitignore）。

**32 位（x86）也已部署**：`deps\boost_1_84_0\stage\lib` 里原本混着一批「名字带 `-x32-`、
内容其实是 x64」的 boost 库（早先失败的 b2 运行留下的），x86 链接会先命中它们 → boost 的
`__thiscall` 符号全解不出（LNK2001，且不会报 LNK1112，因为没有任何成员被真正抽出来）。
用真 x86 库覆盖那 9 个文件后 Win32 一次链接通过：`output\weasel.dll` 1037312 B、
md5 `D5FE2EF773540AD78DA5EDE7A2D9DA7A`、`14C machine (x86)`，已部署到安装目录与
`C:\Windows\SysWOW64\weasel.dll`。32 位宿主（`SysWOW64\WindowsPowerShell` 跑 WinForms 文本框）
实测展开态 4×9：逐列起点差 0–5px、第 1 行对末行漂移 ≤5px，与 x64 完全一致 ✅

---
## 7.2 ✅ 已部署（第十轮，2026-09-19）：数字键按「标签那一行」选词（只重编服务端）

**问题**：用户报「候选词可以显示但是无法实际意义上选择」。根因不在绘制，而在**选谁来上屏**：
标签是客户端 `HorizontalLayout::GetLabelText` 按**高亮那一行**画的（`id % 9 + 1`，只有高亮行
画数字），而 librime 自己的数字选词**不是「本页第 d 个」**——高亮不在该行首格时会漂：

| 实测 | 现象 |
| --- | --- |
| 展开态、`↓` 把高亮移到第 2 行，按 `3` | 上屏「🔟」= 候选表**第 2 位**（正确应是第 12 位 = 第 2 行第 3 列）|
| **收起态**、按 `=` 翻页后按 `3` | 上屏「屎」= **上一页**的词（正确应是新页第 3 个）|

**补丁**（`RimeWithWeasel/RimeWithWeasel.cpp`，`ProcessKeyEvent` 内、网格分支**之前**）：
统一接管数字键 `1`–`9`（主键盘 `0x31`–`0x39` 与小键盘 `KP_1`–`KP_9`），
`target = (高亮索引 / 9) * 9 + (d - 1)` → `SelectCandidateOnCurrentPage(target)`，
与画出来的标签严格一致，不再依赖是否展开。

**闸门（四道，一道都不能删）**：先 `rime_api->get_input(session_id)`，满足任一条就**不接管**，
把数字留给 Lua / 原方案：

1. **全是数字**（允许 `'` 音节分隔符）→ 留给 Lua 的数字编码逻辑，否则「收藏编码 = 131」会被吃掉
   （实测 `1` `3` `1` + 回车仍上屏 `13122500717` ✅）。
2. **以 `v` 开头** → 那是 v 功能菜单与 v 子模式（`vclip` / `vfav` / `vqi` / `vset…`），
   菜单项靠 Lua 收数字切换；被这里吃掉的话「按 3」只会把「常用语」三个字写进文档
   （用户实测的「v 功能无法正常打开」）。
3. **输入里出现大写字母或非字母字符** → 雾凇拼音的快捷输入前缀都带大写字母
   （`cC` 计算 / `U` Unicode / `N` 农历 / `R` 数字大写），它们后面必须还能继续敲数字
   （`cC1+2*3`、`U4E00`、`R123`）；输入里已经有数字/符号（`cC1+2`）时同理。
   用户实测：「用了 cC 之后无法输入数字，一按数字就变成选词」。
4. **以 `rq` / `sj` / `xq` / `dt` 开头**（全小写的日期时间前缀）→ 它们后面也可以跟数字
   （例如指定某一天）。

实测（`tools/verify-quick-digits.ps1`，自带读回文件的测试窗口 `tools/ime-test-pad.ps1`）：

| 例 | 操作 | 结果 |
| --- | --- | --- |
| 计算 | `v`→`3`→`1`，敲 `1+2*3`，空格 | 候选 `1 7 / 2 1+2*3=7`，上屏 **7** ✅ |
| 数字大写 | `v`→`3`→`7`，敲 `123`，空格 | 候选 `1 一百二十三 / 2 壹佰贰拾叁 / 3 一百二十三元整…`，上屏 **一百二十三** ✅ |
| Unicode | `v`→`3`→`8`，敲 `4E00` | 正常出候选（数字进输入框，没被当成选词）✅ |
| 回归 · 数字编码 | 敲 `131` + 回车 | 上屏 **13122500717** ✅ |
| 回归 · 拼音选词 | 敲 `shi` 再按 `3` | 上屏 **识**（数字选词/行内映射照旧）✅ |

**只重编服务端的命令**（客户端 DLL 完全不动，20~27 秒）：

```bat
set "ATL=C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231"
set "BOOST_ROOT=D:\weasel-build\weasel\deps\boost_1_84_0"
msbuild weasel.sln /t:WeaselServer /p:Configuration=Release /p:Platform=x64 /m /nologo /v:m
:: 产出 output\WeaselServer.exe（2684928 B）
:: 部署：停 WeaselServer → 覆盖 C:\Program Files\Rime\weasel-0.17.4\WeaselServer.exe → 启动
```

> ATL 的头/库要进 `INCLUDE` / `LIB`（`…\atlmfc\include`、`…\atlmfc\lib\x64`），
> 否则 `atlbase.h` 找不到；Boost 头只要存在即可（本轮不改依赖）。

**验收矩阵**（`tools/verify-grid-digit.ps1`，每例全新记事本、读回真实内容与候选表逐位比对）：

| 例 | 操作 | 结果 |
| --- | --- | --- |
| A | 收起态按 `3` | 识（第 3 个）✅ |
| B | 展开后按 `3` | 🔟（第 3 个）✅ |
| C | 展开 + `↓` 到第 2 行按 `3` | 是 = 表内第 12 位 ✅ |
| D | 展开 + `=` 翻页按 `1` | 食 = 新页第 1 位 ✅ |
| E | 展开 + `=` 翻页按 `3` | 尸 = 新页第 3 位 ✅ |
| G/H | **收起** + `=` 翻页按 `1` / `3` | 💩 / 尸 = 新页第 1 / 第 3 位 ✅ |
| F | 展开 + `↓` 一行 + `=` 翻页按 `2` | 翻页后高亮按设计回到**同列最上方**，故应选新页第 2 个；脚本按「留在第 2 行」算期望值故对不上，行为自洽（见 PROGRESS §5.6 待人类确认）|
## 7.3 ✅ 已部署（第十七轮，2026-09-19）：v 功能不再显示内部编码（只重编服务端）

**问题**：`v` 功能的输入编码（`v` / `vclip` / `vqi` / `vfav` / `vset*`）会原样出现在**行内预编辑**里，
用户看到的是「神秘字符 `vclip`」（截图里那个小方块就是行内预编辑本身）。

**为什么必须改服务端**：`vclip` 不是任何候选的正文（`lua_menu.lua` 里候选正文全是中文/剪贴板条目），
它是 **composition 的 preedit**。librime 的 Lua API 没有「改 preedit」的接口，而 Weasel 服务端在
把上下文交给前端之前有两次落笔机会：

| 通路 | 位置 | 谁在用 |
| --- | --- | --- |
| 字符串协议 | `_Respond()` → `ctx.preedit=` / `ctx.preedit.cursor=` 消息 | 自己画候选的客户端（TSF：Chrome / 记事本 等） |
| 结构体 | `_GetContext()` → `weasel_context.preedit.str` | 非 TSF 客户端（服务端面板 `m_ui`，如 WinForms） |

**补丁**：新增文件内静态函数 `_VMenuLabel(api, session_id, code, &label)`：

```cpp
if (!code || code[0] != 'v') return false;            // 普通拼音一律不动
if (api->get_option(session_id, "vraw_mode")) return false;  // 原符号模式一律不动
// v → 功能菜单 · vclip → 剪贴板 · vqi → 快捷输入 · vfav → 常用语 · vset* → 设置
```

命中时：`ctx.preedit=` 换成中文名、`ctx.preedit.cursor=` 写「长度,长度,长度」（**不下发高亮范围**，
避免用旧编码偏移去高亮新文案）；`_GetContext()` 里换成 `u8tow(label)` 并跳过 attribute。

> ⚠️ **中文文案必须写成宽字符 `\u` 转义 + `wtou8()`**：本工程没有 `/utf-8`，直接写中文窄字符串会被
> MSVC 按系统代码页（GBK）编码，前端显示乱码。编完可用「在 exe 里按 UTF-16LE 搜 `6a52348d`（剪）」
> 快速自检。

**实测**（`tst/preedit-label-verify2.ps1` + Windows OCR，2026-09-19）：

| 操作 | 行内预编辑 OCR 读出 | 候选窗 |
| --- | --- | --- |
| `v` | 功能菜单 | `842x49` |
| `v`→`2` | 剪贴板 | `3921x49` |
| `v`→`3` | 快捷输入 | `987x49` |
| `v`→`4` | 常用语 | `583x49` |
| `v`→`5`（原符号） | `v`（**故意保留**） | `687x191` |
| 普通拼音 `shi` | `shi`（回归） | `587x49` |
| WinForms 测试窗 `v` / `v`→`2`（服务端面板通路） | 功能菜单 / 剪贴板 | — |

**同轮 Lua 改动**：`menu_processor.lua` 的退格判断从「只有 `vclip`」扩大到**所有 v 功能**
（`is_v_func()`：`v` / `vclip*` / `vqi*` / `vfav*` / `vset*`），一按退格整条输入作废；
实测四种功能 candidates 面板 `842x49`/`3921x49`/`987x49`/`583x49` → 全部 `none`，
日志四行 `[vmenu] 退格取消整条输入 <vclip>|<vqi>|<vfav>|<v>`。

**部署记录**：`WeaselServer.exe` 2685440 → **2688512 B**，md5 `BDF332243AD1B407EDC1F712C357ED8A`
→ `493D4A5CAC45BE0B0A2BE00260579504`；旧文件备份 `WeaselServer.exe.bak-preedit-09191251`；
重编命令同 §7.2（24 秒）。**客户端 DLL 未动。**

## 7.4 ✅ 已部署（第十八轮，2026-09-19）：v 功能一行 4 个 + `+/-` 翻页 + `↓` 展开（**客户端也改了**）

**两个新的文本协议键**（服务端 → 客户端，都走 `_Respond()`）：

| 键 | 取值 | 客户端字段（缺省 = 老行为） | 作用 |
| --- | --- | --- | --- |
| `ctx.grid_cols=` | `4` = v 功能、`9` = 普通打字 | `Context::grid_cols`，缺省 `0` → 当 9 | 换行步长 + 序号步长（原来硬编码 9，见 §2.1/§2.2） |
| `ctx.grid_2d=` | `1` = 按「行 × 列」、`0` = 按 `1..N` 顺序 | `Context::grid_2d`，缺省 `1` → 老行为 | 静态 v 菜单（v 主菜单 5 项、v3 快捷输入 7 项）的数字键是**顺序选**，序号也得顺序画 |

**排版新增一条规则**：一行放不下时**少画 1–3 列**（最少 1 列），
别重排 —— 重排会让收起那一行与展开后的每一行**列位置对不上**。

```cpp
// HorizontalLayout.cpp（DoLayout / _candidateRects 重排 / 拉伸到右边缘 三处都要判）
if ((i % kGridCols) >= draw_cols) { SetRectEmpty(&_candidateRects[i]); … continue; }
```

`draw_cols` 的算法：`min_cols = (kGridCols > 3) ? kGridCols - 3 : 1;`
`while (draw_cols > min_cols && (draw_cols * col_width) > grid_budget) --draw_cols;`
其中 `grid_budget = GetSystemMetrics(SM_CXSCREEN) - offsetX - 2*real_margin_x - 16`。
被省掉的格子是**空矩形**（点不到、不画序号），但槽位仍在 —— 所以对齐是逐像素的。

**实测**（记事本 + Chrome，截图 + OCR）：

| 操作 | 候选窗 | 读出 |
| --- | --- | --- |
| `v`（v 主菜单） | `861x95` | `1 设置 图形窗口 2 剪贴板 历史 3 快捷输入 计算·日期 4 常用语 快捷内容` / `5 原符号 原版 v` |
| `v`→`3` | `808x96` | `1 计算 2 日期 3 时间 按s 4 农历输入` / `5 数字货币转写 6 Unicode 7 返回` |
| `v`→`2`（剪贴板 20 条，长条目） | `1433x49`（收起 2 列） | `1/20 这个栏…` `2/20 D:\VibeCoding\Codex.lnk` |
| `v`→`2`→`↓` | `1433x191`（4 行 × 2 列） | `1/2`、`5/6`、`9/10`、`13/14`（第 3、4 列空着不画） |
| `v`→`2`→`↑` | `1433x49` | 收回 |
| `v`→`2`→`+`（第 2 屏，短条目） | `1424x49`（**画满 4 列**） | `1 Paraformer-zh 5/20` `2 不要显示这个内部代码 6/20` `3 paraformer-zh-small int8 7/20` `4 先再网页跑通了再打包 8/20` |
| `v`→`2`→退格 | 无候选窗 | 整条取消（回归 §7.3） |
| `v`→`2`→`1` | 上屏 | 剪贴板第一条 |
| 普通打字 `shi`（回归） | `660x49` / `↓` `660x189` | **与上一轮一致**，9 列没被裁 |

> ⚠️⚠️ **`lua_filter` 里绝对不能 `ctx:set_option()`**（这一轮踩的雷，1 小时）：
> 第一版用 option `vmenu_list` 传递「是不是列表型 v 功能」，服务端**每次按键栈溢出崩溃**
> （`ntdll.dll` / `0xc00000fd`，`%TEMP%\rime.weasel\*.dmp` 每半分钟一个；
> 现象是「输入法在记事本里完全没反应」）。`set_option` 会让引擎重跑候选管线，
> 管线再进过滤器、过滤器再 `set_option` → 无限递归。
> **判断要放在哪**：要么服务端按输入前缀自己算（本轮做法 `_VMenuListCode`），
> 要么放在 **`menu_processor.lua`**（processor 跑在管线之前，改 option 是安全的）。

**部署记录**（`tools\deploy-grid-dlls.ps1 -SourceDir D:\weasel-build\weasel\output`，5 个文件）：
`WeaselServer.exe` **2692608 B** md5 `DF2B80E2B2106E42329685402D345870`；
`weaselx64.dll`（`C:\Windows\System32\weasel.dll`）**1181696 B** md5 `7969B7C0C6E0A64C8524C4A81B290862`；
`weasel.dll`（`C:\Windows\SysWOW64\weasel.dll`）**1037824 B** md5 `7FD813EF343FC9C0346BEAFC9DEE9B29`；
旧文件备份在 `D:\weasel-build\dll-backup\<时间戳>\`。
重编：`pwsh -NoProfile -File D:\weasel-build\build-vmenu.ps1 -Only all`
（server 44 s / x64 14 s / x86 23 s，前台跑，日志 `D:\weasel-build\build-vmenu.log`）。

> ⚠️ **客户端 DLL 是进程内加载的**：记事本、Chrome、微信… 都得**重启**才会用上新 DLL。
> 验证网页通路时用了独立 profile 的 Chrome：`chrome.exe --user-data-dir=D:\weasel-build\chrome-ime-profile
> --new-window file:///D:/weasel-build/tst/ime-web-test.html`（不动用户的浏览器会话）。

## 7.5 ✅ 已部署（第十九轮，2026-09-19）：剪贴板 / 常用语「固定格宽 + `…` 截断」，格宽上限 = 屏宽 20%

**用户诉求（原话）**：
「剪切板改为一行2个 默认显示3行 用正常候选词的逻辑进行选择（但是拓展栏默认展开）」、
「和选项a差不多 但按上键不要收起 默认就是展开态」、
「这个剪贴板和常用词的候选词的框框长度固定 不能显示完全的候选词用....代替 然后继续解决问题」、
随后追加「剪切板和常用于的候选词长度上限缩短至27% 然后继续」。

**定下来的语义**（剪贴板 `v`→`2`、常用语 `v`→`4`，两者同构）：

| 项 | 行为 |
| --- | --- |
| 网格 | 一行 **2 个** × **3 行** = 一屏 6 条；`menu/page_size` 仍是 36，由 `menu_filter.lua` 用 `lim = core.grid_limit(ctx, code) = 6` 切片 |
| 默认态 | **永远展开**（不需要按 `↓`），`↑` 在第 1 行**被吞掉**（绝不收起） |
| 数字键 | 与正常打字同构：**只选「高亮那一行」里的第 N 个**（`row = current/2; target = row*2 + digit`） |
| `+` / `-` | 按 **6** 翻页（`page_next` / `page_prev`，步长 = 本屏条数） |
| 格宽 | **固定**：`col_width = min(屏宽 20%, 可用宽度/列数)`（此前是「可用宽度的一半」≈ 屏宽 50%），再与 `120 + candidate_spacing` 取大保底 |
| 超长候选 | 绘制阶段裁掉并以 **`…`** 结尾；**候选文本本身不动** → 选中后上屏的仍是完整内容（实测：数字键选第 2 条 → 上屏 3000+ 字全文） |
| 注释 | **剪贴板列表不带注释**（用户：「把后面的剪切板 n/30字样删除」）：`yield_clip_list` 普通列表注释置空；管理列表只在第一项留「显示 20 · m 更多」。注释一去掉，候选词可用宽度 = 整格 → 一格可见约 9 个汉字（原来约 5 个）。**常用语的「常用语 \<触发键\>」保留**（那是触发词，不是位置计数） |

**格宽上限的三次取值**（都是同一个常量 `kVMenuFixedCellPercent`，一次只改一个数字）：

| 时间点 | 取值 | 每格（虚拟） | 面板实测 | 依据 |
| --- | --- | --- | --- | --- |
| 第一次 | 屏宽 ≈50%（`grid_budget/列数`） | 837 | `1700x144` | 「框框长度固定」（原实现直接按可用宽度均分） |
| 第二次 | 屏宽 **27%** | 461 | `945x144` | 「候选词长度上限缩短至27%」 |
| 第三次（当前） | 屏宽 **20%** | 341 | `707x144`（≈ 屏宽 41%） | 「框长度减少到20%（也就是减少4/5）」 |

> ⚠️ **快捷输入（`v`→`3`）故意没跟着改**：它一行 4 个、每格 ≈202 虚拟 ≈ **屏宽 11.8%**，
> 本来就比 20% 还短；套上「屏宽 20%」会把面板从 `808x96` 撑到 ≈`1390x96`（越改越宽，与诉求相反）。
> 静态 v 菜单（v 主菜单 / v3）继续用「自然宽度 + 4 列」，只有**列表型**（`ctx.grid_cols == 2`）
> 才走固定格宽。
>
> ✅ **后续（用户 2026-09-19 追加）**：「把快捷输入的候选词显示也改为和粘贴板相似的2*3格式」→
> 现在 **v3 也下发 `grid_cols = 2`**，于是走同一套固定格宽排版：
>
> * 服务端只改一行：`_VMenuCols` 里 `vqi` 前缀返回 2（`RimeWithWeasel.cpp`）。
>   客户端的 `fixed_cells` 判据是 `explicit_cols && kGridCols == 2`，**不看 `grid_2d`** ——
>   所以 v3 保留 `grid_2d = 0`（顺序序号 1..7、数字键仍由 Lua 顺序选），排版却和剪贴板一样。
> * 实测 `v`→`3` = `707x189`（2 列；**7 个条目 → 4 行**，第 4 行只有「返回」一格）；
>   注释「按 c/r/s/n/h/u/q」保留、右对齐；格宽与剪贴板同为 341 虚拟（屏宽 20%）。
> * v 主菜单仍 `861x95`（4 列）、剪贴板仍 `707x144` —— 互不影响。
> * 想要**严格 2 列 × 3 行**（6 格）的话，第 7 项「返回」必须挪到第二页或从菜单删掉；
>   两条都让某个条目不再一眼可见，所以先按「7 格全可见」实现。
>
> **顺带修掉的老 bug**：v3 的「返回」（数字 `7` 或字母 `q`）**以前按了没反应** ——
> 它原来执行 `ctx:clear()`，在这条 processor 路径上不生效（输入框仍是 `vqi`、候选窗不关）。
> 改成 `replace_input(ctx, "v")` 后真的回到 v 主菜单（实测 `861x95` + 预编辑「功能菜单」）。

**客户端改动（本轮真正的工作量在这里）**：

```cpp
// HorizontalLayout.cpp —— 固定格宽（服务端下发 grid_cols == 2 的列表模式才启用）
const int kVMenuFixedCellPercent = 20;           // ← 想调宽调窄只改这一个数字
const int kScreenW  = GetSystemMetrics(SM_CXSCREEN);
const int grid_budget = kScreenW - offsetX - 2*real_margin_x - 16;
const bool fixed_cells = (explicit_cols && kGridCols == 2 && grid_budget > 0);
int fixed_col_width = 0;
if (fixed_cells)
  fixed_col_width = max(min((int)((long long)kScreenW * kVMenuFixedCellPercent / 100),
                            grid_budget / kGridCols),
                        120 + _style.candidate_spacing);
```

```cpp
// WeaselUI.h —— 新增两个 setter（DirectWrite 文本布局）
SetLayoutWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP);
SetLayoutEllipsisTrimming(pTextFormat);   // CreateEllipsisTrimmingSign + DWRITE_TRIMMING_GRANULARITY_CHARACTER
// WeaselPanel.cpp/_TextOut(..., trim = true) 只给「候选词」和「注释」传 true
```

**⚠️ 本轮踩的两个坑（都是「光标 w」的账，靠临时探针才定位）**：

1. **每行第一个候选的 rect 宽度算成 0**。`HorizontalLayout.cpp` 里换行块的
   `w = offsetX + real_margin_x` 是在**本候选画完之后**才执行的，而候选词 / 注释的 rect
   是在它之前算的 —— 于是第 3、5 个候选（每行第一格）用的是**上一行行尾**的光标，
   固定格宽下 `cell_right - 注释 - w ≤ 0` → 候选词和注释都成了 0 宽矩形
   （现象：第 2、4 条只剩一个「…」，右侧注释整块消失）。
   **修法**：在循环体**开头**就把光标拉回行首，并且行首那一格**不再**加 `candidate_spacing`
   （加了会让该行整体右移 22px，且换行块把 `offsetX` 记成 -22，注释列跟着错开）。
2. **面板宽度随内容抖动**（实测同一天 1008 / 1053 / 945）。
   `w += text_natural_w` 用的是**未裁剪**的自然宽度（剪贴板长句上千像素），
   注释 rect 被顶到格子外面（`right` 远超 `cell_right`），
   而 `max_width_of_rows = max(..., _candidateCommentRects[i].right)` → 面板宽度跟着涨。
   **修法**：固定格宽时 `w = min(w + text_natural_w, cell_right - cmt_block)`。

**定位手段（已删除，记录备查）**：客户端 `WeaselUI.cpp` / `WeaselPanel.cpp` 里临时写
`D:\weasel-build\tst\client-draw.log`，逐条打印
`DRAW i=N TEXT/CMT rect=l,t,r,b w=… cch=… t=…` 与每次 `UPDATE` 拿到的候选文本 ——
正是这条日志直接读出「`i=2 … w=0`」，两分钟定位，省掉盲猜。**验证完必须删掉**（本轮已删干净，
`Test-Path client-draw.log = False`）。

**实测矩阵**（记事本前台 + `probe-fixed.ps1`，全部通过）：

| 操作 | 候选窗（虚拟像素） | 读出 / 判定 |
| --- | --- | --- |
| `v`→`2` 第 1 页 | `707x144` | 2 列 × 3 行；高亮格蓝块 540 物理 = **360 虚拟 ≈ 屏宽 20%**；6 条都画出文字，注释「剪贴板 N/29」右对齐成两列 |
| `v`→`2` 第 2 / 第 3 页（`=`、`==`） | `707x144` / `707x143` | **面板宽度恒定**（修坑 2 之前是 1053 / 945） |
| `v`→`2` → `↓` → 数字 `2` | — | 上屏 `http://127.0.0.1:5173/` = 第 2 行第 2 格（第 4 条）✅ |
| `v`→`2` → `↑` | `707x144`（不收起） | 高亮停在第 1 行，候选窗不收缩 ✅ |
| `v`→`4`（常用语 2 条） | `707x49` | 两条各占固定一格，注释「常用语 wsl / 131」右对齐 ✅ |
| `v`→`4` → 数字 `1` | — | 上屏 `wslzhenshuai@163.com` ✅ |
| `v`→`5`（原符号）/ `↓` / `↑` | `690x49` → `852x191` → `690x49` | 与正常打字完全一致（9 列 1 行 → 4 行 → 收起）✅ |
| `v`→`5` → 数字 `4` | — | 上屏 `vat` = `vac/van/var/vat/…` 的第 4 个 ✅ |
| 普通打字 `shi` / `↓` | `660x49` / `660x189` | **无回归** ✅ |
| `v` 主菜单 / `v`→`3` | `861x95` / `808x96` | 静态菜单不变（4 列、顺序序号、自然宽度）✅ |

**`…` 到底是谁画的**：主题里 `candidate_abbreviate_length: 30`（`%APPDATA%\Rime\weasel.yaml`）
本来就会把 >30 字的候选**在客户端**缩成「前 29 字 + `...` + 末字」，而且**只影响显示**
（`UI::Update` 改的是 `ctx_` 副本，上屏文本不受影响）；本轮新增的 DirectWrite 裁剪是**第二道保险**，
在格宽收紧到 20% 之后真正开始生效（像素级确认：候选词末尾有 3 个基线小点）。

**部署记录**（`tools\deploy-grid-dlls.ps1 -SourceDir D:\weasel-build\weasel\output`）：

| 文件 | 大小 | md5 |
| --- | --- | --- |
| `WeaselServer.exe` | 2695168 B | `BBAE08F85A6F7A01C64F1995C3570C4D` |
| `weaselx64.dll` → `C:\Windows\System32\weasel.dll` | 1182208 B | `9EBA0A41EE493054FE73663B873B27BE` |
| `weasel.dll` → `C:\Windows\SysWOW64\weasel.dll` | 1038848 B | `E2787640E485034FA1D8FD13250F21DD` |

旧文件备份：`D:\weasel-build\dll-backup\20260919-164421\`。
重编：`pwsh -NoProfile -File D:\weasel-build\build-vmenu.ps1 -Only all`（server 20 s / x64 10 s / x86 12 s）。

> ⚠️ 客户端 DLL 是**进程内**加载：记事本、Chrome、微信…**必须重启进程**才会用上新 DLL。
> 在浏览器里复核时请开一个独立 profile（`--user-data-dir=D:\weasel-build\chrome-ime-profile`），
> 别动用户自己的浏览器会话。

## 7. 未做 / 待确认

| 项 | 说明 |
|---|---|
| 托盘入口 | 见 §4.4，编出的 server 丢了这个入口 |
| ~~v 菜单列表里的 `+`~~ | **第十八轮已解决**（见 §7.4）：列表型 v 功能（`vclip*`/`vfav*`/`vsetc*`/`vsetf*`）的 `+`/`-` 现在按「这一屏的条数」翻页，`↓` 展开 4 行 × 4 列 = 16 个 |
| 被省掉的列仍可被数字键选中 | 收起态只画 2 列时按 `3` 会上屏第 3 条（看不见）—— 前端只是没画，选词下标仍按下标算。要做成「不可选」必须让 Lua 只 yield 可见的那几个，而 Lua 不知道前端裁了几列（除非再返一条协议），成本大于收益，先记为已知特性 |
| `+` 的页数（普通打字） | 默认 4 页（`GRID_PAGES = 4`），与展开态 36 个候选对齐；**v 列表的页数按条目数自动算**（`math.ceil(n / lim)`） |
| 「最右边的回车键也要还原」 | 用户提过但含义未定（原始 0.17.4 主题？），未动 |
| language bar 名称 | 仍是 DLL 里的资源字符串，没改 |
