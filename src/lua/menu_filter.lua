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
    passthrough(input)
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
    for i = 1, n do
      yield(buf[i])
    end
    return
  end

  -- 收藏固定占第 2 位
  local c = Candidate("vfav", 0, #code, fav.word, "收藏")
  c.quality = 500000
  local out = place(buf, 2, c)
  for i = 1, #out do
    yield(out[i])
  end
end

return filter
