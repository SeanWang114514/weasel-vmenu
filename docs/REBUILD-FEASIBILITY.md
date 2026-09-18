# 重编 librime + Weasel 的可行性评估

> ## ✅ 已实施（2026-09-18，0.2.5）
> 这份评估的结论**已经落地**：没有改 librime，只改了 Weasel 前端，方向键翻译成
> `highlight_candidate_on_current_page`（正是本文预判的做法）。本机补不齐 Windows SDK + Boost，
> 所以改用 **GitHub Actions** 编。施工单与实测结果见
> [`GRID-CANDIDATE-DLL.md`](GRID-CANDIDATE-DLL.md)。
> 下面保留评估原文（含当时的判断与缺口清单），只作背景参考 —— **别再按它去本机装工具链**。

> 结论先说：**不需要改 librime，只需要改 Weasel**，改动量约 20–40 行 C++；
> 但本机**缺 Windows SDK 和 Boost**，要先把构建环境补齐。
> 本文件是评估，不是施工单 —— 在用户明确同意前不要动现有安装。

## 0. 一句话结论

| 问题 | 结论 |
| --- | --- |
| 要加"只移动高亮、不上屏"的能力，需要改 librime 吗？ | **不需要**。librime 的 C API 里**早就有** `highlight_candidate()`，注释原文就是 *highlight a selection without committing* |
| 那为什么现在做不到？ | 因为**只有 C API 有，librime-lua 没暴露**（探针实测全是 `nil`），Lua 侧够不着 |
| 那要改哪里？ | **只改 Weasel 前端**：在把按键交给 `RimeProcessKey()` 之前，按展开状态把 ↑/↓/←/→ 翻译成 `highlight_candidate(session, 目标下标)` |
| 现在能直接编吗？ | **不能**。缺 Windows SDK（`Windows Kits\10\Include` 与 `Lib` 都不存在）和 Boost 1.84 |
| 风险 | 要替换 `weasel.dll` / `weaselx64.dll`（可能还有 `rime.dll`）。整个安装目录只有 33 MB，可整体备份回滚 |

## 1. 证据链（都是实测/原文，不是推测）

### 1.1 librime C++ 侧：`Highlight()` 存在

`rime/librime` 的 `src/rime/context.h`（master）：

```cpp
  // return false if there is no candidate at index
  bool Select(size_t index);
  // return false if the selected index has not changed
  bool Highlight(size_t index);
```

`Select` = 选中并上屏（这正是 `ctx:select` 在 Lua 里的行为）；**`Highlight` = 只移动高亮**。

### 1.2 librime C API 侧：`highlight_candidate` 存在——**1.13.1 里就有**

`src/rime_api.h`（kRIME_API 结构体，逐 tag 核对过 1.12.0 / 1.13.0 / 1.13.1，三个版本都有）：

```c
  //! highlight a selection without committing
  Bool (*highlight_candidate)(RimeSessionId session_id, size_t index);
  //! highlight a selection without committing
  Bool (*highlight_candidate_on_current_page)(RimeSessionId session_id, size_t index);

  Bool (*change_page)(RimeSessionId session_id, Bool backward);
```

⇒ **运行中的小狼毫 0.17.4（librime 1.13.1）那份 `rime.dll` 已经导出这些函数**，不用重编 librime。

### 1.3 Lua 侧：够不着（这就是当前做不到的直接原因）

在 `grid_key` 里做的探针实测输出：

```
ctx.select ok=true type=function      ← 唯一相关的方法，但它是「选中并上屏」
ctx.select_candidate ok=true type=nil
ctx.set_selected_candidate_index ok=true type=nil
ctx.highlight ok=true type=nil
ctx.move_selection ok=true type=nil
ctx.menu ok=true type=nil
ctx.get_menu ok=true type=nil
ctx.selected_candidate_index ok=true type=nil
```

⇒ librime-lua 没有转出 `highlight_candidate`，也没有暴露任何"只改高亮"的入口。

### 1.4 原生按键也不动高亮（排除"配 key_binder 就行"）

以数字键为基准（`1`→是、`2`→师，说明数字键确实会改变选中项）：

| 操作 | 结果 | 说明 |
| --- | --- | --- |
| `→` ×1 再空格 | 上屏"是"（第 1 个） | 方向键没移动高亮 |
| `→` ×3 再空格 | 上屏"是"（第 1 个） | 同上 |
| `↓↓` 展开后 `→` 再空格 | 上屏"是" | 同上 |
| 把方向键 `return 0`（拒绝、交回后面的处理器） | 输入被 `express_editor` 改坏（只剩 `s`） | 所以现在方向键仍用 `return 2` 吞掉 |

## 2. 本机构建环境现状（实测）

| 项目 | 状态 |
| --- | --- |
| git | ✅ 2.53.0.windows.2 |
| Python | ✅ 3.14.7 |
| CMake | ✅ 4.4.2 |
| Visual Studio | ✅ VS 2026 生成工具 18.9.12120.119（`C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools`） |
| VC++ 工具集 | ✅ 已装（`vcvars64.bat` 存在，MSVC 14.51.36231，`cl.exe` 存在） |
| **Windows SDK** | ✗ **没有**（`Windows Kits\10` 下只有 `Catalogs/Redist/UnionMetadata`，`Include`、`Lib` 都不存在；VS 安装清单里也没有 SDK 组件） |
| **Boost** | ✗ 没有（没装 vcpkg；`C:\boost`、`C:\local`、`D:\boost` 等都不存在） |
| librime / weasel 源码 | ✗ 本地没有，需要 clone |
| 现有安装 | `C:\Program Files\Rime\weasel-0.17.4`，33 MB（`rime.dll` 3442 KB、`weasel.dll` 888 KB、`weaselx64.dll` 1064 KB） |
| 磁盘 | D: 46 GB 可用 ✅ / C: 15 GB（偏紧，构建目录建议放 D:） |

官方 CI（`rime/weasel` 的 `.github/workflows/ci.yml`）给出的依赖口径：

```
submodules: true                       → git submodule update --init --recursive
boost_version: 1.84.0
BOOST_ROOT: ${{ github.workspace }}\deps\boost_1_84_0
./install_boost.bat                    → 用仓库自带脚本装 Boost
sdk: 10.0.19041.0                      → Windows SDK 版本
./build.bat boost arm64                → 用仓库自带脚本构建
```

⇒ 也就是说：**Weasel 官方是自带构建脚本的**（`install_boost.bat` + `build.bat`），不用自己拼 CMake 参数；缺的就是 SDK 和 Boost 这两样。

## 3. 要做的事（如果决定动手）

### 3.1 环境（需要用户参与的地方）

1. 用 **VS Installer** 勾选「Windows 11 SDK」（约 2–3 GB，要管理员）。当前没有 SDK 的头文件和库，**这一步不做，编译一定失败**。
2. clone `rime/weasel`（**取 0.17.4 那个 tag**，与现有安装对齐，避免 ABI/主题行为漂移），`git submodule update --init --recursive`。
3. 跑仓库自带的 `install_boost.bat` 装 Boost 1.84（BOOST_ROOT 指向 `deps\boost_1_84_0`）。
4. 构建目录放 D: 盘（C: 只剩 15 GB）。

### 3.2 代码改动（只动 Weasel，约 20–40 行）

思路：按键在 Weasel 侧是先经过服务端再交给 `RimeProcessKey()` 的，所以在**交出去之前**插一段拦截：

```cpp
// 伪代码，位置需在源码里定点确认（候选：WeaselServer 的按键分发 / RimeWithWeasel 的 ProcessKey 路径）
if (rime_api->get_option(session_id, "vmenu_grid")) {          // 展开状态由 Lua 处理器设置的上下文选项
  RIME_STRUCT(RimeContext, ctx);
  rime_api->get_context(session_id, &ctx);
  int cur = ctx.menu.highlighted_candidate_index;               // 当前高亮
  int n   = ctx.menu.num_candidates;                            // 本页候选数（展开时 36）
  int cols = 9;                                                 // 与主题 max_width 对应的每行列数
  int target = -1;
  if (key == VK_DOWN)  target = cur + cols;
  if (key == VK_UP)    target = cur - cols;
  if (key == VK_LEFT)  target = cur - 1;
  if (key == VK_RIGHT) target = cur + 1;
  if (target >= 0 && target < n &&
      RIME_API_AVAILABLE(rime_api, highlight_candidate)) {
    rime_api->highlight_candidate(session_id, (size_t)target);  // ← 只移动高亮，不上屏
    return handled;                                             // 不要再交给 RimeProcessKey
  }
}
```

要点：
- `vmenu_grid` 这个选项**已经是 Lua 处理器在维护的**（展开时 `ctx:set_option("vmenu_grid", true)`），是 session 级选项，Weasel 用 `get_option` 就能读到 —— **前端与 Lua 的对接不需要新增协议**。
- 用 `RIME_API_AVAILABLE(rime_api, highlight_candidate)` 做版本守卫（这是 librime 官方推荐写法），函数不存在时自动退回原行为。
- `cols` 要跟主题 `style/layout/max_width: 530`（= 9 个一行）一致；若以后改主题，这里也要跟着改，最好改成读配置。
- 边界处理：`target` 越界（例如第一行按 ↑）时**不拦截**，交回 Rime 处理 —— 这样"第一行按 ↑ 收起"的现有行为（Lua 侧 `↑` = 收起）仍然成立。

### 3.3 验证方法（必须实测）

1. 编译产物先**不放回安装目录**，用 `build.bat` 的输出目录起一个独立 `WeaselServer.exe` 试（或先整目录备份）。
2. 回归矩阵：① 默认单行 ✅ ② `↓` 展开 4×9 ✅ ③ 展开后 `↓↓` 下移两行、`←→` 左右移动、上屏内容随高亮变化（用数字键做基准对照）④ 第一行按 `↑` 收起 ⑤ 普通打字（不展开时）方向键行为与现在一致 ⑥ ASCII 模式不受影响。
3. 小狼毫重启后**必须**确认 `vmenu_grid` 选项在非展开状态下为 false，避免拦截误伤普通输入。

### 3.4 回滚

- 施工前：把 `C:\Program Files\Rime\weasel-0.17.4` **整个目录**（33 MB）复制到 D: 备份。
- 出问题：把备份目录覆盖回去 + 重启 `WeaselServer` 即可，配置（`D:\rime-sandbox`）完全不受影响。
- 因为**不动 librime**，所以不存在"要同时回滚两份二进制"的连锁风险。

## 4. 不装 SDK / 不动 Weasel 的替代方案

| 方案 | 能到什么程度 | 代价 |
| --- | --- | --- |
| 维持现状（推荐先做） | 单行 ↔ 4×9 展开收起、第一行 1–9 序号、数字键选前 10 个 | 展开后选不到第 11–36 个；方向键不动选中项 |
| 展开后"按行翻页"（纯 Lua） | 用 `Page_Down/Page_Up` 或自定义键，让候选按 9 个一组滚动 | `page_size` 必须 = 9，那窗口就只剩一行，**和 4×9 网格冲突**，不可行 |
| 过滤器轮转（纯 Lua） | 能改变"哪个候选落在高亮位" | 4×9 网格会随操作滚动/错位，视觉上不是稳定网格，不推荐 |
| 改 Weasel（本文件 §3） | 完全达成目标里的二维移动 | 要补 SDK + Boost，替换前端 dll |

## 5. 建议

1. **先按现状交付**（已经能用、已验证、不碰二进制），把本文件作为"要完整实现时怎么做"的施工依据。
2. 真要动手时，按 §3.1 → §3.2 → §3.3 的顺序走，并且**第一步只装 SDK + 编出一个未修改的 Weasel**，确认能编出与现有版本行为一致的东西，再动代码 —— 把"能不能编"和"改得对不对"分成两次验证。

## 6. 工具链验证实测结果（第 6 轮，已完成）

用户选择"先只验证工具链"，于是把源码和依赖都准备好了，并用**真实编译**验证到底缺什么。

### 6.1 已经准备好的东西

| 项目 | 状态 |
| --- | --- |
| weasel 源码 | ✅ 官方 tag **0.17.4**（HEAD `9cc96e2`）浅克隆到 `D:\weasel-build\weasel` |
| 子模块 | ✅ 递归拉齐（`librime`、`plum`，以及 librime 自己的 `deps/`：leveldb、marisa-trie、opencc、yaml-cpp…） |
| 自带 librime 版本 | ✅ **1.13.1**（HEAD `1c233581`）—— 与当前安装的 `rime.dll` 同一代；其 `src/rime_api.h` 里 **`highlight_candidate` 确实存在（2 处）**，与 §1.2 的结论互相印证 |
| Boost 1.84.0 | ✅ 已下载并解压到 `D:\weasel-build\weasel\deps\boost_1_84_0`（234 MB） |
| 构建脚本 | ✅ 仓库自带 `build.bat`、`env.bat.template`、`install_boost.bat`、`xbuild.bat`；`INSTALL.md` 说明完整 |

### 6.2 缺什么（这是唯一的拦路石）

| 缺失 | 证据 |
| --- | --- |
| **Windows SDK** | 用 `vcvars64.bat` 起 MSVC 环境后编译一个含 `#include <windows.h>` 的最小文件：<br>`t.cpp(1): fatal error C1083: 无法打开包括文件: "windows.h": No such file or directory`<br>`vcvars64` 环境变量里也**没有** `WindowsSDK*` 任何一项；`Windows Kits\10` 下只有 `Catalogs / Redist / UnionMetadata`，**没有 `Include`、没有 `Lib`** |
| **ATL / MFC** | `INSTALL.md` 要求 VS 装 *ATL*、*MFC* 组件（小狼毫的候选窗口本身就是 ATL —— 我们能枚举到类名 `ATL:` 的候选窗口就是证据）。实测 MSVC 14.51.36231 目录下 `atlmfc\include\atlbase.h`、`afxwin.h` **都不存在** |

### 6.3 两个已经绕过/需要留意的坑

- `install_boost.bat` 依赖 **`aria2c` + `7z`**，本机两者都没有 ✗。
  **已绕过**：改用 `Invoke-WebRequest` 下 `boost_1_84_0.tar.gz` + Windows 自带的 `tar -xzf` 解压，成功得到 234 MB 的 Boost（所以 Boost 这一步**不需要**再装 aria2c/7z）。
- 本机 VS 是 **2026（18.x）BuildTools**，而脚本只提供 `env.vs2019.bat` / `env.vs2022.bat`，`env.bat.template` 里默认 `BJAM_TOOLSET=msvc-14.2`、`PLATFORM_TOOLSET=v142`（对应 VS2019/2022）。**编译器本身可用**（`cl.exe` 能跑），但工具集版本号可能要按实际情况调整 —— 这一步要等 SDK 装好、真正跑 `build.bat` 时才能确认。

### 6.4 结论

> **只差用户装两个组件（Windows SDK + ATL/MFC），其余全部就绪。**
> 装完就能跑 `install_boost`（已备好）→ `build.bat` 编出一个未修改的 Weasel，
> 然后再按 §3.2 打上那 20–40 行改动、按 §3.3 验证、按 §3.4 回滚。
> 全程**不需要改 librime**：`highlight_candidate` 在 0.17.4 自带的 librime 1.13.1 里就有。
