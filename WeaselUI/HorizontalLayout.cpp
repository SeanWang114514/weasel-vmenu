#include "stdafx.h"
#include "HorizontalLayout.h"
#include "InlineAnnot.h"

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
  // [vmenu-nolabel] grid_2d = 2：这条候选不画序号。第二十一轮用户诉求（原话）：
  //   「把第一个 131 删除 只留下第二个（这个也最好不要显示序号）」——
  //   纯数字编码输入时候选里只剩「常用语预览」一条，序号「1」既没用又占地方。
  if (grid_seq_mode_ == 2)
    return L"";
  // [vmenu-grid] 静态 v 菜单（v 主菜单 / v3 快捷输入）：数字键是顺序选的（Lua 的 cur=="v"
  // 分支），所以整块按 1..N 顺序编号，且**每一行都要显示**（否则第 2 行的「5 原符号」
  // 没有序号，用户看不出该按几）。服务端用 ctx.grid_2d=0 通知这种情形。
  if (grid_seq_mode_ == 0) {
    if (id < 0)
      return L"  ";
    return std::to_wstring(id + 1) + L" ";
  }
  const int hl_row = this->id / cols;
  // [vpick] grid_2d = 3：符号面板（v5）—— 与 1 同样按「行 × 列」画序号，
  //   但第 1 行是「大栏」：只有前 4 格（4 个大栏）编号 1-4，5-9 是占位空格，
  //   画上序号就是一排没用的数字，所以返回两个空格（与「数字+空格」等宽，
  //   保证大栏行与下面小栏行的左边缘对齐）。其余行照旧 1-9。
  if (grid_seq_mode_ == 3) {
    if (id < 0) return L"  ";
    const int row3 = id / cols;
    const int col3 = id % cols;
    if (row3 == hl_row && !(row3 == 0 && col3 >= 4))
      return std::to_wstring(col3 + 1) + L" ";
    return L"  ";
  }
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
  //   基准列数：普通打字 9；**v 功能菜单 4**（服务端用 ctx.grid_cols 下发，用户要求
  //   「一行显示 4 个」，展开后 4 行 × 4 = 16 个）。旧服务端不发这个键 → 0 → 退化为 9。
  const bool explicit_cols = (_context.grid_cols > 0);
  // [vmenu-line] 静态 v 菜单（v 主菜单 5 项 / v→3 快捷输入 7 项）—— 服务端用 ctx.grid_2d = 0 下发。
  //   用户诉求（第二十轮，原话）：「让 v 功能的页面的候选词在同一行显示」。
  //   这两张菜单是人手定的、条目本来就只有 5~7 条，之前按 4 列 / 2 列折行
  //   （v 主菜单排成 4+1、快捷输入排成 2 列 × 4 行），现在改成：
  //     * **一行排开**（列数 = 候选数，永不折行）；
  //     * **按各格自然宽度**（不统一拉成最宽那一格）—— 条目短，自然宽度既短又贴合内容；
  //     * **不裁列、不截断**（菜单项不允许被藏起来）。
  //   它们永远不会展开成方格，所以不涉及「收起态与展开后各列对齐」那套约束。
  //   旧服务端不发 grid_2d → 缺省 1 → 这里自动退回老行为。
  const bool static_menu = explicit_cols && (_context.grid_2d == 0);
  const int kGridCols =
      static_menu ? max(1, min(candidates_count, MAX_CANDIDATES_COUNT))
                  : ((_context.grid_cols > 0) ? _context.grid_cols : 9);
  // [vmenu-hug] 「排满一页才强制等宽」这条老规则第二十一轮起由 `grid_uniform = grid_multi_row`
  //   取代（收起态一律自然宽度），所以 kGridUniformMin 不再需要。
  // [vmenu-fixed] 剪贴板 / 常用语「固定格宽」占屏幕宽度的百分比：用户定 20%（= 屏宽 1/5，
  //   相对整屏宽度算是「减少 4/5」）。改这一个数字就能整体调宽/调窄（往下还有 120px 的字宽保底）。
  const int kVMenuFixedCellPercent = 20;
  const bool grid_multi_row = !static_menu && (candidates_count > kGridCols);
  int col_width = 0;
  int grid_label_w = 0;                // 网格态统一序号槽宽（见下面注释）
  int draw_cols = kGridCols;           // 本行实际画几格（<= kGridCols，见下面「少放几个」）
  // [vmenu-hug] 每格「自然宽度」（标签 + 间距 + 候选词 + 注释，不含格间间距）。
  //   第二十一轮：收起态按这些自然宽度**紧贴内容**排（框跟着候选词走），
  //   上限超标时也用它算「删掉尾部第 n 条之后还剩多宽」。声明在 if 之外：
  //   下面的宽度上限判断与主循环都要读。
  int cand_widths[MAX_CANDIDATES_COUNT] = {0};
  // [vmenu-boxwidth] 「格宽被压小」标记：长候选 + 上限挤不下时把格宽压到 上限/格数，
  //   文字与注释按格裁成「…」。在 `if (candidates_count)` 之外声明：下面的
  //   「末格拉到右缘」美化（第二个 if 块）也要看它。
  bool cells_shrunk = false;
  // [vmenu-hug] 是否启用「统一列宽」（= 展开态同步成最长的候选词）。在下面的宽度上限
  //   判断里可能被改成 true（兜底：删到 3 条还放不下时退回等宽 + 压窄）。
  bool grid_uniform = false;
  int& cols_per_row = cols_per_row_;   // 换行 / 编号的步长：普通 9、v 功能菜单 4
  cols_per_row = kGridCols;
  // [vmenu-fixed] 「固定格宽」= 剪贴板 / 常用语（服务端下发 grid_cols == 2 的列表模式）。
  //   用户要求：「候选词的框框长度固定，装不下的候选词用 … 代替」。
  //   这类模式的格宽**不再由内容决定**。原来的做法是「取最宽候选当统一列宽」：
  //   一行剪贴板长句（70~120 字）会把列宽顶到 1400px 以上，2 列放不进屏幕 →
  //   触发「少放几格」，实测只剩 1 列，而且面板宽度随剪贴板内容跳来跳去。
  //   现在改成把可用屏幕宽度**按列数等分**并钉死：
  //     * 面板宽度恒定（同一模式永远一样宽），换页 / 换内容都不抖；
  //     * 每格等宽，超长候选词在绘制阶段被裁掉并以「…」结尾（WeaselPanel::_TextOut，
  //       候选词文本本身不动 → 选中后上屏的仍是完整内容）。
  const int kScreenW = GetSystemMetrics(SM_CXSCREEN);
  const int grid_budget =
      (kScreenW > 0) ? (kScreenW - offsetX - 2 * real_margin_x - 16) : 0;
  // [vmenu-line] 静态 v 菜单不走固定格宽：它们的列数现在等于候选数，恰好 2 项时
  //   （例如 vset 的二次确认页）不能被误判成「剪贴板那种 2 列固定格」。
  const bool fixed_cells =
      (!static_menu && explicit_cols && kGridCols == 2 && grid_budget > 0);
  // 固定格宽（含列间距）。上限 = **屏幕宽度的 27%**（用户指定：剪贴板 / 常用语每个候选框
  //   的长度上限就从原来的「可用宽度一半（≈ 屏幕 50%）」缩到 27% —— 格子更短、更整齐，
  //   装不下的候选词照样由绘制阶段裁成「…」，上屏内容仍是完整的一句）。
  //   120px 保底：极端小屏 / 高 DPI 下别窄到看不见字；再与「可用宽度按列数均分」取小。
  int fixed_col_width = 0;
  if (fixed_cells) {
    const int screen_limit = (int)((long long)kScreenW * kVMenuFixedCellPercent / 100);
    fixed_col_width =
        max(min(screen_limit, grid_budget / kGridCols),
            120 + _style.candidate_spacing);
  }
  // [vmenu-grid] 序号算法由服务端下发：1 = 行 × 列（列表 / 普通打字的展开网格），
  // 0 = 顺序 1..N（静态 v 菜单），2 = 不画序号（纯数字编码输入，见 GetLabelText）。
  grid_seq_mode_ = _context.grid_2d;
  // [vmenu-nolabel] 不画序号时，标签槽宽度是 0，标签与候选词之间那个间距也要省掉
  //   （否则候选词左侧会多出约 8px 的空隙，框看着不贴合）。
  const bool no_labels = (_context.grid_2d == 2);
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
      // [vmenu-fuzzy] 内联拼音标注：这一格的宽度 = 词段 + 拼音段 + 段间小距，
      // 与 WeaselPanel 的分段绘制完全一致；带协议的候选词尾不再追加注释宽度。
      const int annot_gap = max(2, _style.hilite_spacing);
      std::vector<vmenu_annot::Seg> annot_segs;
      std::vector<vmenu_annot::Run> annot_runs;
      for (auto i = 0; i < candidates_count && i < MAX_CANDIDATES_COUNT; ++i) {
        int cw = grid_label_w + (no_labels ? 0 : _style.hilite_spacing);
        if (vmenu_annot::Parse(comments.at(i).str, annot_segs)) {
          vmenu_annot::BuildRuns(candidates.at(i).str, annot_segs, annot_runs);
          int tw = 0;
          for (const auto& r : annot_runs) {
            GetTextSizeDW(r.s, r.s.length(),
                          r.is_py ? pDWR->pCommentTextFormat
                                  : pDWR->pTextFormat,
                          pDWR, &size);
            tw += size.cx * (r.is_py ? cmtFontValid : textFontValid);
          }
          cw += tw + annot_gap * (static_cast<int>(annot_runs.size()) - 1);
        } else {
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
        }
        // [vmenu-hug] 记下这一格的自然宽度：收起态直接用它排版，宽度超标时也用它算总宽。
        cand_widths[i] = cw;
        col_width = max(col_width, cw);
      }
      col_width += _style.candidate_spacing;  // 列与列之间的间距
    }
    // [vmenu-fixed] 固定格宽：覆盖上面「按最宽候选」量出来的列宽（本身只当兜底）。
    if (fixed_cells)
      col_width = fixed_col_width;
    // [vmenu-grid] 统一列宽的另一面：万一有**超长候选**（例如很长的常用语 / 剪贴板长句 /
    // English 长词），N 列 × 那个宽度会把面板撑得几乎整屏宽。用户允许「实在太长就少放 1-3 个」：
    // 从「这一行本来有几格」往下减，减到这一行能放进**框宽上限**为止。
    // 减掉的那几格**不画**（visible_cols_），但列位置仍钉在「列号 × 列宽」上，
    // 于是收起态那一行与展开后每一行同一列严格对齐（用户要求「上下对齐」）。
    // 注意：固定格宽（剪贴板 / 常用语）的列宽已经 ≤ budget/列数，这里不会触发裁列。
    //
    // [vmenu-hug] 框宽上限 = min(主题 style/layout/max_width, 屏幕可用宽度)。
    //   第二十一轮用户诉求（原话）：「不开启折叠栏的时候候选词框的大小跟随这个候选词，
    //   打开后就同步成最长的候选词；同时限制候选词整条栏的最长长度，如果超出就删除部分候选词」。
    //   → 收起态（单行）：**每格用自己的自然宽度**（框紧贴候选词，最长的那个不再把整条框撑宽）；
    //   → 展开态（4 行网格）：统一成最宽那一格（就是「同步成最长的候选词」）；
    //   → 两种状态都受上限约束，超出的处理是**先删尾部候选**（至少留 3 条），
    //     删到只剩 3 条还放不下才压窄格宽 + 「…」裁剪（极长词的兜底）。
    //   max_width 是现成的主题键，所以「框最长多长」用户改主题就能调，不用改代码。
    draw_cols = kGridCols;
    const int row_budget = (grid_budget > 0 && _style.max_width > 0)
                               ? min(_style.max_width, grid_budget)
                               : grid_budget;
    // 本行「自然宽度」= 前 n 格各自的自然宽度 + 格间间距（末尾那格后面不留间距）。
    auto natural_row_width = [&](int n) {
      int s = 0;
      for (int i = 0; i < n && i < MAX_CANDIDATES_COUNT; ++i)
        s += cand_widths[i] + _style.candidate_spacing;
      return (n > 0) ? (s - _style.candidate_spacing) : 0;
    };
    if (!static_menu && !fixed_cells && row_budget > 0) {
      const int avail_cols = min(kGridCols, candidates_count);
      // 「至少留 3 条」：候选本来就不足 3 条时全留（不为凑数删到空）。
      const int floor_cols = min(3, avail_cols);
      if (!grid_multi_row) {
        int n = avail_cols;
        while (n > floor_cols && natural_row_width(n) > row_budget)
          --n;
        draw_cols = n;
        if (natural_row_width(n) > row_budget) {
          // 兜底：3 条自然宽度也超标（极长英文词）→ 退回等宽并把格宽压到上限以内，
          //   文字由绘制阶段裁成「…」（候选文本本身不动，上屏仍是完整的）。
          grid_uniform = true;
          col_width = max(row_budget / max(n, 1),
                          120 + _style.candidate_spacing);
          cells_shrunk = true;
        }
      } else if (col_width > 0) {
        // 展开态：格子等宽，按「格数 × 格宽」超标就少放几列（列位置仍钉在列号上，
        //   所以上下每一行省掉的是同样的那几格，仍然严格对齐）。
        while (draw_cols > floor_cols && draw_cols * col_width > row_budget)
          --draw_cols;
        if (draw_cols * col_width > row_budget) {
          col_width = max(row_budget / max(draw_cols, 1),
                          120 + _style.candidate_spacing);
          cells_shrunk = true;
        }
      }
    }
    // [vmenu-grid] 高亮格绝不能被裁掉：高亮所在列一旦被省去，高亮块会整块消失（键盘
    //   选词失去焦点提示），那一格的 rect 又是 (0,0,0,0)，文字会被画到窗口左上角
    //   形成概率出现的「残影/错位」。所以高亮落到尾列时宁可这一行略宽，
    //   也要把高亮所在的那一列画出来（最多也就多放 1 格）。
    if (id >= 0 && id < candidates_count)
      draw_cols = max(draw_cols, (id % kGridCols) + 1);
    // 凡是「格宽被钉死」的两种情况，文字/注释都要裁在格子里（DirectWrite 自动画「…」）。
    const bool clip_cells = fixed_cells || cells_shrunk;
    visible_cols_ = draw_cols;
    const bool cols_trimmed = (draw_cols < kGridCols);
    // [vmenu-hug] 统一列宽**只在展开态启用**（用户要求「打开后就同步成最长的候选词」）。
    //   收起态刻意不统一：框宽紧贴候选词的自然宽度，最长的那个不再把整条框撑宽
    //   （用户要求「不开启折叠栏的时候候选词框的大小跟随这个候选词」）。
    //   固定格宽（剪贴板 / 常用语）与「压窄兜底」当然也是等宽的。
    if (!grid_uniform)
      grid_uniform = !static_menu && grid_multi_row && col_width > 0;
    for (auto i = 0; i < candidates_count && i < MAX_CANDIDATES_COUNT; ++i) {
      // [vmenu-grid] 「实在太长就少放 1-3 个」：这一行第 draw_cols 格之后的候选不画。
      //   注意不画 ≠ 挪走：列位置仍按 kGridCols 的步长排，所以被省掉的永远是每行的**最后几格**，
      //   展开后的每一行省掉的也是同样的那几格 → 上下严格对齐（用户要求）。
      if ((i % kGridCols) >= draw_cols) {
        _candidateLabelRects[i].SetRectEmpty();
        _candidateTextRects[i].SetRectEmpty();
        _candidateCommentRects[i].SetRectEmpty();
        row_of_candidate[i] = i / kGridCols;
        mintop_of_rows[row_of_candidate[i]] = height;
        continue;
      }
      int current_cand_width = 0;
      // [vmenu-fixed] ★ 每行第一个候选必须**先把光标拉回行首**再量尺寸。
      //   原来只有下面的换行块在「本候选画完之后」才回退光标，于是行首那个候选
      //   是用上一行行尾的光标量出来的：固定格宽下 cell_right - 注释 - w 直接 ≤ 0，
      //   候选词和注释都被画成 0 宽（实测第 2、4 个候选 rect 宽度 = 0）。
      //   这里提前回退，下面的换行块算出的 ofx 就变成 0，行高/行数统计不受影响。
      if (grid_multi_row && i > 0 && (i % cols_per_row) == 0) {
        w = offsetX + real_margin_x +
            ((i == id && !grid_multi_row) ? base_offset : 0);
        // 行首**不再**加列间距：加了以后行首格会比第 1 行右移 22px，
        // 后面换行块又会把 offsetX 记成 -22，注释列就会跟着错开一格间距。
      } else if (i > 0)
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
      // [vmenu-nolabel] 没有序号时不加「序号—候选词」之间那个间距（no_labels 时 lab_w = 0）。
      const int lab_gap = no_labels ? 0 : _style.hilite_spacing;
      w += lab_gap;
      current_cand_width += lab_gap;
      const std::wstring& text = candidates.at(i).str;
      // [vmenu-fuzzy] 内联拼音标注：词段用正文字体、拼音段用注释字体逐段量宽求和，
      // 段间加 annot_gap（与 WeaselPanel 的分段绘制完全一致）。
      std::vector<vmenu_annot::Seg> annot_segs;
      std::vector<vmenu_annot::Run> annot_runs;
      const bool annot = vmenu_annot::Parse(comments.at(i).str, annot_segs);
      GetTextSizeDW(text, text.length(), pDWR->pTextFormat, pDWR, &size);
      int text_natural_w = size.cx * textFontValid;
      const int text_h = size.cy;
      if (annot) {
        vmenu_annot::BuildRuns(text, annot_segs, annot_runs);
        const int annot_gap = max(2, _style.hilite_spacing);
        int tw = 0;
        for (const auto& r : annot_runs) {
          GetTextSizeDW(r.s, r.s.length(),
                        r.is_py ? pDWR->pCommentTextFormat : pDWR->pTextFormat,
                        pDWR, &size);
          tw += size.cx * (r.is_py ? cmtFontValid : textFontValid);
        }
        text_natural_w =
            tw + annot_gap * (static_cast<int>(annot_runs.size()) - 1);
      }

      /* Comment */
      // [vmenu-fixed] 注释要在**放候选词之前**量出来：固定格宽下注释右对齐到格子右缘，
      //   候选词只能用「注释左边」为止的那段宽度，超出部分由 DirectWrite 画成「…」。
      bool cmtFontNotTrans =
          (i == id && (_style.hilited_comment_text_color & 0xff000000)) ||
          (i != id && (_style.comment_text_color & 0xff000000));
      // [vmenu-fuzzy] 带内联标注协议的候选：词尾不再画注释（整段已被词内拼音消费）。
      const bool cmt_drawn =
          (!annot && !comments.at(i).str.empty() && cmtFontValid &&
           cmtFontNotTrans);
      int cmt_adv = 0, cmt_h = 0;
      if (cmt_drawn) {
        GetTextSizeDW(comments.at(i).str, comments.at(i).str.length(),
                      pDWR->pCommentTextFormat, pDWR, &size);
        cmt_adv = size.cx * cmtFontValid;
        cmt_h = size.cy;
      }
      // 本格的右缘（= 下一格左缘 - 列间距），与下面 grid_uniform 的「钉列号」算法一致。
      const int cell_right = offsetX + real_margin_x +
                             ((i % cols_per_row) + 1) * col_width -
                             _style.candidate_spacing;
      int draw_text_w = text_natural_w;
      // 注释占位宽度（注释 + 与候选词之间的间距）：固定格宽下文字区与光标都要让出这块。
      const int cmt_block = cmt_drawn ? cmt_adv + _style.hilite_spacing : 0;
      if (clip_cells) {
        draw_text_w = min(text_natural_w, max(0, cell_right - cmt_block - w));
      }
      _candidateTextRects[i].SetRect(w, height, w + draw_text_w, height + text_h);
      if (clip_cells) {
        // [vmenu-fixed] 固定格宽下光标只走到「本格文字区右缘」为止。
        //   原来无条件 w += text_natural_w：剪贴板长句的自然宽度上千像素，
        //   注释 rect 就被顶到格子外面（right 远超 cell_right），
        //   max_width_of_rows 跟着它涨 → **面板宽度随内容/翻页变**（实测 1008 / 1053 抖动）。
        //   夹到 cell_right - cmt_block 之后，注释正好右对齐到格右缘，面板宽度恒定。
        w = min(w + text_natural_w, cell_right - cmt_block);
      } else {
        w += text_natural_w;
      }
      current_cand_width += (text_natural_w + _style.hilite_spacing) * textFontValid;

      if (cmt_drawn) {
        const std::wstring& comment = comments.at(i).str;
        if (clip_cells) {
          // [vmenu-fixed] 注释右对齐到格子右缘：所有行的注释排成整齐的一列。
          //   注释自己放不下时（格子太窄 / 注释太长）同样裁成「…」。
          // [vmenu-boxwidth] 「格宽被压小」的情况（长候选挤不下时）走同一条路：
          //   注释也跟着裁在格子里，不会溢到隔壁格。收起态也不做「末格拉到右缘」的美化：
          //   格宽是压出来的，拉一下最后一格会比别的格宽，高亮块大小就不一致了。
          int cx = max(w, cell_right - cmt_adv);
          const int cw = max(0, min(cmt_adv, cell_right - cx));
          _candidateCommentRects[i].SetRect(cx, height, cx + cw, height + cmt_h);
          w = cx + cmt_adv;
        } else {
          w += _style.hilite_spacing;
          _candidateCommentRects[i].SetRect(w, height, w + cmt_adv,
                                            height + cmt_h);
          w += cmt_adv;
        }
        current_cand_width += (cmt_adv + _style.hilite_spacing) * cmtFontValid;
      } else /* Used for highlighted candidate calculation below */
        _candidateCommentRects[i].SetRect(w, height, w, height + text_h);

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
        // [vmenu-grid] 面板宽度按**实际画出的格数**算：候选比一行格数还少时不留空格
        //   （例如 v 常用语只有 2 条，就不要按 4 格宽画）。
        const int width_cols = min(draw_cols, candidates_count);
        max_width_of_rows =
            max(max_width_of_rows,
                offsetX + real_margin_x + width_cols * col_width);
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
      // [vmenu-grid] 本行被省掉的几格：rect 留空 → 不画、也点不到。
      if ((i % kGridCols) >= draw_cols) {
        _candidateRects[i].SetRectEmpty();
        continue;
      }
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
    visible_cols_ = 0;  // [vmenu-grid] 没有候选：不留下上一帧的裁列状态
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
      // [vmenu-grid] 被省掉的格子不参与「末格拉到右缘」的美化（否则空 rect 会被撑开）
      if ((i % kGridCols) >= draw_cols)
        continue;
      // make rightest candidate's rect right the same for better look
      // [vmenu-fixed] 固定格宽下**不做**这个「末格拉到右缘」的美化：格子本来就等宽，
      //   拉一下会让最后一格比其他格宽几像素，高亮块大小就不一致了。
      //   [vmenu-boxwidth] 格宽被压小的情况同理（见上面 clip_cells 的注释）。
      if ((i < candidates_count - 1 &&
           row_of_candidate[i] < row_of_candidate[i + 1]) ||
          (i == candidates_count - 1))
        // [vmenu-hug] 只有「等宽钉格」的排版才做这个美化：收起态现在是自然宽度、
        //   框要贴着候选词走（用户要求「框的大小跟随候选词」），
        //   把末格拉到面板右缘反而会多出一段空白。
        if (grid_uniform && !grid_multi_row && !fixed_cells && !cells_shrunk)
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
