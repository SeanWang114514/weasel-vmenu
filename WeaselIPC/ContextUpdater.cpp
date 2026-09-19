#include "stdafx.h"
#include <StringAlgorithm.hpp>
#include <WeaselUtility.h>

#include "Deserializer.h"
#include "ContextUpdater.h"

using namespace weasel;

// ContextUpdater

Deserializer::Ptr ContextUpdater::Create(ResponseParser* pTarget) {
  return Deserializer::Ptr(new ContextUpdater(pTarget));
}

ContextUpdater::ContextUpdater(ResponseParser* pTarget)
    : Deserializer(pTarget) {}

ContextUpdater::~ContextUpdater() {}

void ContextUpdater::Store(Deserializer::KeyType const& k,
                           std::wstring const& value) {
  if (!m_pTarget->p_context || k.size() < 2)
    return;

  if (k[1] == L"preedit") {
    _StoreText(m_pTarget->p_context->preedit, k, value);
    return;
  }

  if (k[1] == L"aux") {
    _StoreText(m_pTarget->p_context->aux, k, value);
    return;
  }

  if (k[1] == L"cand") {
    _StoreCand(k, value);
    return;
  }

  // [vmenu-grid] ctx.grid_cols=4 —— v 功能菜单「一行 4 个」，普通打字 9。
  // 走文本协议（不是 boost 结构）是刻意的：老客户端会忽略这个键、新客户端遇到老服务端
  // 保持 0（按 9 渲染），两边版本不一致也不会崩。
  if (k[1] == L"grid_cols") {
    m_pTarget->p_context->grid_cols = _wtoi(value.c_str());
    return;
  }

  // [vmenu-grid] ctx.grid_2d=0/1 —— 序号算法：1 = 按「行 × 列」（列表/普通打字），
  // 0 = 按 1..N 顺序（静态 v 菜单）。同上走文本协议，旧服务端不发就保持默认 1。
  if (k[1] == L"grid_2d") {
    m_pTarget->p_context->grid_2d = _wtoi(value.c_str());
    return;
  }
}

void ContextUpdater::_StoreText(Text& target,
                                Deserializer::KeyType k,
                                std::wstring const& value) {
  if (k.size() == 2) {
    target.clear();
    target.str = unescape_string(value);
    return;
  }
  if (k.size() == 3) {
    // ctx.preedit.cursor
    if (k[2] == L"cursor") {
      std::vector<std::wstring> vec;
      split(vec, value, L",");
      if (vec.size() < 2)
        return;

      weasel::TextAttribute attr;
      attr.type = HIGHLIGHTED;
      attr.range.start = _wtoi(vec[0].c_str());
      attr.range.end = _wtoi(vec[1].c_str());
      attr.range.cursor = _wtoi(vec[2].c_str());

      target.attributes.push_back(attr);
      return;
    }
  }
}

void ContextUpdater::_StoreCand(Deserializer::KeyType k,
                                std::wstring const& value) {
  CandidateInfo& cinfo = m_pTarget->p_context->cinfo;
  std::wstringstream ss(value);
  boost::archive::text_wiarchive ia(ss);

  TryDeserialize(ia, cinfo);

  for (auto& cand : cinfo.candies)
    cand.str = unescape_string(cand.str);
  for (auto& lalel : cinfo.labels)
    lalel.str = unescape_string(lalel.str);
  for (auto& comment : cinfo.comments)
    comment.str = unescape_string(comment.str);
}

// StatusUpdater

Deserializer::Ptr StatusUpdater::Create(ResponseParser* pTarget) {
  return Deserializer::Ptr(new StatusUpdater(pTarget));
}

StatusUpdater::StatusUpdater(ResponseParser* pTarget) : Deserializer(pTarget) {}

StatusUpdater::~StatusUpdater() {}

void StatusUpdater::Store(Deserializer::KeyType const& k,
                          std::wstring const& value) {
  if (!m_pTarget->p_status || k.size() < 2)
    return;

  bool bool_value = (!value.empty() && value != L"0");

  if (k[1] == L"schema_id") {
    m_pTarget->p_status->schema_id = value;
    return;
  }

  if (k[1] == L"ascii_mode") {
    m_pTarget->p_status->ascii_mode = bool_value;
    return;
  }

  if (k[1] == L"composing") {
    m_pTarget->p_status->composing = bool_value;
    return;
  }

  if (k[1] == L"disabled") {
    m_pTarget->p_status->disabled = bool_value;
    return;
  }

  if (k[1] == L"full_shape") {
    m_pTarget->p_status->full_shape = bool_value;
    return;
  }
}
