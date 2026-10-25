# Weasel / VMenu 项目交接提示词

你是下一位负责继续维护本项目的 agent。请在不回退现有用户修改的前提下，继续修复 Weasel 输入法展开候选栏的布局和候选逻辑，并完成真实窗口截图验证。

## 仓库与运行环境

- 父仓库：`D:\weasel-build\weasel`
- 当前分支：`fix/weasel-grid-9x4`
- GitHub 远端：`vmenu`（SeanWang114514/weasel-vmenu）
- 用户配置目录：`D:\rime-sandbox`
- Weasel 安装目录：`C:\Program Files\Rime\weasel-0.17.4`
- 当前使用的 MSBuild：`C:\Program Files\Microsoft Visual Studio\18\Enterprise\MSBuild\Current\Bin\MSBuild.exe`
- 本机只有 VS 2026 v145 工具集。构建时显式加入：
  `/p:PlatformToolset=v145 /p:SolutionDir=D:\weasel-build\weasel\`

## 本次已提交的父仓库改动

1. `WeaselUI/HorizontalLayout.cpp`
   - 展开网格启用统一列宽。
   - 计算每个网格单元的真实左缘和宽度。
   - 候选词和注释限制在当前单元内，避免绘制到相邻候选。
   - 修正符号面板大栏使用独立格宽时的定位。
   - 修正高亮标记左侧位置，避免与首个候选词重叠。
2. `WeaselUI/WeaselPanel.cpp`
   - 词内拼音注音按候选单元剩余宽度裁切。
   - 超出单元宽度时停止绘制后续分段，避免注音跨格重叠。
3. `RimeWithWeasel/RimeWithWeasel.cpp`
   - 普通候选栏收起态接管左右方向键，在候选页内移动高亮。
   - 到达边界时吞掉方向键，避免方向键落到应用文本光标。

## 尚未完成的验证

上一轮已成功构建并部署 `WeaselServer.exe`，但测试时记事本没有被小狼毫接管，候选栏没有出现，所以不能把视觉修复当成已经验证。下一步必须：

1. 确认当前窗口实际使用小狼毫中文输入法。
2. 在空白文档中输入 `rang`，确认候选栏包含“让”。
3. 输入 `zai`、`github`，确认不再出现 `Zaire`、`∫`、`ι` 或“给∫太湖边”这类异常候选。
4. 打开候选展开栏，截图检查：
   - 第一项不与蓝色竖线重影；
   - 每个候选都在自己的格子内；
   - 多行候选之间没有重叠；
   - 展开栏不会把下一行候选绘到上一行；
   - 长候选或带注音候选不会跨格覆盖。
5. 在候选栏收起和展开两种状态分别用左右方向键移动高亮；输入一段拼音后按 Backspace，再检查候选是否重新识别正确。

## 构建与部署

推荐只构建服务端项目：

```powershell
& 'C:\Program Files\Microsoft Visual Studio\18\Enterprise\MSBuild\Current\Bin\MSBuild.exe' `
  'WeaselServer\WeaselServer.vcxproj' /t:Build `
  /p:Configuration=Release /p:Platform=x64 /p:PlatformToolset=v145 `
  /p:SolutionDir='D:\weasel-build\weasel\\' /m /nologo
```

部署前先备份安装目录中的旧文件；上一轮备份示例：
`C:\Program Files\Rime\weasel-0.17.4\WeaselServer.exe.bak-overlap-20261025-010359`

## 子模块注意事项

`librime` 当前是 detached HEAD，且存在未提交本地修改：

- `src/rime/gear/table_translator.cc`：查表前移除撇号/空格分隔符，修复 `u` 部件码查不到词。
- `build.bat`：给带空格的 CMake generator 加引号。
- `deps/*`、`dist_x64/`、`lib_x64/` 等还有本地构建状态或产物。

父仓库中的 `librime-local.patch` 保存了前两项顶层源文件改动，可在需要时执行：

```powershell
git -C D:\weasel-build\weasel\librime apply ..\librime-local.patch
```

补丁不包含 `deps/*` 的嵌套子模块状态和 `dist_x64/`、`lib_x64/` 生成目录。若要继续使用这些子模块改动，请先在子模块单独建立明确分支和提交，再决定是否推送到有权限的 librime fork；不要把生成目录提交进仓库，也不要直接强推官方 `rime/librime`。

## 操作约束

- 不要 `git reset --hard`、`git checkout --` 或删除用户备份。
- 不要覆盖 `RimeWithWeasel.cpp`、`HorizontalLayout.cpp` 中已有的用户改动。
- 视觉验证必须以真实截图为准，不能只凭代码推断“已修复”。
- 若输入法未接管测试窗口，先解决输入法激活/切换问题，再继续截图验证。

完成后请报告：构建结果、部署文件、实际截图验证结果、仍存在的问题，以及父仓库和 `librime` 子模块各自的 Git 状态。
