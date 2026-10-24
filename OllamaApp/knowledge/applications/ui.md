---
id: KB-APP-UI
type: application
status: OFFICIAL
updatedAt: YYYY-MM-DD
stability: evolving
confidence: high
evidence:
  - code: OllamaApp/OllamaApp/ContentView.swift
---

# UI 模块（SwiftUI）

## AI 使用摘要
- 适用场景：改聊天 UI、修自动滚动、优化抽屉与历史会话交互
- 关键入口：ContentView / ChatView / HistorySessionsView / ChatMessageRow

## 职责与边界
- 职责：输入、发送、停止、消息展示、历史列表、设置页
- 边界：生成逻辑与网络在 `OllamaManager` 编排层；UI 只驱动动作与展示状态

## 关键交互（以代码为准）
- 生成中：
  - 禁用输入框与 model 输入
  - 显示 stop 按钮
  - assistant 空内容 + loading dots
- 自动滚动：
  - 监听 messages 变化与 last.content 变化，滚到底部

## 易错点门禁
- 避免因频繁 onChange 导致滚动抖动/性能问题
- stop 时 UI 状态及时收敛，避免按钮状态与 isGenerating 不一致