
            
          
**整体分层（从上到下）**
- **App 入口层**：`OllamaAppApp` 仅承载 `WindowGroup`，根视图为 `ContentView()`。
- **UI 展示层（SwiftUI Views）**：`ContentView` 负责首页与历史抽屉；`ChatView` 承载主聊天；`ChatMessageRow` 负责消息展示；`DeepSeekSettingsView` 管理聊天与 Embedding 配置；`AIDebugPanelView` 负责运行时调试、Memory 与 Evaluation 展示；`TodoAgentDebugView` 负责 Todo Agent 的调试与 HITL 交互。
- **状态与业务层（Manager / ViewModel）**：`OllamaManager` 是主聊天编排核心，负责消息状态、会话生命周期、流式生成、调试快照与 Memory 写入触发；`TodoAgentDebugViewModel` 负责 Todo Agent 页面状态与待确认动作承接。
- **AI 网关层（统一收口）**：`AIClient` 是唯一模型网关入口，统一负责路由、重试、fallback、上下文构建、流式事件下发与 embedding 调用；所有模型请求统一经 `AIRequest` / `AIResponseEvent` 协议管线流转。
- **上下文构建层（Context Building）**：`MemoryContextBuilder` 以装饰器方式包裹 `WebSearchContextBuilder`，在不侵入主链路的前提下按需注入联网上下文与长期记忆上下文。
- **能力层（Abilities）**：`LLM/Memory` 提供 Embedding、记忆存储与召回；`Agent/Todo` 提供 Tool Calling、ReAct 循环与 Human-in-the-loop；`LLM/Evaluation` 提供内建评测 Harness。
- **数据模型层（Domain Models）**：核心定义位于 `LLM/Core/LLMTypes.swift`，包括 `ChatMessage`、`ChatSession`、`AIRequest`、`AIResponseEvent`、`AIUsage`、`AIToolDefinition`、`AIToolCall` 等。

**当前 AI 调用链路**
- **主聊天链路**
  - UI：`ChatView` 调 `OllamaManager.generate(...)`
  - Manager：构造 `AIRequest`
  - Gateway：`AIClient.responseStream(for:)`
  - Context：按开关注入 Web / Memory
  - Provider：当前主模型为 `DeepSeekProviderClient`
  - Event：以 `.started / .preview / .delta / .reasoning / .toolCalls / .memoryContext / .usage / .completed` 等事件回传
- **Embedding 链路**
  - `MemoryService` 通过 `AIClient.embeddings(for:)` 统一收口
  - Embedding Provider 采用独立配置（BaseURL / Model / API Key），与聊天 DeepSeek 配置解耦
- **Agent Tool 链路**
  - `TodoAgent` 基于 ReAct 循环请求模型
  - 模型产出 `toolCalls` 后，低风险工具直接执行；高风险 `delete_todo` 进入 `pendingAction`
  - `TodoAgentDebugView` 使用 `confirmationDialog` 完成 Human-in-the-loop 确认/取消

**已落地核心能力**
- **TOP1：端侧 RAG Memory 闭环**
  - 本地 JSON 持久化记忆
  - 远程 Embedding + 本地召回
  - `MemoryContextBuilder` 注入记忆上下文
  - `AIDebugPanelView` 可查看 Memory Store 与召回命中
- **TOP2：端内评测 Harness（规则优先）**
  - 内建评测 Case
  - 通过 `AIEvaluationRunner` 直接复用 `AIClient`
  - 在 `AIDebugPanelView` 中展示通过率、耗时、Memory 命中与失败原因
- **TOP3：Todo Agent Tool Calling + HITL**
  - Todo Tool Schema 已接入 `AIRequest.tools`
  - 高风险删除操作需显式确认后才执行
  - 调试页可观察 Agent 对话、本地 TodoStore 与待确认动作

**数据持久化与配置**
- **聊天历史**：持久化到 `Application Support/ChatSessions/<provider>/`，索引与完整会话分离。
- **长期记忆**：持久化到 `Application Support/AIMemory/` 下的本地 JSON 文件。
- **API Key**：聊天与 Embedding 分别使用 Keychain 存储。
- **运行时配置**：`UserDefaults` / `AppStorage` 管理模型、联网开关、Memory 开关、Embedding BaseURL / Model 等。

**可观测性**
- **调试快照**：`AIDebugSnapshot` 记录请求状态、Provider、Prompt、Usage、Memory 命中、错误等。
- **遥测**：`ChatTelemetryRecorder` 统一记录 generation / embedding 事件。
- **调试 UI**：`AIDebugPanelView` 与 `TodoAgentDebugView` 分别覆盖主聊天与 Agent 场景。

**项目形态**
- 工程：`OllamaApp.xcodeproj` + `OllamaApp.xcworkspace`
- 依赖：保留 CocoaPods 工程形态，但当前核心能力主要基于原生 Swift / SwiftUI / Swift Concurrency / URLSession 实现
- 测试：已新增面向 Memory / Evaluation 的工程化测试与端内回归能力，业务能力不再仅依赖模板测试
