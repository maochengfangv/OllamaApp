---
requirementId: RQ-YYYYMMDD-XXX
status: IN_PROGRESS | DONE | BLOCKED
owner: {yourName}
validatedAt: YYYY-MM-DD HH:MM
updatedAt: YYYY-MM-DD HH:MM
---

# Implementation Check（需求对账）

## 对账结论（维度评分矩阵）
> 目的：一眼看出哪条腿瘸了，避免"功能 done 但取消 broken"的假阳性

| 维度 | 状态（todo/partial/done/blocked） | 备注 |
|------|----------------------------------|------|
| overall（综合） | todo | 取维度中最差状态 |
| 功能正确性 | todo | 是否满足 requirement 目标 |
| 取消语义收敛 | todo | **P0 硬门禁**：stop 后 Task 取消 + isGenerating 归位 |
| 安全边界合规 | todo | **P0 硬门禁**：Keychain 存储 + 无日志泄露 |
| 异常路径覆盖 | todo | 网络错误/超时/模型不存在等分支 |
| 历史落盘一致 | todo | 聊天记录序列化/反序列化无破损 |
| 网络策略正确 | todo | 模拟器 127.0.0.1 / ATS 配置 |

- blocked items（具体阻塞点 + 需要谁介入）：
  - 

---

## P0 关键约束对账（硬门禁，必须全 done）
> 与 requirement.md 关键约束节一一对应

- [ ] 网络/ATS/127.0.0.1 约束
  - requirement 原文：{摘抄 requirement.md:24}
  - 代码位置：{file}#{type/function}
  - 状态：todo | partial | done | changed | blocked
  - 证据：{diff片段 / Info.plist 配置截图 / 真机局域网连通记录}

- [ ] 取消语义（stop 后收敛）
  - requirement 原文：{摘抄 requirement.md:25}
  - 代码位置：{file}#{流式循环处 / stop 按钮处理处}
  - 状态：todo | partial | done | changed | blocked
  - 证据：{流式循环内 Task.isCancelled 检查 diff；stop 触发 cancel 后 isGenerating 归位的日志/截图}

- [ ] 安全边界（Keychain/日志/历史）
  - requirement 原文：{摘抄 requirement.md:26}
  - 代码位置：{Keychain 读写处 / 所有 print/Logger 调用点}
  - 状态：todo | partial | done | changed | blocked
  - 证据：{Keychain 查询 API 调用 diff；grep 日志确认无 API Key / Secret 输出}

---

## Checklist（逐条对照 requirement 方案节）
> 与 requirement.md 改动点一一对应，不可遗漏

- [ ] 改动点 1：{摘抄 requirement.md:29-31}
  - requirement 原文：{文件/类型/函数 + 行为描述}
  - 代码位置：{file}#{type/function}
  - 状态：todo | partial | done | changed | blocked
  - 变更摘要：{改了什么，为何调整了需求（changed 必须填原因）}
  - 证据：{diff / 运行截图 / 单元测试通过记录}

- [ ] 改动点 2：{摘抄 requirement.md:32+}
  - ...

---

## 验收标准对账（Acceptance Mapping）
> 与 requirement.md:34-38 四类验收标准双向映射

### 功能验收
| requirement 验收项 | 实现状态 | 验证证据 |
|-------------------|---------|---------|
| {摘抄 requirement 功能项 1} | todo / partial / done | 截图/日志 |
| ... | ... | ... |

### 异常验收
| requirement 验收项 | 实现状态 | 验证证据 |
|-------------------|---------|---------|
| {摘抄 requirement 异常项 1} | todo / partial / done | 错误弹窗截图 / 降级路径日志 |

### 取消验收（**P0**）
| requirement 验收项 | 实现状态 | 验证证据 |
|-------------------|---------|---------|
| 流式输出中点击 stop → 1s 内停止输出 | todo / partial / done | 录屏 / 日志时间戳 |
| stop 后 isGenerating → false，可再次发起请求 | todo / partial / done | 状态机截图 |
| Task 资源释放（无内存泄漏） | todo / partial / done | Instruments 截图 / cancel 回调日志 |

### 历史一致性验收
| requirement 验收项 | 实现状态 | 验证证据 |
|-------------------|---------|---------|
| 重启后历史记录可恢复，字段无缺失 | todo / partial / done | 重启前后对比截图 |
| 中断中的消息（取消/异常）落盘状态正确 | todo / partial / done | 中途 kill app 后恢复验证 |

---

## 手工验证结果（最小回归报告）
> 与 requirement.md:40-42 手工验证步骤对应，必须附结果

| 场景 | 步骤 | 预期结果 | 实际结果 | 结论（PASS/FAIL） | 证据 |
|------|------|---------|---------|-----------------|------|
| 场景 1：{摘抄 requirement} | 1. xxx 2. xxx | ... | ... | PASS/FAIL | 截图/录屏 |
| 场景 2：{摘抄 requirement} | ... | ... | ... | ... | ... |

---

## 风险与回滚核对
| requirement 风险项 | 是否实际发生 | 处理方式 | 回滚策略是否奏效 |
|-------------------|-------------|---------|---------------|
| {摘抄 requirement.md:45 风险 1} | 是/否 | {处理记录} | N/A / 奏效 / 未奏效 |

---

## 改动追溯清单（Code Review 入口）
> 帮 reviewer 快速定位，按文件聚合

| 文件 | 改动行数 | 涉及改动点 | 关键函数/行号 |
|------|---------|-----------|-------------|
| OllamaManager.swift | +32/-8 | 改动点 1, 改动点 2 | `streamChat():120-167`, `stopGenerate():189-195` |
| ContentView.swift | +15/-3 | 改动点 3 | `StopButton:45-52` |

---

## Validate 结论（门禁结果）
- [ ] `/rd:validate` 对账：requirement 方案节无遗漏项
- [ ] P0 关键约束：全部 done（取消语义 + 安全边界 + 网络约束）
- [ ] 异常路径：无 P0 级遗漏
- [ ] 手工回归：全 PASS
- 最终 verdict：**PASS（可合入）** / **FAIL（阻塞合入）**