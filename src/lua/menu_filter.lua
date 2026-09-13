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

-- 第一行（前 9 个）的候选在注释里带上 1-9 序号：
-- 主题里 label_format 已留空（rime 的 alternative_select_labels 在 Weasel 上不生效，
-- 实测窗口里第 10 个之后的序号是 Weasel 自己画的），所以序号改走注释，
-- 这样正好只有第一行有数字、下面几行干净。注释只是显示，不会进上屏文字。
local function number_row1(cand, i)
  if i < 1 or i > 9 then return end
  pcall(function()
    local c0 = cand.comment
    if c0 == nil or c0 == "" then
      cand.comment = tostring(i)
    else
      cand.comment = tostring(i) .. " " .. c0
    end
  end)
end
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
    -- 用户要求「无论如何都在一行；候选太长就丢掉最后几个候选」。
    -- 本机 weasel.dll 还是旧版（按宽度折行），所以这里先按估算宽度截断：
    -- CJK/表情一个字符 3 字节、ASCII 1 字节，加上注释（序号）与间距，超出预算就停止放出。
    -- 展开态（36 个）不做这个限制，交给 Weasel 侧「每 9 个换行」的补丁处理。
    -- 用户要求：**不许丢候选**，全部强制显示在一行（窗口宽度随内容变宽），绝不换行。
    -- 折行与否由 Weasel 侧补丁控制（候选 <=9 时完全不折行），这里不再做任何截断。
    local k = 0
    for cand in input:iter() do
      k = k + 1
      if k > lim then break end
      number_row1(cand, k)
      yield(cand)
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
      -- 主题里 label_format 已留空，v 菜单的序号也改写在注释里；
      -- 注释本来就有数字的（快捷输入那种「按 1 · …」）不再重复加。
      pcall(function()
        local c0 = buf[i].comment
        if c0 == nil or c0 == "" then
          buf[i].comment = tostring(i)
        elseif not c0:find("%d") then
          buf[i].comment = tostring(i) .. " " .. c0
        end
      end)
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
    number_row1(out[i], i)
    yield(out[i])
  end
end

return filter
