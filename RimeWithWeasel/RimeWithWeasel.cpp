#include "stdafx.h"
#include <logging.h>
#include <RimeWithWeasel.h>
#include <StringAlgorithm.hpp>
#include <WeaselConstants.h>
#include <WeaselUtility.h>
#include <boost/algorithm/string.hpp>
#include <vector>

#include <cstring>
#include <filesystem>
#include <fstream>   // [vmenu-cfg] 读 grid-settings.txt（候选方格列数设置）
#include <map>
#include <regex>
#include <rime_api.h>

#define TRANSPARENT_COLOR 0x00000000
#define ARGB2ABGR(value)                                 \
  ((value & 0xff000000) | ((value & 0x000000ff) << 16) | \
   (value & 0x0000ff00) | ((value & 0x00ff0000) >> 16))
#define RGBA2ABGR(value)                                   \
  (((value & 0xff) << 24) | ((value & 0xff000000) >> 24) | \
   ((value & 0x00ff0000) >> 8) | ((value & 0x0000ff00) << 8))
typedef enum { COLOR_ABGR = 0, COLOR_ARGB, COLOR_RGBA } ColorFormat;

#ifdef USE_SHARP_COLOR_CODE
#define HEX_REGEX std::regex("^(0x|#)[0-9a-f]+$", std::regex::icase)
#define TRIMHEAD_REGEX std::regex("0x|#", std::regex::icase)
#else
#define HEX_REGEX std::regex("^0x[0-9a-f]+$", std::regex::icase)
#define TRIMHEAD_REGEX std::regex("0x", std::regex::icase)
#endif
using namespace weasel;

static RimeApi* rime_api;

// [vmenu-cfg] 候选方格列数的用户配置（<用户目录>\grid-settings.txt）。
//
// 用户诉求（原话）：「展开栏只显示 6 个，并且在 v1 的控制面板可以设置展开栏的每行数量
// 和没有展开栏的默认的每行数量」。于是列数从「硬编码 9 / 4 / 2」变成两个可调值：
//   cols_collapsed = 收起（没展开栏）时一行几个，默认 9
//   cols_expanded  = 按下 ↓ 展开后一行几个，默认 9
// 文件格式与 lua 侧的 fuzzy-settings.txt / candidate-settings.txt 同构：
//   「# 注释头 + 键=值」、LF、UTF-8 无 BOM；缺键 / 缺文件一律用默认值。
//
// ★ 为什么读盘放在服务端：前端 HorizontalLayout 的列数**只能**由服务端下发的
//   ctx.grid_cols 决定（客户端 DLL 是独立的进程内模块，自己不知道用户的设置），
//   而 lua 又拿不到「前端一行画几个」的权威值（换行是前端算的）。服务端在这里读一次，
//   lua 侧同时读同一个文件（见 vmenu_core.lua 的 grid_cfg），两边保持一致。
//
// ★ 读盘节流：ProcessKeyEvent / _Respond 都是热路径，所以加 1 秒 TTL 缓存
//   （与 lua 侧的 settings_cached 同构）。设置面板改完最迟 1 秒生效。
namespace {
const int kGridColsCollapsedDefault = 9;
const int kGridColsExpandedDefault = 9;
const int kGridColsMin = 1;
const int kGridColsMax = 20;
// [vmenu-uppage] 与 src/lua/vmenu_core.lua 必须一致：
//   GRID_ROWS = 4（展开栏的行数）、GRID_PAGES = 16（页码 option vmenu_page_0..15）。
// 改了 lua 那边这两个值，这里也要跟着改，否则「↑ 回上页」会读不到页码 / 落错行。
const int kGridRows = 4;
const int kGridPages = 16;
// [vmenu-uppage-list] ★ 列表型 v 功能（vclip / vfav / vsetc / vsetf）的实际几何是
//   2 列 × 3 行（lua 侧 M.LIST_COLS=2 / M.LIST_ROWS=3 / M.LIST_LIMIT=6），**不是** 4 行。
//   这里原先把 kGridRows(=4) 无差别地用来算「↑ 回上页」的落点：
//     restore = (4-1)*2 + col = 6 + col   →  一页只有 6 条（索引 0..5），6/7 双双越界，
//     又被下面的 new_count-1 夹成同一个 5 —— 列信息在这一步被抹掉，于是用户要的
//     「上一页最后一行、同一列」退化成「永远落在最后一条」。
//   改成按列表实际行数算，col 才真正起作用：
//     col=0 → 4（上一页最后一行左格），col=1 → 5（上一页最后一行右格）。
const int kListRows = 3;

struct GridCfg {
  int collapsed = kGridColsCollapsedDefault;
  int expanded = kGridColsExpandedDefault;
};

// 把 "键=值" 里的整数夹到合法区间；非法就返回 fallback。
int _GridClampInt(const std::string& v, int fallback) {
  try {
    const int n = std::stoi(v);
    if (n < kGridColsMin || n > kGridColsMax) return fallback;
    return n;
  } catch (...) {
    return fallback;
  }
}

// 读 <用户目录>\grid-settings.txt。1 秒 TTL；失败一律返回默认值（绝不抛异常）。
const GridCfg& _GridCfgCached() {
  static GridCfg cfg;
  static DWORD last_tick = 0;
  const DWORD now = ::GetTickCount();
  // 注意 last_tick == 0 表示「从没读过」；GetTickCount 回绕时也只是多读一次。
  if (last_tick != 0 && (now - last_tick) < 1000) return cfg;

  last_tick = now;
  GridCfg fresh;  // 先建默认值：中途任何失败都退化为默认，不会留下半读状态
  try {
    const std::filesystem::path p =
        std::filesystem::path(WeaselUserDataPath().wstring()) / L"grid-settings.txt";
    std::ifstream in(p, std::ios::binary);
    if (in) {
      std::string line;
      while (std::getline(in, line)) {
        // 兼容 CRLF：把行尾的 \r 去掉
        if (!line.empty() && line.back() == '\r') line.pop_back();
        const size_t hash = line.find('#');
        if (hash != std::string::npos) line.erase(hash);  // 允许行内注释
        const size_t eq = line.find('=');
        if (eq == std::string::npos) continue;
        std::string k = line.substr(0, eq);
        std::string v = line.substr(eq + 1);
        // 去掉两侧空白
        const char* ws = " \t";
        const size_t kb = k.find_first_not_of(ws);
        k = (kb == std::string::npos) ? "" : k.substr(kb, k.find_last_not_of(ws) - kb + 1);
        const size_t vb = v.find_first_not_of(ws);
        v = (vb == std::string::npos) ? "" : v.substr(vb, v.find_last_not_of(ws) - vb + 1);
        if (k == "cols_collapsed")
          fresh.collapsed = _GridClampInt(v, kGridColsCollapsedDefault);
        else if (k == "cols_expanded")
          fresh.expanded = _GridClampInt(v, kGridColsExpandedDefault);
      }
    }
  } catch (...) {
    // 读盘/解析异常：保持默认值（输入法绝不能因为设置文件坏了而不能打字）
  }
  cfg = fresh;
  return cfg;
}

// [vmenu-uppage-trace] 把「翻页后在第 1 行按 ↑」这次处理写进用户目录的
// vmenu-uppage.log。用途：让验收脚本能直接读文件确认这条分支真的被走到、
// 以及落点算成了什么，不必依赖 rime 的 log_level=debug（默认看不到 DLOG）。
//
// 为什么要单独一个文件而不是复用 vmenu-debug.log：
//   vmenu-debug.log 是 lua 侧写的，lua 与 C++ 各自 open/write/close，
//   分开写避免两边同时追加造成内容交错。
//
// 拿到用户目录：优先环境变量 RIME_USER_DATA_DIR，其次读注册表里 Weasel 的
// RimeUserDir，最后回落到 WeaselServer.exe 所在目录。全都失败就静默放弃
// （诊断代码绝不能影响输入）。
inline void _UpPageTrace(int page, int col, int restore, int count) {
  try {
    wchar_t dir[MAX_PATH] = {0};
    DWORD n = GetEnvironmentVariableW(L"RIME_USER_DATA_DIR", dir, MAX_PATH);
    if (n == 0 || n >= MAX_PATH) {
      HKEY hk = nullptr;
      if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Software\\Rime\\Weasel", 0,
                        KEY_READ, &hk) == ERROR_SUCCESS) {
        DWORD cb = sizeof(dir);
        DWORD type = 0;
        if (RegQueryValueExW(hk, L"RimeUserDir", nullptr, &type,
                             reinterpret_cast<LPBYTE>(dir), &cb) != ERROR_SUCCESS)
          dir[0] = 0;
        RegCloseKey(hk);
      }
    }
    if (dir[0] == 0) {
      if (GetModuleFileNameW(nullptr, dir, MAX_PATH) == 0)
        return;
      if (wchar_t* p = wcsrchr(dir, L'\\'))
        *p = 0;
    }
    std::wstring path(dir);
    path += L"\\vmenu-uppage.log";

    SYSTEMTIME st;
    GetLocalTime(&st);
    char line[256];
    _snprintf_s(line, sizeof(line), _TRUNCATE,
                "%02d:%02d:%02d up-page from page=%d col=%d -> restore=%d "
                "of %d\r\n",
                st.wHour, st.wMinute, st.wSecond, page, col, restore, count);
    HANDLE f = CreateFileW(path.c_str(), FILE_APPEND_DATA,
                           FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                           OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (f == INVALID_HANDLE_VALUE)
      return;
    DWORD written = 0;
    WriteFile(f, line, (DWORD)strlen(line), &written, nullptr);
    CloseHandle(f);
  } catch (...) {
    // 诊断代码失败一律忽略
  }
}
}  // namespace

// [vmenu-grid] v 功能菜单判定与「一行几列」——定义在下面（_Respond 之前），
// ProcessKeyEvent 里也要用（数字键换行换算、方向键网格导航），先声明。
inline bool _VMenuLabel(RimeApi* api,
                        RimeSessionId session_id,
                        const char* code,
                        std::string* label);
inline bool _IsVMenu(RimeApi* api, RimeSessionId session_id, const char* code);
inline int _VMenuCols(RimeApi* api, RimeSessionId session_id, const char* code);
inline bool _VMenuList(RimeApi* api, RimeSessionId session_id, const char* code);
inline int _VMenuSeqMode(RimeApi* api,
                         RimeSessionId session_id,
                         const char* code,
                         int candidates);
WeaselSessionId _GenerateNewWeaselSessionId(SessionStatusMap sm, DWORD pid) {
  if (sm.empty())
    return (WeaselSessionId)(pid + 1);
  return (WeaselSessionId)(sm.rbegin()->first + 1);
}

int expand_ibus_modifier(int m) {
  return (m & 0xff) | ((m & 0xff00) << 16);
}

static void CleanOldLogs() {
  char ymd[12] = {0};
  time_t now = time(NULL);
  strftime(ymd, sizeof(ymd), ".%Y%m%d", localtime(&now));
  std::string today(ymd);
  const std::string app_name = "rime.weasel";
  std::string dir = WeaselLogPath().string();
  if (!fs::exists(fs::path(dir)))
    return;
  std::vector<fs::path> files;
  try {
    // preparing files
    for (const auto& entry : fs::directory_iterator(dir)) {
      const std::string& file_name(entry.path().filename().string());
      if (entry.is_regular_file() && !entry.is_symlink() &&
          boost::starts_with(file_name, app_name) &&
          boost::ends_with(file_name, ".log") &&
          !boost::contains(file_name, today)) {
        files.push_back(entry.path());
      }
    }
  } catch (const fs::filesystem_error&) {
  }
  // remove files
  for (const auto& file : files) {
    try {
      // ensure write permission
      fs::permissions(file, fs::perms::owner_write);
      fs::remove(file);
    } catch (const fs::filesystem_error&) {
    }
  }
}

RimeWithWeaselHandler::RimeWithWeaselHandler(UI* ui)
    : m_ui(ui),
      m_active_session(0),
      m_disabled(true),
      m_current_dark_mode(false),
      m_global_ascii_mode(false),
      m_show_notifications_time(1200),
      _UpdateUICallback(NULL) {
  rime_api = rime_get_api();
  assert(rime_api);
  m_pid = GetCurrentProcessId();
  uint16_t msbit = 0;
  for (auto i = 31; i >= 0; i--) {
    if (m_pid & (1 << i)) {
      msbit = i;
      break;
    }
  }
  m_pid = (m_pid << (31 - msbit));
  _Setup();
}

RimeWithWeaselHandler::~RimeWithWeaselHandler() {
  m_show_notifications.clear();
  m_session_status_map.clear();
  m_app_options.clear();
}

bool add_session = false;
void _UpdateUIStyle(RimeConfig* config, UI* ui, bool initialize);
bool _UpdateUIStyleColor(RimeConfig* config,
                         UIStyle& style,
                         std::string color = "");
void _LoadAppOptions(RimeConfig* config, AppOptionsByAppName& app_options);

void _RefreshTrayIcon(const RimeSessionId session_id,
                      const std::function<void()> _UpdateUICallback) {
  // Dangerous, don't touch
  static char app_name[256] = {0};
  auto ret = rime_api->get_property(session_id, "client_app", app_name,
                                    sizeof(app_name) - 1);
  if (!ret || u8tow(app_name) == std::wstring(L"explorer.exe"))
    boost::thread th([=]() {
      ::Sleep(100);
      if (_UpdateUICallback)
        _UpdateUICallback();
    });
  else if (_UpdateUICallback)
    _UpdateUICallback();
}

void RimeWithWeaselHandler::_Setup() {
  RIME_STRUCT(RimeTraits, weasel_traits);
  std::string shared_dir = wtou8(WeaselSharedDataPath().wstring());
  std::string user_dir = wtou8(WeaselUserDataPath().wstring());
  weasel_traits.shared_data_dir = shared_dir.c_str();
  weasel_traits.user_data_dir = user_dir.c_str();
  weasel_traits.prebuilt_data_dir = weasel_traits.shared_data_dir;
  std::string distribution_name = wtou8(get_weasel_ime_name());
  weasel_traits.distribution_name = distribution_name.c_str();
  weasel_traits.distribution_code_name = WEASEL_CODE_NAME;
  weasel_traits.distribution_version = WEASEL_VERSION;
  weasel_traits.app_name = "rime.weasel";
  std::string log_dir = WeaselLogPath().u8string();
  weasel_traits.log_dir = log_dir.c_str();
  rime_api->setup(&weasel_traits);
  rime_api->set_notification_handler(&RimeWithWeaselHandler::OnNotify, this);
}

void RimeWithWeaselHandler::Initialize() {
  m_disabled = _IsDeployerRunning();
  if (m_disabled) {
    return;
  }

  LOG(INFO) << "Initializing la rime.";
  rime_api->initialize(NULL);
#if 0
  if (rime_api->start_maintenance(/*full_check = */ False)) {
    m_disabled = true;
  }
#endif
  CleanOldLogs();

  RimeConfig config = {NULL};
  if (rime_api->config_open("weasel", &config)) {
    if (m_ui) {
      _UpdateUIStyle(&config, m_ui, true);
      _UpdateShowNotifications(&config, true);
      m_current_dark_mode = IsUserDarkMode();
      if (m_current_dark_mode) {
        const int BUF_SIZE = 255;
        char buffer[BUF_SIZE + 1] = {0};
        if (rime_api->config_get_string(&config, "style/color_scheme_dark",
                                        buffer, BUF_SIZE)) {
          std::string color_name(buffer);
          _UpdateUIStyleColor(&config, m_ui->style(), color_name);
        }
      }
      m_base_style = m_ui->style();
    }
    Bool global_ascii = false;
    if (rime_api->config_get_bool(&config, "global_ascii", &global_ascii))
      m_global_ascii_mode = !!global_ascii;
    if (!rime_api->config_get_int(&config, "show_notifications_time",
                                  &m_show_notifications_time))
      m_show_notifications_time = 1200;
    _LoadAppOptions(&config, m_app_options);
    rime_api->config_close(&config);
  }
  m_last_schema_id.clear();
}

void RimeWithWeaselHandler::Finalize() {
  m_active_session = 0;
  m_disabled = true;
  m_session_status_map.clear();
  LOG(INFO) << "Finalizing la rime.";
  rime_api->finalize();
}

DWORD RimeWithWeaselHandler::FindSession(WeaselSessionId ipc_id) {
  if (m_disabled)
    return 0;
  Bool found = rime_api->find_session(to_session_id(ipc_id));
  DLOG(INFO) << "Find session: session_id = " << to_session_id(ipc_id)
             << ", found = " << found;
  return found ? (ipc_id) : 0;
}

DWORD RimeWithWeaselHandler::AddSession(LPWSTR buffer, EatLine eat) {
  if (m_disabled) {
    DLOG(INFO) << "Trying to resume service.";
    EndMaintenance();
    if (m_disabled)
      return 0;
  }
  RimeSessionId session_id = (RimeSessionId)rime_api->create_session();
  if (m_global_ascii_mode) {
    for (const auto& pair : m_session_status_map) {
      if (pair.first) {
        rime_api->set_option(session_id, "ascii_mode",
                             !!pair.second.status.is_ascii_mode);
        break;
      }
    }
  }

  WeaselSessionId ipc_id =
      _GenerateNewWeaselSessionId(m_session_status_map, m_pid);
  DLOG(INFO) << "Add session: created session_id = " << session_id
             << ", ipc_id = " << ipc_id;
  SessionStatus& session_status = new_session_status(ipc_id);
  session_status.style = m_base_style;
  session_status.session_id = session_id;
  _ReadClientInfo(ipc_id, buffer);

  RIME_STRUCT(RimeStatus, status);
  if (rime_api->get_status(session_id, &status)) {
    std::string schema_id = status.schema_id;
    m_last_schema_id = schema_id;
    _LoadSchemaSpecificSettings(ipc_id, schema_id);
    _LoadAppInlinePreeditSet(ipc_id, true);
    _UpdateInlinePreeditStatus(ipc_id);
    _RefreshTrayIcon(session_id, _UpdateUICallback);
    session_status.status = status;
    session_status.__synced = false;
    rime_api->free_status(&status);
  }
  m_ui->style() = session_status.style;
  // show session's welcome message :-) if any
  if (eat) {
    _Respond(ipc_id, eat);
  }
  add_session = true;
  _UpdateUI(ipc_id);
  add_session = false;
  m_active_session = ipc_id;
  return ipc_id;
}

DWORD RimeWithWeaselHandler::RemoveSession(WeaselSessionId ipc_id) {
  if (m_ui)
    m_ui->Hide();
  if (m_disabled)
    return 0;
  DLOG(INFO) << "Remove session: session_id = " << to_session_id(ipc_id);
  // TODO: force committing? otherwise current composition would be lost
  rime_api->destroy_session(to_session_id(ipc_id));
  m_session_status_map.erase(ipc_id);
  m_active_session = 0;
  return 0;
}

void RimeWithWeaselHandler::UpdateColorTheme(BOOL darkMode) {
  RimeConfig config = {NULL};
  if (rime_api->config_open("weasel", &config)) {
    if (m_ui) {
      _UpdateUIStyle(&config, m_ui, true);
      m_current_dark_mode = darkMode;
      if (darkMode) {
        const int BUF_SIZE = 255;
        char buffer[BUF_SIZE + 1] = {0};
        if (rime_api->config_get_string(&config, "style/color_scheme_dark",
                                        buffer, BUF_SIZE)) {
          std::string color_name(buffer);
          _UpdateUIStyleColor(&config, m_ui->style(), color_name);
        }
      }
      m_base_style = m_ui->style();
    }
    rime_api->config_close(&config);
  }

  for (auto& pair : m_session_status_map) {
    RIME_STRUCT(RimeStatus, status);
    if (rime_api->get_status(to_session_id(pair.first), &status)) {
      _LoadSchemaSpecificSettings(pair.first, std::string(status.schema_id));
      _LoadAppInlinePreeditSet(pair.first, true);
      _UpdateInlinePreeditStatus(pair.first);
      pair.second.status = status;
      pair.second.__synced = false;
      rime_api->free_status(&status);
    }
  }
  m_ui->style() = get_session_status(m_active_session).style;
}

// [vpick] 符号面板（v 功能菜单第 5 项，内部编码 vpick…）：前缀判断。
// 必须与 src/lua/vmenu_core.lua 的 mode_of / is_pick_code 一致。
// 与 _VMenuLabel 分开写是因为它在本文件里被用在 ProcessKeyEvent（早于 _VMenuLabel 定义）。
inline bool _VPickCode(const char* code) {
  if (!code) return false;
  return strncmp(code, "vpick", 5) == 0;
}

// [vpick] 第 1 行大类的个数。必须与这三处保持一致：
//   src/lua/vmenu_symbols.lua 的 TABS、src/lua/vmenu_core.lua 的 PICK_CATS（都是 4）、
//   以及下面 _PickGetCat / _PickActivate 里写死的 vpick_cat0..3。
// 用 kPickTabs 下发（ctx.pick_cats），前端据此算大类行居中。
static const int kPickTabs = 4;

// [vpick] 当前激活的大栏（option vpick_cat0..3，第一个为 true 的下标；全灭时按 0）。
// 与 vmenu_core.lua 的 pick_cat 同一套读法。
static int _PickGetCat(RimeApi* api, RimeSessionId session_id) {
  if (!api) return 0;
  char name[32];
  for (int i = 0; i < 4; ++i) {
    snprintf(name, sizeof(name), "vpick_cat%d", i);
    if (api->get_option(session_id, name)) return i;
  }
  return 0;
}

// [vpick] 切换大栏：写 4 个 vpick_cat* option（只写有变化的），顺手把页码归到第 1 页。
// set_option 会通知 librime 重跑候选管线 —— 这正是我们想要的（候选换成新大栏的内容）。
// 调用方在之后必须重新 highlight(目标大栏)：重翻译会把高亮重置回第 0 格。
void RimeWithWeaselHandler::_PickActivate(RimeSessionId session_id, int cat) {
  if (cat < 0 || cat > 3) return;
  const int cur = _PickGetCat(rime_api, session_id);
  if (cur == cat) return;  // 已经在这个大栏：什么都不写（写 option = 重翻译，白花）
  char name[32];
  // 与 page_set 同理：先把目标大栏点亮再灭旧的，避免中途出现「全都灭着」的空窗
  //（全灭时 Lua 的 pick_cat 按 0 处理，会闪一帧第 1 大栏的候选）。
  snprintf(name, sizeof(name), "vpick_cat%d", cat);
  if (!rime_api->get_option(session_id, name))
    rime_api->set_option(session_id, name, true);
  for (int i = 0; i < 4; ++i) {
    if (i == cat) continue;
    snprintf(name, sizeof(name), "vpick_cat%d", i);
    if (rime_api->get_option(session_id, name))
      rime_api->set_option(session_id, name, false);
  }
  // 换栏同时把页码归第 1 页：不然是上一栏翻过的页码，一进来小栏就是空的。
  // 与 Lua page_set 同序：先把 0 点亮再灭旧的，避免中途出现「全都灭着」的空窗。
  int page = -1;
  for (int i = 0; i < 16; ++i) {
    snprintf(name, sizeof(name), "vmenu_page_%d", i);
    if (rime_api->get_option(session_id, name)) { page = i; break; }
  }
  if (page > 0) {
    snprintf(name, sizeof(name), "vmenu_page_0");
    if (!rime_api->get_option(session_id, name))
      rime_api->set_option(session_id, name, true);
    for (int i = 1; i < 16; ++i) {
      snprintf(name, sizeof(name), "vmenu_page_%d", i);
      if (rime_api->get_option(session_id, name))
        rime_api->set_option(session_id, name, false);
    }
  }
}

// [vpick] 「刚进面板」检测 + 把高亮钉回当前大栏。
// 背景（实测 bug）：librime 的 highlighted_candidate_index 是**跨输入保留**的 ——
// 上一次选中的格子会一路带进新输入：比如刚上屏过小栏第 1 格「+」（下标 9），
// 下次 v5 进面板时高亮还在 9，光标就默认落进小栏，数字键/方向键的第一下也跟着错位。
// 用户要求「首先是大栏」，所以输入从别的东西变成 vpick 的那一帧把它钉回当前大栏。
// 放在 _Respond 里是因为所有按键路径（含鼠标点开后客户端补的那记 VK_SELECT）
// 都会先回数据再刷新界面：这里改完，紧接着的 get_context 拿到的就是第 0 格。
void RimeWithWeaselHandler::_PickEntryPin(RimeSessionId session_id) {
  if (!session_id || !rime_api) return;
  const char* in = rime_api->get_input(session_id);
  const bool is_pick = _VPickCode(in);
  bool& was = m_pick_active[session_id];
  if (is_pick && !was) {
    // 大栏 = 当前激活的 vpick_cat*（上次关面板时停在哪一栏就还是哪一栏），
    // 这样高亮格和小栏内容永远对得上；category 为 0 时等价于第 0 格。
    const int tab = _PickGetCat(rime_api, session_id);
    was = !!rime_api->highlight_candidate_on_current_page(session_id,
                                                           (size_t)tab);
    if (was)
      DLOG(INFO) << "[vpick] entry: pin highlight to tab " << tab;
    return;  // 没钉上（候选还没生成出来）就保持 false，下一帧 _Respond 再试
  }
  was = is_pick;
}

BOOL RimeWithWeaselHandler::ProcessKeyEvent(KeyEvent keyEvent,
                                            WeaselSessionId ipc_id,
                                            EatLine eat) {
  DLOG(INFO) << "Process key event: keycode = " << keyEvent.keycode
             << ", mask = " << keyEvent.mask << ", ipc_id = " << ipc_id;
  if (m_disabled)
    return FALSE;
  RimeSessionId session_id = to_session_id(ipc_id);
  // [vmenu-grid] 候选窗口展开成 4 行 × 9 列时的二维方向键导航。
  // 背景：rime 自带的 navigator 不处理左右方向键，librime-lua 也没有「只移动高亮」的 API
  // （ctx:select 是「选中并上屏」，用它会把候选直接打出去）。而 librime 的 C API 本来就有
  // highlight_candidate_on_current_page —— Weasel 自己在鼠标滚轮/hover 时已经在用（见
  // WeaselTSF/CandidateList.cpp:409、:427），这里沿用同一套做法。
  // 是否处于展开状态由 Lua 处理器维护的 vmenu_grid 选项表示（前端与 Lua 不用新增协议）；
  // 目标下标越界时不拦截，交回 rime 处理，从而保留「第一行按 ↑ 收起」等原有行为。
  // [vmenu-grid] 数字键：与**画出来的标签**严格一致，不依赖是否展开。
  // 标签由 HorizontalLayout::GetLabelText 按「高亮那一行」画 id%9+1；而 librime 自己的
  // selector 并不是「本页第 d 个」——高亮不在该行第 1 格时它会漂：
  //   实测① 展开态、高亮下移到第 2 行后按 3 → 上屏「🔟」（表内第 2 位）而不是第 12 位；
  //   实测② 收起态按 = 翻页后按 3 → 上屏「屎」（第 1 页的词），而不是第 2 页第 3 个。
  // 所以这里统一接管数字键：target = 高亮所在行行首 + (d-1)，再走「选中并上屏」。
  // 收起态 / v 菜单里高亮在第 1 行 → 等价于原来的「本页第 d 个」，行为不变。
  {
    int digit = -1;
    if (keyEvent.keycode >= 0x31 && keyEvent.keycode <= 0x39)
      digit = (int)keyEvent.keycode - 0x31;
    else if (keyEvent.keycode >= ibus::Keycode::KP_1 &&
             keyEvent.keycode <= ibus::Keycode::KP_9)
      digit = (int)keyEvent.keycode - (int)ibus::Keycode::KP_1;
    if (digit >= 0 && !(keyEvent.mask & ibus::Modifier::RELEASE_MASK) &&
        RIME_API_AVAILABLE(rime_api, select_candidate_on_current_page)) {
      // ⚠️ 闸门一：输入为空或**全是数字**时不接管，把数字留给 Lua 的数字编码逻辑
      //   （收藏可以设成 131 这种纯数字编码，用户逐位敲 1→3→1 时要能建码）。
      // ⚠️ 闸门二：输入以 `v` 开头时也不接管 —— 那是我们自己的 v 功能菜单与 v 子模式
      //   （v 菜单 / vclip / vfav / vqi / vset…）。菜单项、子模式都要靠 Lua 的
      //   menu_processor 收到数字才切换，如果被这里当成「选中并上屏」，按 3 就只会把
      //   「常用语」三个字写进文档 —— 用户实测的「v 功能无法正常打开」就是这个。
      const char* input = rime_api->get_input(session_id);
      // [vmenu-grid] 复制一份：下面还会调 rime（_VMenuCols / _VMenuList → get_option），
      // get_input 的裸指针可能被 librime 复用，留着用会读到脏内存。
      const std::string input_str = input ? input : "";
      bool digits_only = true;
      bool v_prefix = false;
      bool first_char = true;
      // ⚠️ 闸门三：输入里出现**大写字母**或**非字母字符**时不接管。
      //   雾凇拼音的快捷输入前缀都带大写字母（cC 计算 / U Unicode / N 农历 / R 数字大写），
      //   这些模式后面必须还能继续敲数字（cC1+2*3、U4E00、R123）—— 用户实测的
      //   「用了 cC 之后无法输入数字、一按数字就变成选词」就是这个。
      //   输入里已经有数字或符号（cC1+2）时同样不接管，否则后面的数字全被吃掉。
      bool has_upper = false;
      bool has_other = false;
      for (const char* p = input ? input : ""; *p != '\0'; ++p) {
        if (*p == '\'' || *p == ' ') continue;
        if (first_char) {
          first_char = false;
          v_prefix = (*p == 'v');
        }
        if (*p < '0' || *p > '9') digits_only = false;
        if (*p >= 'A' && *p <= 'Z')
          has_upper = true;
        else if (*p < 'a' || *p > 'z')
          has_other = true;
      }
      // ⚠️ 闸门四：日期/时间类前缀（rq / sj / xq / dt，全小写）后面也可以跟数字
      //   （例如指定某天），这些前缀还在输入框里时不接管数字。
      bool date_prefix = false;
      if (input && *input) {
        const char* kDatePrefixes[] = { "rq", "sj", "xq", "dt" };
        for (size_t i = 0; i < sizeof(kDatePrefixes) / sizeof(kDatePrefixes[0]); ++i) {
          if (strncmp(input, kDatePrefixes[i], strlen(kDatePrefixes[i])) == 0) {
            date_prefix = true;
            break;
          }
        }
      }
      // [vmenu-grid] v 功能菜单展开态（vmenu_grid）也要接管数字：
      //   那时标签是按「4 列」的行号画的（第 2 行的标签是 1-4），必须用同一个列数换算，
      //   否则按第 2 行的「1」会选到第 1 行第 1 个。收起态照旧不接管（菜单靠 Lua 的数字切换）。
      //   ★ 只对**列表型** v 功能接管：静态菜单（v 主菜单 / v3 快捷输入）的序号是 1..N 顺序，
      //     数字键必须继续交给 Lua 顺序选，按二维换算会选错。
      const bool grid_open =
          !!(rime_api->get_option(session_id, "vmenu_grid"));
      // [vmenu-grid] 原符号模式（v 主菜单第 5 项 = vraw_mode）例外：那里的 v 开头是用户
      //   自己敲的符号编码（vfh / vbd / va…），但候选窗是照**普通打字**的网格画的
      //   （_VMenuLabel 在 vraw 下返回 false → 9 列、按高亮行画 1-9），所以数字键必须
      //   和普通打字一样接管，否则就是「序号画着却按不动、按 3 反而把编码补成 v3」——
      //   用户反馈的「v5 的候选词选择逻辑没有和正常的候选词选择逻辑同步」正是这里。
      //   ★ 代价（用户已确认）：v3 / v10 这类「数字编码」不再能当编码输入。
      const bool vraw_mode =
          !!(rime_api->get_option(session_id, "vraw_mode"));
      const bool v_grid_digits =
          v_prefix && grid_open &&
          _VMenuList(rime_api, session_id, input_str.c_str());
      if ((!digits_only && (!v_prefix || vraw_mode) && !has_upper &&
           !has_other && !date_prefix) ||
          v_grid_digits) {
        RIME_STRUCT(RimeContext, ctx);
        if (rime_api->get_context(session_id, &ctx)) {
          const int current = ctx.menu.highlighted_candidate_index;
          const int count = ctx.menu.num_candidates;
          rime_api->free_context(&ctx);
          // [vmenu-grid] 列数与前端一致：v 功能菜单 4 列，普通打字 9 列。
          const int cols =
              _VMenuCols(rime_api, session_id, input_str.c_str());
          // [vpick] 大栏行（第 0 行）的数字键不选候选：
          //   1-4 = 切换到对应大栏（与 ←/→ 同一套语义），5-9 落在占位空格上直接吞掉，
          //   否则「常用字符」这四个字会被当成候选提交进文档。
          if (_VPickCode(input_str.c_str()) && current >= 0 && current < 9) {
            if (digit <= 3) {
              _PickActivate(session_id, digit);
              HighlightCandidateOnCurrentPage((size_t)digit, ipc_id, eat);
              m_active_session = ipc_id;
            }
            return TRUE;
          }
          const int row = (current > 0) ? (current / cols) : 0;
          const int target = row * cols + digit;
          if (target < count) {
            DLOG(INFO) << "vmenu-grid: digit " << (digit + 1) << " -> row " << row
                       << ", select " << target << " (highlight was " << current
                       << ")";
            SelectCandidateOnCurrentPage((size_t)target, ipc_id);
            _Respond(ipc_id, eat);
            _UpdateUI(ipc_id);
            m_active_session = ipc_id;
            return TRUE;
          }
        }
      }
    }
  }
  // [vmenu-grid] 展开态的方向键网格导航 / 加减号翻页。
  // ★ 静态 v 菜单（v 主菜单 / v3 快捷输入）不接：它们没有可展开的第二屏，
  //   而且 ↑↓ 在菜单里应该还是「移动高亮」（Lua/引擎自己的行为），
  //   接管后按 4 列跳行会显得莫名其妙。列表型 v 功能与普通打字照旧接管。
  // ★ get_input 返回的是 librime 内部缓冲，紧接着还有别的 rime 调用，
  //   不能把裸指针留着用（会读到已被覆盖的内存），先拷贝成 std::string。
  const std::string grid_input = rime_api->get_input(session_id);
  const bool grid_is_v = _IsVMenu(rime_api, session_id, grid_input.c_str());
  // ===== [vpick] 符号面板（v 菜单第 5 项）：大栏 + 小栏 双层方向键导航 =====
  // 用户诉求（2026-09-30）：
  //   * 最上面独立一栏是「大栏」（常用字符 / 符号 / 希腊字符 / 颜文字），←/→ 选择大栏；
  //   * 小栏是 4 行 × 9 列预览，光标在小栏时 ←/→ 在格子间移动，撞到行边界自动换行；
  //   * ↓：大栏 → 进入小栏；↑：小栏第一行 → 回大栏，大栏上再按 ↑ = 关闭窗口。
  // 光标 = 高亮格：0..3 = 大栏（4..8 是大栏行的 5 个占位空格，键盘永远停不到），
  // 9..44 = 小栏 36 格。移动高亮只能在服务端做（librime-lua 没有「只移动高亮」的 API）。
  // 大栏切换 = 写 vpick_cat* option（set_option 会重翻译 → 候选换成新大栏），
  // 换完把高亮重新放回该大栏（重翻译会把高亮重置到第 0 格）。
  if (!(keyEvent.mask & ibus::Modifier::RELEASE_MASK) &&
      _VPickCode(grid_input.c_str())) {
    const int kc = (int)keyEvent.keycode;
    const bool kDown = (kc == (int)ibus::Keycode::Down);
    const bool kUp = (kc == (int)ibus::Keycode::Up);
    const bool kLeft = (kc == (int)ibus::Keycode::Left);
    const bool kRight = (kc == (int)ibus::Keycode::Right);
    const bool kSpace = (kc == 0x20 || kc == (int)ibus::Keycode::KP_Space);
    const bool kReturn = (kc == 0xff0d || kc == (int)ibus::Keycode::KP_Enter);
    const bool kPageFwd = (kc == 0x2b || kc == 0x3d || kc == 0xffbd ||
                           kc == 0xff56 || kc == (int)ibus::Keycode::KP_Add);
    const bool kPageBack =
        (kc == 0x2d || kc == 0xff55 || kc == (int)ibus::Keycode::KP_Subtract);
    if (kDown || kUp || kLeft || kRight || kSpace || kReturn || kPageFwd ||
        kPageBack) {
      RIME_STRUCT(RimeContext, pctx);
      int current = -1;
      int count = 0;
      if (rime_api->get_context(session_id, &pctx)) {
        current = pctx.menu.highlighted_candidate_index;
        count = pctx.menu.num_candidates;
        rime_api->free_context(&pctx);
      }
      const bool on_tab = (current >= 0 && current < 9);
      // 大栏格下标（0..3）：4..8 是占位，就近归到 3（鼠标 hover 才可能停上去）
      const int tab = (current < 4) ? current : 3;

      // --- 空格 / 回车 ---
      if (kSpace || kReturn) {
        if (current >= 0 && current < 9) {
          // 大栏上 = 切换大栏（占位格吞掉，绝不把「常用字符」写进文档）
          if (current < 4) {
            _PickActivate(session_id, current);
            HighlightCandidateOnCurrentPage((size_t)current, ipc_id, eat);
            m_active_session = ipc_id;
          }
          return TRUE;
        }
        // 小栏：直接「选中当前高亮格」= 上屏该符号并关窗。
        // ★ 不能 return FALSE：ProcessKeyEvent 返回 FALSE = 把键交给**应用程序**，
        //   rime（含 Lua 的 space/Return 分支）根本不会被调用 —— 实测空格和回车
        //   原样敲进了记事本（文档变成 " \r\n"）。要交回 rime 必须自己调
        //   process_key；而 select_candidate_on_current_page 本身就是「确认高亮
        //   候选」，语义正好，还少一次 Lua 往返。
        rime_api->select_candidate_on_current_page(session_id, current);
        _Respond(ipc_id, eat);
        _UpdateUI(ipc_id);
        m_active_session = ipc_id;
        return TRUE;
      }

      int target = -1;
      bool page_fwd = false;
      if (kLeft) {
        if (on_tab) {
          const int nt = (tab + 3) % 4;
          _PickActivate(session_id, nt);
          HighlightCandidateOnCurrentPage((size_t)nt, ipc_id, eat);
          m_active_session = ipc_id;
          return TRUE;
        }
        target = current - 1;
        // 「撞到边界就换行」：current == 9 时再往左就出了小栏 —— 上一行正是大栏行，
        // 落回当前大栏格（4..8 是占位空格，键盘永远停不上去，直接归到 vpick_cat*）。
        // current >= 10 时 target >= 9，永远走不到这个分支。
        if (target < 9) target = _PickGetCat(rime_api, session_id);
      } else if (kRight) {
        if (on_tab) {
          const int nt = (tab + 1) % 4;
          _PickActivate(session_id, nt);
          HighlightCandidateOnCurrentPage((size_t)nt, ipc_id, eat);
          m_active_session = ipc_id;
          return TRUE;
        }
        target = current + 1;
        if (target >= count) return TRUE;  // 小栏最后一格：吞掉
      } else if (kDown) {
        if (on_tab) {
          target = 9 + (current % 4);  // 下键去小栏选择（同列往下）
          if (target >= count) return TRUE;
        } else {
          target = current + 9;
          if (target >= count) page_fwd = true;  // 小栏最后一行：整页下翻
        }
      } else if (kUp) {
        if (on_tab) {
          // 大栏上按 ↑ = 关闭窗口
          rime_api->clear_composition(session_id);
          _Respond(ipc_id, eat);
          _UpdateUI(ipc_id);
          m_active_session = ipc_id;
          return TRUE;
        }
        if (current < 18)
          target = _PickGetCat(rime_api, session_id);  // 小栏第一行 ↑ = 回到当前大栏
        else
          target = current - 9;
      }

      if (page_fwd || kPageFwd || kPageBack) {
        // 整页翻（+ / - 或小栏最后一行 ↓）：键交给 rime（Lua 的 pick 分支按
        // 36 个/页整屏翻），翻完把光标放回原处：大栏回原格，小栏回同列第一行。
        Bool handled = rime_api->process_key(
            session_id, keyEvent.keycode, expand_ibus_modifier(keyEvent.mask));
        int restore = -1;
        if (current >= 0 && current < 9)
          restore = tab;
        else if (current >= 9)
          restore = 9 + (current % 9);
        RIME_STRUCT(RimeContext, pctx2);
        if (rime_api->get_context(session_id, &pctx2)) {
          const int cnt = pctx2.menu.num_candidates;
          rime_api->free_context(&pctx2);
          if (restore >= cnt) restore = cnt - 1;
          if (restore >= 0 && cnt > 0)
            rime_api->highlight_candidate_on_current_page(session_id,
                                                          (size_t)restore);
        }
        _Respond(ipc_id, eat);
        _UpdateUI(ipc_id);
        m_active_session = ipc_id;
        return TRUE;
      }
      if (target >= 0 && target < count) {
        HighlightCandidateOnCurrentPage((size_t)target, ipc_id, eat);
        m_active_session = ipc_id;
        return TRUE;
      }
      if (kLeft || kRight || kUp || kDown) return TRUE;  // 越界：吞掉，别动输入行光标
      return FALSE;
    }
  }
  // [collapsed-candidate-nav] 普通候选栏在收起态也要支持左右键移动高亮。
  //   展开网格由下面的 vmenu-grid 分支处理；vpick 符号面板则由上面的专用分支处理。
  //   这里仅接管普通拼音候选，避免把 v 菜单的左右键语义改掉。
  if (!(keyEvent.mask & ibus::Modifier::RELEASE_MASK) &&
      !rime_api->get_option(session_id, "vmenu_grid") && !grid_is_v &&
      RIME_API_AVAILABLE(rime_api, highlight_candidate_on_current_page)) {
    const bool kLeft = keyEvent.keycode == ibus::Keycode::Left;
    const bool kRight = keyEvent.keycode == ibus::Keycode::Right;
    if (kLeft || kRight) {
      RIME_STRUCT(RimeContext, ctx);
      if (rime_api->get_context(session_id, &ctx)) {
        const int current = ctx.menu.highlighted_candidate_index;
        const int count = ctx.menu.num_candidates;
        rime_api->free_context(&ctx);
        if (count > 0) {
          // librime 在没有高亮时通常返回 -1；首次按左右键时从对应端进入。
          const int target =
              (current < 0) ? (kRight ? 0 : count - 1)
                            : (current + (kRight ? 1 : -1));
          if (target >= 0 && target < count) {
            HighlightCandidateOnCurrentPage((size_t)target, ipc_id, eat);
            m_active_session = ipc_id;
            return TRUE;
          }
          // 边界处吞掉方向键，避免它落到应用里移动文本光标；候选仍保持高亮。
          return TRUE;
        }
      }
    }
  }
  if (!(keyEvent.mask & ibus::Modifier::RELEASE_MASK) &&
      rime_api->get_option(session_id, "vmenu_grid") &&
      (!grid_is_v ||
       _VMenuList(rime_api, session_id, grid_input.c_str()))) {
    // [vmenu-grid] 列数：v 功能菜单 4 列（一行 4 个），普通打字 9 列。
    const int kGridColumns =
        _VMenuCols(rime_api, session_id, grid_input.c_str());
    // [vmenu-grid] 翻页键：+ / -。
    // 主键盘 + = shift+equal，客户端 ConvertKeyEvent 经 ToUnicodeEx 转成 XK_plus(0x2b)、
    // 主键盘 - = XK_minus(0x2d)；小键盘 + / - = KP_Add / KP_Subtract。
    // ★ 还要接「主键盘 = / -」与 PageDown / PageUp（0x3d / 0xffbd / 0xff56 / 0xff55）：
    //   原版横向候选窗的翻页键就是 -/=，rime 默认 key_binder 也会把它们映射成
    //   Page_Up/Page_Down。不接的话展开态按 = 会走 librime 自己的分页，和我们 Lua 的
    //   整屏翻页（36 个/页）打架，用户看到的就是「+- 翻页不正常」。
    const bool kPageFwdKey = (keyEvent.keycode == 0x2b ||
                              keyEvent.keycode == 0x3d ||
                              keyEvent.keycode == 0xffbd ||
                              keyEvent.keycode == 0xff56 ||
                              keyEvent.keycode == ibus::Keycode::KP_Add);
    const bool kPageBackKey = (keyEvent.keycode == 0x2d ||
                               keyEvent.keycode == 0xff55 ||
                               keyEvent.keycode == ibus::Keycode::KP_Subtract);
    int delta = 0;
    switch (keyEvent.keycode) {
      case ibus::Keycode::Down:
        delta = kGridColumns;
        break;
      case ibus::Keycode::Up:
        delta = -kGridColumns;
        break;
      case ibus::Keycode::Left:
        delta = -1;
        break;
      case ibus::Keycode::Right:
        delta = 1;
        break;
      default:
        break;
    }
    if ((delta != 0 || kPageFwdKey || kPageBackKey) &&
        RIME_API_AVAILABLE(rime_api, highlight_candidate_on_current_page)) {
      RIME_STRUCT(RimeContext, ctx);
      if (rime_api->get_context(session_id, &ctx)) {
        const int current = ctx.menu.highlighted_candidate_index;
        const int count = ctx.menu.num_candidates;
        rime_api->free_context(&ctx);
        const int target = current + delta;
        // [vmenu-uppage] ★ 翻页后在第 1 行按 ↑ = **翻回上一页**（而不是收起展开栏）。
        //
        // 用户诉求（原话）：「在翻页以后 当用户选择在展开栏的第一行时 注意是在翻页的情况下
        //   按↑键 它是回到上页 而不是关闭展开栏」。
        //
        // 语义：只有「已经翻过页（page > 0）」且「高亮就在第 1 行」时，↑ 才走这条路。
        //   * 光标落点 = **上一页的最后一行**（用户选择的口径）里与当前同一列的那一格，
        //     这样「↑ 一下、↓ 一下」能原样回到原位，手感是连续的；
        //   * 一页放不满时（上一页候选不够 rows 行），就落到上一页实际存在的最后一行；
        //   * page == 0 时**不走这里**：那时 ↑ 仍然是「收起展开栏」（原有行为，用户没要求改）。
        //
        // ★ 必须在下面那条通用翻页路径**之前**判断：否则 -kGridColumns 会先命中
        //   「target >= 0」分支？不会 —— 第 1 行时 target = current - cols < 0 会落到翻页路径，
        //   而那条路径只处理「+ / - 」与 ↓，↑ 会掉到最底下被吞掉（既不翻页也不收起），
        //   正是用户报的那个 bug。所以这里显式处理。
        const bool kUpKey = (keyEvent.keycode == ibus::Keycode::Up);
        if (kUpKey && delta < 0 && current >= 0 && current < kGridColumns) {
          // 高亮在第 1 行 → 看当前页码；page > 0 就翻回上一页。
          int page = -1;
          for (int i = 0; i < kGridPages; ++i) {
            char pname[32];
            snprintf(pname, sizeof(pname), "vmenu_page_%d", i);
            if (rime_api->get_option(session_id, pname)) {
              page = i;
              break;
            }
          }
          if (page > 0) {
            const int col = current % kGridColumns;
            // [vmenu-uppage-list] 行数按当前 v 功能类型取：列表型 3 行，其它（普通打字
            //   展开栏）仍是 4 行。用错行数会让 restore 越界、被夹成同一条，列就丢了。
            // vpick 是 9 列特殊符号面板，不属于 2×3 固定列表。
            const bool fixed_list =
                _VMenuList(rime_api, session_id, grid_input.c_str()) &&
                !_VPickCode(grid_input.c_str());
            const int rows = fixed_list ? kListRows : kGridRows;
            // ★ [翻页回上页] 先把一次性开关 vmenu_uppage 置 true，再把这记 ↑ 交给 rime。
            //
            // 为什么需要这个开关：
            //   Lua 的 menu_processor 收到 ↑ 时的默认语义是「收起展开栏」（见
            //   vmenu_core.lua 的 M.grid_key：expanded + ↑ → grid_set(false) + page_reset(0)）。
            //   于是「先 process_key 再改高亮」会被 lua 抢先收起网格、并把页码清零 ——
            //   实测面板高度 796x190 → 729x49，用户看到的就是「按 ↑ 还是收起了」。
            //   置上这个开关后，lua 改走「翻回上一页且保持展开」，两边语义才一致。
            //   lua 用完会自己清掉；这里再兜底清一次，避免异常路径残留。
            rime_api->set_option(session_id, "vmenu_uppage", True);
            Bool handled = rime_api->process_key(
                session_id, keyEvent.keycode, expand_ibus_modifier(keyEvent.mask));
            // 兜底清开关（正常路径 lua 已清，重复清是幂等的）。
            rime_api->set_option(session_id, "vmenu_uppage", False);
            // 翻页后重新取一次候选总数：新一页可能不足 rows 行。
            int new_count = 0;
            RIME_STRUCT(RimeContext, pctx_up);
            if (rime_api->get_context(session_id, &pctx_up)) {
              new_count = pctx_up.menu.num_candidates;
              rime_api->free_context(&pctx_up);
            }
            // 目标 = 本页最后一行里**同一列**那一格；再夹进 [0, new_count-1]。
            // 上一页不满一整屏时（例如只剩 2 条），夹取会把它压回该页实际最后一条。
            int restore = (rows - 1) * kGridColumns + col;
            if (restore >= new_count) restore = new_count - 1;
            if (restore < 0) restore = 0;
            DLOG(INFO) << "vmenu-grid: up-page (row1 -> prev page), col " << col
                       << ", restore " << restore << " of " << new_count;
            // [vmenu-uppage-trace] 除了 DLOG（需要 debug 日志等级才看得到），
            // 再往用户目录写一行纯文本。这样验收脚本可以直接读文件取证，
            // 不依赖 rime 的 log_level 设置。
            _UpPageTrace(page, col, restore, new_count);
            if (new_count > 0)
              rime_api->highlight_candidate_on_current_page(session_id,
                                                            (size_t)restore);
            _Respond(ipc_id, eat);
            _UpdateUI(ipc_id);
            m_active_session = ipc_id;
            return handled;
          }
        }
        // 普通方向键：目标下标没越界 → 直接移动高亮（候选窗口不变）。
        if (!kPageFwdKey && !kPageBackKey && target >= 0 && target < count) {
          DLOG(INFO) << "vmenu-grid: move highlight " << current << " -> "
                     << target;
          HighlightCandidateOnCurrentPage((size_t)target, ipc_id, eat);
          m_active_session = ipc_id;
          return TRUE;
        }
        // [vmenu-grid] 翻页路径：
        //   * + / -（主键盘与小键盘）→ 把键交给 rime（Lua 处理器用选项整屏翻页，一页 36 个，
        //     于是新一屏的第 1 行 = 原来的第 5 行，「以此类推」逐页继续）；
        //   * 已展开时按 ↓ 且「越界向下」（＝高亮已在最后一行）→ 同样按继续翻页处理。
        // 翻页会重建候选菜单，高亮随之落回第 1 格；这里再把高亮放回**同一列的第一行**
        // （用户要求「光标停在同一纵列的最上方」）：col = 原高亮 % 9 即它所在的列。
        if (kPageFwdKey || kPageBackKey ||
            (delta > 0 && keyEvent.keycode == ibus::Keycode::Down)) {
          const int col = current % kGridColumns;
          DLOG(INFO) << "vmenu-grid: page " << (kPageBackKey ? "back" : "fwd")
                     << ", keep col " << col;
          Bool handled = rime_api->process_key(
              session_id, keyEvent.keycode, expand_ibus_modifier(keyEvent.mask));
          if (col >= 0 && col < kGridColumns)
            rime_api->highlight_candidate_on_current_page(session_id, col);
          _Respond(ipc_id, eat);
          _UpdateUI(ipc_id);
          m_active_session = ipc_id;
          return handled;
        }
      }
    }
  }
  Bool handled = rime_api->process_key(session_id, keyEvent.keycode,
                                       expand_ibus_modifier(keyEvent.mask));
  // vim_mode when keydown only
  if (!handled && !(keyEvent.mask & ibus::Modifier::RELEASE_MASK)) {
    bool isVimBackInCommandMode =
        (keyEvent.keycode == ibus::Keycode::Escape) ||
        ((keyEvent.mask & (1 << 2)) &&
         (keyEvent.keycode == ibus::Keycode::XK_c ||
          keyEvent.keycode == ibus::Keycode::XK_C ||
          keyEvent.keycode == ibus::Keycode::XK_bracketleft));
    if (isVimBackInCommandMode &&
        rime_api->get_option(session_id, "vim_mode") &&
        !rime_api->get_option(session_id, "ascii_mode")) {
      rime_api->set_option(session_id, "ascii_mode", True);
    }
  }
  _Respond(ipc_id, eat);
  _UpdateUI(ipc_id);
  m_active_session = ipc_id;
  return (BOOL)handled;
}

void RimeWithWeaselHandler::CommitComposition(WeaselSessionId ipc_id) {
  DLOG(INFO) << "Commit composition: ipc_id = " << ipc_id;
  if (m_disabled)
    return;
  rime_api->commit_composition(to_session_id(ipc_id));
  _UpdateUI(ipc_id);
  m_active_session = ipc_id;
}

void RimeWithWeaselHandler::ClearComposition(WeaselSessionId ipc_id) {
  DLOG(INFO) << "Clear composition: ipc_id = " << ipc_id;
  if (m_disabled)
    return;
  rime_api->clear_composition(to_session_id(ipc_id));
  _UpdateUI(ipc_id);
  m_active_session = ipc_id;
}

void RimeWithWeaselHandler::SelectCandidateOnCurrentPage(
    size_t index,
    WeaselSessionId ipc_id) {
  DLOG(INFO) << "select candidate on current page, ipc_id = " << ipc_id
             << ", index = " << index;
  if (m_disabled)
    return;
  RimeSessionId session_id = to_session_id(ipc_id);
  // [vpick] 鼠标点到大栏上不许「选中上屏」：0-3 = 切换大栏，4-8 = 占位空格忽略。
  // 否则点一下「常用字符」就把这四个字提交进了文档。
  // ★ 9+ 是小栏格子：必须放行到下面的 select（数字键选格走的也是这条路，
  //   以前 >=4 一律吞掉，导致小栏里按数字键没有任何反应）。
  const char* pick_input = rime_api->get_input(session_id);
  if (_VPickCode(pick_input)) {
    if (index < 9) {
      if (index < 4) {
        // 切大栏 + 把高亮放回该大栏（set_option 重翻译会把高亮重置到第 0 格）。
        // 这里**不**调 _Respond：本路径没有 eat（空 std::function 调用会抛异常），
        // 客户端点完会补一个 VK_SELECT 键，走 ProcessKeyEvent 正常回数据。
        _PickActivate(session_id, (int)index);
        rime_api->highlight_candidate_on_current_page(session_id, index);
      }
      return;  // 4-8 是占位空格：什么都不做，绝不 select 上屏
    }
  }
  rime_api->select_candidate_on_current_page(session_id, index);
}

bool RimeWithWeaselHandler::HighlightCandidateOnCurrentPage(
    size_t index,
    WeaselSessionId ipc_id,
    EatLine eat) {
  DLOG(INFO) << "highlight candidate on current page, ipc_id = " << ipc_id
             << ", index = " << index;
  bool res = rime_api->highlight_candidate_on_current_page(
      to_session_id(ipc_id), index);
  _Respond(ipc_id, eat);
  _UpdateUI(ipc_id);
  return res;
}

bool RimeWithWeaselHandler::ChangePage(bool backward,
                                       WeaselSessionId ipc_id,
                                       EatLine eat) {
  DLOG(INFO) << "change page, ipc_id = " << ipc_id
             << (backward ? "backward" : "foreward");
  bool res = rime_api->change_page(to_session_id(ipc_id), backward);
  _Respond(ipc_id, eat);
  _UpdateUI(ipc_id);
  return res;
}

void RimeWithWeaselHandler::FocusIn(DWORD client_caps, WeaselSessionId ipc_id) {
  DLOG(INFO) << "Focus in: ipc_id = " << ipc_id
             << ", client_caps = " << client_caps;
  if (m_disabled)
    return;
  _UpdateUI(ipc_id);
  m_active_session = ipc_id;
}

void RimeWithWeaselHandler::FocusOut(DWORD param, WeaselSessionId ipc_id) {
  DLOG(INFO) << "Focus out: ipc_id = " << ipc_id;
  if (m_ui)
    m_ui->Hide();
  m_active_session = 0;
}

void RimeWithWeaselHandler::UpdateInputPosition(RECT const& rc,
                                                WeaselSessionId ipc_id) {
  DLOG(INFO) << "Update input position: (" << rc.left << ", " << rc.top
             << "), ipc_id = " << ipc_id
             << ", m_active_session = " << m_active_session;
  if (m_ui)
    m_ui->UpdateInputPosition(rc);
  if (m_disabled)
    return;
  if (m_active_session != ipc_id) {
    _UpdateUI(ipc_id);
    m_active_session = ipc_id;
  }
}

std::string RimeWithWeaselHandler::m_message_type;
std::string RimeWithWeaselHandler::m_message_value;
std::string RimeWithWeaselHandler::m_message_label;
std::string RimeWithWeaselHandler::m_option_name;

void RimeWithWeaselHandler::OnNotify(void* context_object,
                                     uintptr_t session_id,
                                     const char* message_type,
                                     const char* message_value) {
  // may be running in a thread when deploying rime
  RimeWithWeaselHandler* self =
      reinterpret_cast<RimeWithWeaselHandler*>(context_object);
  if (!self || !message_type || !message_value)
    return;
  m_message_type = message_type;
  m_message_value = message_value;
  if (RIME_API_AVAILABLE(rime_api, get_state_label) &&
      !strcmp(message_type, "option")) {
    Bool state = message_value[0] != '!';
    const char* option_name = message_value + !state;
    m_option_name = option_name;
    const char* state_label =
        rime_api->get_state_label(session_id, option_name, state);
    if (state_label) {
      m_message_label = std::string(state_label);
    }
  }
}

void RimeWithWeaselHandler::_ReadClientInfo(WeaselSessionId ipc_id,
                                            LPWSTR buffer) {
  std::string app_name;
  std::string client_type;
  // parse request text
  wbufferstream bs(buffer, WEASEL_IPC_BUFFER_LENGTH);
  std::wstring line;
  while (bs.good()) {
    std::getline(bs, line);
    if (!bs.good())
      break;
    // file ends
    if (line == L".")
      break;
    const std::wstring kClientAppKey = L"session.client_app=";
    if (starts_with(line, kClientAppKey)) {
      std::wstring lwr = line;
      to_lower(lwr);
      app_name = wtou8(lwr.substr(kClientAppKey.length()));
    }
    const std::wstring kClientTypeKey = L"session.client_type=";
    if (starts_with(line, kClientTypeKey)) {
      client_type = wtou8(line.substr(kClientTypeKey.length()));
    }
  }
  SessionStatus& session_status = get_session_status(ipc_id);
  RimeSessionId session_id = session_status.session_id;
  // set app specific options
  if (!app_name.empty()) {
    rime_api->set_property(session_id, "client_app", app_name.c_str());

    auto it = m_app_options.find(app_name);
    if (it != m_app_options.end()) {
      AppOptions& options(m_app_options[it->first]);
      for (const auto& pair : options) {
        DLOG(INFO) << "set app option: " << pair.first << " = " << pair.second;
        rime_api->set_option(session_id, pair.first.c_str(), Bool(pair.second));
      }
    }
  }
  // ime | tsf
  rime_api->set_property(session_id, "client_type", client_type.c_str());
  // inline preedit
  bool inline_preedit =
      session_status.style.inline_preedit && (client_type == "tsf");
  rime_api->set_option(session_id, "inline_preedit", Bool(inline_preedit));
  // show soft cursor on weasel panel but not inline
  rime_api->set_option(session_id, "soft_cursor", Bool(!inline_preedit));
}

void RimeWithWeaselHandler::_GetCandidateInfo(CandidateInfo& cinfo,
                                              RimeContext& ctx) {
  cinfo.candies.resize(ctx.menu.num_candidates);
  cinfo.comments.resize(ctx.menu.num_candidates);
  cinfo.labels.resize(ctx.menu.num_candidates);
  for (int i = 0; i < ctx.menu.num_candidates; ++i) {
    cinfo.candies[i].str = escape_string(u8tow(ctx.menu.candidates[i].text));
    if (ctx.menu.candidates[i].comment) {
      cinfo.comments[i].str =
          escape_string(u8tow(ctx.menu.candidates[i].comment));
    }
    if (RIME_STRUCT_HAS_MEMBER(ctx, ctx.select_labels) && ctx.select_labels) {
      cinfo.labels[i].str = escape_string(u8tow(ctx.select_labels[i]));
    } else if (ctx.menu.select_keys) {
      cinfo.labels[i].str =
          escape_string(std::wstring(1, ctx.menu.select_keys[i]));
    } else {
      cinfo.labels[i].str = std::to_wstring((i + 1) % 10);
    }
  }
  cinfo.highlighted = ctx.menu.highlighted_candidate_index;
  cinfo.currentPage = ctx.menu.page_no;
  cinfo.is_last_page = ctx.menu.is_last_page;
}

void RimeWithWeaselHandler::StartMaintenance() {
  m_session_status_map.clear();
  Finalize();
  _UpdateUI(0);
}

void RimeWithWeaselHandler::EndMaintenance() {
  if (m_disabled) {
    Initialize();
    _UpdateUI(0);
  }
  m_session_status_map.clear();
}

void RimeWithWeaselHandler::SetOption(WeaselSessionId ipc_id,
                                      const std::string& opt,
                                      bool val) {
  // from no-session client, not actual typing session
  if (!ipc_id) {
    if (m_global_ascii_mode && opt == "ascii_mode") {
      for (auto& pair : m_session_status_map)
        rime_api->set_option(to_session_id(pair.first), "ascii_mode", val);
    } else {
      rime_api->set_option(to_session_id(m_active_session), opt.c_str(), val);
    }
  } else {
    rime_api->set_option(to_session_id(ipc_id), opt.c_str(), val);
  }
}

void RimeWithWeaselHandler::OnUpdateUI(std::function<void()> const& cb) {
  _UpdateUICallback = cb;
}

bool RimeWithWeaselHandler::_IsDeployerRunning() {
  HANDLE hMutex = CreateMutex(NULL, TRUE, L"WeaselDeployerMutex");
  bool deployer_detected = hMutex && GetLastError() == ERROR_ALREADY_EXISTS;
  if (hMutex) {
    CloseHandle(hMutex);
  }
  return deployer_detected;
}

void RimeWithWeaselHandler::_UpdateUI(WeaselSessionId ipc_id) {
  // if m_ui nullptr, _UpdateUI meaningless
  if (!m_ui)
    return;

  Status& weasel_status = m_ui->status();
  Context weasel_context;

  RimeSessionId session_id = to_session_id(ipc_id);
  bool is_tsf = _IsSessionTSF(session_id);

  if (ipc_id == 0)
    weasel_status.disabled = m_disabled;

  _GetStatus(weasel_status, ipc_id, weasel_context);

  if (!is_tsf) {
    _GetContext(weasel_context, session_id);
  }

  SessionStatus& session_status = get_session_status(ipc_id);
  if (rime_api->get_option(session_id, "inline_preedit"))
    session_status.style.client_caps |= INLINE_PREEDIT_CAPABLE;
  else
    session_status.style.client_caps &= ~INLINE_PREEDIT_CAPABLE;

  if (weasel_status.composing && !is_tsf) {
    m_ui->Update(weasel_context, weasel_status);
    m_ui->Show();
  } else if (!_ShowMessage(weasel_context, weasel_status) && !is_tsf) {
    m_ui->Hide();
    m_ui->Update(weasel_context, weasel_status);
  }

  _RefreshTrayIcon(session_id, _UpdateUICallback);

  m_message_type.clear();
  m_message_value.clear();
  m_message_label.clear();
  m_option_name.clear();
}

void RimeWithWeaselHandler::_LoadSchemaSpecificSettings(
    WeaselSessionId ipc_id,
    const std::string& schema_id) {
  if (!m_ui)
    return;
  RimeConfig config;
  if (!rime_api->schema_open(schema_id.c_str(), &config))
    return;
  _UpdateShowNotifications(&config);
  m_ui->style() = m_base_style;
  _UpdateUIStyle(&config, m_ui, false);
  SessionStatus& session_status = get_session_status(ipc_id);
  session_status.style = m_ui->style();
  UIStyle& style = session_status.style;
  // load schema color style config
  const int BUF_SIZE = 255;
  char buffer[BUF_SIZE + 1] = {0};
  const auto update_color_scheme = [&]() {
    std::string color_name(buffer);
    RimeConfigIterator preset = {0};
    if (rime_api->config_begin_map(
            &preset, &config, ("preset_color_schemes/" + color_name).c_str())) {
      _UpdateUIStyleColor(&config, style, color_name);
      rime_api->config_end(&preset);
    } else {
      RimeConfig weaselconfig;
      if (rime_api->config_open("weasel", &weaselconfig)) {
        _UpdateUIStyleColor(&weaselconfig, style, color_name);
        rime_api->config_close(&weaselconfig);
      }
    }
  };
  const char* key =
      m_current_dark_mode ? "style/color_scheme_dark" : "style/color_scheme";
  if (rime_api->config_get_string(&config, key, buffer, BUF_SIZE))
    update_color_scheme();
  // load schema icon start
  {
    const auto load_icon = [](RimeConfig& config, const char* key1,
                              const char* key2) {
      const auto user_dir = WeaselUserDataPath();
      const auto shared_dir = WeaselSharedDataPath();
      const int BUF_SIZE = 255;
      char buffer[BUF_SIZE + 1] = {0};
      if (rime_api->config_get_string(&config, key1, buffer, BUF_SIZE) ||
          (key2 != NULL &&
           rime_api->config_get_string(&config, key2, buffer, BUF_SIZE))) {
        auto resource = u8tow(buffer);
        if (fs::is_regular_file(user_dir / resource))
          return (user_dir / resource).wstring();
        else if (fs::is_regular_file(shared_dir / resource))
          return (shared_dir / resource).wstring();
      }
      return std::wstring();
    };
    style.current_zhung_icon =
        load_icon(config, "schema/icon", "schema/zhung_icon");
    style.current_ascii_icon = load_icon(config, "schema/ascii_icon", NULL);
    style.current_full_icon = load_icon(config, "schema/full_icon", NULL);
    style.current_half_icon = load_icon(config, "schema/half_icon", NULL);
  }
  // load schema icon end
  rime_api->config_close(&config);
}

void RimeWithWeaselHandler::_LoadAppInlinePreeditSet(WeaselSessionId ipc_id,
                                                     bool ignore_app_name) {
  SessionStatus& session_status = get_session_status(ipc_id);
  RimeSessionId session_id = session_status.session_id;
  static char _app_name[50];
  rime_api->get_property(session_id, "client_app", _app_name,
                         sizeof(_app_name) - 1);
  std::string app_name(_app_name);
  if (!ignore_app_name && m_last_app_name == app_name)
    return;
  m_last_app_name = app_name;
  bool inline_preedit = session_status.style.inline_preedit;
  bool found = false;
  if (!app_name.empty()) {
    auto it = m_app_options.find(app_name);
    if (it != m_app_options.end()) {
      AppOptions& options(m_app_options[it->first]);
      for (const auto& pair : options) {
        if (pair.first == "inline_preedit") {
          rime_api->set_option(session_id, pair.first.c_str(),
                               Bool(pair.second));
          session_status.style.inline_preedit = Bool(pair.second);
          found = true;
          break;
        }
      }
    }
  }
  if (!found) {
    session_status.style.inline_preedit = m_base_style.inline_preedit;
    // load from schema.
    RIME_STRUCT(RimeStatus, status);
    if (rime_api->get_status(session_id, &status)) {
      std::string schema_id = status.schema_id;
      RimeConfig config;
      if (rime_api->schema_open(schema_id.c_str(), &config)) {
        Bool value = False;
        if (rime_api->config_get_bool(&config, "style/inline_preedit",
                                      &value)) {
          session_status.style.inline_preedit = value;
        }
        rime_api->config_close(&config);
      }
      rime_api->free_status(&status);
    }
  }
  if (session_status.style.inline_preedit != inline_preedit)
    _UpdateInlinePreeditStatus(ipc_id);
}

bool RimeWithWeaselHandler::_ShowMessage(Context& ctx, Status& status) {
  // show as auxiliary string
  std::wstring& tips(ctx.aux.str);
  bool show_icon = false;
  if (m_message_type == "deploy") {
    if (m_message_value == "start")
      if (GetThreadUILanguage() == MAKELANGID(LANG_ENGLISH, SUBLANG_ENGLISH_US))
        tips = L"Deploying RIME";
      else
        tips = L"正在部署 RIME";
    else if (m_message_value == "success")
      if (GetThreadUILanguage() == MAKELANGID(LANG_ENGLISH, SUBLANG_ENGLISH_US))
        tips = L"Deployed";
      else
        tips = L"部署完成";
    else if (m_message_value == "failure") {
      if (GetThreadUILanguage() ==
          MAKELANGID(LANG_CHINESE, SUBLANG_CHINESE_TRADITIONAL))
        tips = L"有錯誤，請查看日誌 %TEMP%\\rime.weasel\\rime.weasel.*.INFO";
      else if (GetThreadUILanguage() ==
               MAKELANGID(LANG_CHINESE, SUBLANG_CHINESE_SIMPLIFIED))
        tips = L"有错误，请查看日志 %TEMP%\\rime.weasel\\rime.weasel.*.INFO";
      else
        tips =
            L"There is an error, please check the logs "
            L"%TEMP%\\rime.weasel\\rime.weasel.*.INFO";
    }
  } else if (m_message_type == "schema") {
    tips = /*L"【" + */ status.schema_name /* + L"】"*/;
  } else if (m_message_type == "option") {
    status.type = SCHEMA;
    if (m_message_value == "!ascii_mode") {
      show_icon = true;
    } else if (m_message_value == "ascii_mode") {
      show_icon = true;
    } else
      tips = u8tow(m_message_label);

    if (m_message_value == "full_shape" || m_message_value == "!full_shape")
      status.type = FULL_SHAPE;
  }
  if (tips.empty() && !show_icon)
    return m_ui->IsCountingDown();
  auto foption = m_show_notifications.find(m_option_name);
  auto falways = m_show_notifications.find("always");
  if ((!add_session && (foption != m_show_notifications.end() ||
                        falways != m_show_notifications.end())) ||
      m_message_type == "deploy") {
    m_ui->Update(ctx, status);
    if (m_show_notifications_time)
      m_ui->ShowWithTimeout(m_show_notifications_time);
    return true;
  } else {
    return m_ui->IsCountingDown();
  }
}
inline std::string _GetLabelText(const std::vector<Text>& labels,
                                 int id,
                                 const wchar_t* format) {
  wchar_t buffer[128];
  swprintf_s<128>(buffer, format, labels.at(id).str.c_str());
  return wtou8(std::wstring(buffer));
}

// v 功能菜单（vmenu_*.lua）：输入框里那一串其实是**内部编码**
// （vclip = 剪贴板 / vqi = 快捷输入 / vfav = 常用语 / vset* = 设置 / v = 功能菜单）。
// 用户明确要求「不要显示这个内部代码」，所以这里按前缀换成中文名再交给前端显示。
//   * 首字母不是 v 的一律不动：普通拼音、以及 cC / rq / sj / U / N / R 这些前缀照旧显示；
//   * 原符号模式（vraw_mode，菜单第 5 项）下也完全不动 —— 那时 v 开头是用户自己敲的符号编码。
// 注意：文案一律写成宽字符的 \u 转义再由 wtou8 转 UTF-8。本工程没有 /utf-8 编译开关，
//       直接写中文窄字符串会被按系统代码页（GBK）处理，出来的字节不是 UTF-8，前端就是乱码。
inline bool _VMenuLabel(RimeApi* api,
                        RimeSessionId session_id,
                        const char* code,
                        std::string* label) {
  if (!api || !code || code[0] != 'v')
    return false;
  if (api->get_option(session_id, "vraw_mode"))
    return false;
  std::string input(code);
  if (input.size() == 1) {
    *label = wtou8(L"\u529f\u80fd\u83dc\u5355");  // 功能菜单
    return true;
  }
  if (input.compare(0, 5, "vclip") == 0) {
    *label = wtou8(L"\u526a\u8d34\u677f");  // 剪贴板
    return true;
  }
  if (input.compare(0, 4, "vqi") == 0) {
    *label = wtou8(L"\u5feb\u6377\u8f93\u5165");  // 快捷输入
    return true;
  }
  if (input.compare(0, 4, "vfav") == 0) {
    *label = wtou8(L"\u5e38\u7528\u8bed");  // 常用语
    return true;
  }
  // 符号面板（v 菜单第 5 项；原来的「原符号」顺延为第 6 项）。
  // 文本用码点构造，避免源码里出现反斜杠转义 / 依赖代码页的中文字面量。
  if (input.compare(0, 5, "vpick") == 0) {
    *label = wtou8(std::wstring({(wchar_t)0x7B26, (wchar_t)0x53F7,
                                 (wchar_t)0x9762, (wchar_t)0x677F}));
    return true;
  }
  if (input.compare(0, 4, "vset") == 0) {
    *label = wtou8(L"\u8bbe\u7f6e");  // 设置
    return true;
  }
  return false;
}

// [vmenu-grid] 「当前是不是 v 功能菜单」——与 _VMenuLabel 共用同一套前缀判断，
// 用来决定候选窗**一行几列**：v 功能菜单 4 列（用户要求「一行显示 4 个」），普通打字 9 列。
// 原符号模式（vraw_mode）不算：那里 v 开头是用户自己敲的符号编码，仍按 9 列。
inline bool _IsVMenu(RimeApi* api, RimeSessionId session_id, const char* code) {
  std::string label;
  return _VMenuLabel(api, session_id, code, &label);
}

// [vmenu-grid] 「这次是不是列表型 v 功能」（剪贴板 / 常用语 / 管理列表）。
// 列表：一屏 6 个（2 列 × 3 行），序号按「行 × 列」算，数字键由服务端按二维接管。
// 静态菜单（v 主菜单 5 项、v3 快捷输入 7 项）：全部一次显示，序号按 1..N 顺序算，
// 数字键永远交给 Lua 顺序选。
// 前缀表必须与 src/lua/vmenu_core.lua 的 mode_of / parse_sub 一致：
//   vclip… → clip、vfav… → fav、vsetc…/vsetf… → set 里的列表。
// ★ 刻意不用 option 传递：试过在 lua_filter 里 ctx:set_option("vmenu_list", …)，
//   服务端当场**栈溢出崩溃**（0xc00000fd，事件日志 ntdll.dll / 0xc00000fd）——
//   set_option 会通知引擎重跑候选管线，管线再进过滤器、再 set_option…无限递归。
inline bool _VMenuListCode(const char* code) {
  if (!code) return false;
  const std::string s(code);
  if (s.compare(0, 5, "vclip") == 0) return true;
  // [vpick] 符号面板也算「列表型」：数字键按二维选、方向键网格导航都由服务端接管。
  //   列数 / 序号算法在 _VMenuCols / _VMenuSeqMode 里再单独覆盖（9 列、大栏行序号 1-4）。
  if (s.compare(0, 5, "vpick") == 0) return true;
  if (s.compare(0, 4, "vfav") == 0) return true;
  if (s.size() >= 5 && s.compare(0, 4, "vset") == 0 &&
      (s[4] == 'c' || s[4] == 'f'))
    return true;
  return false;
}

// [vmenu-grid] 一行几列（9 = 普通打字 / 2 = 剪贴板·常用语 / 4 = 其它 v 功能菜单）。
// [一行 2 个] 用户要求：剪贴板与常用语「一行 2 个、默认显示 3 行、默认就是展开态」，
//   所以**列表型** v 功能一律 2 列；其余 v 功能菜单仍是 4 列（「v 的功能一行显示 4 个」）。
// 前端 WeaselUI/HorizontalLayout.cpp 按这个列号钉格子，收起态那一行与展开后每一行的
// 同一列逐像素对齐；万一某个格子实在太宽（很长的剪贴板条目），前端会少画 1 格
// （2 → 1），但仍保住列位置，不重排候选。
//
// [vmenu-cfg] 现在「普通打字」的列数由 grid-settings.txt 决定（收起 / 展开两套）：
//   用户诉求（原话）：「展开栏只显示 6 个，并且在 v1 的控制面板可以设置展开栏的
//   每行数量 和 没有展开栏的默认的每行数量」。
//   * 收起（vmenu_grid 未开）→ cfg.collapsed（默认 9）
//   * 展开（vmenu_grid 已开）→ cfg.expanded（默认 9）
//   v 功能自己的列数（4 / 2 / 9）保持不变：那些是 v 菜单的专用排版，
//   而且剪贴板 / 常用语「2 列 = 固定格宽」与 v3 的 2 列都依赖它，不能跟着用户值走。
// ★ vmenu_grid 是会话级 option，必须用 get_option 读（不能靠参数传）。
inline int _VMenuCols(RimeApi* api, RimeSessionId session_id, const char* code) {
  if (!_IsVMenu(api, session_id, code)) {
    const GridCfg& cfg = _GridCfgCached();
    // vmenu_grid = 「展开栏已打开」。它是会话级 option，由 lua 的 core.grid_set 维护；
    // get_option 对不存在的 option 返回 False（不会崩），所以这里直接读。
    const bool opened = (api != nullptr) && api->get_option(session_id, "vmenu_grid");
    return opened ? cfg.expanded : cfg.collapsed;
  }
  // [快捷输入 2 列] 用户要求：v3 快捷输入的候选显示也改成「和剪贴板相似的 2 列格式」。
  //   注意 vqi **不是列表型**：它仍是静态菜单 —— 序号顺序 1..N（ctx.grid_2d = 0），
  //   数字键仍由 menu_processor.lua 按序号选，服务端不接管。
  //   这里只把列数从 4 改成 2：客户端 HorizontalLayout 的 fixed_cells 只看 grid_cols == 2，
  //   所以 v3 自动获得「等宽固定格 + 屏宽 20% + 超长 … 截断」的同一套排版。
  {
    const std::string s(code ? code : "");
    // [vpick] 符号面板：最上面一栏（大栏）整行 4 个 + 5 个占位，小栏 4 行 × 9 列，
    //   整窗按 9 列换行 —— 大栏正好独占第 1 行。
    if (s.compare(0, 5, "vpick") == 0) return 9;
    if (s.compare(0, 3, "vqi") == 0) return 2;
  }
  return _VMenuListCode(code) ? 2 : 4;
}

inline bool _VMenuList(RimeApi* api, RimeSessionId session_id, const char* code) {
  return _IsVMenu(api, session_id, code) && _VMenuListCode(code);
}

// [vmenu-grid] 序号算法（前端 ctx.grid_2d）：
//   0 = 顺序 1..N（静态 v 菜单：v 主菜单 5 项、v3 快捷输入 7 项，数字键由 Lua 顺序选）；
//   1 = 按「行 × 列」编号（列表型 v 功能 + 普通打字的展开网格）；
//   2 = **不画序号**（[vmenu-nolabel] 纯数字编码输入，且候选只剩一条「常用语预览」）。
//       第二十一轮用户诉求（原话）：「把第一个 131 删除 只留下第二个（这个也最好不要显示
//       序号）」—— 那条候选是「回车才上屏」的预览，序号「1」既没用又占地方。
//       只在「候选恰好 1 条」时启用：万一是别的候选（比如数字真的出了候选），
//       序号还得照画，否则数字键选词就没有对照了。
inline int _VMenuSeqMode(RimeApi* api,
                         RimeSessionId session_id,
                         const char* code,
                         int candidates) {
  if (_IsVMenu(api, session_id, code)) {
    // [vpick] 符号面板序号 = 3：与 1 同样「按行 × 列」画，但第 1 行（大栏）
    //   只给前 4 格编号（5-9 是占位空格，画了就是一排没用的数字）。
    if (_VPickCode(code)) return 3;
    return _VMenuListCode(code) ? 1 : 0;
  }
  if (code && *code && candidates == 1) {
    const std::string s(code);
    if (s.find_first_not_of("0123456789") == std::string::npos)
      return 2;
  }
  return 1;
}

bool RimeWithWeaselHandler::_Respond(WeaselSessionId ipc_id, EatLine eat) {
  std::set<std::string> actions;
  std::list<std::string> messages;

  SessionStatus& session_status = get_session_status(ipc_id);
  RimeSessionId session_id = session_status.session_id;
  // [vpick] 刚进符号面板的那一帧：把高亮钉回当前大栏（「首先是大栏」）。
  // 必须在下面 get_context 之前做，否则发出去的就是旧的高亮格。
  _PickEntryPin(session_id);
  RIME_STRUCT(RimeCommit, commit);
  if (rime_api->get_commit(session_id, &commit)) {
    actions.insert("commit");

    std::string commit_text = escape_string<char>(commit.text);
    messages.push_back(std::string("commit=") + commit_text + '\n');
    rime_api->free_commit(&commit);
  }

  bool is_composing = false;
  RIME_STRUCT(RimeStatus, status);
  if (rime_api->get_status(session_id, &status)) {
    is_composing = !!status.is_composing;
    actions.insert("status");
    messages.push_back(std::string("status.ascii_mode=") +
                       std::to_string(status.is_ascii_mode) + '\n');
    messages.push_back(std::string("status.composing=") +
                       std::to_string(status.is_composing) + '\n');
    messages.push_back(std::string("status.disabled=") +
                       std::to_string(status.is_disabled) + '\n');
    messages.push_back(std::string("status.full_shape=") +
                       std::to_string(status.is_full_shape) + '\n');
    messages.push_back(std::string("status.schema_id=") +
                       std::string(status.schema_id) + '\n');
    if (m_global_ascii_mode &&
        (session_status.status.is_ascii_mode != status.is_ascii_mode)) {
      for (auto& pair : m_session_status_map) {
        if (pair.first != ipc_id)
          rime_api->set_option(to_session_id(pair.first), "ascii_mode",
                               !!status.is_ascii_mode);
      }
    }
    session_status.status = status;
    rime_api->free_status(&status);
  }

  RIME_STRUCT(RimeContext, ctx);
  if (rime_api->get_context(session_id, &ctx)) {
    if (is_composing) {
      actions.insert("ctx");
      switch (session_status.style.preedit_type) {
        case UIStyle::PREVIEW:
          if (ctx.commit_text_preview != NULL) {
            std::string first = ctx.commit_text_preview;
            messages.push_back(std::string("ctx.preedit=") +
                               escape_string<char>(first) + '\n');
            messages.push_back(
                std::string("ctx.preedit.cursor=") +
                std::to_string(utf8towcslen(first.c_str(), 0)) + ',' +
                std::to_string(utf8towcslen(first.c_str(), (int)first.size())) +
                ',' +
                std::to_string(utf8towcslen(first.c_str(), (int)first.size())) +
                '\n');
            break;
          }
          // no preview, fall back to composition
        case UIStyle::COMPOSITION: {
          std::string vlabel;
          if (_VMenuLabel(rime_api, session_id, ctx.composition.preedit,
                          &vlabel)) {
            // v 功能菜单：不把内部编码显示出来，只显示它代表的功能名（无高亮范围）
            messages.push_back(std::string("ctx.preedit=") +
                               escape_string<char>(vlabel.c_str()) + '\n');
            int vlen = utf8towcslen(vlabel.c_str(), (int)vlabel.size());
            messages.push_back(std::string("ctx.preedit.cursor=") +
                               std::to_string(vlen) + ',' +
                               std::to_string(vlen) + ',' +
                               std::to_string(vlen) + '\n');
            break;
          }
          messages.push_back(std::string("ctx.preedit=") +
                             escape_string<char>(ctx.composition.preedit) +
                             '\n');
          if (ctx.composition.sel_start <= ctx.composition.sel_end) {
            messages.push_back(
                std::string("ctx.preedit.cursor=") +
                std::to_string(utf8towcslen(ctx.composition.preedit,
                                            ctx.composition.sel_start)) +
                ',' +
                std::to_string(utf8towcslen(ctx.composition.preedit,
                                            ctx.composition.sel_end)) +
                ',' +
                std::to_string(utf8towcslen(ctx.composition.preedit,
                                            ctx.composition.cursor_pos)) +
                '\n');
          }
          break;
        }
        case UIStyle::PREVIEW_ALL: {
          CandidateInfo cinfo;
          _GetCandidateInfo(cinfo, ctx);
          std::string vlabel;
          const bool v_menu = _VMenuLabel(rime_api, session_id,
                                          ctx.composition.preedit, &vlabel);
          std::string preedit_show =
              v_menu ? vlabel : std::string(ctx.composition.preedit);
          std::string topush = std::string("ctx.preedit=") +
                               escape_string<char>(preedit_show.c_str()) +
                               "  [";
          for (auto i = 0; i < ctx.menu.num_candidates; i++) {
            std::string label =
                session_status.style.label_font_point > 0
                    ? _GetLabelText(
                          cinfo.labels, i,
                          session_status.style.label_text_format.c_str())
                    : "";
            std::string comment = session_status.style.comment_font_point > 0
                                      ? wtou8(cinfo.comments.at(i).str)
                                      : "";
            std::string mark_text = session_status.style.mark_text.empty()
                                        ? "*"
                                        : wtou8(session_status.style.mark_text);
            std::string prefix =
                (i != ctx.menu.highlighted_candidate_index) ? "" : mark_text;
            topush += " " + prefix + escape_string(label) +
                      escape_string<char>(ctx.menu.candidates[i].text) + " " +
                      escape_string(comment);
          }
          messages.push_back(topush + " ]\n");
          if (!v_menu && ctx.composition.sel_start <= ctx.composition.sel_end) {
            messages.push_back(
                std::string("ctx.preedit.cursor=") +
                std::to_string(utf8towcslen(ctx.composition.preedit,
                                            ctx.composition.sel_start)) +
                ',' +
                std::to_string(utf8towcslen(ctx.composition.preedit,
                                            ctx.composition.sel_end)) +
                ',' +
                std::to_string(utf8towcslen(ctx.composition.preedit,
                                            ctx.composition.cursor_pos)) +
                '\n');
          }
          break;
        }
      }
    }
    if (ctx.menu.num_candidates) {
      CandidateInfo cinfo;
      std::wstringstream ss;
      boost::archive::text_woarchive oa(ss);
      _GetCandidateInfo(cinfo, ctx);

      oa << cinfo;

      messages.push_back(std::string("ctx.cand=") + wtou8(ss.str()) + '\n');
    }
    // [vmenu-grid] 候选窗「一行几列」下发前端：v 功能菜单 4（一行 4 个），普通打字 9。
    // 前端 HorizontalLayout 用它当换行 / 序号步长，收起态那一行与展开后每一行用同一套格子；
    // 一行放不下时前端会「少放 1-3 个」（见 HorizontalLayout.cpp 的 visible_cols_）。
    // 每次都发（不是只在变化时发），这样从 v 列表回到普通打字不会留下旧的列数。
    // preedit 先拷贝：下面两次判断内部还会调 rime（get_option），
    // 不能一直拿着 RimeContext 里的裸指针。
    const std::string preedit_str =
        ctx.composition.preedit ? ctx.composition.preedit : "";
    messages.push_back(
        std::string("ctx.grid_cols=") +
        std::to_string(_VMenuCols(rime_api, session_id, preedit_str.c_str())) +
        '\n');
    // [vmenu-grid] 序号算法：1 = 按「行 × 列」（列表 / 普通打字的展开网格），
    // 0 = 按 1..N 顺序（静态 v 菜单：v 主菜单 5 项、v3 快捷输入 7 项，数字键就是顺序选），
    // 2 = 不画序号（纯数字编码输入且只剩 1 条候选，见 _VMenuSeqMode）。
    // 同样每次都发；老服务端不发这一行时前端默认 1 = 原来的行为。
    messages.push_back(
        std::string("ctx.grid_2d=") +
        std::to_string(_VMenuSeqMode(rime_api, session_id,
                                     preedit_str.c_str(),
                                     ctx.menu.num_candidates)) +
        '\n');
    // [vpick] 符号面板的大类个数（当前恒为 4）。只有真在符号面板时才发，
    //   别的时候发 0 = 「不是符号面板」。
    //   为什么要发：前端要用它算「第 1 行整组居中」。前端原来靠候选宽度猜哪几个是
    //   补齐用的占位空格，但格宽由当页最宽候选决定 —— 颜文字那一栏格宽涨到 191 时，
    //   第一个表情（99px）会被猜成大类，整组宽度多带一格、大类行右偏 36px（实测）。
    //   服务端本来就知道是 4 个（vpick_cat0..3），直接发过去最可靠。
    messages.push_back(
        std::string("ctx.pick_cats=") +
        std::to_string(_VPickCode(preedit_str.c_str()) ? kPickTabs : 0) +
        '\n');
    rime_api->free_context(&ctx);
  }

  // configuration information
  actions.insert("config");
  messages.push_back(std::string("config.inline_preedit=") +
                     std::to_string((int)session_status.style.inline_preedit) +
                     '\n');

  // style
  if (!session_status.__synced) {
    std::wstringstream ss;
    boost::archive::text_woarchive oa(ss);
    oa << session_status.style;

    actions.insert("style");
    messages.push_back(std::string("style=") + wtou8(ss.str().c_str()) + '\n');
    session_status.__synced = true;
  }

  // summarize

  if (actions.empty()) {
    messages.insert(messages.begin(), std::string("action=noop\n"));
  } else {
    std::string actionList(join(actions, ","));
    messages.insert(messages.begin(),
                    std::string("action=") + actionList + '\n');
  }

  messages.push_back(std::string(".\n"));

  return std::all_of(messages.begin(), messages.end(),
                     [&eat](std::string& msg) {
                       auto wmsg = u8tow(msg);
                       return eat(wmsg);
                     });
}

static inline COLORREF blend_colors(COLORREF fcolor, COLORREF bcolor) {
  // 提取各通道的值
  BYTE fA = (fcolor >> 24) & 0xFF;  // 获取前景的 alpha 通道
  BYTE fB = (fcolor >> 16) & 0xFF;  // 获取前景的 blue 通道
  BYTE fG = (fcolor >> 8) & 0xFF;   // 获取前景的 green 通道
  BYTE fR = fcolor & 0xFF;          // 获取前景的 red 通道
  BYTE bA = (bcolor >> 24) & 0xFF;  // 获取背景的 alpha 通道
  BYTE bB = (bcolor >> 16) & 0xFF;  // 获取背景的 blue 通道
  BYTE bG = (bcolor >> 8) & 0xFF;   // 获取背景的 green 通道
  BYTE bR = bcolor & 0xFF;          // 获取背景的 red 通道
  // 将 alpha 通道转换为 [0, 1] 的浮动值
  float fAlpha = fA / 255.0f;
  float bAlpha = bA / 255.0f;
  // 计算每个通道的加权平均值
  float retAlpha = fAlpha + (1 - fAlpha) * bAlpha;
  // 混合红、绿、蓝通道
  BYTE retR = (BYTE)((fR * fAlpha + bR * bAlpha * (1 - fAlpha)) / retAlpha);
  BYTE retG = (BYTE)((fG * fAlpha + bG * bAlpha * (1 - fAlpha)) / retAlpha);
  BYTE retB = (BYTE)((fB * fAlpha + bB * bAlpha * (1 - fAlpha)) / retAlpha);
  // 返回合成后的颜色
  return (BYTE)(retAlpha * 255) << 24 | retB << 16 | retG << 8 | retR;
}
// parse color value, with fallback value
static Bool _RimeGetColor(RimeConfig* config,
                          const std::string key,
                          int& value,
                          const ColorFormat& fmt,
                          const unsigned int& fallback) {
  RimeApi* rime_api = rime_get_api();
  char color[256] = {0};
  if (!rime_api->config_get_string(config, key.c_str(), color, 256)) {
    value = fallback;
    return False;
  }
  const auto color_str = std::string(color);
  const auto make_opaque = [&](int& value) {
    value = (fmt != COLOR_RGBA) ? (value | 0xff000000)
                                : ((value << 8) | 0x000000ff);
  };
  const auto ConvertColorToAbgr = [](int color, ColorFormat fmt = COLOR_ABGR) {
    if (fmt == COLOR_ABGR)
      return color & 0xffffffff;
    else if (fmt == COLOR_ARGB)
      return ARGB2ABGR(color) & 0xffffffff;
    else
      return RGBA2ABGR(color) & 0xffffffff;
  };
  if (std::regex_match(color_str, HEX_REGEX)) {
    auto tmp = std::regex_replace(color_str, TRIMHEAD_REGEX, "").substr(0, 8);
    switch (tmp.length()) {
      case 6:  // color code without alpha, xxyyzz add alpha ff
        value = std::stoul(tmp, 0, 16);
        make_opaque(value);
        break;
      case 3:  // color hex code xyz => xxyyzz and alpha ff
        tmp = std::string(2, tmp[0]) + std::string(2, tmp[1]) +
              std::string(2, tmp[2]);
        value = std::stoul(tmp, 0, 16);
        make_opaque(value);
        break;
      case 4:  // color hex code vxyz => vvxxyyzz
        tmp = std::string(2, tmp[0]) + std::string(2, tmp[1]) +
              std::string(2, tmp[2]) + std::string(2, tmp[3]);
        value = std::stoul(tmp, 0, 16);
        break;
      case 7:
      case 8:  // color code with alpha
        value = std::stoul(tmp, 0, 16);
        break;
      default:  // invalid length
        value = fallback;
        return False;
    }
  } else {
    int tmp = 0;
    if (!rime_api->config_get_int(config, key.c_str(), &tmp)) {
      value = fallback;
      return False;
    } else
      value = tmp;
    make_opaque(value);
  }
  value = ConvertColorToAbgr(value, fmt);
  return True;
}
// parset bool type configuration to T type value trueValue / falseValue
template <typename T>
void _RimeGetBool(RimeConfig* config,
                  const char* key,
                  bool cond,
                  T& value,
                  const T& trueValue = true,
                  const T& falseValue = false) {
  RimeApi* rime_api = rime_get_api();
  Bool tempb = False;
  if (rime_api->config_get_bool(config, key, &tempb) || cond)
    value = (!!tempb) ? trueValue : falseValue;
}
//	parse string option to T type value, with fallback
template <typename T>
void _RimeParseStringOptWithFallback(RimeConfig* config,
                                     const std::string& key,
                                     T& value,
                                     const std::map<std::string, T>& amap,
                                     const T& fallback) {
  RimeApi* rime_api = rime_get_api();
  char str_buff[256] = {0};
  if (rime_api->config_get_string(config, key.c_str(), str_buff, 255)) {
    auto it = amap.find(std::string(str_buff));
    value = (it != amap.end()) ? it->second : fallback;
  } else
    value = fallback;
}

template <typename T>
void _RimeGetIntStr(RimeConfig* config,
                    const char* key,
                    T& value,
                    const char* fb_key = nullptr,
                    const void* fb_value = nullptr,
                    const std::function<void(T&)>& func = nullptr) {
  RimeApi* rime_api = rime_get_api();
  if constexpr (std::is_same<T, int>::value) {
    if (!rime_api->config_get_int(config, key, &value) && fb_key != 0)
      rime_api->config_get_int(config, fb_key, &value);
  } else if constexpr (std::is_same<T, std::wstring>::value) {
    const int BUF_SIZE = 2047;
    char buffer[BUF_SIZE + 1] = {0};
    if (rime_api->config_get_string(config, key, buffer, BUF_SIZE) ||
        rime_api->config_get_string(config, fb_key, buffer, BUF_SIZE)) {
      value = u8tow(buffer);
    } else if (fb_value) {
      value = *(T*)fb_value;
    }
  }
  if (func)
    func(value);
}

void RimeWithWeaselHandler::_UpdateShowNotifications(RimeConfig* config,
                                                     bool initialize) {
  Bool show_notifications = true;
  RimeConfigIterator iter;
  if (initialize)
    m_show_notifications_base.clear();
  m_show_notifications.clear();

  if (rime_api->config_get_bool(config, "show_notifications",
                                &show_notifications)) {
    // config read as bool, for gloal all on or off
    if (show_notifications)
      m_show_notifications["always"] = true;
    if (initialize)
      m_show_notifications_base = m_show_notifications;
  } else if (rime_api->config_begin_list(&iter, config, "show_notifications")) {
    // config read as list, list item should be option name in schema
    // or key word 'schema' for schema switching tip
    while (rime_api->config_next(&iter)) {
      char buffer[256] = {0};
      if (rime_api->config_get_string(config, iter.path, buffer, 256))
        m_show_notifications[std::string(buffer)] = true;
    }
    if (initialize)
      m_show_notifications_base = m_show_notifications;
    rime_api->config_end(&iter);
  } else {
    // not configured, or incorrect type
    if (initialize)
      m_show_notifications_base["always"] = true;
    m_show_notifications = m_show_notifications_base;
  }
}

// update ui's style parameters, ui has been check before referenced
static void _UpdateUIStyle(RimeConfig* config, UI* ui, bool initialize) {
  UIStyle& style(ui->style());
  const std::function<void(std::wstring&)> rmspace = [](std::wstring& str) {
    str = std::regex_replace(str, std::wregex(L"\\s*(,|:|^|$)\\s*"), L"$1");
  };
  const std::function<void(int&)> _abs = [](int& value) { value = abs(value); };
  // get font faces
  _RimeGetIntStr(config, "style/font_face", style.font_face, 0, 0, rmspace);
  std::wstring* const pFallbackFontFace = initialize ? &style.font_face : NULL;
  _RimeGetIntStr(config, "style/label_font_face", style.label_font_face, 0,
                 pFallbackFontFace, rmspace);
  _RimeGetIntStr(config, "style/comment_font_face", style.comment_font_face, 0,
                 pFallbackFontFace, rmspace);
  // able to set label font/comment font empty, force fallback to font face.
  if (style.label_font_face.empty())
    style.label_font_face = style.font_face;
  if (style.comment_font_face.empty())
    style.comment_font_face = style.font_face;
  // get font points
  _RimeGetIntStr(config, "style/font_point", style.font_point);
  if (style.font_point <= 0)
    style.font_point = 12;
  _RimeGetIntStr(config, "style/label_font_point", style.label_font_point,
                 "style/font_point", 0, _abs);
  _RimeGetIntStr(config, "style/comment_font_point", style.comment_font_point,
                 "style/font_point", 0, _abs);
  _RimeGetIntStr(config, "style/candidate_abbreviate_length",
                 style.candidate_abbreviate_length, 0, 0, _abs);
  _RimeGetBool(config, "style/inline_preedit", initialize,
               style.inline_preedit);
  _RimeGetBool(config, "style/vertical_auto_reverse", initialize,
               style.vertical_auto_reverse);
  const std::map<std::string, UIStyle::PreeditType> _preeditMap = {
      {std::string("composition"), UIStyle::COMPOSITION},
      {std::string("preview"), UIStyle::PREVIEW},
      {std::string("preview_all"), UIStyle::PREVIEW_ALL}};
  _RimeParseStringOptWithFallback(config, "style/preedit_type",
                                  style.preedit_type, _preeditMap,
                                  style.preedit_type);
  const std::map<std::string, UIStyle::AntiAliasMode> _aliasModeMap = {
      {std::string("force_dword"), UIStyle::FORCE_DWORD},
      {std::string("cleartype"), UIStyle::CLEARTYPE},
      {std::string("grayscale"), UIStyle::GRAYSCALE},
      {std::string("aliased"), UIStyle::ALIASED},
      {std::string("default"), UIStyle::DEFAULT}};
  _RimeParseStringOptWithFallback(config, "style/antialias_mode",
                                  style.antialias_mode, _aliasModeMap,
                                  style.antialias_mode);
  const std::map<std::string, UIStyle::HoverType> _hoverTypeMap = {
      {std::string("none"), UIStyle::HoverType::NONE},
      {std::string("semi_hilite"), UIStyle::HoverType::SEMI_HILITE},
      {std::string("hilite"), UIStyle::HoverType::HILITE}};
  _RimeParseStringOptWithFallback(config, "style/hover_type", style.hover_type,
                                  _hoverTypeMap, style.hover_type);
  const std::map<std::string, UIStyle::LayoutAlignType> _alignType = {
      {std::string("top"), UIStyle::ALIGN_TOP},
      {std::string("center"), UIStyle::ALIGN_CENTER},
      {std::string("bottom"), UIStyle::ALIGN_BOTTOM}};
  _RimeParseStringOptWithFallback(config, "style/layout/align_type",
                                  style.align_type, _alignType,
                                  style.align_type);
  _RimeGetBool(config, "style/display_tray_icon", initialize,
               style.display_tray_icon);
  _RimeGetBool(config, "style/ascii_tip_follow_cursor", initialize,
               style.ascii_tip_follow_cursor);
  _RimeGetBool(config, "style/horizontal", initialize, style.layout_type,
               UIStyle::LAYOUT_HORIZONTAL, UIStyle::LAYOUT_VERTICAL);
  _RimeGetBool(config, "style/paging_on_scroll", initialize,
               style.paging_on_scroll);
  _RimeGetBool(config, "style/click_to_capture", initialize,
               style.click_to_capture, true, false);
  _RimeGetBool(config, "style/fullscreen", false, style.layout_type,
               ((style.layout_type == UIStyle::LAYOUT_HORIZONTAL)
                    ? UIStyle::LAYOUT_HORIZONTAL_FULLSCREEN
                    : UIStyle::LAYOUT_VERTICAL_FULLSCREEN),
               style.layout_type);
  _RimeGetBool(config, "style/vertical_text", false, style.layout_type,
               UIStyle::LAYOUT_VERTICAL_TEXT, style.layout_type);
  _RimeGetBool(config, "style/vertical_text_left_to_right", false,
               style.vertical_text_left_to_right);
  _RimeGetBool(config, "style/vertical_text_with_wrap", false,
               style.vertical_text_with_wrap);
  const std::map<std::string, bool> _text_orientation = {
      {std::string("horizontal"), false}, {std::string("vertical"), true}};
  bool _text_orientation_bool = false;
  _RimeParseStringOptWithFallback(config, "style/text_orientation",
                                  _text_orientation_bool, _text_orientation,
                                  _text_orientation_bool);
  if (_text_orientation_bool)
    style.layout_type = UIStyle::LAYOUT_VERTICAL_TEXT;
  _RimeGetIntStr(config, "style/label_format", style.label_text_format);
  _RimeGetIntStr(config, "style/mark_text", style.mark_text);
  _RimeGetIntStr(config, "style/layout/baseline", style.baseline, 0, 0, _abs);
  _RimeGetIntStr(config, "style/layout/linespacing", style.linespacing, 0, 0,
                 _abs);
  _RimeGetIntStr(config, "style/layout/min_width", style.min_width, 0, 0, _abs);
  _RimeGetIntStr(config, "style/layout/max_width", style.max_width, 0, 0, _abs);
  _RimeGetIntStr(config, "style/layout/min_height", style.min_height, 0, 0,
                 _abs);
  _RimeGetIntStr(config, "style/layout/max_height", style.max_height, 0, 0,
                 _abs);
  // layout (alternative to style/horizontal)
  const std::map<std::string, UIStyle::LayoutType> _layoutMap = {
      {std::string("vertical"), UIStyle::LAYOUT_VERTICAL},
      {std::string("horizontal"), UIStyle::LAYOUT_HORIZONTAL},
      {std::string("vertical_text"), UIStyle::LAYOUT_VERTICAL_TEXT},
      {std::string("vertical+fullscreen"), UIStyle::LAYOUT_VERTICAL_FULLSCREEN},
      {std::string("horizontal+fullscreen"),
       UIStyle::LAYOUT_HORIZONTAL_FULLSCREEN}};
  _RimeParseStringOptWithFallback(config, "style/layout/type",
                                  style.layout_type, _layoutMap,
                                  style.layout_type);
  // disable max_width when full screen
  if (style.layout_type == UIStyle::LAYOUT_HORIZONTAL_FULLSCREEN ||
      style.layout_type == UIStyle::LAYOUT_VERTICAL_FULLSCREEN) {
    style.max_width = 0;
    style.inline_preedit = false;
  }
  _RimeGetIntStr(config, "style/layout/border", style.border,
                 "style/layout/border_width", 0, _abs);
  _RimeGetIntStr(config, "style/layout/margin_x", style.margin_x);
  _RimeGetIntStr(config, "style/layout/margin_y", style.margin_y);
  _RimeGetIntStr(config, "style/layout/spacing", style.spacing, 0, 0, _abs);
  _RimeGetIntStr(config, "style/layout/candidate_spacing",
                 style.candidate_spacing, 0, 0, _abs);
  _RimeGetIntStr(config, "style/layout/hilite_spacing", style.hilite_spacing, 0,
                 0, _abs);
  _RimeGetIntStr(config, "style/layout/hilite_padding_x",
                 style.hilite_padding_x, "style/layout/hilite_padding", 0,
                 _abs);
  _RimeGetIntStr(config, "style/layout/hilite_padding_y",
                 style.hilite_padding_y, "style/layout/hilite_padding", 0,
                 _abs);
  _RimeGetIntStr(config, "style/layout/shadow_radius", style.shadow_radius, 0,
                 0, _abs);
  // disable shadow for fullscreen layout
  style.shadow_radius *=
      (!(style.layout_type == UIStyle::LAYOUT_HORIZONTAL_FULLSCREEN ||
         style.layout_type == UIStyle::LAYOUT_VERTICAL_FULLSCREEN));
  _RimeGetIntStr(config, "style/layout/shadow_offset_x", style.shadow_offset_x);
  _RimeGetIntStr(config, "style/layout/shadow_offset_y", style.shadow_offset_y);
  // round_corner as alias of hilited_corner_radius
  _RimeGetIntStr(config, "style/layout/hilited_corner_radius",
                 style.round_corner, "style/layout/round_corner", 0, _abs);
  // corner_radius not set, fallback to round_corner
  _RimeGetIntStr(config, "style/layout/corner_radius", style.round_corner_ex,
                 "style/layout/round_corner", 0, _abs);
  // fix padding and spacing settings
  if (style.layout_type != UIStyle::LAYOUT_VERTICAL_TEXT) {
    // hilite_padding vs spacing
    // if hilite_padding over spacing, increase spacing
    style.spacing = max(style.spacing, style.hilite_padding_y * 2);
    // hilite_padding vs candidate_spacing
    if (style.layout_type == UIStyle::LAYOUT_VERTICAL_FULLSCREEN ||
        style.layout_type == UIStyle::LAYOUT_VERTICAL) {
      // vertical, if hilite_padding_y over candidate spacing,
      // increase candidate spacing
      style.candidate_spacing =
          max(style.candidate_spacing, style.hilite_padding_y * 2);
    } else {
      // horizontal, if hilite_padding_x over candidate
      // spacing, increase candidate spacing
      style.candidate_spacing =
          max(style.candidate_spacing, style.hilite_padding_x * 2);
    }
    // hilite_padding_x vs hilite_spacing
    if (!style.inline_preedit)
      style.hilite_spacing = max(style.hilite_spacing, style.hilite_padding_x);
  } else  // LAYOUT_VERTICAL_TEXT
  {
    // hilite_padding_x vs spacing
    // if hilite_padding over spacing, increase spacing
    style.spacing = max(style.spacing, style.hilite_padding_x * 2);
    // hilite_padding vs candidate_spacing
    // if hilite_padding_x over candidate
    // spacing, increase candidate spacing
    style.candidate_spacing =
        max(style.candidate_spacing, style.hilite_padding_x * 2);
    // vertical_text_with_wrap and hilite_padding_y over candidate_spacing
    if (style.vertical_text_with_wrap)
      style.candidate_spacing =
          max(style.candidate_spacing, style.hilite_padding_y * 2);
    // hilite_padding_y vs hilite_spacing
    if (!style.inline_preedit)
      style.hilite_spacing = max(style.hilite_spacing, style.hilite_padding_y);
  }
  // fix padding and margin settings
  int scale = style.margin_x < 0 ? -1 : 1;
  style.margin_x = scale * max(style.hilite_padding_x, abs(style.margin_x));
  scale = style.margin_y < 0 ? -1 : 1;
  style.margin_y = scale * max(style.hilite_padding_y, abs(style.margin_y));
  // get enhanced_position
  _RimeGetBool(config, "style/enhanced_position", initialize,
               style.enhanced_position, true, false);
  // get color scheme
  const int BUF_SIZE = 255;
  char buffer[BUF_SIZE + 1] = {0};
  if (initialize && rime_api->config_get_string(config, "style/color_scheme",
                                                buffer, BUF_SIZE))
    _UpdateUIStyleColor(config, style);
}
// load color configs to style, by "style/color_scheme" or specific scheme name
// "color" which is default empty
static bool _UpdateUIStyleColor(RimeConfig* config,
                                UIStyle& style,
                                std::string color) {
  const int BUF_SIZE = 255;
  char buffer[BUF_SIZE + 1] = {0};
  std::string color_mark = "style/color_scheme";
  // color scheme
  if (rime_api->config_get_string(config, color_mark.c_str(), buffer,
                                  BUF_SIZE) ||
      !color.empty()) {
    std::string prefix("preset_color_schemes/");
    prefix += (color.empty()) ? buffer : color;
    // define color format, default abgr if not set
    ColorFormat fmt = COLOR_ABGR;
    const std::map<std::string, ColorFormat> _colorFmt = {
        {std::string("argb"), COLOR_ARGB},
        {std::string("rgba"), COLOR_RGBA},
        {std::string("abgr"), COLOR_ABGR}};
    _RimeParseStringOptWithFallback(config, (prefix + "/color_format"), fmt,
                                    _colorFmt, COLOR_ABGR);
#define COLOR(key, value, fallback) \
  _RimeGetColor(config, (prefix + "/" + key), value, fmt, fallback)
    COLOR("back_color", style.back_color, 0xffffffff);
    COLOR("shadow_color", style.shadow_color, 0);
    COLOR("prevpage_color", style.prevpage_color, 0);
    COLOR("nextpage_color", style.nextpage_color, 0);
    COLOR("text_color", style.text_color, 0xff000000);
    COLOR("candidate_text_color", style.candidate_text_color, style.text_color);
    COLOR("candidate_back_color", style.candidate_back_color, 0);
    COLOR("border_color", style.border_color, style.text_color);
    COLOR("hilited_text_color", style.hilited_text_color, style.text_color);
    COLOR("hilited_back_color", style.hilited_back_color, style.back_color);
    COLOR("hilited_candidate_text_color", style.hilited_candidate_text_color,
          style.hilited_text_color);
    COLOR("hilited_candidate_back_color", style.hilited_candidate_back_color,
          style.hilited_back_color);
    COLOR("hilited_candidate_shadow_color",
          style.hilited_candidate_shadow_color, 0);
    COLOR("hilited_shadow_color", style.hilited_shadow_color, 0);
    COLOR("candidate_shadow_color", style.candidate_shadow_color, 0);
    COLOR("candidate_border_color", style.candidate_border_color, 0);
    COLOR("hilited_candidate_border_color",
          style.hilited_candidate_border_color, 0);
    COLOR("label_color", style.label_text_color,
          blend_colors(style.candidate_text_color, style.candidate_back_color));
    COLOR("hilited_label_color", style.hilited_label_text_color,
          blend_colors(style.hilited_candidate_text_color,
                       style.hilited_candidate_back_color));
    COLOR("comment_text_color", style.comment_text_color,
          style.label_text_color);
    COLOR("hilited_comment_text_color", style.hilited_comment_text_color,
          style.hilited_label_text_color);
    COLOR("hilited_mark_color", style.hilited_mark_color, 0);
#undef COLOR
    return true;
  }
  return false;
}

static void _LoadAppOptions(RimeConfig* config,
                            AppOptionsByAppName& app_options) {
  app_options.clear();
  RimeConfigIterator app_iter;
  RimeConfigIterator option_iter;
  rime_api->config_begin_map(&app_iter, config, "app_options");
  while (rime_api->config_next(&app_iter)) {
    AppOptions& options(app_options[app_iter.key]);
    rime_api->config_begin_map(&option_iter, config, app_iter.path);
    while (rime_api->config_next(&option_iter)) {
      Bool value = False;
      if (rime_api->config_get_bool(config, option_iter.path, &value)) {
        options[option_iter.key] = !!value;
      }
    }
    rime_api->config_end(&option_iter);
  }
  rime_api->config_end(&app_iter);
}

void RimeWithWeaselHandler::_GetStatus(Status& stat,
                                       WeaselSessionId ipc_id,
                                       Context& ctx) {
  SessionStatus& session_status = get_session_status(ipc_id);
  RimeSessionId session_id = session_status.session_id;
  RIME_STRUCT(RimeStatus, status);
  if (rime_api->get_status(session_id, &status)) {
    std::string schema_id = "";
    if (status.schema_id)
      schema_id = status.schema_id;
    stat.schema_name = u8tow(status.schema_name);
    stat.schema_id = u8tow(status.schema_id);
    stat.ascii_mode = !!status.is_ascii_mode;
    stat.composing = !!status.is_composing;
    stat.disabled = !!status.is_disabled;
    stat.full_shape = !!status.is_full_shape;
    if (schema_id != m_last_schema_id) {
      session_status.__synced = false;
      m_last_schema_id = schema_id;
      if (schema_id != ".default") {  // don't load for schema select menu
        bool inline_preedit = session_status.style.inline_preedit;
        _LoadSchemaSpecificSettings(ipc_id, schema_id);
        _LoadAppInlinePreeditSet(ipc_id, true);
        if (session_status.style.inline_preedit != inline_preedit)
          // in case of inline_preedit set in schema
          _UpdateInlinePreeditStatus(ipc_id);
        // refresh icon after schema changed
        _RefreshTrayIcon(session_id, _UpdateUICallback);
        m_ui->style() = session_status.style;
        if (m_show_notifications.find("schema") != m_show_notifications.end() &&
            m_show_notifications_time > 0) {
          ctx.aux.str = stat.schema_name;
          m_ui->Update(ctx, stat);
          m_ui->ShowWithTimeout(m_show_notifications_time);
        }
      }
    }
    rime_api->free_status(&status);
  }
}

void RimeWithWeaselHandler::_GetContext(Context& weasel_context,
                                        RimeSessionId session_id) {
  RIME_STRUCT(RimeContext, ctx);
  if (rime_api->get_context(session_id, &ctx)) {
    if (ctx.composition.length > 0) {
      std::string vlabel;
      if (_VMenuLabel(rime_api, session_id, ctx.composition.preedit,
                      &vlabel)) {
        // v 功能菜单：前端只看到功能名，看不到 vclip / vqi / vfav 这类内部编码
        weasel_context.preedit.str = u8tow(vlabel.c_str());
      } else {
        weasel_context.preedit.str = u8tow(ctx.composition.preedit);
        if (ctx.composition.sel_start < ctx.composition.sel_end) {
          TextAttribute attr;
          attr.type = HIGHLIGHTED;
          attr.range.start =
              utf8towcslen(ctx.composition.preedit, ctx.composition.sel_start);
          attr.range.end =
              utf8towcslen(ctx.composition.preedit, ctx.composition.sel_end);

          weasel_context.preedit.attributes.push_back(attr);
        }
      }
    }
    if (ctx.menu.num_candidates) {
      CandidateInfo& cinfo(weasel_context.cinfo);
      _GetCandidateInfo(cinfo, ctx);
    }
    rime_api->free_context(&ctx);
  }
}

bool RimeWithWeaselHandler::_IsSessionTSF(RimeSessionId session_id) {
  static char client_type[20] = {0};
  rime_api->get_property(session_id, "client_type", client_type,
                         sizeof(client_type) - 1);
  return std::string(client_type) == "tsf";
}

void RimeWithWeaselHandler::_UpdateInlinePreeditStatus(WeaselSessionId ipc_id) {
  if (!m_ui)
    return;
  SessionStatus& session_status = get_session_status(ipc_id);
  RimeSessionId session_id = session_status.session_id;
  // set inline_preedit option
  bool inline_preedit =
      session_status.style.inline_preedit && _IsSessionTSF(session_id);
  rime_api->set_option(session_id, "inline_preedit", Bool(inline_preedit));
  // show soft cursor on weasel panel but not inline
  rime_api->set_option(session_id, "soft_cursor", Bool(!inline_preedit));
}
