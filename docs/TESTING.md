# 测试与验证（TESTING）

## 0. 原则

1. **真按键 + 截图**：不靠「读代码觉得对」。每个结论都要有一张图或一次真按键的输出。
2. **看 `AFTER=` 判据**：`tools/type-and-shot.ps1` 会打印目标窗口标题（记事本标题=文档内容），
   这比截图更硬。
3. **测延迟要测到「窗口真的在屏幕上」**：`MainWindowHandle != 0` 不够（曾经窗口停在
   -48000,-48000 也被判定为「已显示」），必须同时 `GetWindowRect` 的 `Left/Top > -1000`。
4. **改完 lua 先重启服务再测**，并等 ≥ 6 秒（方案没加载完就打字会丢按键）。
5. **回归矩阵**（每次改动都要过一遍）：

| 用例 | 按键 | 期望 |
| --- | --- | --- |
| 普通拼音 | `n,i` | 候选 你/尼/泥…，不受影响 |
| 纯数字（非编码） | `1,2,3,4,5,enter` | 原样 `12345` |
| 字母编码 + 回车 | `w,s,l,enter` | 收藏内容上屏 |
| 字母编码 + 候选第 2 位 | `w,s,l,2` | 收藏内容上屏 |
| 纯数字编码 | `1,3,8` | 候选直接显示收藏内容 |
| v 菜单 | `esc,v` | 5 个短候选 |
| 文字设置 | `esc,v,5` | 设置根菜单 |
| 设置窗口 | `esc,v,1` | 窗口出现在屏幕上（< 300 ms） |

---

## 1. 工具（`tools/`）

### `type-and-shot.ps1` —— 主力工具

```powershell
# 干净记事本 → 抢焦点 → 真按键 → 截图
Get-Process notepad -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Process notepad; Start-Sleep -Seconds 2
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\type-and-shot.ps1 `
  -Target notepad -Keys 'esc,w,s,l,enter' -Out .\shots\x.png `
  -ShotX 0 -ShotY 40 -ShotW 1700 -ShotH 560
# 输出：FOCUSED=<窗口标题>  AFTER=<按完之后的标题=文档内容>  SHOT=<文件>
```

* 抢焦点用 `AttachThreadInput` + `BringWindowToTop` + 先按一下 ALT 解锁前台锁
  —— 这台机器上 Chrome 会不断抢前台，普通 `SetForegroundWindow` 拿不到。
* `-NoClick` 可以不做「点击编辑区」这一步（默认会点一下确保焦点在文本框）。

### 延迟测试

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\v1-latency-test.ps1 -Runs 3
# gui pid = … / run 1: window visible after 72 ms / min = 56 ms max = 72 ms avg = 65 ms

powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\v1-e2e-test.ps1 -Out .\shots\e2e.png
# hidden before test = True
# v then 1 : settings window visible after 84 ms
# flag consumed = True
```

`v1-latency-test.ps1` 先写 `hide` 把窗口藏起来，再写时间戳，之后每 5 ms 轮询；
`v1-e2e-test.ps1` 真的按 `v` 和 `1`（会先聚焦记事本）。

### 其它

| 工具 | 用途 |
| --- | --- |
| `run-vmenu-tests.ps1` | 18 步菜单流程逐张截图（`shots\vmenu\`） |
| `shot-window.ps1 -Match ' v '` | 只抓设置窗口（DPI-aware） |
| `window-keys-shot.ps1 -Match ' v ' -Keys 'ctrl+tab'` | 抢前台 + 发组合键 + 抓窗口（切设置窗口标签页用） |
| `list-windows.ps1 -MinWidth 600` | 列出可见窗口：`pid / hwnd / 物理坐标 / 标题` |
| `ime-test.ps1` | 老版按键+截图（记事本会移到 80,60） |
| `focus-notepad.ps1` | 只抢焦点 |

---

## 2. 截图取证的坑

| 坑 | 说明 |
| --- | --- |
| **候选栏比 1200 px 宽** | 3 条长收藏的候选栏能到 1300 px。抓宽一点（`-ShotW 1700`），否则右边被截断 |
| **别把桌面截进去** | 截图会带进桌面侧边栏/其它窗口。裁到内容区域：见下面的「暗像素包围盒」办法 |
| **DPI** | 本进程 `SetProcessDPIAware()` 后是**物理坐标**（2560×1440）；不感知的话是虚拟坐标（1707×960）。`GetWindowRect` 抓到的是物理的，别和虚拟混用 |
| **窗口可能停在屏幕外** | 判断「可见」必须同时看句柄和 rect（见原则 3） |
| **前台窗口不是你要的那个** | 抓图前先 `window-keys-shot.ps1`（它内部会抢前台并校验 `FOREGROUND_OK=True`） |

### 自动定位候选栏（裁图用）

候选行在截图里是一大片深色像素，扫一遍就能得到包围盒：

```powershell
Add-Type -AssemblyName System.Drawing
$bmp = [Drawing.Bitmap]::FromFile($raw)
$minX=99999;$maxX=-1;$minY=99999;$maxY=-1
for ($y=150; $y -lt 330; $y++) { for ($x=0; $x -lt $bmp.Width; $x++) {
  $c=$bmp.GetPixel($x,$y); if (($c.R+$c.G+$c.B)/3 -lt 150) {
    if($x -lt $minX){$minX=$x}; if($x -gt $maxX){$maxX=$x}
    if($y -lt $minY){$minY=$y}; if($y -gt $maxY){$maxY=$y} } } }
"bbox: x $minX..$maxX  y $minY..$maxY"   # 例：x 83..1340  y 161..259
```

然后用 `Graphics.DrawImage` 裁出 `(x-20, y-20, w+40, h+40)`。

---

## 3. 怎么生成「不含真实数据」的截图

发布用的截图**必须**是示例数据。做法（本项目实际用过）：

1. 复制 `examples/favorites.example.dict.yaml` 覆盖真实收藏文件，
   **先备份并记录 SHA256**：
   ```powershell
   Copy-Item $real $bak -Force
   "backup sha256 = $((Get-FileHash $bak -Algorithm SHA256).Hash)"
   Copy-Item examples\favorites.example.dict.yaml $real -Force
   ```
2. 抓图（输入法侧用示例编码，如 `you` / `138`）。
3. **还原并校验**：
   ```powershell
   Copy-Item $bak $real -Force
   (Get-FileHash $real -Algorithm SHA256).Hash -eq (Get-FileHash $bak -Algorithm SHA256).Hash  # 必须 True
   ```
4. 设置窗口的截图用**独立的演示目录**（例如 `C:\rime-demo`），不要动真实目录：
   ```powershell
   # 先停掉监督者和常驻窗口，避免两个实例抢互斥体
   powershell -NoProfile -ExecutionPolicy Bypass -File .\src\windows\vmenu-watcher-stop.ps1
   Start-Process powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden',
     '-File','.\src\windows\vmenu-settings-gui.ps1','-RimeDir','C:\rime-demo','-ShowNow') -WindowStyle Hidden
   # 抓图 → 结束后再双击 clipboard-sync.bat 把真实服务拉回来
   ```

---

## 4. 静态检查

```powershell
# 1) PowerShell 语法（PS 5.1）
$errs = $null
[void][System.Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($f), [ref]$errs)
if ($errs.Count) { $errs | ForEach-Object { "line $($_.Token.StartLine): $($_.Message)" } }

# 2) BOM 检查（含中文的 .ps1 必须带 BOM）
(([IO.File]::ReadAllBytes($p)[0..2]) -join ',')      # 期望 239,187,191

# 3) bat 编码检查（必须 CRLF + 纯 ASCII）
$b=[IO.File]::ReadAllBytes($bat); ($b | Where-Object {$_ -gt 127}).Count   # 期望 0

# 4) 两个 lua 目录一致性
foreach ($f in 'vmenu_core.lua','menu_processor.lua','lua_menu.lua','menu_filter.lua') {
  (Get-FileHash "D:\rime-sandbox\lua\$f" -Algorithm MD5).Hash -eq
  (Get-FileHash "$env:APPDATA\Rime\lua\$f" -Algorithm MD5).Hash
}   # 全部期望 True
```

---

## 5. 实测记录（本机 2560×1440 @150%，Weasel 0.17.4）

| 指标 | 数值 |
| --- | --- |
| 标记文件 → 窗口在屏幕上 | 56 / 63 / 72 ms（avg 65 ms） |
| 真按 `v` → `1` → 窗口出现 | 84 / 103 / 106 ms |
| 冷启动后第一次显示 | 106 ms（离屏预建前是 348 ms） |
| 改动前（每次重启 PowerShell + 解析 700 行脚本） | 2000–4000 ms |
| 打字命中收藏（`wsl`） | 无感（≥ 3 字符才读一次小文件） |
