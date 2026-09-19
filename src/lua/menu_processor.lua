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

-- 「这个输入是不是 v 功能」：菜单 v / 剪贴板 vclip / 快捷输入 vqi / 常用语 vfav / 设置 vset…
-- 用来把「退格 = 整条取消」的作用范围限制在 v 功能里，不影响普通打字和原符号编码。
local function is_v_func(s)
  if s == "v" then return true end
  return s:sub(1, 5) == "vclip" or s:sub(1, 3) == "vqi"
    or s:sub(1, 4) == "vfav" or s:sub(1, 4) == "vset"
end

local function is_back_key(repr)
  local rp = string.lower(repr or "")
  return rp == "backspace" or rp == "back_space" or rp == "back"
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
  -- ===== 原符号模式：按键也照**普通打字**来处理 =====
  -- 用户反馈：「v5 的候选词选择逻辑没有和正常的候选词选择逻辑同步」。
  -- 原符号模式以前是「完全不拦截、全交给原版」，但候选窗是照普通打字的网格画的
  -- （一行 9 个、高亮行画 1-9），而服务端的数字键补丁在 v 开头时被闸门挡住 →
  -- 序号画着却按不动。现在这里只接管三件事，其余按键照旧放行：
  --   ① +/- 翻页（和普通打字同一套页码）；
  --   ② ↓ 展开 / 第一行按 ↑ 收起（core.grid_key）；
  --   ③ 继续敲符号编码时页码回到第 1 页。
  if core.raw(ctx) then
    local r_next = (repr == "plus" or repr == "KP_Add" or repr == "equal"
      or repr == "KP_Equal" or repr == "Next" or repr == "Page_Down")
    local r_prev = (repr == "minus" or repr == "KP_Subtract" or repr == "Prior"
      or repr == "Page_Up")
    if r_next then
      pcall(core.page_next, ctx)
      return 1
    end
    if r_prev then
      pcall(core.page_prev, ctx)
      return 1
    end
    local r_arrow = (repr == "Down" or repr == "Up" or repr == "Left" or repr == "Right")
    if not r_arrow then
      -- 继续敲编码 = 换了一份候选，页码必须回第 1 页，否则新编码会显示成空白页
      pcall(core.page_reset, ctx)
    end
    local ok_rgrid, r_handled = pcall(core.grid_key, ctx, repr)
    if ok_rgrid and r_handled then return 1 end
    return 2
  end

  -- ===== 纯数字常用语编码（如 131）：**必须排在翻页 / 方格之前** =====
  -- 用户诉求（第二十轮，原话）：
  --   「输入数字的时候会变成候选状态，也就是无法在输入如 13 的时候直接按 "-" 等按键在后面
  --     插入一个 "-"，但是要保留数字作为常用语的编码（如常用语 13122500717 在输入 131 的时候
  --     会在候选词中显示，但是有且只有在输入回车后才会输入完整的常用语，输入 1 等词的时候
  --     不会输入而是正常地加在后面）」
  -- 于是这里的规则：
  --   ① 数字还能延长编码（仍是某条纯数字编码的前缀）→ 并进输入框（照旧）；
  --   ② 已经延长不了（例如 131 之后再按 3）→ **不再交给选字键去选候选**（否则会把整条
  --      常用语直接打出去），而是把「已输入的数字 + 这个数字」原样上屏 = 正常地加在后面；
  --   ③ 符号键（- = +）→ 先把已输入的数字上屏，再插入符号（13 + - → 13-）；
  --      其它符号不用管：数字本身已经占候选第 1 位（menu_filter.lua），方案自己的标点处理
  --      提交的就是「当前选中的候选」= 那串数字，同样会得到「13。」这种结果；
  --   ④ 回车仍然是**唯一**把整条常用语上屏的按键（见下面的 Return 分支）。
  -- 放在最前面的原因：下面的翻页分支会把 `-`/`=` 吃掉（第二十轮已收窄，但数字编码这条
  -- 路径必须优先），而「- 插不进去」正是用户报的问题。
  if (cur == "" or cur:match("^%d+$")) and not core.raw(ctx) then
    local sym = nil
    if repr:match("^%d$") then
      local ok_pre, is_pre = pcall(core.digit_prefix, cur .. repr)
      if ok_pre and is_pre then
        ctx:push_input(repr)
        return 1
      end
      if cur == "" then
        -- 输入还是空的、而这个数字开不了任何数字编码 → 交给原生（照旧直接上屏）
        return 2
      end
      sym = repr
    elseif cur ~= "" then
      if repr == "minus" or repr == "KP_Subtract" then
        sym = "-"
      elseif repr == "equal" or repr == "KP_Equal" then
        sym = "="
      elseif repr == "plus" or repr == "KP_Add" then
        sym = "+"
      end
    end
    if sym then
      core.debug_log("[vmenu] 数字编码直接上屏 <" .. cur .. sym .. ">")
      local ok_commit = pcall(function()
        env.engine:commit_text(cur .. sym)
        ctx:clear()
      end)
      if ok_commit then return 1 end
    end
  end

  -- ===== v 功能里「退格 = 整条输入全部丢掉」=====
  -- 用户诉求：「back 键全部删除 不显示」：不管当前是 v 菜单、v2 剪贴板、v3 快捷输入、
  -- 常用语还是设置，一按退格这条输入就整条作废 —— ctx:clear() 之后输入为空，
  -- 候选窗与输入框里什么都不剩（内部编码也随之消失）。
  -- 原符号模式在上面已经处理完（只接翻页 / 展开收起）：那里 v 开头是用户自己敲的符号编码，
  -- 退格仍然只删一个字。
  if cur ~= "" and is_v_func(cur) and is_back_key(repr) then
    core.debug_log("[vmenu] 退格取消整条输入 <" .. cur .. ">")
    ctx:clear()
    return 1
  end

  -- 收藏编码「打完 + 回车」= 直接调用收藏内容。
  -- 纯数字编码（如 131）本来靠「整屏只有一个候选时回车上屏」这个巧合生效，
  -- 这里显式接管：数字编码、字母编码一律支持，行为统一，也不再依赖巧合。
  -- 只有输入和某条编码完全一致时才接管，其余回车行为原样放行。
  -- 候选窗口展开/收起 + 加减号翻页。
  -- ★ v 功能的「列表型」子模式（剪贴板 vclip / 常用语 vfav / 管理列表 vsetc·vsetf）：
  --   [一行 2 个] 用户要求剪贴板与常用语「一行 2 个、默认显示 3 行、默认展开」，
  --   所以这些列表**没有收起态**：一屏固定 2 列 × 3 行 = 6 个，加减号按 6 个翻页，
  --   ↓↑←→ 由服务端补丁逐格移动、第一行按 ↑ 不再收起（见下面的 v_list_mode 分支）。
  -- 静态菜单（v 主菜单 / v3 快捷输入）不放进来：它们条目少、本来就全显示，而且数字键是
  -- 顺序选（1..N），一旦展开态让服务端接管数字键就会按「行 × 列」选错（服务端用
  -- _VMenuListCode 做了同样的判断，两边一致）。
  local is_v_mode = core.is_v_code(cur)
  local v_list_mode = is_v_mode and core.is_list_code(cur)
  if cur ~= "" and (not is_v_mode or v_list_mode) then
    -- 「+ 号下翻」：用户要求保留这个功能 —— 收起态一行只有 9 个候选（v 列表是 4 个），
    -- 按 + 把可见窗口后移一屏，配合 Weasel 标签槽的序号即可直接选词。
    -- rime 默认把 KP_Add 绑成 plus（只当标点、会直接上屏），所以必须在这里拦下来。
    -- 主键盘 +（shift+equal）与小键盘 +（KP_Add）在 librime 里都归一化成 plus；
    -- 减号是 minus / KP_Subtract。两个方向都要接，「原来的 +- 翻页」才算回来。
    -- ★ 还必须连 equal / Next / Prior 一起接：
    --   主键盘 `=`/`-` 在 rime 的 **默认 key_binder** 里被映射成 Page_Down/Page_Up
    --   （实测日志：key repr=equal → key repr=Next），键先被 key_binder 抢走，
    --   我们的页码根本不前进 —— 用户看到的就是「+= 翻页没反应」。
    --   `=` 是「下一页」、`-` 是「上一页」，和原版横向候选窗的翻页键一致。
    --
    -- ===== 第二十轮修正：`-` / `=` 不再无条件抢走 =====
    -- 用户诉求（原话）：「输入数字的时候会变成候选状态，也就是无法在输入如 13 的时候直接按
    --   "-" 等按键在后面插入一个 "-"」。上面那段把 `-`/`=` 无条件当翻页，于是
    --   ① 敲「13」（数字编码）时按 `-` 什么都不会发生（数字留在候选里、`-` 被吃掉）；
    --   ② 敲 cC1+2-3 这种算式时 `-` 也进不去（同样被吃）。
    -- 现在的规则（两处都保留原有手感）：
    --   * `+` / KP_Add（下翻）**任何情况都保留** —— 用户明确要求保留这个功能；
    --   * `-` / `=` / Page_Up / Page_Down 只在两种情况下当翻页：
    --       ① v 的列表模式（剪贴板 / 常用语 —— 用户明确要「加减号翻页」）；
    --       ② 输入是纯小写拼音（原来的手感；雾凇的方案里 `-`/`=` 本来就是翻页键）。
    --     其余情况（纯数字编码见上面的 digit 分支、cC / U / N / R 这些带大写或数字的前缀）
    --     一律放行：`-` 会走方案自己的标点处理 —— 那正是「先把已输入内容上屏、再插入符号」。
    local plain_pinyin = cur:match("^[a-z']+$") ~= nil
    local page_keys_ok = v_list_mode or plain_pinyin
    local is_next = (repr == "plus" or repr == "KP_Add")
      or (page_keys_ok and (repr == "equal" or repr == "KP_Equal"
        or repr == "Next" or repr == "Page_Down"))
    local is_prev = page_keys_ok and (repr == "minus" or repr == "KP_Subtract"
      or repr == "Prior" or repr == "Page_Up")
    -- v 子菜单里的字母键（d 删除 / x 清空 / q 返回 / m 更多）优先级更高，不能被翻页吃掉；
    -- 这些键不在 is_next / is_prev 里，所以顺序上天然不冲突。
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
    if v_list_mode then
      -- ===== 剪贴板 / 常用语：固定 2 列 × 3 行，**永远是展开态** =====
      -- 用户要求「一行 2 个、默认显示 3 行、用正常候选词的逻辑选择（但拓展栏默认展开）」，
      -- 并补充「按上键不要收起，默认就是展开态」。所以：
      --   ① 每个按键都把「展开」钉住（服务端的数字键 / 方向键 / 翻页补丁以它为门槛）；
      --   ② ↑ 在第一行时不再收起 —— 补丁发现 -2 越界会把按键放行到这里，直接吞掉；
      --   ③ ↓ / ← / → 的逐格移动、以及「最后一行再按 ↓ = 翻页」都由补丁完成，
      --      落到这里只可能是「跑的是没有补丁的原版 server」，此时不拦，交回 rime。
      pcall(core.grid_lock, ctx)
      if repr == "Up" then return 1 end
    else
      local ok_grid, handled = pcall(core.grid_key, ctx, repr)
      if ok_grid and handled then return 1 end
    end
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

  -- 纯数字收藏编码（如 131）：**已经挪到函数开头**（「纯数字常用语编码」那一段）。
  -- 挪上去的原因：数字编码路径要排在翻页分支之前，否则 `-` 会被当成「上一页」吃掉
  -- （第二十轮用户报的「13 之后按 - 插不进去」）。这里不再重复处理。

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
    if repr == "2" then
      -- 剪贴板：固定 2 列 × 3 行、进列表就是展开态，所以立刻把「展开」钉住
      replace_input(ctx, "vclip")
      pcall(core.grid_lock, ctx)
      return 1
    end
    -- 第 3 项：快捷输入（计算 / 日期 / 时间 / 星期 …）
    if repr == "3" then replace_input(ctx, "vqi") return 1 end
    -- 第 4 项：常用语（第二次互换后在第 4 位）
    if repr == "4" then
      replace_input(ctx, "vfav")
      pcall(core.grid_lock, ctx)
      return 1
    end
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
  -- 快捷键是「v3 + 字母」：c 计算 / r 日期 / s 时间 / u Unicode /
  -- n 农历输入 / h 数字货币转写 / q 返回。字母认的是**项目本身**，与候选顺序无关。
  -- 另外保留数字键 1-7 —— 候选窗口上的标签是数字，而且**标签按渲染顺序走**，
  -- 实测渲染顺序是：1 计算 2 日期 3 时间 4 农历输入 5 数字货币转写 6 Unicode 7 返回
  -- （和 yield_quick 的书写顺序不完全一样，Unicode 被排到了第 6）。
  -- 所以这里的数字映射必须跟着**实测渲染顺序**，不能跟着书写顺序，否则
  -- 「按屏幕上写着 5 的那一项」会选错。改动菜单项后要重新量一遍顺序。
  -- 这些前缀都是雾凇拼音自带的（recognizer/patterns + lua_translator），
  -- 原来直接输入这些前缀的方式全部保留：cC / rq / sj / U / N / R。
  if cur == "vqi" then
    local k = string.lower(repr or "")
    if k == "1" or k == "c" then replace_input(ctx, "cC") return 1 end
    if k == "2" or k == "r" then replace_input(ctx, "rq") return 1 end
    if k == "3" or k == "s" then replace_input(ctx, "sj") return 1 end
    if k == "4" or k == "n" then replace_input(ctx, "N" .. os.date("%Y%m%d")) return 1 end
    if k == "5" or k == "h" then replace_input(ctx, "R") return 1 end
    if k == "6" or k == "u" then replace_input(ctx, "U") return 1 end
    if k == "7" or k == "q" then replace_input(ctx, "v") return 1 end
    return 2
  end
  -- ===== 设置根菜单 =====
  if cur == "vset" then
    if repr == "1" then
      replace_input(ctx, "vsetc")
      pcall(core.grid_lock, ctx)   -- 剪贴板管理（列表）：同剪贴板，一律展开态
      return 1
    end
    if repr == "2" then
      replace_input(ctx, "vsetf")
      pcall(core.grid_lock, ctx)   -- 常用语管理（列表）：同上
      return 1
    end
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
      -- 删除模式：数字按「本屏第 N 条」删除；m / + 下一屏；q 返回。
      -- [v 一行 4 个] 「本屏」的条数跟菜单切片一致：收起 4 个、展开 16 个（core.grid_limit），
      -- 页码用和列表同一套 option（core.page_get），不再用输入码里的 m 个数自己算窗口，
      -- 否则「屏幕上一屏 4 个、m 却跳过 9 个」会错位。
      if is_more_key(repr) then
        core.page_next(ctx)
        return 1
      end
      if repr == "q" then replace_input(ctx, "vset") return 1 end
      local lim = core.grid_limit(ctx, cur)
      local n = tonumber(repr)
      if n and n >= 1 and n <= lim then
        local items
        if base == "c" then items = core.read_clip() else items = core.read_fav() end
        local idx = core.page_get(ctx) * lim + n
        if items[idx] then
          table.remove(items, idx)
          if base == "c" then core.write_clip(items) else core.write_fav(items) end
        end
        -- 原地刷新，便于连续删除（本屏内容会跟着重排）
        return 1
      end
      if repr:match("^%a$") then return 1 end
      return 2
    end

    -- 列表模式
    if base == "c" and is_more_key(repr) then
      -- [v 一行 4 个] 与列表切片保持一致：m / + 直接翻到下一屏（原来用输入码里的 m 个数
      -- 记窗口，一屏 9 个，和现在一屏 4/16 个不匹配）。
      core.page_next(ctx)
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
