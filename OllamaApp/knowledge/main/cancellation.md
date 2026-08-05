---
id: KB-MAIN-CANCELLATION
type: main
status: OFFICIAL
updatedAt: YYYY-MM-DD
stability: evolving
confidence: high
evidence:
  - code: OllamaApp/OllamaApp/OllamaManager.swift (stopGenerating, Task, stream loop)
  - code: OllamaApp/OllamaApp/ContentView.swift (stop button)
---

# Streaming + Cancellation（端侧生成中断语义）

## AI 使用摘要
- 适用场景：修 stop 不生效、处理“停止后 UI/历史状态不一致”
- 核心原则：取消要可达；取消后状态要收敛；历史要可控落盘

## 当前实现事实（以代码为准）
- Stop 入口：UI 点击 stop → manager.stopGenerating()
- stopGenerating 行为：
  - cancel 当前 Task
  - isGenerating = false
  - updateCurrentSession() 落盘
- Ollama 流式循环：
  - for await line in result.lines
  - 每轮检查 Task.isCancelled，取消则 break

## 质量门禁（改动取消相关逻辑时必做）
- 停止后是否还能继续 append token
- 停止后 isGenerating 是否及时为 false
- 停止后历史是否落盘且不产生“空 assistant 消息”异常
- 非 200 / 解析失败 / 取消三种分支的 UI 文案是否可接受