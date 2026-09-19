#include "stdafx.h"
#include "HorizontalLayout.h"

using namespace weasel;

// [vmenu-grid] 候选序号：画在「当前高亮那一行」每个候选的**前面**。
//
// 为什么必须放在标签槽：
//   * Weasel 的水平布局里，一格候选是「标签 → 候选词 → 注释」，只有标签槽在词的左侧。
//     之前把序号塞进候选注释（menu_filter.lua 的 number_row1），渲染出来是
//     「这个1 这股2」—— 数字跟在词**后面**，不符合「数字在词前」。
//   * 注释是**翻译阶段**由过滤器生成的，移动高亮不会重新跑过滤器，所以注释里的序号
//     永远钉在第一行，不可能「按高亮行重新编号」。标签槽是**每次绘制**都重算的，天然
//     跟随高亮。
//
// 为什么跳过 style/label_format 模板：
//   本机主题把 label_format 设成 " "（只有空格、没有 %s），模板会把标签文字整个吃掉，
//   所以这里对网格态直接返回 "数字+空格"，不再走模板。
//
// 编号规则：
//   * 本候选所在行 (id / 9) == 高亮所在行 (this->id / 9) 时，显示列号 1-9；
//   * 其余行返回两个空格 —— 宽度与「数字+空格」接近，保证各行候选词左边缘对齐，
//     同时满足「下面几行不带序号」。
//   * 收起态只有一行（候选数 <= 9），此时整行就是高亮行，所以序号照样是 1-9。
std::wstring HorizontalLayout::GetLabelText(const std::vector<Text>& labels,
                                            int id,
                                            const wchar_t* format) const {
  const int cols = (cols_per_row_ > 0) ? cols_per_row_ : 9;
  const int hl_row = this->id / cols;
  const int row = id / cols;
  if (row == hl_row)
    return std::to_wstring(id % cols + 1) + L" ";
  return L"  ";
}

void HorizontalLayout::DoLayout(CDCHandle dc, PDWR pDWR) {
  CSize size;
  int width = offsetX + real_margin_x, height = offsetY + real_margin_y;
  int w = offsetX + real_margin_x;

  /* calc mark_text sizes */
  if ((_style.hilited_mark_color & 0xff000000)) {
    CSize sg;
    if (candidates_count) {
      if (_style.mark_text.empty())
        GetTextSizeDW(L"|", 1, pDWR->pTextFormat, pDWR, &sg);
      else
        GetTextSizeDW(_style.mark_text, _style.mark_text.length(),
                      pDWR->pTextFormat, pDWR, &sg);
    }

    mark_width = sg.cx;
    mark_height = sg.cy;
    if (_style.mark_text.empty()) {
      mark_width = mark_height / 7;
      if (_style.linespacing && _style.baseline)
        mark_width =
            (int)((float)mark_width / ((float)_style.linespacing / 100.0f));
      mark_width = max(mark_width, 6);
    }
    mark_gap = (_style.mark_text.empty()) ? mark_width
                                          : mark_width + _style.hilite_spacing;
  }
  int base_offset = ((_style.hilited_mark_color & 0xff000000)) ? mark_gap : 0;

  // calc page indicator
  CSize pgszl, pgszr;
  if (!IsInlinePreedit()) {
    GetTextSizeDW(pre, pre.length(), pDWR->pPreeditTextFormat, pDWR, &pgszl);
    GetTextSizeDW(next, next.length(), pDWR->pPreeditTextFormat, pDWR, &pgszr);
  }
  bool page_en = (_style.prevpage_color & 0xff000000) &&
                 (_style.nextpage_color & 0xff000000);
  int pgw = page_en ? (pgszl.cx + pgszr.cx + _style.hilite_spacing +
                       _style.hilite_padding_x * 2)
                    : 0;
  int pgh = page_en ? max(pgszl.cy, pgszr.cy) : 0;

  /* Preedit */
  if (!IsInlinePreedit() && !_context.preedit.str.empty()) {
    size = GetPreeditSize(dc, _context.preedit, pDWR->pPreeditTextFormat, pDWR);
    int szx = pgw, szy = max(size.cy, pgh);
    // icon size higher then preedit text
    int yoffset = (STATUS_ICON_SIZE >= szy && ShouldDisplayStatusIcon())
                      ? (STATUS_ICON_SIZE - szy) / 2
                      : 0;
    _preeditRect.SetRect(w, height + yoffset, w + size.cx,
                         height + yoffset + size.cy);
    height += szy + 2 * yoffset + _style.spacing;
    width = max(width, real_margin_x * 2 + size.cx + szx);
    if (ShouldDisplayStatusIcon())
      width += STATUS_ICON_SIZE;
  }

  /* Auxiliary */
  if (!_context.aux.str.empty()) {
    size = GetPreeditSize(dc, _context.aux, pDWR->pPreeditTextFormat, pDWR);
    // icon size higher then auxiliary text
    int yoffset = (STATUS_ICON_SIZE >= size.cy && ShouldDisplayStatusIcon())
                      ? (STATUS_ICON_SIZE - size.cy) / 2
                      : 0;
    _auxiliaryRect.SetRect(w, height + yoffset, w + size.cx,
                           height + yoffset + size.cy);
    height += size.cy + 2 * yoffset + _style.spacing;
    width = max(width, real_margin_x * 2 + size.cx);
  }

  int row_cnt = 0;
  int max_width_of_rows = 0;
  int height_of_rows[MAX_CANDIDATES_COUNT] = {0};    // height of every row
  int row_of_candidate[MAX_CANDIDATES_COUNT] = {0};  // row info of every cand
  int mintop_of_rows[MAX_CANDIDATES_COUNT] = {0};
  // only when there are candidates
  // [vmenu-grid] 统一列宽的量：作用域要覆盖下面「定位」与「设置 rect」两段 pass
  const int kGridCols = 9;
  const bool grid_multi_row = (candidates_count > kGridCols);
  int col_width = 0;
  int grid_label_w = 0;                // 网格态统一序号槽宽（见下面注释）
  int& cols_per_row = cols_per_row_;   // 正常 = 9；超长候选时下面会下调
  if (candidates_count) {
    w = offsetX + real_margin_x;
    // [vmenu-grid] 「严格整齐」：网格态先量出**统一列宽**。
    // 原版逐个累加每个候选的真实宽度 w，于是「这个」比「这」宽一格，
    // 每行第 2 列的起点都不同，展开后的 9×4 网格参差不齐。
    // 现在取所有候选里最宽的一格（标签 + 间距 + 词 + 注释）当所有列宽，
    // 每个候选钉在「列号 × 列宽」上 → 每列严格对齐。
    if (candidates_count > 1) {
      // 先定「序号槽」的固定宽度：
      //   序号只画在高亮那一行，其余行用等宽占位（"  "）。但「数字+空格」比两个
      //   空格宽 ~8px，于是第 1 行的词整体比第 2–4 行右移 8px —— 实测就是这点差异。
      //   所以网格态把序号槽宽度**钉死**成所有行里最宽的那个（即数字+空格），
      //   各行候选词左边缘才是真正严格对齐。
      for (auto i = 0; i < candidates_count && i < MAX_CANDIDATES_COUNT; ++i) {
        std::wstring lb =
            GetLabelText(labels, i, _style.label_text_format.c_str());
        GetTextSizeDW(lb, lb.length(), pDWR->pLabelTextFormat, pDWR, &size);
        grid_label_w = max(grid_label_w, size.cx * labelFontValid);
      }
      for (auto i = 0; i < candidates_count && i < MAX_CANDIDATES_COUNT; ++i) {
        int cw = grid_label_w + _style.hilite_spacing;
        GetTextSizeDW(candidates.at(i).str, candidates.at(i).str.length(),
                      pDWR->pTextFormat, pDWR, &size);
        cw += size.cx * textFontValid;
        bool cmtOk =
            (i == id && (_style.hilited_comment_text_color & 0xff000000)) ||
            (i != id && (_style.comment_text_color & 0xff000000));
        if (!comments.at(i).str.empty() && cmtFontValid && cmtOk) {
          GetTextSizeDW(comments.at(i).str, comments.at(i).str.length(),
                        pDWR->pCommentTextFormat, pDWR, &size);
          cw += _style.hilite_spacing + size.cx * cmtFontValid;
        }
        col_width = max(col_width, cw);
      }
      col_width += _style.candidate_spacing;  // 列与列之间的间距
    }
    // [vmenu-grid] 统一列宽的另一面：万一有**超长候选**（例如很长的常用语），
    // 9 列 × 那个宽度会把面板撑得比屏幕还宽。用户允许「实在太长就少放几个」，
    // 于是按屏幕可用宽度反算每行最多放几列（下限 3 列，保证还是个网格）。
    // 正常中文候选（1–4 字）算出来仍然是 9 列，行为完全不变。
    const int kScreenW = GetSystemMetrics(SM_CXSCREEN);
    const int grid_budget =
        (kScreenW > 0) ? (kScreenW - offsetX - 2 * real_margin_x - 16) : 0;
    cols_per_row = kGridCols;
    if (grid_multi_row && col_width > 0 && grid_budget > 0) {
      while (cols_per_row > 3 && cols_per_row * col_width > grid_budget)
        --cols_per_row;
    }
    // 统一列宽在**展开态一律启用**（要的就是严格行列对齐）；
    // 收起态（单行 9 个）也启用，让每一格等宽 —— 用户要求「每个预选词都用同一个长度」，
    // 收起态量出来 95/100/101 这种 ±3px 的抖动就是各格自然宽度不同造成的。
    // 唯一的例外：这一行 9 格会超出屏幕（候选超长）时退回自然宽度，别把面板撑出屏幕。
    const bool grid_uniform =
        (candidates_count > 1 && col_width > 0 &&
         (grid_multi_row || grid_budget <= 0 ||
          kGridCols * col_width <= grid_budget));
    for (auto i = 0; i < candidates_count && i < MAX_CANDIDATES_COUNT; ++i) {
      int current_cand_width = 0;
      if (i > 0)
        w += _style.candidate_spacing;
      // [vmenu-grid] 等宽网格不给高亮格加 base_offset：高亮块本来就是整格，
      //   加了会让那一格的文字比其他格右移几个像素，「严格对齐」就破了。
      if (id == i && !grid_uniform)
        w += base_offset;
      /* Label */
      // [vmenu-grid] 网格态用统一序号槽宽（见上面的 grid_label_w 注释）。
      std::wstring label =
          GetLabelText(labels, i, _style.label_text_format.c_str());
      GetTextSizeDW(label, label.length(), pDWR->pLabelTextFormat, pDWR, &size);
      const int lab_w = grid_uniform ? max(grid_label_w, size.cx * labelFontValid)
                                     : size.cx * labelFontValid;
      _candidateLabelRects[i].SetRect(w, height, w + lab_w, height + size.cy);
      w += lab_w;
      current_cand_width += lab_w;

      /* Text */
      w += _style.hilite_spacing;
      const std::wstring& text = candidates.at(i).str;
      GetTextSizeDW(text, text.length(), pDWR->pTextFormat, pDWR, &size);
      _candidateTextRects[i].SetRect(w, height, w + size.cx * textFontValid,
                                     height + size.cy);
      w += size.cx * textFontValid;
      current_cand_width += (size.cx + _style.hilite_spacing) * textFontValid;

      /* Comment */
      bool cmtFontNotTrans =
          (i == id && (_style.hilited_comment_text_color & 0xff000000)) ||
          (i != id && (_style.comment_text_color & 0xff000000));
      if (!comments.at(i).str.empty() && cmtFontValid && cmtFontNotTrans) {
        const std::wstring& comment = comments.at(i).str;
        GetTextSizeDW(comment, comment.length(), pDWR->pCommentTextFormat, pDWR,
                      &size);
        w += _style.hilite_spacing;
        _candidateCommentRects[i].SetRect(w, height, w + size.cx * cmtFontValid,
                                          height + size.cy);
        w += size.cx * cmtFontValid;
        current_cand_width += (size.cx + _style.hilite_spacing) * cmtFontValid;
      } else /* Used for highlighted candidate calculation below */
        _candidateCommentRects[i].SetRect(w, height, w, height + size.cy);

      // [vmenu-grid] 折行策略改为「按个数」，不再按宽度：
      //   * 候选数 <= 9：**无论如何都排成一行**（长词也不折行，窗口宽度随之变宽）。
      //     用户明确要求「无论如何都在一行显示」——按宽度折行时只要有一个词偏宽
      //     就会被挤到第二行，调 max_width 只能推后临界点，治不了本。
      //   * 候选数 >  9：每 cols_per_row 个强制换行（正常就是 9），即「每行严格 9 个」网格。
      const bool vmenu_line_break =
          grid_multi_row && i > 0 && (i % cols_per_row) == 0;
      if (vmenu_line_break) {
        // max_width_of_rows current row
        max_width_of_rows =
            max(max_width_of_rows, _candidateCommentRects[i - 1].right);
        w = offsetX + real_margin_x +
            ((i == id && !grid_multi_row) ? base_offset : 0);
        int ofx = w - _candidateLabelRects[i].left;
        int ofy = height_of_rows[row_cnt] + _style.candidate_spacing;
        // offset rects to next row
        _candidateLabelRects[i].OffsetRect(ofx, ofy);
        _candidateTextRects[i].OffsetRect(ofx, ofy);
        _candidateCommentRects[i].OffsetRect(ofx, ofy);
        // max width of next row, if it's the last candidate, make sure
        // max_width_of_rows calc right
        max_width_of_rows =
            max(max_width_of_rows, _candidateCommentRects[i].right);
        mintop_of_rows[row_cnt] = height;
        height += ofy;
        row_cnt++;
      } else if (!grid_multi_row)
        max_width_of_rows = max(max_width_of_rows, w);

      // [vmenu-grid] 把光标「钉」到本列右缘：列号 = i % cols_per_row。
      //   ★ 这里必须用**列号**算，不能用循环里累加出来的 w：
      //     换行时 w 被重置成新行的行首，而累加值还是上一行末尾的值，
      //     用它补齐会把新行第 2 格起推到面板外（实测第 2–4 行只剩第 1 格可见）。
      if (grid_uniform) {
        w = offsetX + real_margin_x + ((i % cols_per_row) + 1) * col_width -
            _style.candidate_spacing;
        max_width_of_rows = max(
            max_width_of_rows,
            offsetX + real_margin_x + cols_per_row * col_width);
      }
      // calculate height of current row is the max of three rects
      mintop_of_rows[row_cnt] = height;
      height_of_rows[row_cnt] =
          max(height_of_rows[row_cnt], _candidateLabelRects[i].Height());
      height_of_rows[row_cnt] =
          max(height_of_rows[row_cnt], _candidateTextRects[i].Height());
      height_of_rows[row_cnt] =
          max(height_of_rows[row_cnt], _candidateCommentRects[i].Height());
      // set row info of current candidate
      row_of_candidate[i] = row_cnt;
    }

    // reposition for alignment, exp when rect height not equal to
    // height_of_rows
    for (auto i = 0; i < candidates_count && i < MAX_CANDIDATES_COUNT; ++i) {
      int base_left = (i == id) ? _candidateLabelRects[i].left - base_offset
                                : _candidateLabelRects[i].left;
      if (grid_uniform) {
        // [vmenu-grid] 高亮块 = 完整一格（等宽），所有格子的选中块大小一致
        const int cell_left =
            offsetX + real_margin_x + (i % cols_per_row) * col_width;
        _candidateRects[i].SetRect(
            cell_left, mintop_of_rows[row_of_candidate[i]],
            cell_left + col_width - _style.candidate_spacing,
            mintop_of_rows[row_of_candidate[i]] +
                height_of_rows[row_of_candidate[i]]);
      } else
        _candidateRects[i].SetRect(base_left, mintop_of_rows[row_of_candidate[i]],
                                   _candidateCommentRects[i].right,
                                   mintop_of_rows[row_of_candidate[i]] +
                                       height_of_rows[row_of_candidate[i]]);
      int ol = 0, ot = 0, oc = 0;
      if (_style.align_type == UIStyle::ALIGN_CENTER) {
        ol = (height_of_rows[row_of_candidate[i]] -
              _candidateLabelRects[i].Height()) /
             2;
        ot = (height_of_rows[row_of_candidate[i]] -
              _candidateTextRects[i].Height()) /
             2;
        oc = (height_of_rows[row_of_candidate[i]] -
              _candidateCommentRects[i].Height()) /
             2;
      } else if (_style.align_type == UIStyle::ALIGN_BOTTOM) {
        ol = (height_of_rows[row_of_candidate[i]] -
              _candidateLabelRects[i].Height());
        ot = (height_of_rows[row_of_candidate[i]] -
              _candidateTextRects[i].Height());
        oc = (height_of_rows[row_of_candidate[i]] -
              _candidateCommentRects[i].Height());
      }
      _candidateLabelRects[i].OffsetRect(0, ol);
      _candidateTextRects[i].OffsetRect(0, ot);
      _candidateCommentRects[i].OffsetRect(0, oc);
    }
    height = mintop_of_rows[row_cnt] + height_of_rows[row_cnt] - offsetY;
    width = max(width, max_width_of_rows);
  } else {
    height -= _style.spacing + offsetY;
    width += _style.hilite_spacing + _style.border;
  }

  width += real_margin_x;
  height += real_margin_y;

  if (candidates_count) {
    width = max(width, _style.min_width);
    height = max(height, _style.min_height);
  }
  if (candidates_count) {
    for (auto i = 0; i < candidates_count && i < MAX_CANDIDATES_COUNT; ++i) {
      // make rightest candidate's rect right the same for better look
      if ((i < candidates_count - 1 &&
           row_of_candidate[i] < row_of_candidate[i + 1]) ||
          (i == candidates_count - 1))
        if (!grid_multi_row)
          _candidateRects[i].right = width - real_margin_x;
    }
  }
  _highlightRect = _candidateRects[id];
  UpdateStatusIconLayout(&width, &height);
  _contentSize.SetSize(width + offsetX, height + 2 * offsetY);
  _contentRect.SetRect(0, 0, _contentSize.cx, _contentSize.cy);

  // calc page indicator
  if (page_en && candidates_count && !_style.inline_preedit) {
    int _prex = _contentSize.cx - offsetX - real_margin_x +
                _style.hilite_padding_x - pgw;
    int _prey = (_preeditRect.top + _preeditRect.bottom) / 2 - pgszl.cy / 2;
    _prePageRect.SetRect(_prex, _prey, _prex + pgszl.cx, _prey + pgszl.cy);
    _nextPageRect.SetRect(_prePageRect.right + _style.hilite_spacing, _prey,
                          _prePageRect.right + _style.hilite_spacing + pgszr.cx,
                          _prey + pgszr.cy);
    if (ShouldDisplayStatusIcon()) {
      _prePageRect.OffsetRect(-STATUS_ICON_SIZE, 0);
      _nextPageRect.OffsetRect(-STATUS_ICON_SIZE, 0);
    }
  }

  // prepare temp rect _bgRect for roundinfo calculation
  CopyRect(_bgRect, _contentRect);
  _bgRect.DeflateRect(offsetX + 1, offsetY + 1);
  // prepare round info for single row status, only for single row situation
  _PrepareRoundInfo(dc);
  // readjust for multi rows
  if (row_cnt)  // row_cnt > 0, at least 2 candidates
  {
    _roundInfo[0].IsBottomLeftNeedToRound = false;
    _roundInfo[candidates_count - 1].IsTopRightNeedToRound = false;
    for (auto i = 1; i < candidates_count; i++) {
      _roundInfo[i].Hemispherical = _roundInfo[0].Hemispherical;
      if (row_of_candidate[i] == row_cnt &&
          row_of_candidate[i - 1] == row_cnt - 1)
        _roundInfo[i].IsBottomLeftNeedToRound = true;
      if (row_of_candidate[i] == 0 && row_of_candidate[i + 1] == 1)
        _roundInfo[i].IsTopRightNeedToRound = _style.inline_preedit;
    }
  }
  // truely draw content size calculation
  _contentRect.DeflateRect(offsetX, offsetY);
}
