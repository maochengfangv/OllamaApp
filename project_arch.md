
            
          
**整体分层（从上到下）**
- **App 入口层**：[`OllamaAppApp`](file:///Users/maochengfang/Documents/LLMProject/LLM_OllamaAPP/OllamaApp/OllamaApp/OllamaAppApp.swift#L10-L16) 只有一个 `WindowGroup`，根视图是 `ContentView()`。
- **UI 展示层（SwiftUI Views）**：主要围绕 [`ContentView.swift`](file:///Users/maochengfang/Documents/LLMProject/LLM_OllamaAPP/OllamaApp/OllamaApp/ContentView.swift) 和独立视图展开，包含：
  - `ContentView`：首页新建会话入口 + 历史会话抽屉。
  - `ChatView`：聊天页面（模型输入、消息列表、发送/停止）。
  - `ChatMessageRow`：单条消息 UI（气泡、复制；你新增的“重新发送”入口也在这里）。
  - `DeepSeekSettingsView`：DeepSeek Base URL + API Key 管理 UI（Keychain + AppStorage）。
- **状态与业务层（ViewModel / Manager）**：[`OllamaManager`](file:///Users/maochengfang/Documents/LLMProject/LLM_OllamaAPP/OllamaApp/OllamaApp/OllamaManager.swift#L41-L615) 是核心，承担：
  - 聊天状态：`@Published messages / isGenerating / chatHistory`
  - 会话生命周期：`startNewChat` / `loadChat` / `deleteHistory`
  - 生成控制：`generate`（发送新消息）/ `stopGenerating`（取消当前任务）/ `resend`（重发指定 user 消息，截断后续并重新生成）
- **数据模型层（Domain Models）**：核心定义位于 `LLM/Core/LLMTypes.swift` 与相关 Provider 文件：
  - `ChatMessage`（role + content + id）
  - `ChatSession`（id + messages + title + date）
  - `LLMProvider`（当前仅 `deepseek`）

**当前 Provider 调用链路**
- **DeepSeek（远程）**
  - UI：`DeepSeekChatView` 调 `manager.generate(prompt:model:webEnabled:)`
  - Manager：走 `generateWithDeepSeek(model:webEnabled:query:)`
  - 鉴权：API Key 存在 Keychain（`KeychainStore`）
  - Base URL：来自 `UserDefaults`（`DeepSeekBaseURL`），自动尝试拼出若干候选 `/chat/completions` URL 并 fallback
  - “联网”增强：`webEnabled` 时先尝试 Open-Meteo（天气）或 DuckDuckGo（摘要/相关条目），把结果塞进 system prompt，再请求 DeepSeek（当前实现 `stream: false`，一次性返回）

**数据持久化与配置**
- **聊天历史**：按 provider 维度持久化到 `Application Support/ChatSessions/<provider>/`，索引与完整会话分离保存。
- **会话标题策略**：取“最后一条 user 消息”的前 15 字作为标题（超出加 `...`）。
- **DeepSeek API Key**：Keychain（`Security` 框架），`DeepSeekSettingsView` 负责写入/清除。
- **模型选择**：`@AppStorage` 保存 `SelectedDeepSeekModel`；联网开关用 `@AppStorage("DeepSeekWebEnabled")`。

**项目形态**
- 工程：`OllamaApp.xcodeproj` + `OllamaApp.xcworkspace`
- CocoaPods：有 `Podfile` 但当前没有实际 Pod 依赖（`Podfile.lock` 只有 CocoaPods 版本信息）
- 测试：`OllamaAppTests`/`OllamaAppUITests` 为默认模板，暂无业务测试
