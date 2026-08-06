---
requirementId: RQ-YYYYMMDD-XXX
status: DRAFT | REVIEW | IN_PROGRESS | DONE | BLOCKED
owner: {yourName}
reviewer: {reviewerName}
priority: P0 | P1 | P2
estimatedDays: {X}d
updatedAt: YYYY-MM-DD HH:MM
dueAt: YYYY-MM-DD HH:MM
---

# Requirement：{标题}

> ⚠️ **AI 填写强制规则**：本文件每一节必须**完整填写**后方可进入编码。任何留空或模糊描述（如"优化性能"而无量化指标）均视为 DRAFT，禁止触发代码改动。
>
> 🔗 **对账映射契约**：本文件中 → 对应 implementation-check.md 对账节：
> - 关键约束（P0） → implementation-check「P0 关键约束对账」
> - 方案改动点 → implementation-check「Checklist」
> - 验收标准 → implementation-check「验收标准对账」
> - 手工验证步骤 → implementation-check「手工验证结果」
> - 风险与回滚 → implementation-check「风险与回滚核对」

## 背景与目标
- 背景（业务/技术驱动，量化痛点）：
  - {例：当前流式输出点击 stop 后平均 3.5s 才停止，用户反馈卡顿，影响转化率 12%}
- 目标（必须可验证，拆分为 P0/P1/P2）：
  - 🟥 **P0（必须达成，阻塞合入）**：
    - {例：流式输出中点击 stop → 1s 内停止输出，isGenerating 归位为 false}
    - {例：API Key 不落日志、不进 UserDefaults，仅存 Keychain}
  - 🟧 **P1（重要增强）**：
    - {例：停止后已输出内容持久化到历史记录，不丢失}
  - 🟩 **P2（锦上添花，本期不做可延期）**：
    - {例：停止按钮点击增加动效反馈}

## 非目标（明确不做什么 + AI 常见越界预警）
- ✅ 明确不做：
  - {例：本次不改历史记录的数据结构，兼容现有 schema}
  - {例：不引入新的第三方网络库，继续使用 URLSession}
- ⚠️ **AI 禁止越界**（AI Coding 时最容易顺手改的坑，必须写）：
  - {例：禁止修改 ContentView 中与本需求无关的 UI 样式（如配色、字体）}
  - {例：禁止重构 OllamaManager 现有网络层签名，仅在内部补充取消逻辑}
  - {例：禁止删除或注释掉任何现有 print/Logger 语句，如需修改需单独列改动点}

## 影响范围（按模块/文件精确列出 + 改动类型）
> 改动类型：新增(+) / 修改(~) / 删除(-) | 兼容性风险：🟢无 / 🟡中（需迁移）/ 🔴高（破坏性变更）

| 模块 | 文件路径 | 改动类型 | 兼容性风险 | 说明 |
|------|---------|---------|-----------|------|
| UI | OllamaApp/OllamaApp/ContentView.swift | ~ | 🟢 | Stop 按钮绑定逻辑调整 |
| Core | OllamaApp/OllamaApp/OllamaManager.swift | ~ / + | 🟡 | 流式循环增加 isCancelled 检查，暴露 stop() 方法 |
| Config | OllamaApp/OllamaApp/Info.plist | 不变 | 🟢 | |
| Security | OllamaApp/OllamaApp/KeychainHelper.swift | + / ~ | 🟡 | API Key 存储逻辑迁移 |
| 其他 | | | | |

### 历史兼容性声明
- {例：新增字段 `interrupted: Bool` 到 ChatMessage，旧版本读取时默认 false，不崩溃（前向兼容）}
- {例：Keychain 存储 Key 名称不变，迁移时自动读取旧值转存，用户无需重新配置}

## 关键约束（P0 · 硬门禁 · 全部达标才能合入）
> 🔒 **填写要求**：每条必须**可被 grep / 静态检查 / 运行时断言**验证，禁止模糊词（"尽量"、"最好"、"合理"）。
> 对应 KB：knowledge/main/networking.md · cancellation.md · security-config.md

- **网络/ATS/127.0.0.1 约束**：
  - requirement 描述：
    - {例：模拟器访问本地 Ollama 必须硬编码 `127.0.0.1`，禁止使用 `localhost`（防止 IPv6 解析失败）}
    - {例：本地 HTTP 请求必须在 Info.plist 的 NSAppTransportSecurity → NSExceptionDomains 中显式声明 127.0.0.1，禁止全局 NSAllowsArbitraryLoads = YES}
  - 验证方式：{grep 代码中无 `localhost`；Info.plist 审查 / plutil 校验}

- **取消语义（stop 后必须如何收敛）**：
  - requirement 描述：
    - {例：所有 `for try await line in URLSession.shared.bytes(from:).lines` 循环体内第一行必须 `if Task.isCancelled { break }`}
    - {例：`stopGenerate()` 方法必须调用 `streamTask?.cancel()` 并同步设置 `isGenerating = false`，不得依赖异步回调延迟设值}
    - {例：连续快速点击 stop + start，不得出现前一次请求的残余输出拼接到后一次对话中}
  - 验证方式：{Code Review 检查流式循环；手动录屏验证 1s 内停止；日志中检查 cancel 时间戳 vs 停止输出时间戳}

- **安全边界（Keychain/日志/历史）**：
  - requirement 描述：
    - {例：`apiKey` 属性只允许通过 `KeychainHelper.string(forKey: kApiKeyKey)` 读取，禁止在其他属性/单例中缓存明文}
    - {例：全局 grep 禁止出现 `print(apiKey)` / `Logger("\(apiKey)")` / `UserDefaults.standard.set(apiKey, forKey: ...)`}
    - {例：聊天历史落盘时，如消息对象中意外携带敏感字段，必须在 encode 前剔除（ CodingKeys 白名单）}
  - 验证方式：{全项目正则 grep `apiKey.*print\|Logger.*apiKey\|UserDefaults.*apiKey`；断点检查 UserDefaults plist 文件内容}

## 方案（在哪里改、怎么改 · 按优先级）
> 📌 **填写规则**：每个改动点必须标注 P0/P1/P2 + 依赖关系。改动点数量应与 implementation-check  Checklist 项数**严格相等**，对账时缺一项即算遗漏。

### 依赖项（先满足再动工）
- 前置改动：{如无则填"无"；例：RQ-20260801-002 KeychainHelper 重构完成并合入 main}
- KB 必读：{例：knowledge/main/cancellation.md 第 3 节 Swift Concurrency 取消陷阱}

---

- 🟥 **改动点 1（P0）**：{一句话描述，例：在 OllamaManager.streamChat() 流式循环中增加 Task.isCancelled 检查}
  - 位置（文件/类型/函数/行号范围）：OllamaApp/OllamaApp/OllamaManager.swift / OllamaManager / streamChat() / L120-L167
  - 行为（入参 → 处理 → 出参/副作用，精确到语句级别）：
    - 入参不变；在 `for try await line in ...` 循环体开头插入 `guard !Task.isCancelled else { break }`
    - 循环 break 后追加 `try? decoder.finishDecoding()` 收尾，防止 JSON 解析残留
  - 依赖：{无 / 改动点 N}
  - 替代方案与弃用原因：{例：方案 B：用 withCancellationHandler → 弃用：与现有 TaskGroup 结构冲突，引入额外锁开销}

- 🟥 **改动点 2（P0）**：{...}
  - ...

- 🟧 **改动点 3（P1）**：{...}
  - ...

- 🟩 **改动点 4（P2）**：{...}
  - ...

## 验收标准（Acceptance · 可量化 · 可自动化）
> ⚖️ **填写要求**：每条必须包含**触发条件 + 可观测结果 + 量化阈值**。禁止"正常运行"、"体验良好"等不可测描述。
> 对应对账节：implementation-check.md「验收标准对账」

### 功能验收（P0=必须全过，P1=至少 80%）
1. {触发条件：用户输入 "Hello" 选择 llama3 模型点击发送}
   → {可观测：100ms 内首字流式输出，完整响应与 curl 命令行调用结果逐字一致}
   → {阈值：首字延迟 < 200ms，内容差异率 = 0%}
2. {...}

### 异常验收（P0 全覆盖）
1. {触发条件：Ollama 服务未启动时发起请求}
   → {可观测：弹出友好错误 "无法连接本地模型服务 (127.0.0.1:11434)"，不崩溃，isGenerating 3s 内归位 false}
   → {阈值：无 crash，错误信息包含 IP 和端口}
2. {触发条件：API Key 为空（云端模型）发起请求}
   → {可观测：跳转到设置页并高亮 API Key 输入框，错误 Toast 不泄露任何 Key 片段}

### 取消验收（**P0 · 零容忍**）
1. {触发条件：流式输出进行到第 50% 时点击 stop}
   → {可观测：输出停止 + isGenerating = false + 可立即发起下一次请求 + 无 "cancelled" 未处理崩溃}
   → {阈值：从 stop 点击到停止输出 ≤ 1000ms（真机），连续 10 次无状态卡住}
2. {触发条件：App 进入后台自动触发 cancel（didEnterBackground）}
   → {可观测：流式任务被取消，回到前台不继续吐旧内容}

### 历史一致性验收
1. {触发条件：流式输出中途被取消 → kill App → 重启}
   → {可观测：历史列表中该条消息显示为 "(已中断)"，已输出的文本完整保留，无空白消息或崩溃}
   → {阈值：JSON 序列化/反序列化无字段丢失，10 次重启恢复成功率 = 100%}
2. {触发条件：升级安装（旧版本存在历史数据）→ 首次启动}
   → {可观测：旧历史全部可见，无 nil 字段导致的 SwiftUI 崩溃}

## 手工验证步骤（最小回归 · 可执行）
> 🧪 **要求**：每个场景包含前置条件 + 步骤 + 预期结果。合入前必须至少执行一次并在 implementation-check 中记录 PASS/FAIL。

- **场景 1：正常流式对话 + 中途停止（P0 主路径）**
  - 前置条件：Mac 端 Ollama 已启动，llama3 模型已 pull，模拟器已配置 127.0.0.1
  - 步骤：
    1. 打开 App 输入 "写一首 100 行的诗"，点击发送
    2. 输出到第 20 行左右点击 ■ Stop 按钮
    3. 观察按钮状态后立刻再次点击发送新消息
  - 预期结果：
    1. Stop 点击后 1s 内停止输出
    2. Stop 按钮变回发送可用态（isGenerating=false）
    3. 第二次新消息能正常流式输出，无第一次残余内容

- **场景 2：弱网/断网异常恢复**
  - 前置条件：...
  - 步骤：...
  - 预期结果：...

---

## 风险与回滚（含触发条件 + 验证）
> 🚨 **填写规则**：每条风险必须有等级 + 触发条件 + 可观测信号 + 回滚操作 + 回滚验证方法。

| # | 风险描述 | 等级（🟢低/🟡中/🔴高） | 触发条件 | 可观测信号 | 回滚策略 | 回滚验证 |
|---|---------|---------------------|---------|-----------|---------|---------|
| 1 | 取消逻辑改动导致流式循环死锁，主线程卡死 | 🔴高 | 取消 + 并发点击 start 3 次以上 | Xcode 面板显示主线程 blocked，FPS 掉到 0 | 回滚 OllamaManager.swift 中 streamChat() 到上一版本（commit hash 记在合入 commit message） | 回滚后连续发 5 条长消息均能正常完成 |
| 2 | Keychain 迁移导致老用户 API Key 丢失 | 🟡中 | 从 1.0 升级安装到 1.1 | 设置页 API Key 输入框为空 | 回滚 KeychainHelper 迁移逻辑，恢复读取旧 Key 名 | 回滚后升级安装 API Key 自动恢复显示（非空） |
| 3 | ... | ... | ... | ... | ... | ... |

### 自动回滚触发器（CI 门禁）
- {例：单元测试 `testCancellationStopsWithin1Second` 失败 → 自动标记 PR BLOCKED，禁止合入}
- {例：grep 扫描到 `UserDefaults.*apiKey` → 自动打回修改}

---

## 关联知识（KB · 防止重复踩坑）
> 🔗 编码前必须阅读以下 KB，确认本需求不违反既有沉淀：
- knowledge/INDEX.md（总入口 + ROUTING）
- knowledge/main/networking.md（模拟器网络/ATS 约束）
- knowledge/main/cancellation.md（Swift Concurrency 取消 5 条陷阱）
- knowledge/main/security-config.md（Keychain 存储边界 + 日志脱敏）
- knowledge/applications/{具体业务模块}.md（如有）

---

## Review 签字门禁（人工审核触发条件）
> 🛡️ 以下情况**必须人工 Review**，禁止 AI 自闭环：
- [ ] 涉及 Keychain/Crypto 等安全边界变更
- [ ] 涉及 Swift Concurrency Task/AsyncStream 重构（取消语义变更）
- [ ] 涉及 C++/ObjC/Swift 桥接或 Runtime Swizzle
- [ ] 改动文件数 > 5 个 或 改动行数 > 200 行
- [ ] 存在 🟡 及以上兼容性风险

AI 必须在 coding 前判断本需求是否命中以上条件，如是则在 owner/reviewer 字段明确标注等待人工 Review。