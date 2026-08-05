---
id: KB-MAIN-NETWORKING
type: main
status: OFFICIAL
updatedAt: YYYY-MM-DD
stability: stable
confidence: high
evidence:
  - code: OllamaApp/OllamaApp/OllamaManager.swift (baseURL)
  - code: OllamaApp/OllamaApp/Info.plist (ATS)
---

# Networking / ATS / Simulator vs Device

## AI 使用摘要
- 适用场景：连本地 Ollama、处理网络错误、准备真机联调
- 使用前必须核对：当前 baseURL、端口、是否走代理/隧道、真机网络环境

## 稳定事实（必须遵守）
- 模拟器访问本机服务：优先用 127.0.0.1（避免 localhost 解析到 IPv6 ::1 导致拒绝连接）
- 访问 HTTP（Ollama 默认）：需要 ATS 配置允许（当前项目已开启 NSAllowsArbitraryLoads）

## 当前项目配置（以代码为准）
- Ollama baseURL：OllamaApp/OllamaApp/OllamaManager.swift（baseURL 常量）
- ATS：OllamaApp/OllamaApp/Info.plist（NSAllowsArbitraryLoads = true）

## 真机连接策略（约束）
- 真机无法用 127.0.0.1 访问 Mac 上的 Ollama
- 需要改为：局域网 IP / 端口映射 / 隧道（并记录“选择哪一种、对应 URL”）

## 排障最小路径
- 症状：connection refused / timeout / 非 200
- 检查顺序：
  1) Ollama 是否在跑、端口是否 11434
  2) URL 是否可达（模拟器/真机分别验证）
  3) ATS 是否被收紧（如果未来改为白名单）
  4) 返回码与 error body（Ollama 非 200 会拼接 Details）