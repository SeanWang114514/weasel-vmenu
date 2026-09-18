-- v 功能菜单：候选压制 / 收藏插入滤镜（必须排在 engine/filters 最后）
-- 作用：
--   1) 处于 v 相关模式时，只保留本功能自己的候选，
--      丢掉 script_translator / melt_eng / punctuator 产生的竞争候选
--      （例如输入 v 时的「于 与 vac van var」、输入 vclip 时的英文词）；
--   2) 正常打字时，输入满 3 个字符命中收藏编码，就把收藏内容插到候选第 2 位。
-- 性能：非 v 模式且没命中收藏时直接透传，不做任何缓存表分配，避免影响打字速度。
local core = require("vmenu_core")

local function passthrough(input)
  for cand in input:iter() do
    yield(cand)
  end
end

-- 把 fav 插到第 pos 位，并把整表 quality 改成从高到低递减：
-- 这样无论菜单是按「滤镜产出顺序」还是按「quality 排序」决定先后，结果都一致。
local function place(list, pos, fav)
  local out = {}
  local n = #list
  if pos < 1 then pos = 1 end
  for i = 1, n do
    if i == pos then out[#out + 1] = fav end
    out[#out + 1] = list[i]
  end
  if pos > n then out[#out + 1] = fav end
  for i = 1, #out do
    local c = out[i]
    pcall(function() c.quality = 1000000 - i end)
  end
  return out
end

-- 序号不再由这里（候选注释）产生！
-- 2026-09-18 修正：注释在 Weasel 水平布局里排在候选词的**后面**，实测渲染成
-- 「这个1 这股2」，而且注释是翻译阶段由过滤器生成的 —— 移动高亮不会重新跑过滤器，
-- 所以注释里的序号永远钉在第一行，做不到「按高亮行重新编号」。
-- 现在序号由 Weasel 侧的标签槽负责（WeaselUI/HorizontalLayout.cpp 的 GetLabelText
-- 覆写）：标签槽在词的左侧，每帧重算，随高亮行给 1-9。此文件不再碰 comment。
local function filter(input, env)
  local ctx = env.engine.context
  local code = ctx.input

  local want = nil
  local fav = nil

  if type(code) == "string" and code ~= "" then
    local ok_raw, raw = pcall(core.raw, ctx)
    local ok_ascii, ascii = pcall(function() return ctx:get_option("ascii_mode") end)
    if (ok_ascii and ascii) or (ok_raw and raw) then
      passthrough(input)
      return
    end
    want = core.want_type(code)
    if want == nil then
      local ok_fav, hit = pcall(core.fav_hit, code)
      if ok_fav and type(hit) == "table" then fav = hit end
    end
  end

  if want == nil and fav == nil then
    -- 正常打字、没命中收藏：只放出当前状态允许的个数
    --   单行（默认）= 9 个，正好一行；按 ↓ 展开后 = 36 个，自动换成 4 行 × 9 列
    local lim = core.grid_limit(ctx)
    -- 用户要求：「还有保留 + 号下翻选择预选词的功能」。
    -- 收起态一行只有 9 个，第 10 个以后够不着；按 +（下翻）就把可见窗口整体后移 9 个，
    -- 于是第二页显示第 10-18 个候选，序号仍是 1-9（序号由 Weasel 标签槽按当前可见行给）。
    -- 展开态一屏已有 36 个（9×4），不再叠加翻页。
    -- [整页翻] 收起态与展开态都翻页（原来展开态完全没接！）；每页 = lim 个，
    -- 所以新一屏的第 1 行正好是原来第 5 行（用户要求），窗口长度仍是 lim（9 或 36）。
    local step = core.GRID_COLS
    local page = core.page_get(ctx)
    -- 用户要求：**不许丢候选**，全部强制显示在一行（窗口宽度随内容变宽），绝不换行。
    -- 折行与否由 Weasel 侧补丁控制（候选 <=9 时完全不折行），这里只决定「取哪 9 个」。
    local buf = {}
    local k = 0
    for cand in input:iter() do
      k = k + 1
      buf[k] = cand
    end
    local start = page * lim   -- [整页翻] 收起态 9 个/页、展开态 36 个/页：于是新一页第 1 行 = 原来第 5 行
    if start >= k then start = 0 end  -- 翻过头就回到第一页，绝不留空窗口
    for i = start + 1, math.min(k, start + lim) do
      yield(buf[i])
    end
    return
  end

  local buf = {}
  local n = 0
  for cand in input:iter() do
    if want ~= nil then
      -- v 相关模式：只留自己的候选
      if cand.type == want or cand.type == "vact" then
        n = n + 1
        buf[n] = cand
      end
    else
      -- 正常打字：全收，顺便把已经存在的同一条收藏候选去掉，避免重复
      if cand.type == "vfav" and cand.text == fav.word then
        -- 丢弃重复
      else
        n = n + 1
        buf[n] = cand
      end
    end
  end

  if want ~= nil then
    if n == 0 then
      passthrough(input)
      return
    end
    -- 同样受当前状态限制：收起时最多 9 个（一行，不换行），按 ↓ 展开后才能看到最多 36 个，
    -- 也就是「每行 9 个」，第 10 个及以后靠展开查看。
    local lim = core.grid_limit(ctx)
    for i = 1, math.min(n, lim) do
      -- v 菜单的序号同样交给 Weasel 的标签槽（按高亮行 1-9）。
      -- 候选自带的注释（如快捷输入的「按 1 · …」）保持原样，不再拼数字。
      yield(buf[i])
    end
    return
  end

  -- 收藏固定占第 2 位
  local c = Candidate("vfav", 0, #code, fav.word, "常用语")
  c.quality = 500000
  local out = place(buf, 2, c)
  local lim = core.grid_limit(ctx)
  for i = 1, #out do
    if i > lim then break end
    yield(out[i])
  end
end

return filter
