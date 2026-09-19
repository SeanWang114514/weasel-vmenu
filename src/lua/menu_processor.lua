-- v 功能菜单：按键处理（必须排在 speller / selector 之前）
-- 只在 v 相关模式下拦截按键，其余按键一律 return 2 放行。
-- 整个处理体用 pcall 包裹：任何异常都退化为「不处理」，绝不阻塞输入。
local core = require("vmenu_core")

local function replace_input(ctx, s)
  ctx:clear()
  ctx:push_input(s)
end

local function is_more_key(repr)
  return repr == "m" or repr == "plus"
end

local function handle(key, env)
  if key:release() then return 2 end

  local ctx = env.engine.context
  local repr = key:repr() or ""
  local cur = ctx.input or ""

  -- 英文 / ASCII 模式：v 功能整体关闭，按键原样放行
  local ok_ascii, ascii = pcall(function() return ctx:get_option("ascii_mode") end)
  if ok_ascii and ascii then
    core.set_raw(ctx, false)
    return 2
  end

  -- 输入清空 = 本次组合结束，退出原符号模式
  if cur == "" then
    core.set_raw(ctx, false)
    -- 新一次输入的第一个键：此时 ctx.input 还是空的，下面的 grid_key 收不到这个键，
    -- 于是「展开」状态会一直留着，导致普通打字也按 36 个候选排版（候选窗口换行成 4 行）。
    -- 用户要求「原本的一行显示」必须回来，所以在这里无条件复位成单行。
    pcall(core.grid_reset, ctx)
    -- 「下翻」页码也要复位，否则下一次打字会从上一轮的第 2 页开始。
    pcall(core.page_reset, ctx)
  end
  -- 原符号模式：完全不拦截，让 speller / punctuator 按原版行为处理
  if core.raw(ctx) then return 2 end

  -- 收藏编码「打完 + 回车」= 直接调用收藏内容。
  -- 纯数字编码（如 131）本来靠「整屏只有一个候选时回车上屏」这个巧合生效，
  -- 这里显式接管：数字编码、字母编码一律支持，行为统一，也不再依赖巧合。
  -- 只有输入和某条编码完全一致时才接管，其余回车行为原样放行。
  -- 候选窗口展开/收起 + 二维选择（只在正常打字时生效；v 菜单里保持原样）
  if cur ~= "" and not core.mode_of(cur) then
    -- 「+ 号下翻」：用户要求保留这个功能 —— 收起态一行只有 9 个候选，按 + 把可见窗口
    -- 后移 9 个（第 10-18 个候选），配合 Weasel 标签槽的 1-9 序号即可直接选词。
    -- rime 默认把 KP_Add 绑成 plus（只当标点、会直接上屏），所以必须在这里拦下来。
    -- 主键盘 +（shift+equal）与小键盘 +（KP_Add）在 librime 里都归一化成 plus；
    -- 减号是 minus / KP_Subtract。两个方向都要接，「原来的 +- 翻页」才算回来。
    -- ★ 还必须连 equal / Next / Prior 一起接：
    --   主键盘 `=`/`-` 在 rime 的 **默认 key_binder** 里被映射成 Page_Down/Page_Up
    --   （实测日志：key repr=equal → key repr=Next），键先被 key_binder 抢走，
    --   我们的页码根本不前进 —— 用户看到的就是「+= 翻页没反应」。
    --   `=` 是「下一页」、`-` 是「上一页」，和原版横向候选窗的翻页键一致。
    local is_next = (repr == "plus" or repr == "KP_Add" or repr == "equal"
      or repr == "KP_Equal" or repr == "Next" or repr == "Page_Down")
    local is_prev = (repr == "minus" or repr == "KP_Subtract" or repr == "Prior"
      or repr == "Page_Up")
    if is_next then
      -- [同列光标] 「翻页后光标停在原列最上方」不在这里做：本机 librime 没有
      --   「读/写当前选中下标」的 API，由自编 Weasel 补丁完成（RimeWithWeasel.cpp）。
      pcall(core.page_next, ctx)
      return 1
    end
    if is_prev then
      pcall(core.page_prev, ctx)
      return 1
    end
    local ok_grid, handled = pcall(core.grid_key, ctx, repr)
    if ok_grid and handled then return 1 end
  end

  if repr == "Return" and cur ~= "" and not core.mode_of(cur) then
    local ok_hit, hit = pcall(core.fav_exact, cur)
    if ok_hit and hit then
      local ok_commit = pcall(function()
        env.engine:commit_text(hit.word)
        ctx:clear()
      end)
      if ok_commit then return 1 end
    end
  end

  -- 注意：v 菜单里不拦截方向键；普通打字时上面的 grid_key 会接管方向键做网格导航
  --   （默认单行 9 个，按 ↓ 展开成 4 行 × 9 列，见 src/lua/vmenu_core.lua 与 docs/ARCHITECTURE.md §3.6）

  -- 纯数字收藏编码（如 131）：数字本来是选字键，进不了编码，
  -- 只有当输入为空或全是数字、且它仍是某条数字编码的开头时才接管。
  if repr:match("^%d$") and (cur == "" or cur:match("^%d+$")) then
    local ok_pre, is_pre = pcall(core.digit_prefix, cur .. repr)
    if ok_pre and is_pre then
      ctx:push_input(repr)
      return 1
    end
  end

  -- ===== 主菜单 =====
  if cur == "" and repr == "v" then
    ctx:push_input("v")
    return 1
  end
  if cur == "v" then
    if repr == "1" then
      -- 打开可视化设置界面：只写标记文件，由后台守护进程打开窗口
      core.request_gui()
      ctx:clear()
      return 1
    end
    if repr == "2" then replace_input(ctx, "vclip") return 1 end
    -- 第 3 项：快捷输入（计算 / 日期 / 时间 / 星期 …）
    if repr == "3" then replace_input(ctx, "vqi") return 1 end
    -- 第 4 项：常用语（第二次互换后在第 4 位）
    if repr == "4" then replace_input(ctx, "vfav") return 1 end
    -- 第 5 项：原符号（第二次互换后在第 5 位）
    -- 说明：原来的「文字设置」（vset 纯键盘设置）已去掉，vset* 代码保留但菜单进不去
    if repr == "5" then
      -- 还原原版 v 模式：输入回到 v，之后用户直接输入符号编码
      replace_input(ctx, "v")
      core.set_raw(ctx, true)
      return 1
    end
    return 2
  end

  -- ===== 快捷输入：选中后把触发前缀直接写进输入框，之后的按键交给原方案 =====
  -- 菜单保留 6 项，快捷键是「v3 + 字母」：c 计算 / r 日期 / s 时间 / u Unicode /
  -- n 农历输入 / h 数字货币转写。候选窗口上画出来的标签是数字，所以 1-6 也一并保留，
  -- 两个键位等价（字母是主推的快捷键）。
  -- 这些前缀都是雾凇拼音自带的（recognizer/patterns + lua_translator），
  -- 原来直接输入这些前缀的方式全部保留：cC / rq / sj / U / N / R。
  if cur == "vqi" then
    local k = string.lower(repr or "")
    if k == "1" or k == "c" then replace_input(ctx, "cC") return 1 end
    if k == "2" or k == "r" then replace_input(ctx, "rq") return 1 end
    if k == "3" or k == "s" then replace_input(ctx, "sj") return 1 end
    if k == "4" or k == "u" then replace_input(ctx, "U") return 1 end
    if k == "5" or k == "n" then replace_input(ctx, "N" .. os.date("%Y%m%d")) return 1 end
    if k == "6" or k == "h" then replace_input(ctx, "R") return 1 end
    if k == "q" then ctx:clear() return 1 end
    return 2
  end
  -- ===== 设置根菜单 =====
  if cur == "vset" then
    if repr == "1" then replace_input(ctx, "vsetc") return 1 end
    if repr == "2" then replace_input(ctx, "vsetf") return 1 end
    if repr == "3" then replace_input(ctx, "vsetn") return 1 end
    if repr == "4" then replace_input(ctx, "vsetx") return 1 end
    if repr == "5" then replace_input(ctx, "v") return 1 end
    return 2
  end

  -- ===== 默认显示条数 =====
  if cur == "vsetn" then
    local n
    if repr == "1" then n = 20
    elseif repr == "2" then n = 30
    elseif repr == "3" then n = 40
    elseif repr == "4" then n = 50 end
    if n then
      core.write_page(n)
      replace_input(ctx, "vset")
      return 1
    end
    if repr == "5" then replace_input(ctx, "vset") return 1 end
    return 2
  end

  -- ===== 缓存清理（二次确认页）=====
  if cur == "vsetx" then
    if repr == "1" or repr == "y" then
      core.write_clip({})
      replace_input(ctx, "vset")
      return 1
    end
    if repr == "2" or repr == "n" then replace_input(ctx, "vset") return 1 end
    return 2
  end

  -- ===== 剪贴板 / 收藏 的子模式 =====
  local base, act, more = core.parse_sub(cur)
  if base then
    if act == "x" then
      -- 清空确认页
      if repr == "1" or repr == "y" then
        if base == "c" then core.write_clip({}) else core.write_fav({}) end
        replace_input(ctx, "vset")
        return 1
      end
      if repr == "2" or repr == "n" then replace_input(ctx, "vset") return 1 end
      return 2
    end

    if act == "d" then
      -- 删除模式：数字按「本屏第 N 条」删除；m 下一组；q 返回
      if is_more_key(repr) then
        replace_input(ctx, "vset" .. base .. "d" .. string.rep("m", more + 1))
        return 1
      end
      if repr == "q" then replace_input(ctx, "vset") return 1 end
      local n = tonumber(repr)
      if n and n >= 1 and n <= core.WINDOW then
        local items
        if base == "c" then items = core.read_clip() else items = core.read_fav() end
        local idx = more * core.WINDOW + n
        if items[idx] then
          table.remove(items, idx)
          if base == "c" then core.write_clip(items) else core.write_fav(items) end
        end
        -- 原地刷新，便于连续删除
        replace_input(ctx, "vset" .. base .. "d" .. string.rep("m", more))
        return 1
      end
      if repr:match("^%a$") then return 1 end
      return 2
    end

    -- 列表模式
    if base == "c" and is_more_key(repr) then
      if more < math.floor((core.MAX_PAGE - core.MIN_PAGE) / core.STEP) then
        replace_input(ctx, "vsetc" .. string.rep("m", more + 1))
      end
      return 1
    end
    if repr == "d" then replace_input(ctx, "vset" .. base .. "d") return 1 end
    if repr == "x" then replace_input(ctx, "vset" .. base .. "x") return 1 end
    if repr == "q" then replace_input(ctx, "vset") return 1 end
    -- 管理列表里字母没有用途（数字才是选择标签），吞掉以免污染编码
    if repr:match("^%a$") then return 1 end
    -- 数字等其余按键交给 selector，正常上屏候选
    return 2
  end

  return 2
end

return function(key, env)
  local ok, res = pcall(handle, key, env)
  if ok and type(res) == "number" then return res end
  return 2
end
