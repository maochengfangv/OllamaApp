---
id: KB-APP-LLM-CORE
type: application
status: OFFICIAL
updatedAt: YYYY-MM-DD
stability: evolving
confidence: high
evidence:
  - code: OllamaApp/OllamaApp/OllamaManager.swift
---

# Core 模块（OllamaManager / Provider / History）

## AI 使用摘要
- 适用场景：改流式解析、加新 Provider、修历史/会话、做质量门禁
- 关键入口：OllamaManager.generate / resend / stopGenerating

## 核心数据结构（以代码为准）
- ChatMessage(role: user/model, content)
- ChatSession(id, messages, title, date)
- 历史存储：UserDefaults（key 由 provider 决定）

## Provider 行为概览
- Ollama：
  - endpoint: /api/generate
  - stream: true
  - 每行 JSON 解码 OllamaResponse 并 append response
- DeepSeek：
  - endpoint: /chat/completions（会尝试多种 base 拼接）
  - stream: false（当前）
  - 可选 webEnabled：会写入【联网结果】前缀再回答

## 门禁（改动时必须验证）
- 主线程更新：OllamaManager 是 @MainActor，messages/isGenerating 更新必须保持一致
- 取消可达：stream loop 必须检查 Task.isCancelled
- 历史一致性：updateCurrentSession 的调用点是否覆盖成功/失败/取消三条路径