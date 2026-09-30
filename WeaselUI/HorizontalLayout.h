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
  // [vmenu-grid] 「换行步长」= 每行几列的**基准值**：普通打字 9，v 功能菜单 4
  // （由服务端 ctx.grid_cols 下发）。换行与序号都按这个步长走。
  // 序号是按「行」分组的（见 GetLabelText），所以这个值要在两次调用之间保持：
  // 用 mutable 成员缓存，GetLabelText 读上一帧 DoLayout 算出的值（候选表不变时等价）。
  mutable int cols_per_row_ = 9;
  // [vmenu-grid] 「本行实际画出几格」<= cols_per_row_。
  //   候选太宽时（一行 N 格会超出屏幕）用户允许「少放 1-3 个」：
  //   DoLayout 把每行的格数减到刚好放得进屏幕（最多减 3，最少 1），
  //   第 draw_cols 格之后的候选**本轮不画**，但列位置仍钉在「列号 × 列宽」上，
  //   所以收起态那一行和展开后每一行的同一列严格对齐（用户要求）。
  mutable int visible_cols_ = 0;  // 0 = 不裁（全部画）
  // [vmenu-grid] 序号算法（服务端 ctx.grid_2d）：
  //   0 = 按 1..N 顺序编号（静态 v 菜单：v 主菜单 5 项、v3 快捷输入 7 项，
  //       数字键是顺序选的，所以每一行都要把序号显示出来）；
  //   1 = 按「行 × 列」编号（列表 / 普通打字的展开网格：第 2 行的标签是 1-4，
  //       数字键在服务端也是按行 × 列换算的，两边必须一致）；
  //   2 = **不画序号**（[vmenu-nolabel] 纯数字编码输入：候选里只剩「常用语预览」一条，
  //       用户要求「这个也最好不要显示序号」）。
  // 与 cols_per_row_ 同理，用 mutable 缓存上一帧 DoLayout 收到的值。
  mutable int grid_seq_mode_ = 1;
};
};  // namespace weasel
