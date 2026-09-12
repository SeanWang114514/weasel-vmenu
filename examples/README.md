# 示例数据（examples）

这里的文件**全部是编造的示例数据**，可以直接复制到 `<RimeUserDir>` 里试跑，
也可以用来生成「不含真实内容」的截图。文件名都带 `example`，避免和真实文件混淆。

| 文件 | 放到哪里 | 说明 |
| --- | --- | --- |
| `clipboard-cache.example.txt` | `<RimeUserDir>\clipboard-cache.txt` | 8 条剪贴板示例（含中文、URL、邮箱、订单号） |
| `favorites.example.dict.yaml` | `<RimeUserDir>\cn_dicts\favorites.dict.yaml` | 3 条收藏：字母编码 `you`/`addr` + 纯数字编码 `138` |
| `vmenu-settings.example.txt` | `<RimeUserDir>\vmenu-settings.txt` | 列表默认显示 30 条 |
| `rime_ice.custom.example.yaml` | 作为 `rime_ice.custom.yaml` 的参考 | 结构性配置（processors / translators / filters）的写法 |

## 试跑示例数据

```powershell
$Rime = (Get-ItemProperty 'HKCU:\Software\Rime\Weasel').RimeUserDir
# ★ 先备份真实文件！
Copy-Item "$Rime\clipboard-cache.txt" "$Rime\clipboard-cache.txt.bak" -ErrorAction SilentlyContinue
Copy-Item "$Rime\cn_dicts\favorites.dict.yaml" "$Rime\cn_dicts\favorites.dict.yaml.bak" -ErrorAction SilentlyContinue
# 换入示例
Copy-Item .\examples\clipboard-cache.example.txt "$Rime\clipboard-cache.txt" -Force
Copy-Item .\examples\favorites.example.dict.yaml "$Rime\cn_dicts\favorites.dict.yaml" -Force
New-Item -ItemType Directory -Force "$Rime\cn_dicts" | Out-Null
Copy-Item .\examples\vmenu-settings.example.txt "$Rime\vmenu-settings.txt" -Force
# 重启输入法服务（lua 侧读文件是即时的，但保险起见）
Get-Process WeaselServer | Stop-Process -Force; Start-Sleep 2
Start-Process 'C:\Program Files\Rime\weasel-0.17.4\WeaselServer.exe'
```

验证示例：

| 输入 | 期望 |
| --- | --- |
| `you` | 候选第 2 位 = `alice@example.com 收藏` |
| `you` + 回车 | 上屏 `alice@example.com` |
| `138` | 候选 = `13800138000 收藏` |
| `v` | 5 条菜单 |
| `v` `2` | 显示 8 条示例剪贴板（设置文件写的是 30，但只有 8 条） |

试完记得把 `.bak` 还原回去（或者直接重新复制真实文件），并确认内容对得上。

## 生成截图

设置窗口的截图请用**独立的演示目录**，不要动真实目录：

```powershell
# 造一个演示用户目录
New-Item -ItemType Directory -Force C:\rime-demo\cn_dicts | Out-Null
Copy-Item .\examples\clipboard-cache.example.txt C:\rime-demo\clipboard-cache.txt -Force
Copy-Item .\examples\favorites.example.dict.yaml C:\rime-demo\cn_dicts\favorites.dict.yaml -Force
Copy-Item .\examples\vmenu-settings.example.txt C:\rime-demo\vmenu-settings.txt -Force
# 用演示目录启动设置窗口（先停掉守护进程，避免两个实例抢互斥体）
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\windows\vmenu-watcher-stop.ps1
Start-Process powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden',
  '-File','.\src\windows\vmenu-settings-gui.ps1','-RimeDir','C:\rime-demo','-ShowNow') -WindowStyle Hidden
```

输入法侧的截图（候选栏）需要临时换掉**真实收藏文件**，务必按 `docs/TESTING.md` §3
的「备份 → 替换 → 截图 → 还原 → 校验 SHA256」流程做。

> ⚠️ 不要把真实的 `clipboard-cache.txt` / `favorites.dict.yaml` / 截图提交进仓库：
> 剪贴板里通常有邮箱、手机号、地址、内部链接。`.gitignore` 已经挡住了这些文件名。
