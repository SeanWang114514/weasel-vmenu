# 文件格式（FILE-FORMATS）

所有文件都在 **Rime 用户目录**（`<RimeUserDir>`，本机为 `D:\rime-sandbox`）。
输入法（Lua）与设置窗口（PowerShell）读写的是**同一批文件**，格式必须严格一致。

| 文件 | 编码 | 谁写 | 谁读 |
| --- | --- | --- | --- |
| `clipboard-cache.txt` | UTF-8 **无 BOM** | `clipboard-sync.ps1`、设置窗口 | Lua、设置窗口 |
| `cn_dicts/favorites.dict.yaml` | UTF-8 无 BOM | 设置窗口、用户 | Lua、设置窗口 |
| `vmenu-settings.txt` | UTF-8 无 BOM | 设置窗口、Lua（`v`→`5`→`3`） | Lua、设置窗口 |
| `open-settings.flag` | 文本（内容不解析） | Lua | 常驻设置窗口（读完即删） |

> **为什么强调「无 BOM」**：带 BOM 时第一条剪贴板内容会多出一个看不见的字符（`U+FEFF`），
> 粘贴出去会莫名多一个空格或让「第一条」匹配失败。

---

## 1. `clipboard-cache.txt`

```
https://example.com/weasel-vmenu/quick-start
明天的会议改到上午十点，地点还是 3 楼会议室。
git clone https://github.com/example/weasel-vmenu.git
alice@example.com
```

* **一行一条**，`\n` 分隔（写文件时用 `\n`，Windows 记事本也能打开）。
* **最新在最上面**，读取顺序即显示顺序。
* **去重**：新内容如果已存在，会先删掉旧的再插到最前面。
* **上限 50 条**（`clipboard-sync.ps1 -Max`，默认 50），超出丢弃**最旧的**。
* **多行内容会被压平成一行**（把 `\r\n`/`\r`/`\n` 换成空格）—— 格式本身就是一行一条。
* 单条最长 2000 字符（超出截断）。
* 空行/纯空白行在读的时候会被跳过。
* 显示条数是**另一个设置**（`vmenu-settings.txt` 的 `clip_page`），与缓存上限无关：
  缓存最多留 50 条，列表默认只显示 20 条，可以按 `m` 一屏一屏加。

写入是**原子**的：先写 `clipboard-cache.txt.tmp`，再 `Move-Item -Force` 覆盖，
避免写到一半被读成半截文件。

## 2. `cn_dicts/favorites.dict.yaml`

```yaml
# Rime dictionary
# encoding: utf-8
---
name: favorites
version: "2026-09-13"
sort: by_weight
...
alice@example.com	you	100000
13800138000	138	100000
北京市朝阳区示例路 1 号	addr	100000
```

* `...` 之后是正文，**每行一条：`内容 <TAB> 编码 <TAB> 词频`**（制表符分隔，不是空格）。
* 以 `#` 开头的行和空行会被忽略；`...` 之前的 YAML 头原样保留。
* **编码**：用于打字命中（`fav_hit` / `fav_exact`）和 `v`→`3` 搜索；匹配时**不分大小写**。
* **内容**：最终上屏的文字，任意 UTF-8 文本（可以含空格）。
* **词频**：本项目的 Lua 不使用它（固定写 `100000`），保留是为了兼容 Rime 词典格式。
* 顺序**有意义**：`v`→`3` 列表和设置窗口都按文件顺序显示，设置窗口的「上移/下移」就是改顺序。
* 编码建议 **≥ 3 个字符**：打字预览规则要求输入 ≥ 3 位；不足 3 位的编码只能用 `v`→`3`。
* **纯数字编码**（如 `138`）是特例，见 `ARCHITECTURE.md` §3.3：中文模式下数字本来是选字键，
  由 `menu_processor` 接管后才进得了编码。

示例文件：[`examples/favorites.example.dict.yaml`](../examples/favorites.example.dict.yaml)

## 3. `vmenu-settings.txt`

```ini
# v 功能菜单设置
clip_page=30
```

* `clip_page`：剪贴板列表**默认显示条数**，合法范围 **20–50**（超出范围按默认 20 处理）。
* 解析规则：`^%s*([%w_]+)%s*=%s*(%d+)`，其它行忽略。
* 文件不存在时用默认值 20（不会自动创建；在设置窗口点一次「保存」才写）。

## 4. `open-settings.flag`

| 内容 | 含义 |
| --- | --- |
| 不存在 | 稳态。没有待处理的打开请求 |
| 任意文本（Lua 写的是 `os.time()` 的时间戳） | 「请把设置窗口显示出来」 |
| `hide` | 「把设置窗口藏起来」（**只给测试脚本用**：`v1-latency-test.ps1` 用它复位） |

生命周期：Lua 写 → 常驻窗口每 60 ms 检查一次 → **读到就删除**再处理。
所以正常情况下这个文件在磁盘上几乎不存在；如果它一直存在，
说明常驻窗口进程没在跑（见 `TROUBLESHOOTING.md`）。

## 5. 编码规则速查（改文件前先看这张表）

| 文件类型 | 要求 | 为什么 |
| --- | --- | --- |
| `.lua` | UTF-8 **无 BOM** | librime-lua 按 UTF-8 读；带 BOM 会让第一行语法错 |
| 数据文件（上表 1–3） | UTF-8 **无 BOM** | 见文首说明 |
| `.ps1`（纯 ASCII） | 无 BOM 也行 | PS 5.1 按 ANSI 解析，ASCII 不受影响 |
| `.ps1`（含中文，如 `vmenu-settings-gui.ps1`） | **必须带 BOM**（`EF BB BF`） | 否则 PS 5.1 按 ANSI 解析，界面中文全乱、字符串可能破坏语法 |
| `.bat` | **CRLF + 纯 ASCII** | cmd.exe 按活动代码页逐块解码，多字节字符跨块会错位 |
| `.md` / `.yaml` 文档与配置 | UTF-8（无 BOM 更保险） | Git / 编辑器通用 |
