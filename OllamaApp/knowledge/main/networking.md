---
id: KB-MAIN-NETWORKING
type: main
status: OFFICIAL
updatedAt: YYYY-MM-DD
stability: stable
confidence: high
evidence:
  - code: OllamaApp/OllamaApp/Views/Settings/DeepSeekSettingsView.swift
  - code: OllamaApp/OllamaApp/LLM/Providers/DeepSeekProvider.swift
---

# Networking / ATS / Simulator vs Device

## AI 使用摘要
- 适用场景：排查 DeepSeek 请求失败、Base URL 配置错误、超时或鉴权问题
- 使用前必须核对：当前 Base URL、API Key、网络环境、服务端返回码

## 稳定事实（必须遵守）
- 当前主链路为云端 HTTPS 请求，不依赖本地 127.0.0.1 服务
- API Key 必须来自 Keychain，不能回退到 UserDefaults 明文存储

## 当前项目配置（以代码为准）
- Base URL：由 `DeepSeekSettingsView` 管理并持久化
- 网络请求：由 `DeepSeekProvider` 统一发起

## 排障最小路径
- 症状：timeout / 401 / 403 / 非 200 / 返回体解析失败
- 检查顺序：
  1) API Key 是否存在且未过期
  2) Base URL 是否指向可用的 `/chat/completions` 服务
  3) 网络环境是否阻断外网 HTTPS
  4) 返回码与错误响应体是否提示鉴权、限流或服务异常