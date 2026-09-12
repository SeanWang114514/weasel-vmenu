# 常见问题（TROUBLESHOOTING）

## 输入法侧

### 按 `v` 没有任何反应

1. `WeaselServer.exe` 在跑吗？`Get-Process WeaselServer`
2. 两个 lua 目录一致吗？（`TESTING.md` §4 的第 4 条）
3. `build\rime_ice.schema.yaml` 里 `engine/processors` 有没有 `lua_processor@*menu_processor`？
   没有就跑 `patch-build-schema.ps1` 再重启服务。
4. `WeaselServer` 日志里有没有 lua 报错：
   ```powershell
   Get-ChildItem "$env:TEMP\rime.weasel\*.log" | Sort-Object LastWriteTime -Descending |
     Select-Object -First 1 | Get-Content | Select-String 'lua|ERROR' | Select-Object -Last 20
   ```
5. 是不是在**英文 / ASCII 模式**？v 功能在该模式下整体关闭，按 `v` 出字母 v（这是设计）。

### 打字变卡 / 一按某个键就卡死

基本可以断定是**在输入线程里做了阻塞的事**：读大文件、起进程（`io.popen`）、等锁。
本项目所有 lua 都已 `pcall` + 只读写小文本文件；如果你新加了逻辑，先按
`AGENT-HANDOFF.md` 的「硬约束」检查一遍。

### 收藏不在候选第 2 位

* 输入是不是**不足 3 个字符**？（规则要求 ≥ 3，避免逐字符读盘）
* 编码匹配是**前缀**匹配，检查编码有没有打错。
* 是不是 `menu_filter.lua` 里 `place()` 之后的 `quality` 重排被删了？
  候选表在 filter 之后还会按 quality 排序，不重排就会乱位。

### 打纯数字没有候选（比如 `138` 应该出收藏）

`menu_processor.lua` 的数字接管分支需要满足：输入为空或全是数字、且
「已输入 + 新按键」仍是某条**纯数字编码**的前缀。检查：

* 收藏里真的有 `138` 这条编码吗？
* `digit_prefix` 里是不是写成了 `#s < #k`？必须是 `#s <= #k`，否则打完整条编码的那一下会被漏掉。

### 回车把原始编码上屏了，而不是收藏内容

`menu_processor.lua` 的 `Return` 分支要求**输入与编码完全一致**（`fav_exact`）。
* `wsl` 会命中，`ws`（前缀）不会 —— 前者是「打完编码」，后者是「还没打完」。
* 该分支被人删掉的话，只有数字编码还能靠「整屏只有一个候选」的巧合回车上屏。

### 有些候选（如「显示更多」）鼠标点不动

**这是 Weasel 的机制，不是 bug**：候选窗口的鼠标点击 = 「提交这一条候选文字」，
不经过按键处理链，所以操作行只能用键盘（`m` / `+` / `d` / `x` / `q`）。

---

## 设置窗口侧

### `v`→`1` 按了没反应

```powershell
# 1) 常驻窗口和守护进程各有一个吗？（注意：命令里不要出现脚本全名，否则会匹配到自己）
$pat = 'vmenu-' + 'settings-gui.ps1'
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine.IndexOf($pat) -ge 0 } |
  ForEach-Object { "gui pid=$($_.ProcessId)" }
$wpat = 'vmenu-' + 'watcher.ps1'
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine.IndexOf($wpat) -ge 0 } |
  ForEach-Object { "watcher pid=$($_.ProcessId)" }
# 2) 标记文件是不是积压了（稳态下不该存在）
Test-Path 'D:\rime-sandbox\open-settings.flag'
```

* 两个都没有 → 双击 `clipboard-sync.bat`（或 `打开设置.bat`）。
* 有窗口进程但窗口不出来 → 结束它，等 3 秒让守护进程用新脚本重新拉起。
* 标记文件一直在 → 常驻窗口没在轮询（进程卡了或不存在）。

### 窗口弹出很慢（几秒）

说明每次都在**重新启动 PowerShell**（而不是让常驻进程显示窗口）。检查
`vmenu-settings-gui.ps1` 里：

* 单实例互斥体分支是否还在（已有实例应该「写标记文件 + `exit 0`」）；
* 进程启动时是否做了离屏 `Show()`+`Hide()` 预建；
* 主循环是否还在每 60 ms 轮询标记文件（而不是每次重开窗口）。

### 窗口里的列表是空的

* 演示目录 / `-RimeDir` 指对了吗？窗口标题里没有路径，但「设置与缓存」页会列出三个文件路径。
* 文件是不是被别的程序写成了带 BOM 或改成了别的编码？
* 设置窗口只在前台显示时刷新数据；点「重新载入」可以手动刷新。

### 关了窗口，再按 `v`→`1` 又弹出来（想彻底退出）

点 × **本来就是只隐藏**（这是秒开的设计）。彻底退出：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\windows\vmenu-watcher-stop.ps1
```

（它会停掉守护进程和常驻窗口；再按 `v`→`1` 就不会有窗口了，此时用
`打开设置.bat` 仍可临时开一个。）

### 中文变成乱码 / 界面文字全乱

编码问题：

* `vmenu-settings-gui.ps1` **必须带 BOM**（`EF BB BF`）——用 `edit` 工具改完常见会丢 BOM；
* `.bat` 必须 CRLF + 纯 ASCII；
* 数据文件必须 UTF-8 **不带** BOM。
详见 `FILE-FORMATS.md` §5。

---

## 服务与生命周期

### 重启电脑后 `v`→`1` 没反应

两个后台服务不会自启。双击一次 `clipboard-sync.bat` 即可。
（仓库里**故意没有**加开机自启：不会静默往用户机器写启动项。需要的话自己加一个启动项，
指向 `clipboard-sync.bat`。）

### `.bat` 文件被安全软件删掉

本机装了火绒 HIPS，「`.bat` 里 `start` 一个隐藏 PowerShell」是典型可疑行为。
`打开设置.bat` 因此改成「先写标记文件 + 拉起守护脚本」。如果它被删了：
直接用 `clipboard-sync.bat`（同一套动作），或者手动执行：

```powershell
Start-Process powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden',
  '-File','.\src\windows\vmenu-watcher.ps1','-RimeDir','D:\rime-sandbox') -WindowStyle Hidden
```

### 多个实例 / 抢互斥体

* 设置窗口：互斥体 `RimeVMenuSettingsGui`，第二个实例只会写标记文件然后退出（不会开第二个窗口）。
* 守护进程：互斥体 `RimeVMenuWatcher`，第二个实例直接退出。
* 想「全部推倒重来」：双击 `clipboard-sync.bat`（它先停旧实例再启动）。

---

## 日志与现场

| 东西 | 位置 |
| --- | --- |
| Rime / lua 日志 | `%TEMP%\rime.weasel\rime.weasel.<host>.<user>.log.INFO.*.log` |
| 输入法文件 | `<RimeUserDir>`（本机 `D:\rime-sandbox`） |
| 编译后的方案 | `<RimeUserDir>\build\rime_ice.schema.yaml` |
| 截好的验证图 | 项目目录下 `shots\`（发布用的图在仓库 `screenshots\`） |
