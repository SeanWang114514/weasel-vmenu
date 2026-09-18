#pragma once

#include "StandardLayout.h"

namespace weasel {
class HorizontalLayout : public StandardLayout {
 public:
  HorizontalLayout(const UIStyle& style,
                   const Context& context,
                   const Status& status,
                   PDWR pDWR)
      : StandardLayout(style, context, status, pDWR) {}
  virtual void DoLayout(CDCHandle dc, PDWR pDWR = NULL);
  // [vmenu-grid] 候选序号改走「标签槽」：标签槽是水平布局里唯一排在候选词**左侧**的
  // 位置，而且这里能拿到高亮下标（this->id），可以随 ↑↓←→ 重新编号。
  virtual std::wstring GetLabelText(const std::vector<Text>& labels,
                                    int id,
                                    const wchar_t* format) const;
};
};  // namespace weasel
