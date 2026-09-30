#pragma once
#include <algorithm>
#include <string>
#include <vector>

// [vmenu-fuzzy] 前后鼻音模糊：候选词内联拼音标注协议（渲染端）。
//
// 协议（由 lua 滤镜 fuzzy_filter.lua 写入 candidate comment）：
//   comment = L"\x02" + "off:py;off:py;..."
//   * off = 插入点（候选文本码点序号，1 基）：拼音画在第 off 个字之后；
//     off == 字数 表示画在词尾。
//   * py  = 该字的真实拼音音节（模糊命中的那个写法用真实读音，如 yin→ying）。
//
// 渲染：拼音以「注释字体 + 注释颜色」（灰色小字）画在候选词**中间**，两侧留
// hilite_spacing 间距；带协议的候选词尾不再画 comment（整段被消费）。
// 上屏文本永远是 candidate.text 原文 —— 协议只活在 comment 里，不影响上屏。
//
// 不是该协议的注释 Parse() 返回 false，调用方走原渲染路径，绝不影响
// v 菜单 / 普通候选 / 部件反查等任何既有注释。
namespace vmenu_annot {

struct Seg {
  int at;  // 插入点：码点序号（at == 字数 表示词尾）
  std::wstring py;
};

struct Run {
  std::wstring s;
  bool is_py;
};

// 解析协议 comment；失败返回 false 并清空 segs。
inline bool Parse(const std::wstring& cmt, std::vector<Seg>& segs) {
  segs.clear();
  if (cmt.size() < 4 || cmt[0] != L'\x02') return false;
  size_t i = 1;
  while (i < cmt.size()) {
    if (cmt[i] < L'0' || cmt[i] > L'9') return false;
    int at = 0;
    while (i < cmt.size() && cmt[i] >= L'0' && cmt[i] <= L'9') {
      at = at * 10 + (cmt[i] - L'0');
      ++i;
      if (at > 65535) return false;  // 防御：协议字段异常
    }
    if (i >= cmt.size() || cmt[i] != L':') return false;
    ++i;
    const size_t start = i;
    while (i < cmt.size() && cmt[i] != L';') ++i;
    if (i == start) return false;  // 空拼音
    segs.push_back({at, cmt.substr(start, i - start)});
    if (i < cmt.size() && cmt[i] == L';') ++i;
  }
  if (segs.empty()) return false;
  std::sort(segs.begin(), segs.end(),
            [](const Seg& a, const Seg& b) { return a.at < b.at; });
  return true;
}

// 把「候选文本 + 标注」切成交替的渲染片段：词段 / 拼音段。
inline void BuildRuns(const std::wstring& text,
                      const std::vector<Seg>& segs,
                      std::vector<Run>& runs) {
  runs.clear();
  // 按码点切分（保留代理对）
  std::vector<std::wstring> cps;
  cps.reserve(text.size());
  for (size_t i = 0; i < text.size(); ++i) {
    const wchar_t c = text[i];
    if (c >= 0xD800 && c <= 0xDBFF && i + 1 < text.size() &&
        text[i + 1] >= 0xDC00 && text[i + 1] <= 0xDFFF) {
      cps.push_back(text.substr(i, 2));
      ++i;
    } else {
      cps.push_back(text.substr(i, 1));
    }
  }
  auto push = [&runs](const std::wstring& s, bool py) {
    if (s.empty()) return;
    if (!runs.empty() && runs.back().is_py == py)
      runs.back().s += s;
    else
      runs.push_back({s, py});
  };
  size_t si = 0;
  for (int pos = 0; pos <= static_cast<int>(cps.size()); ++pos) {
    while (si < segs.size() && segs[si].at == pos) {
      push(segs[si].py, true);
      ++si;
    }
    if (pos < static_cast<int>(cps.size())) push(cps[pos], false);
  }
  while (si < segs.size()) {  // at > 字数：防御性画在词尾
    push(segs[si].py, true);
    ++si;
  }
}

// 量宽辅助：返回各片段 + 片段间应加的间距次数（runs.size()-1）。
// 具体字体量宽由调用方按 is_py 选择 pTextFormat / pCommentTextFormat。

}  // namespace vmenu_annot
