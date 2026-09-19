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

 private:
  // [vmenu-grid] 实际每行几列：正常固定 9；只有出现超长候选（9 列会超出屏幕）时，
  // DoLayout 才按屏幕可用宽度把它下调（用户允许「实在太长就少放几个，行列仍对齐」）。
  // 序号是按「行」分组的（见 GetLabelText），所以这个值要在两次调用之间保持：
  // 用 mutable 成员缓存，GetLabelText 读上一帧 DoLayout 算出的值（候选表不变时等价）。
  mutable int cols_per_row_ = 9;
};
};  // namespace weasel
