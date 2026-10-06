-- test-enter-logic.lua —— 直接测 menu_processor 里那段「数字未打满时回车」的判定逻辑
--
-- 为什么写这个：真机 GUI 回归台这一轮反复被环境问题卡住（微信输入法抢 IME 槽、
--   WeaselServer 起了两个实例、编辑器 TSF 连接失效），跑十几次都拿不到干净的按键。
--   而「回车该不该上屏数字」本质是**一个纯逻辑判断**，可以直接喂 cur/repr 进去验，
--   不必依赖真机。真机回归等环境干净了再补。
--
-- 用法：lua test-enter-logic.lua

-- ↓↓↓ 与 menu_processor.lua 里的判定保持**逐字一致**（改了那边要同步这里）
local function decide(cur, repr)
  if repr ~= "Return" then return "pass" end
  if cur == "" then return "pass" end

  -- fav_exact：只有完整编码才算命中
  local FAV = { ["131"] = "13122500717", ["wsl"] = "wslzhenshuai@163.com" }
  local hit = FAV[cur]

  if hit then
    if cur:match("^%d+$") then return "commit_fav"   -- 纯数字完整编码 → 上屏常用语
    else return "swallow" end                        -- 字母编码 → 吞掉
  end

  -- 没命中完整编码：数字 → 上屏数字 + 放行换行
  if cur:match("^%d+$") then return "commit_digits_then_newline" end
  return "pass"
end

local cases = {
  -- cur,     repr,      期望
  { "1",      "Return",  "commit_digits_then_newline" },  -- 用户报的核心场景
  { "13",     "Return",  "commit_digits_then_newline" },
  { "131",    "Return",  "commit_fav" },                  -- 完整编码 → 常用语
  { "wsl",    "Return",  "swallow" },                     -- 字母编码 → 吞掉
  { "",       "Return",  "pass" },                        -- 空输入 → 换行
  { "1",      "a",       "pass" },                        -- 非回车 → 不管
}

local fail = 0
for _, c in ipairs(cases) do
  local got = decide(c[1], c[2])
  local ok = (got == c[3])
  if not ok then fail = fail + 1 end
  print(string.format("%s  cur=%-5s repr=%-8s 得到=%-28s 期望=%s",
    ok and "PASS" or "FAIL", "["..c[1].."]", c[2], got, c[3]))
end
print("")
if fail == 0 then print("全部通过 (" .. #cases .. " 项)") else print(fail .. " 项失败") end
os.exit(fail == 0 and 0 or 1)
