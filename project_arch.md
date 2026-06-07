
toolName: view_files
            
status: success
          
            
filePath: /Users/maochengfang/Documents/LLMProject/LLM_OllamaAPP/OllamaApp/OllamaApp/OllamaAppApp.swift
          

        
            
toolName: view_files
            
status: success
          
            
filePath: /Users/maochengfang/Documents/LLMProject/LLM_OllamaAPP/OllamaApp/Podfile
          

        
            
toolName: view_files
            
status: success
          
            
filePath: /Users/maochengfang/Documents/LLMProject/LLM_OllamaAPP/OllamaApp/Podfile.lock
          

        
            
toolName: view_files
            
status: success
          
            
filePath: /Users/maochengfang/Documents/LLMProject/LLM_OllamaAPP/OllamaApp/OllamaAppTests/OllamaAppTests.swift
          

        
            
toolName: view_files
            
status: success
          
            
filePath: /Users/maochengfang/Documents/LLMProject/LLM_OllamaAPP/OllamaApp/OllamaApp/Info.plist
          
**整体分层（从上到下）**
- **App 入口层**：[`OllamaAppApp`](file:///Users/maochengfang/Documents/LLMProject/LLM_OllamaAPP/OllamaApp/OllamaApp/OllamaAppApp.swift#L10-L16) 只有一个 `WindowGroup`，根视图是 `ContentView()`。
- **UI 展示层（SwiftUI Views）**：主要都集中在 [`ContentView.swift`](file:///Users/maochengfang/Documents/LLMProject/LLM_OllamaAPP/OllamaApp/OllamaApp/ContentView.swift) 一个文件里，包含：
  - `ContentView`：左侧/主导航 + 历史会话列表入口（Ollama / DeepSeek 各一套）。
  - `OllamaChatView` / `DeepSeekChatView`：聊天页面（模型输入、消息列表、发送/停止）。
  - `ChatMessageRow`：单条消息 UI（气泡、复制；你新增的“重新发送”入口也在这里）。
  - `DeepSeekSettingsView`：DeepSeek Base URL + API Key 管理 UI（Keychain + AppStorage）。
- **状态与业务层（ViewModel / Manager）**：[`OllamaManager`](file:///Users/maochengfang/Documents/LLMProject/LLM_OllamaAPP/OllamaApp/OllamaApp/OllamaManager.swift#L41-L615) 是核心，承担：
  - 聊天状态：`@Published messages / isGenerating / chatHistory`
  - 会话生命周期：`startNewChat` / `loadChat` / `deleteHistory`
  - 生成控制：`generate`（发送新消息）/ `stopGenerating`（取消当前任务）/ `resend`（重发指定 user 消息，截断后续并重新生成）
- **数据模型层（Domain Models）**：都在 `OllamaManager.swift` 内定义：
  - `ChatMessage`（role + content + id）
  - `ChatSession`（id + messages + title + date）
  - `LLMProvider`（`.ollama` / `.deepseek`）
  - 网络请求/响应 DTO：`OllamaRequest` / `OllamaResponse`、DeepSeek 的 request/response 内嵌结构体

**两条 Provider 的调用链路**
- **Ollama（本地）**
  - UI：`OllamaChatView` 调 `manager.generate(prompt:model:)`
  - Manager：走 `generateWithOllama(prompt:model:)`
  - 网络：POST `http://127.0.0.1:11434/api/generate`，`stream: true`，用 `URLSession.shared.bytes(for:)` 按行增量拼接回复
  - 配置：[`Info.plist`](file:///Users/maochengfang/Documents/LLMProject/LLM_OllamaAPP/OllamaApp/OllamaApp/Info.plist#L4-L7) 开了 `NSAllowsArbitraryLoads`，允许本地 HTTP
- **DeepSeek（远程）**
  - UI：`DeepSeekChatView` 调 `manager.generate(prompt:model:webEnabled:)`
  - Manager：走 `generateWithDeepSeek(model:webEnabled:query:)`
  - 鉴权：API Key 存在 Keychain（`KeychainStore`）
  - Base URL：来自 `UserDefaults`（`DeepSeekBaseURL`），自动尝试拼出若干候选 `/chat/completions` URL 并 fallback
  - “联网”增强：`webEnabled` 时先尝试 Open-Meteo（天气）或 DuckDuckGo（摘要/相关条目），把结果塞进 system prompt，再请求 DeepSeek（当前实现 `stream: false`，一次性返回）

**数据持久化与配置**
- **聊天历史**：每个 provider 使用独立的 `UserDefaults` key：`ChatHistory_ollama` / `ChatHistory_deepseek`；每次生成结束或停止会 `updateCurrentSession()` 保存。
- **会话标题策略**：取“最后一条 user 消息”的前 15 字作为标题（超出加 `...`）。
- **DeepSeek API Key**：Keychain（`Security` 框架），`DeepSeekSettingsView` 负责写入/清除。
- **模型选择**：`@AppStorage` 保存 `SelectedOllamaModel` / `SelectedDeepSeekModel`；DeepSeek 的联网开关也用 `@AppStorage("DeepSeekWebEnabled")`。

**项目形态**
- 工程：`OllamaApp.xcodeproj` + `OllamaApp.xcworkspace`
- CocoaPods：有 `Podfile` 但当前没有实际 Pod 依赖（`Podfile.lock` 只有 CocoaPods 版本信息）
- 测试：`OllamaAppTests`/`OllamaAppUITests` 为默认模板，暂无业务测试
