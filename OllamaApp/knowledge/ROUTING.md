---
id: KB-ROUTING
type: routing
status: OFFICIAL
updatedAt: YYYY-MM-DD
---

# Routing（从需求线索定位到代码入口）

## 规则
- 优先用“线索 → 模块 → 入口文件/函数”的方式定位，不全量读知识
- 知识库提供约束与入口，字段/签名/实现细节以代码为准

## 线索 → 模块 → 入口
### 线索：Stop / Cancel / Stopped / 生成中断
- 模块：取消语义
- KB：./main/cancellation.md
- 代码入口：
  - UI Stop：OllamaApp/OllamaApp/ContentView.swift（stop 按钮）
  - Core：OllamaApp/OllamaApp/OllamaManager.swift（stopGenerating / Task cancel / stream loop）

### 线索：127.0.0.1 / localhost / 连接失败 / ATS
- 模块：网络与运行环境
- KB：./main/networking.md
- 代码入口：
  - baseURL：OllamaApp/OllamaApp/OllamaManager.swift（Ollama baseURL）
  - ATS：OllamaApp/OllamaApp/Info.plist

### 线索：DeepSeek Key / Base URL / 401 / 404
- 模块：安全与配置、Provider
- KB：./main/security-config.md + ./applications/llm-core.md
- 代码入口：
  - KeychainStore：OllamaApp/OllamaApp/OllamaManager.swift
  - 设置页：OllamaApp/OllamaApp/ContentView.swift（DeepSeekSettingsView）
  - BaseURL 兼容：OllamaApp/OllamaApp/OllamaManager.swift（URL 生成函数）

### 线索：自动滚动 / 消息列表 / 已复制
- 模块：UI
- KB：./applications/ui.md
- 代码入口：OllamaApp/OllamaApp/ContentView.swift（ScrollViewReader / ChatMessageRow）