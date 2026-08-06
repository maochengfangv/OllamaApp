---
# ============================================================
# 需求状态模板（每个 RQ-* 目录内各存一份）
# 命名目录建议：rd/requirements/RQ-YYYYMMDD-{slug}/status.md
# ============================================================
---

id: RQ-YYYYMMDD-{slug}          # 全局唯一，与目录名保持一致
title: "{需求标题一句话}"
owner: "{负责人姓名或多人逗号分隔}"
stage: Draft                    # Draft / Clarified / Analyzed / Implementing / Validated / Released / Backfilled
updatedAt: YYYY-MM-DD HH:mm     # 每次推进阶段或改动阻塞项时更新

# 外部工单关联（可选但强烈建议）
externalId: ""                  # JIRA-1234 / FEISHU-5678 / GH-ISSUE-90 / 其它看板ID

# 代码分支与 PR
baseBranch: main                # 基线分支
branch: ""                      # feature/RQ-YYYYMMDD-{slug}
pr: ""                         # PR 链接或编号
commit: ""                     # 当前已验证到的 commit hash（可选）

# 模块影响范围（与 requirement.md touchFiles 保持一致或更粗即可）
modules:
  - ui                          # ContentView / 设置页 / 消息列表 / 交互态
  - llm-core                    # OllamaManager：generate / stop / resend / provider
  - networking                  # 127.0.0.1 / ATS / DeepSeek BaseURL 兼容
  - security                    # Keychain / API Key / 日志脱敏
  - storage                     # 历史记录 / UserDefaults / 后续文件存储迁移
  - knowledge                   # 本次会改动或新增 KB 条目

# 关联文件（最小原则，写关键入口，避免和 requirement 完全重复）
touchFiles:
  - OllamaApp/OllamaApp/ContentView.swift
  - OllamaApp/OllamaApp/OllamaManager.swift

# 依赖 / 冲突（和 requirement.md 保持一致，但此处用于全局 REGISTRY 聚合更快读）
dependsOn: []                   # ["RQ-20260805-xxx"]
conflictsWith: []               # ["RQ-20260810-xxx"]

# 质量门禁通过情况（门禁 = 阶段转换的条件）
gates:
  verifyPrd: N/A                # N/A / TODO / PASS / BLOCKED  （对 /rd:verify-prd）
  clarifyReview: N/A            # （对 clarify review：阻塞问题和业务口径确认）
  analysisReview: N/A           # （对 analysis/routing review：应用边界/影响范围）
  verifyRequirement: N/A        # （对 /rd:verify-requirement：编码前契约确认）
  designReview: N/A             # （对方案 review：扩展点/架构路径/兼容策略）
  validate: N/A                 # （对 /rd:validate：requirement 与 diff 对账）
  codeReview: N/A               # （对 /rd:code-review：发布前质量和一致性）
  releasePlan: N/A              # （对 /rd:release-plan：灰度/回滚/观测确认）
  knowledgeBackfill: N/A        # （对 knowledge backfill：稳定经验回补）

# 阻塞项（未清则不允许进入下一阶段；禁止 merge）
blockers:
  - status: open                # open / done / canceled
    stage: Implementing         # 阻塞发生在哪个阶段
    owner: ""
    summary: "{一句话说明阻塞}"
    due: YYYY-MM-DD             # 期望解决时间
    evidence: ""                # 证据：会议纪要/链接/代码位置

# 知识库回补计划（发布后 2 周内应完成 Backfilled，或写 Skipped + 原因）
backfill:
  plan: []                      # ["knowledge/main/cancellation.md", "knowledge/applications/llm-core.md"]
  skipped: false                # true 时必须写 reason
  reason: ""

---

# Status：{title}

## 一句话进度（写在看板里也能一眼看懂）
- 一句话：

## 阶段推进记录（每次阶段变更加一行，防扯皮）
| 时间 | 阶段 | 操作人 | 说明 |
|---|---|---|---|
| YYYY-MM-DD HH:mm | Draft | owner | 创建需求 |
| YYYY-MM-DD HH:mm | Clarified | owner | clarify 通过，阻塞项 0 个 |

## 关联产物目录（同目录下必须存在）
- [requirement.md](./requirement.md)
- [implementation-check.md](./implementation-check.md)
- [continue-prompt.md](./continue-prompt.md)
