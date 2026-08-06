---
requirementId: RQ-YYYYMMDD-XXX
status: IN_PROGRESS | BLOCKED | NEED_REVIEW
owner: {yourName}
lastSessionId: {上次对话 session ID，用于回溯上下文}
lastCommitHash: {本地未合入临时改动的 commit 或 diff 锚点}
codeCheckpointAt: YYYY-MM-DD HH:MM（代码快照时间，接续前先确认关键文件 hash 未变）
updatedAt: YYYY-MM-DD HH:MM
---

# Continue Prompt（AI 接续开发最小上下文 + 防改偏门禁）

> 🎯 **目标读者**：下一次接手的 AI Agent（或跨天接续的自己）。
>
> 🔒 **使用规则**：新 AI 必须先完整阅读本文档，再动代码。未通过「接续后第一件事」检查清单，禁止写任何代码。
>
> 🔗 **三表闭环契约**：本文档 ↔ requirement.md ↔ implementation-check.md 通过 requirementId 绑定；任务完成定义必须同时回写 implementation-check 对应行。
>
> ⚠️ **增量变更边界**：本次接续允许改动的文件清单见下方「必读上下文 → 代码入口」，超出范围的改动必须先回到 requirement.md 增补影响范围和改动点，否则视为 AI 越界。

## 接续状态快照（精准对齐 requirement 改动点）
> 📌 **填写规则**：每一条完成/未完成项必须绑定 requirement.md「方案」节的改动点编号（例：改动点 2），以及 implementation-check.md 对应 Checklist 行号。

### ✅ 已完成项（附实现锚点）
| 序号 | 对应 requirement 改动点 | 简述 | 代码锚点（文件/函数/行号） | implementation-check 勾稽行 | 验证状态（单测/截图/commit） |
|------|------------------------|------|--------------------------|---------------------------|-----------------------------|
| 1 | 改动点 1（P0） | 流式循环增加 Task.isCancelled 检查 | OllamaManager.swift:120-167 / streamChat() → L132 | Checklist 改动点 1 行 | ✅ 单测 testStreamLoopCancellation PASS |
| 2 | 改动点 X（P1） | ... | ... | ... | ... |

### ⏳ 未完成项（按优先级排序 + 状态百分比）
| 序号 | 对应 requirement 改动点 | 简述 | 已完成进度 | 未完成原因 / 接续入口 | DoD（完成定义） |
|------|------------------------|------|-----------|---------------------|----------------|
| 1 | 🟥 改动点 2（P0） | stopGenerate() 触发 cancel + isGenerating 同步归位 | 30%（cancel 已写，isGenerating 归位逻辑缺） | OllamaManager.swift:189-195 / stopGenerate() 函数末尾 | 点击 stop → 1s 内 isGenerating=false，可立即重发请求（10 次连续无卡住） |
| 2 | 🟧 改动点 3（P1） | ... | ... | ... | ... |

### 🚧 阻塞点（必须有人拍板，AI 禁止自行决策）
| # | 阻塞描述 | 等谁（Owner / PM / Reviewer） | 等待什么决策 | 超时兜底方案（例：24h 无回复走默认方案 A） |
|---|---------|-------------------------------|-------------|------------------------------------------|
| 1 | 取消后历史记录的状态文案是「已中断」还是「(已停止)」，产品未定稿 | @Owner 张三 | 确认 UI 文案 | 24h 无回复先默认「(已中断)」，留 TODO 等上线前替换 |

### 🔧 已知临时 Workaround（新 AI 必须优先清理）
| # | Workaround 描述 | 文件/行号 | 清理触发条件 | 清理后要做的回归 |
|---|----------------|-----------|-------------|----------------|
| 1 | 为了先跑通取消流程，临时在 ContentView 用 `DispatchQueue.main.asyncAfter(deadline: .now()+2)` 硬编码归位 isGenerating | ContentView.swift:48-51 | 等改动点 2 的 stopGenerate() 同步归位逻辑写完 | 删除临时代码后跑 10 次连续 stop/start，无状态卡住 |

### 🏗️ 当前构建状态（接续前先拉平到这个状态）
- 编译：✅ PASS / ❌ FAIL（如 FAIL，注明最后一次可编译的 commit：`abc123`）
- 单元测试：X/Y 通过（失败用例：`testApiKeyNotInUserDefaults` → 原因：未实现）
- 已知崩溃点：例 → 进入设置页快速切换模型 3 次 → EXC_BAD_ACCESS（回溯栈：OllamaManager.swift:234）
- 本地未提交改动：git status 输出摘要（例：M OllamaManager.swift M ContentView.swift）

## 最小阅读集合（只看这些，不要瞎翻整项目）
> ⏱️ 目标：让新 AI 在 3 分钟内进入状态，禁止阅读无关文件。

### 📄 RD 三件套（必须按顺序读）
1. **Requirement**：`{path-to-requirement.md}`
   - 重点读：关键约束（P0）节、方案改动点 2/3、验收标准-取消验收
   - 跳过：P2 改动点、风险里的低概率项
2. **Implementation Check（已完成部分）**：`{path-to-implementation-check.md}`
   - 重点读：Checklist 已打勾的项、P0 关键约束对账 → 取消语义（已 done 33%）
   - 不要覆盖已 done 项的代码！
3. **Continue Prompt（即本文）**：接续状态快照 + 下一步执行计划

### 📚 KB（只列与未完成任务直接相关的章节，非全量）
- knowledge/main/cancellation.md → 第 3 节「Swift Concurrency 取消的 5 个陷阱」（重点：不要在 Task 外读取 Task.isCancelled）
- knowledge/main/security-config.md → 第 2 节「Keychain 存储 vs UserDefaults 的边界」
- 跳过：networking.md（本次接续不涉及网络配置变更）

### 💻 代码入口（精确到函数 + 读这个文件看什么）
| 文件路径 | 精确锚点（函数/行号范围） | 阅读目的（新 AI 看完要懂什么） | 本次允许改动？（是/否/仅清理 TODO） |
|---------|--------------------------|-------------------------------|----------------------------------|
| OllamaApp/OllamaApp/OllamaManager.swift | `stopGenerate():189-195` + `streamChat():120-167`（L132 是已加的 isCancelled 检查） | 理解改动点 1 的实现方式，stopGenerate 里缺的 isGenerating 赋值逻辑 | ✅ 是 |
| OllamaApp/OllamaApp/ContentView.swift | `StopButton 动作绑定:45-52`（L48-51 是要清理的 Workaround） | 理解 stop 按钮如何调用 stopGenerate，清理临时代码 | ⚠️ 仅清理 TODO，不能改按钮样式 |
| OllamaApp/OllamaApp/KeychainHelper.swift | 不动 | 本次接续不涉及 Keychain 改造 | ❌ 否（越界） |
| OllamaApp/OllamaApp/Info.plist | 不动 | 本次接续不涉及 ATS 配置 | ❌ 否（越界） |

### 📌 遗留 TODO / FIXME 锚点（新 AI 动代码前先 grep 一遍）
```
// TODO(CONTINUE-20260806): 删除 ContentView.swift:48-51 硬编码的 asyncAfter，改用 stopGenerate 同步归位
// FIXME(CONTINUE-20260806): testApiKeyNotInUserDefaults 用例跳过，等 Keychain 改造完启用
```
> grep 命令：`grep -rn 'CONTINUE-20260806' OllamaApp/`
> 新 AI 必须先处理完这些遗留标记，再写新功能。

## 接续硬约束（不可越界 · 直接同步 requirement P0）
> 🛡️ **AI 禁止清单**：下一条违反，合入时 implementation-check 的 P0 关键约束直接判 BLOCKED。
> 对应 implementation-check「P0 关键约束对账」节，每项完成后必须回打勾。

### 约束 1：取消语义收敛（P0 · requirement.md:25）
- ✅ 必须做：
  - 所有流式循环（`for try await line in ...`）首行保留 `guard !Task.isCancelled else { break }`（AI 禁止删除/注释这条语句！grep 可验）
  - `stopGenerate()` 必须：先 `streamTask?.cancel()` → **同步**（非异步回调）设置 `isGenerating = false` → 返回
- ❌ 禁止操作：
  - 禁止用 `asyncAfter` / Timer 延迟归位 isGenerating（本次接续必须清理 ContentView.swift:48-51 这个 workaround）
  - 禁止在 Task 外部判断 `Task.isCancelled`（结果永远是 false，会导致取消失效）

### 约束 2：安全边界合规（P0 · requirement.md:26）
- ✅ 必须做：
  - apiKey 读取唯一入口：`KeychainHelper.string(forKey: kApiKeyKey)`
  - 新增 Logger/print 时，如涉及配置类对象，先手动走一遍字段脱敏
- ❌ 禁止操作：
  - 禁止 `UserDefaults.standard.set(apiKey, forKey: ...)`（全项目 grep 可验）
  - 禁止 `Logger("\(apiKey)")` / `print(apiKey)`（全项目 grep 可验）
  - 禁止在 ChatMessage 的 Codable CodingKeys 中包含 apiKey 字段

### 约束 3：历史落盘一致（P1 · requirement.md:38）
- ✅ 必须做：中断的对话消息写入 history 前，必须设置 `status = .interrupted` 枚举值（不能只写纯文本 "已中断"）
- ❌ 禁止操作：禁止改动 ChatMessage 的现有字段名 / JSON 键名（会破坏旧版本历史兼容），必须新增字段走可选解包

### 🚦 增量改动门禁
- 本次接续最多改动 **3 个文件**（OllamaManager.swift、ContentView.swift、{测试文件}）
- 超过上限 → 必须先回到 requirement.md「影响范围」和「方案」节增补，并在 implementation-check 新增 Checklist 行，否则视为 AI 越界改偏

## 接续执行计划（按依赖链排序 · 每步做完先回写对账再继续）
> 🔗 **执行顺序铁律**：必须按 1 → 2 → 3 顺序，每步 DoD 达成后，先回写 implementation-check.md 对应行，再进入下一步。禁止跳步并行。

| 顺序 | 任务名（对应 requirement 改动点） | 前置依赖 | 完成定义（DoD · 可验证） | 完成后必须回写哪些 RD 文件 | 验证动作（自己先跑一遍再交） |
|------|----------------------------------|---------|------------------------|--------------------------|----------------------------|
| 1 | 🧹 清理遗留 Workaround（重要！先做这个） | 无 | 删除 ContentView.swift:48-51 的 asyncAfter 硬编码；grep 无 `CONTINUE-20260806` 遗留 TODO | continue-prompt.md：本任务上方 Workaround 表格第 1 行删除 | 编译通过 + 连续 stop/start 3 次无编译报错 |
| 2 | 🟥 改动点 2：stopGenerate() 同步归位 isGenerating | 任务 1 完成 | OllamaManager.swift:189-195 中，streamTask?.cancel() **紧接一行**写 `isGenerating = false`（不在回调内）；连续 10 次快速 stop+start 无状态卡住 | 1. implementation-check.md → P0 关键约束对账「取消语义」打勾为 done；2. implementation-check.md → Checklist 改动点 2 打勾 done | 1. 跑单测 `testCancellationStopsWithin1Second` PASS；2. 录屏 10 次连续操作存到 evidence/ 目录；3. 代码 grep `Task.isCancelled` ≥ 2 处（流式循环 + 可能的 decode 循环） |
| 3 | 🟧 改动点 3：取消的对话消息落盘为 .interrupted 状态 | 任务 2 完成 | 取消 break 后，组装 ChatMessage 时 `status = .interrupted`；kill App 重启后该条消息显示「(已中断)」而不是空白 | implementation-check.md → Checklist 改动点 3 打勾 + 验收标准对账「历史一致性」项 1 PASS | 手工验证 requirement 场景 1（中途取消→kill→重启）；对比重启前后消息 JSON 无字段缺失 |
| 4 | 🔍 收尾：全量门禁校验 + 对账 | 任务 1-3 done | 1. P0 关键约束 3 项全部 done；2. requirement 改动点 1/2/3 全部打勾；3. 无 grep 命中 `UserDefaults.*apiKey` / `localhost`（模拟器场景） | implementation-check.md → Validate 结论节 5 个 checkbox 全勾，最终 verdict = PASS | 1. 全量单测 X/Y 全部 PASS；2. 跑 `/rd:validate` 对账脚本无报错 |

---

## 接续后第一件事（新 AI 启动检查清单 · 1 分钟搞定）
> ❌ 以下任一项不通过，禁止写任何代码。先修复状态 / 联系 owner。

- [ ] **编译基线**：拉取代码后直接 build，确认 PASS（如果 FAIL，先回退到 `lastCommitHash` 锚点）
- [ ] **关键文件未被篡改**：以下 2 个文件的 hash 与 `codeCheckpointAt` 快照一致，否则有人中途改了代码需要重新对齐
  - OllamaManager.swift: `shasum -a 256 OllamaApp/OllamaApp/OllamaManager.swift`
  - ContentView.swift: `shasum -a 256 OllamaApp/OllamaApp/ContentView.swift`
- [ ] **遗留 TODO 扫描**：`grep -rn 'CONTINUE-20260806' OllamaApp/` 输出数量与本文「遗留 TODO 锚点」节一致（无新增隐藏 TODO）
- [ ] **P0 约束 grep 预检查**：
  - `grep -rn 'UserDefaults.*apiKey' OllamaApp/` → 无结果
  - `grep -rn 'Task.isCancelled' OllamaApp/OllamaManager.swift` → 至少 1 处（流式循环）

---

## 对账回写指引（AI 做完必看）
每完成一个任务，**必须按以下顺序回写 3 份 RD 资产**，不能只改代码：
1. **implementation-check.md**：
   - 对应 Checklist 行打勾 + 状态改 done + 填证据（commit hash / 单测 PASS）
   - 如该任务涉及 P0 关键约束 / 验收标准 / 手工验证，同步回写对应表格行
   - 维度评分矩阵的对应维度从 todo/partial → done
2. **continue-prompt.md（即本文）**：
   - 接续状态快照 → 未完成项表格把该行挪到「已完成项」，补充代码锚点和验证状态
   - 接续执行计划表格 → 已完成的 DoD 行打标记 ✅
3. **requirement.md**：（仅当实际实现偏离方案时才动）
   - 如改动点的「位置/行为」和 requirement 原文不一致 → 更新 requirement 方案节，并在 frontmatter updatedAt 刷新时间 + 状态 = NEED_REVIEW

> ⚠️ 三表不一致（例：代码改了但 implementation-check 没打勾）= 对账失败，下次接续视为未完成，必须返工。