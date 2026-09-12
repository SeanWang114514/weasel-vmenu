# AGENT-HANDOFF · 给下一个 agent 的交接说明

> **先读这份，再动代码。** 这份文档假设你（下一个 agent）没有本次会话的上下文，
> 但可以直接在这台机器上操作。

---

## 0. 60 秒上手

1. 这是 **Windows 输入法扩展**项目，宿主是 **小狼毫 Weasel 0.17.4 + librime 1.13.1 + rime-ice**。
   它给输入法加了一套「按 `v` 打开的功能菜单」（现在 **4 项**：设置 / 剪贴板 / 常用语 / 原符号）、
   常驻的 WinForms 设置窗口（支持双击编辑）、以及多行候选框。
2. 输入法侧是 **librime-lua**（`src/lua/`），宿主侧是 **PowerShell 5.1 脚本 + bat**（`src/windows/`）。
   **没有任何需要编译的代码。**
3. 改动之后通常要做这两件事，否则看不到效果：
   * 改了 **lua** → 把文件同步到两个 lua 目录，然后**重启 `WeaselServer.exe`**；
   * 改了 **`.ps1`** → 结束对应的常驻进程，让 `vmenu-watcher.ps1` 用新脚本重新拉起。
   * 改了 **主题/方案的候选框键**（`max_width` / `page_size`）→ 改 `custom.yaml` **和**
     `build/*.yaml`，再重启 `WeaselServer`。
4. 验证一律用**截图 + 真按键**（`tools/` 里现成的脚本），不要靠「读代码觉得对」。
5. 当前状态与开放问题见 [`PROGRESS.md`](PROGRESS.md) 第 4、5 节。

---

## 1. 本机环境事实（写死的事实，别再试探）

| 事实 | 值 |
| --- | --- |
| 系统 | Windows 10/11（本机用户名/主机名从略：`$env:USERNAME` / `$env:COMPUTERNAME`） |
| Python / Node | 本机有 Node v24（用于读 DSH 会话文件等）；主脚本语言是 **Windows PowerShell 5.1**（**没有** pwsh 7） |
| Weasel | `C:\Program Files\Rime\weasel-0.17.4\`（`WeaselServer.exe`、`WeaselDeployer.exe`） |
| Rime 用户目录 | 注册表 `HKCU\Software\Rime\Weasel` 的 `RimeUserDir` → **`D:\rime-sandbox`**（这是当前生效目录） |
| Lua 镜像目录 | `%APPDATA%\Rime\lua\` —— **必须与 `<RimeUserDir>\lua\` 保持 MD5 一致**（历史遗留的双目录结构，两边都要放） |
| 方案 | `rime_ice`（雾凇拼音），编译产物 `D:\rime-sandbox\build\rime_ice.schema.yaml` |
| 候选框换行 | 主题键 `style/layout/max_width` = **300**（`0` = 不换行），写在 `weasel.custom.yaml` + `build/weasel.yaml` + `%APPDATA%\Rime\build\weasel.yaml` |
| 一页候选数 | 方案键 `menu/page_size` = **18**（原 9），写在 `rime_ice.custom.yaml` + `build/rime_ice.schema.yaml` |
| 屏幕 | 物理 2560×1440，缩放 150%（虚拟 1707×960） |
| 安全软件 | 火绒 HIPS 在运行（会盯「bat 起隐藏 PowerShell」这类行为） |
| 本项目工作目录 | `D:\VibeCoding\输入法`（脚本、截图、备份都在这里） |

### 部署器的一个坑（一定要知道）

`WeaselDeployer` / `WeaselServer /deploy` 在**这台机器上不会重新编译 schema**：
librime 的 `DetectModifications` 判定「无改动」后会**直接中止整个部署**。
所以 `engine/processors|translators|filters`、`punctuator/symbols`、`recognizer/patterns`
这些**结构性**配置的改动，必须用 `src/windows/patch-build-schema.ps1`
把语义**直接写回** `build\rime_ice.schema.yaml`，再重启服务。脚本可重复运行。

---

## 2. 硬约束（违反会出事故）

| # | 约束 | 原因 |
| --- | --- | --- |
| 1 | **绝不在 Rime 输入线程里启动子进程**（Lua 里禁用 `io.popen` / `os.execute`） | 早期版本在 Lua 里读剪贴板，直接卡死输入法。Lua 只能读写文本文件 |
| 2 | Lua 里的对外函数一律用 `pcall` 兜底，异常时 `return 2`（放行） | 输入法绝不能因为扩展报错而不能打字 |
| 3 | 普通打字路径**不读写文件**（`fav_hit` 只在输入 ≥ 3 字符时才读） | 打字流畅度优先 |
| 4 | 候选顺序：filter 的 yield 顺序是权威，但**必须同时把 `quality` 改成严格递减** | 否则后置排序会打乱「常用语在第 2 位」 |
| 5 | 改完 lua **必须重启 `WeaselServer.exe`** | librime-lua 是启动时加载模块 |
| 6 | 两个 lua 目录必须同步（MD5 一致） | 双目录结构，不同步会出现「改了没生效」 |
| 7 | `.ps1` 里**要么纯 ASCII，要么带 BOM** | PS 5.1 把无 BOM 的 UTF-8 当 ANSI 解析，中文注释/字符串会炸解析 |
| 8 | `.bat` 必须 **CRLF + 纯 ASCII** | cmd.exe 按活动代码页逐块解码，多字节字符跨块会错位 |
| 9 | 按命令行匹配进程来杀进程的脚本，**必须排除自己**（`$PID`）或运行时拼接脚本名 | 自己的 pwsh 命令行里含脚本字面名 → 自杀（实测把自己打断过） |
| 10 | 不要永久修改系统输入法选择 / 不要静默写开机启动项 | 用户环境优先；需要自启时先问 |
| 11 | **Lua 一律不拦截方向键**（`↓`/`↑`/`←`/`→` 不写进任何分支） | 原版 `navigator` 的行为已正确（`↓`/`→` = 下一个候选、不上屏），自己接管会破坏手感并与换行/翻页逻辑打架 |
| 12 | 改 `build/*.yaml`（`weasel.yaml` / `rime_ice.schema.yaml`）**只用 `[IO.File]::ReadAllText/WriteAllText` + UTF-8** | PS 5.1 的 `Get-Content`/`Set-Content` 按 ANSI 解码，写坏 YAML 后**候选窗口完全不显示** |
| 13 | 候选框行数/列数**不要去 Lua 里找办法** | 换行是 Weasel 主题 `style/layout/max_width` 的渲染行为，一页条数是 schema 的 `menu/page_size`，输入法内无法运行时切换 |

---

## 3. 目录与「改哪里」

```
src/lua/           → 复制到 <RimeUserDir>\lua\ 和 %APPDATA%\Rime\lua\
  vmenu_core.lua      共享核心：路径、设置读写、剪贴板/常用语读写、命中判断、原符号标记
  menu_processor.lua  ★ 按键总管（必须排在 speller/selector 之前）：v 菜单（1-4）、数字编码、回车调用
                        方向键一律不拦截；主菜单第 5 项已去掉（vset* 保留但不可从菜单进入）
  lua_menu.lua        ★ translator：产出所有菜单/列表候选（文案都在这里，要改文案就改它）
                        yield_menu 现在只 yield 4 项：设置/剪贴板/常用语/原符号
  menu_filter.lua     ★ filter：v 模式只留需要的候选；普通打字时把常用语插到第 2 位

src/windows/       → 放到任意目录（脚本间用 %~dp0 互相调用，必须保持同目录）
  vmenu-settings-gui.ps1  ★ 常驻设置窗口（WinForms）：三个标签页 + 标记文件轮询 + 离屏预建
                            + 列表双击编辑（Edit-Clipboard / Edit-Favorite）
  vmenu-watcher.ps1       监督者：窗口没在跑就拉起来（单实例互斥体 RimeVMenuWatcher）
  vmenu-watcher-stop.ps1  停止监督者 + 常驻窗口
  clipboard-sync.ps1      剪贴板 → clipboard-cache.txt
  clipboard-sync-stop.ps1 停止剪贴板同步
  patch-build-schema.ps1  把结构性配置写回 build\rime_ice.schema.yaml
  clipboard-sync.bat      一键重启两个服务并打开设置窗口
  打开设置.bat             先写标记文件，再拉起监督者（最快的备用入口）
  重建部署.bat             patch-build-schema + 重启服务

tools/             → 验证工具（见第 5 节）
examples/          → 示例数据（常用语、剪贴板缓存、设置文件、custom.yaml）
screenshots/       → README 用图（**全部是示例数据**，不要往这里放真实剪贴板内容）
```

---

## 4. 怎么改、怎么让它生效

### 改 Lua（输入法行为、菜单文案、命中规则）

```powershell
# 1) 在 src/lua/ 改完，同步到两个目录
$a = 'D:\rime-sandbox\lua'; $b = "$env:APPDATA\Rime\lua"
foreach ($f in 'vmenu_core.lua','menu_processor.lua','lua_menu.lua','menu_filter.lua') {
  Copy-Item (Join-Path $a $f) (Join-Path $b $f) -Force
}
# 2) 重启输入法服务
Get-Process WeaselServer -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
Start-Process 'C:\Program Files\Rime\weasel-0.17.4\WeaselServer.exe'
Start-Sleep -Seconds 7      # 等它把方案加载完，太早打字会丢按键
# 3) 看日志有没有 lua 报错（有的话一定是 lua 语法/API 用错）
Get-ChildItem "$env:TEMP\rime.weasel\*.log" | Sort-Object LastWriteTime -Descending |
  Select-Object -First 1 | Get-Content | Select-String 'lua|ERROR' | Select-Object -Last 20
```

### 改设置窗口（`vmenu-settings-gui.ps1`）

```powershell
# 结束常驻窗口（注意：命令里不要出现脚本全名，否则会匹配到自己的进程）
$pat = 'vmenu-' + 'settings-gui.ps1'
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine.IndexOf($pat) -ge 0 } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
# 3 秒内 vmenu-watcher.ps1 会用新脚本把它拉起来
# ★ 编辑后必须补回 BOM：
$p = 'D:\VibeCoding\输入法\vmenu-settings-gui.ps1'
$t = [IO.File]::ReadAllText($p)
[IO.File]::WriteAllText($p, $t, (New-Object Text.UTF8Encoding($true)))
'BOM: ' + (([IO.File]::ReadAllBytes($p)[0..2]) -join ',')   # 必须是 239,187,191
```

### 改结构性配置（processors / translators / filters / punctuator）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\windows\patch-build-schema.ps1 -RimeDir D:\rime-sandbox
# 然后重启 WeaselServer（或直接双击 src\windows\重建部署.bat）
```

### 改候选框行列数（多行候选）

**不在 Lua 里**，只有两个键；两处（`custom.yaml` + `build/*.yaml`）都要改，然后重启服务。
**必须用 UTF-8 读写**，绝不能用 `Get-Content`/`Set-Content`（会把 YAML 写坏，
后果是候选窗口完全不显示）：

```powershell
function Set-YamlValue($p, $pattern, $value) {
  $t = [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8)
  $t = [regex]::Replace($t, $pattern, $value)
  [IO.File]::WriteAllText($p, $t, (New-Object Text.UTF8Encoding($false)))   # false = 无 BOM
}
# 每行几个（越小行越多）：0 = 不换行；实测 620 不换行、300 换行
Set-YamlValue 'D:\rime-sandbox\build\weasel.yaml' '(?m)^(\s*max_width:)\s*\d+' '$1 300'
# 一页几条（现在 18 ≈ 4 行 × 5 列）
Set-YamlValue 'D:\rime-sandbox\build\rime_ice.schema.yaml' '(?m)^(\s*page_size:)\s*\d+' '$1 18'
# custom.yaml 里的 patch 也要同步改，再重启服务：
Get-Process WeaselServer -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Process 'C:\Program Files\Rime\weasel-0.17.4\WeaselServer.exe'
# 看日志确认没有 Error parsing；回退 = max_width 0 + page_size 9
```

验证要用**截图**：`v` 之后或打一段拼音刷出 ≥ 6 条候选，看是否折行。

---

## 5. 验证工具（全部在 `tools/`，都是 ASCII-only 的 PS 5.1 脚本）

| 工具 | 用途 | 例子 |
| --- | --- | --- |
| `type-and-shot.ps1` | **抢焦点 + 真按键 + 截图**（`AttachThreadInput` + ALT 解锁，能打赢 Chrome 抢焦点） | `-Target notepad -Keys 'esc,w,s,l,enter' -Out shots\x.png -ShotX 0 -ShotY 40 -ShotW 1700 -ShotH 560` |
| `ime-test.ps1` | 老版按键+截图（会把记事本移到 80,60） | `-Keys 'esc,v,1' -Out shots\x.png` |
| `run-vmenu-tests.ps1` | 把 18 个菜单流程步骤各截一张图 | 无参数 |
| `v1-latency-test.ps1` | 标记文件 → 窗口出现在屏幕上的延迟（轮询 5 ms） | `-Runs 3` |
| `v1-e2e-test.ps1` | **真按 `v` `1`** → 窗口出现的端到端延迟 | `-Out shots\e2e.png` |
| `gui-dblclick-test.ps1` | **设置窗口双击编辑**：截图找行 + 真实鼠标双击 → 等弹框标题 | `-Row 1 -Out shots\dblclick.png`；`-PreX 300 -PreY 200 -Row 1 -Expect '修改常用语'`；`-Row 1 -TypeInto test`（会真的改文件，先备份） |
| `shot-window.ps1` | 按窗口标题抓单个窗口（DPI-aware） | `-Match ' v ' -Out shots\w.png` |
| `window-keys-shot.ps1` | 抢前台 + 发组合键（如 `ctrl+tab`）+ 抓窗口 | `-Match ' v ' -Keys 'ctrl+tab' -Out x.png` |
| `list-windows.ps1` | 列出可见窗口（pid / hwnd / 物理坐标 / 标题） | `-MinWidth 600` |
| `focus-notepad.ps1` | 只抢焦点 | 无参数 |

### 截图取证的正确姿势

1. 先 `Get-Process notepad | Stop-Process -Force`，再 `Start-Process notepad`（干净文档，标题显示内容）。
2. `type-and-shot.ps1` 会返回 `FOCUSED=` / `AFTER=`（记事本标题=已输入内容）/ `SHOT=`，
   **`AFTER=` 就是判据**：例如 `AFTER=*13800138000` 表示号码真的上屏了。
3. 需要看清楚候选栏时，用 `-ShotW 1700` 抓宽一点（候选栏可能超过 1200 px），
   再用 `System.Drawing` 裁到正文区域，避免把桌面/其它窗口截进去。
4. 想确认「窗口真的可见」，必须同时判 `MainWindowHandle != 0` **且** `GetWindowRect` 的
   `Left/Top > -1000`（曾经出现过窗口停在 -48000,-48000 却被判为「已显示」）。
5. **设置窗口的 GUI 自动化不要用 UI Automation**：`FindAll(Descendants, TrueCondition)`
   对它是 0 个元素。只能「截图找行 + 真实鼠标」，并且进程要先 `SetProcessDPIAware()`
   （否则坐标被 1.5 倍缩放，点到别的行）。模态弹框要用 `EnumWindows` + `GetWindowTextW` 找
   （它不进 `Process.MainWindowTitle`）。现成实现：`tools/gui-dblclick-test.ps1`。

---

## 6. 排查手册（症状 → 检查点）

| 症状 | 先查什么 |
| --- | --- |
| 按 `v` 没反应 | `WeaselServer` 是否在跑；两个 lua 目录是否一致；`WeaselServer` 日志里有没有 lua 报错；`patch-build-schema.ps1` 是否写入过 `lua_processor@*menu_processor` |
| `v`→`1` 没反应 | `vmenu-watcher` 和常驻窗口进程是否各有一个（见 §3 的检查命令）；`open-settings.flag` 是否被消费（稳态下不该存在） |
| 窗口弹得慢 | 常驻进程还在吗？如果每次都要重新起 PowerShell，看 `-ShowNow` 分支和离屏预建那两段是否被改坏 |
| 常用语不在第 2 位 | `menu_filter.lua` 的 `place()` 是否还把整表 `quality` 改成递减；`fav_hit` 是否被改成「精确匹配」 |
| 打数字没候选 | `menu_processor.lua` 的 `digit_prefix` 分支是否还在（注意 `#s <= #k`，写成 `<` 会漏最后一位） |
| 回车把原始编码上屏而不是常用语 | `menu_processor.lua` 的 `Return` 分支是否还在；`fav_exact` 是否要求**完全一致** |
| 保存的中文变乱码 | 对应文件是不是 BOM/编码问题（`.ps1` 带 BOM、数据文件不带 BOM、`.bat` 纯 ASCII + CRLF） |
| **打字完全看不到候选框** | `build\weasel.yaml` 是不是被 `Get-Content`/`Set-Content` 写坏了（日志里找 `Error parsing`）；用 UTF-8 读写改回 |
| 候选框不换行（还是长长一条） | `build\weasel.yaml` 的 `max_width` 是不是 `0`；`page_size` 是不是还停在 `9`（改完要重启 `WeaselServer`） |
| 按 `↓` / `→` 没反应或行为怪 | `menu_processor.lua` 里是不是有人加了方向键分支 —— **不该有**，方向键必须放行给原版 `navigator` |
| 菜单里按 `5` 没反应 | **正常**：第 5 项已去掉，`vset*` 只能手打 `vset` 进入 |
| 双击列表某一项没反应 | 是不是没点到行？列表区域默认 `ListTop=200`（跳过表头）；用 `gui-dblclick-test.ps1 -DryRun` 先确认找得到行 |
| 打字变卡 | 是不是在普通打字路径里读了文件或起了进程（约束 1、3） |

---

## 7. 安全改动清单（每次改完都过一遍）

- [ ] Lua：`pcall` 兜底、普通路径不读盘、不启动进程
- [ ] 同步两个 lua 目录并校验 MD5
- [ ] 重启 `WeaselServer` 并等 ≥ 6 秒
- [ ] 看日志没有新的 lua/ERROR
- [ ] 用 `type-and-shot.ps1` 真按键验证，并**看图**确认候选栏内容
- [ ] 回归：`ni`（普通拼音候选正常）、`12345`（纯数字正常）、`wsl`/`138`（常用语命中）、`v` 菜单（4 项）、`v`→`3` 列表
- [ ] 改了 `.ps1` 的话补回 BOM 并检查解析（`Parser::ParseFile`）
- [ ] 改了候选框键（`max_width`/`page_size`）的话：`custom.yaml` 与 `build/*.yaml` 都改了、用 UTF-8 读写、日志没有 `Error parsing`、截图确认折行
- [ ] 双击编辑的测试跑完**把数据还原**并校验 sha256
- [ ] 截图/示例数据里**不出现真实剪贴板、邮箱、手机号**

---

## 8. 当前状态 / 已完成 / 下一步

### 已完成并验收（2026-09-13 第二轮）

* `v` 菜单 **4 项**（`1 设置` / `2 剪贴板` / `3 常用语` / `4 原符号`）；第 5 项「文字设置」已去掉。
* 「收藏」→「常用语」改名（**只改用户可见文本**；`favorites.dict.yaml` / `vfav` / `vset*` /
  `vmenu-settings.txt` 等内部标识沿用旧名）。
* **多行候选框**：主题 `style/layout/max_width = 300` + 方案 `menu/page_size = 18`
  → 一页 18 条、约 4 行 × 5 列；回退 = `0` + `9`。方向键 `↓↑←→` 一律交回 librime `navigator`
  （`↓`/`→` = 下一个候选，不上屏）。
* 设置窗口**双击编辑**：剪贴板页弹「编辑第 N 条」、常用语页弹「修改常用语」；
  已端到端验收（双击第 1 行 → 输入 `test` → 文件第 1 行变化 → 还原后 sha256 一致）。
* 新测试工具 `tools/gui-dblclick-test.ps1`（截图找行 + 真实鼠标双击），
  用法与实测几何见 `TESTING.md` §1；退出码 0 / 1 / 2。

### 下一步（按价值排序）

1. **确认开放问题 1**（「最右边的回车键也要还原」的确切含义，见 `PROGRESS.md` §5）——
   到现在**仍未确认**；如果是别的意思，改 `menu_processor.lua` 的 `Return` 分支即可。
2. **`vset*` 死代码怎么处理待定**：菜单去掉第 5 项后它已不可达（只有手打 `vset` 进得去）。
   删掉能省一大段文案与分支；留着保留「窗口挂了也能改设置」的兜底。需要人类拍板。
3. **多行候选框参数是否再调**：现在 `max_width=300` + `page_size=18`。
   想变列数就调 `max_width`（`620` 不换行、`300` 换行），想变总条数就调 `page_size`；
   都需要改 `custom.yaml` + `build/*.yaml` 并重启服务。
4. DPI 感知：给 `vmenu-settings-gui.ps1` 加 `SetProcessDPIAware()` 并把所有尺寸乘 `DpiX/96`，
   解决 150% 下文字略软。
5. 开机自启（用户明确要求时）：加 `install-autostart.ps1`（写入启动项前必须显式确认）。
6. 剪贴板条目支持多行（现在被压平成一行）；需要改缓存格式 + 读写两侧。
7. 常用语编码不足 3 位时也能在打字时命中（现在只能用 `v`→`3`）；代价是要在 1–2 个字符时也读文件，
   需要先做性能测量。
