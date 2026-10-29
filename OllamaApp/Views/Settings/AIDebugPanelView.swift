import SwiftUI

struct AIDebugPanelView: View {
    let provider: LLMProvider
    @ObservedObject var manager: OllamaManager
    var memory: any MemoryServicing = MemoryService.shared
    var evaluationRunner = AIEvaluationRunner()
    @Environment(\.dismiss) private var dismiss
    @State private var memoryItems: [MemoryItem] = []
    @State private var evaluationResults: [AIEvaluationResult] = []
    @State private var isRunningEvaluation = false

    var body: some View {
        NavigationStack {
            List {
                Section("Runtime") {
                    keyValueRow("Provider", provider.displayName)
                    keyValueRow("Generating", manager.isGenerating ? "Yes" : "No")
                    keyValueRow("Current Session", manager.currentSessionId ?? "None")
                    keyValueRow("Message Count", "\(manager.messages.count)")
                }

                Section("Memory Store (RAG)") {
                    keyValueRow("Enabled", AIMemorySettings.isEnabled ? "Yes" : "No")
                    keyValueRow("Embedding Model", AIEmbeddingModel.configured)
                    keyValueRow("Total Items", "\(memoryItems.count)")

                    if memoryItems.isEmpty {
                        Text("No memories stored yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(memoryItems) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.text)
                                    .font(.body)
                                    .textSelection(.enabled)
                                Text(item.createdAt.formatted(date: .abbreviated, time: .standard))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    Button("清空记忆库", role: .destructive) {
                        memory.clearMemories()
                        reloadMemoryItems()
                    }
                    .disabled(memoryItems.isEmpty)
                }

                Section("Evaluation") {
                    keyValueRow("Model", evaluationModel)
                    keyValueRow("Memory Seed", isMemorySeedReady ? "Ready" : "Missing")

                    if !isMemorySeedReady {
                        Text("记忆库为空，Memory 类评测会因前置条件不满足而失败。请先写入如“我叫小芳 我是浙江人”这类事实型记忆，再运行内建评测。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button(isRunningEvaluation ? "评测运行中..." : "运行内建评测") {
                        Task { await runBuiltInEvaluations() }
                    }
                    .disabled(isRunningEvaluation)

                    if isRunningEvaluation {
                        ProgressView()
                    }

                    if !evaluationResults.isEmpty {
                        keyValueRow("Pass Rate", "\(passedEvaluationCount) / \(evaluationResults.count)")
                        ForEach(evaluationResults) { result in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.title)
                                    .font(.body.weight(.medium))
                                Text(result.isPassed ? "Passed" : "Failed")
                                    .font(.caption)
                                    .foregroundStyle(result.isPassed ? .green : .red)
                                if let memoryHitCount = result.memoryHitCount {
                                    Text("Memory Hits: \(memoryHitCount)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let durationMs = result.durationMs {
                                    Text("Duration: \(durationMs) ms")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if !result.failures.isEmpty {
                                    Text(result.failures.joined(separator: "\n"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                if let snapshot = manager.latestDebugSnapshot {
                    Section("Request") {
                        keyValueRow("Request ID", snapshot.requestID.uuidString)
                        keyValueRow("Status", snapshot.status.rawValue)
                        keyValueRow("Entry Provider", snapshot.entryProvider.rawValue)
                        keyValueRow("Resolved Provider", snapshot.resolvedProvider?.rawValue ?? "Pending")
                        keyValueRow("Fallback Provider", snapshot.fallbackProvider?.rawValue ?? "None")
                        keyValueRow("Route Policy", snapshot.routePolicySummary)
                        keyValueRow("Model", snapshot.model)
                        keyValueRow("Template", snapshot.promptTemplateID.rawValue)
                        keyValueRow("Scene", snapshot.promptScene.rawValue)
                        keyValueRow("Module", snapshot.promptModule)
                        keyValueRow("Output Format", snapshot.outputFormat.rawValue)
                        keyValueRow("Web Enabled", snapshot.webEnabled ? "Yes" : "No")
                        keyValueRow("Retry", "\(snapshot.retryCount) / \(snapshot.retryLimit)")
                        keyValueRow("Fallback Used", snapshot.fallbackUsed ? "Yes" : "No")
                        keyValueRow("Prompt", snapshot.promptPreview.isEmpty ? "Empty" : snapshot.promptPreview)
                    }

                    Section("Performance") {
                        keyValueRow("Duration", formatMs(snapshot.durationMs))
                        keyValueRow("First Token", formatMs(snapshot.firstTokenLatencyMs))
                        keyValueRow("Updated At", snapshot.updatedAt.formatted(date: .omitted, time: .standard))
                    }

                    if let usage = snapshot.usage {
                        Section("Usage") {
                            keyValueRow("Input Characters", formatInt(usage.inputCharacters))
                            keyValueRow("Output Characters", "\(usage.outputCharacters)")
                            keyValueRow("Total Characters", formatInt(usage.totalCharacters))
                            keyValueRow("Input Tokens", formatInt(usage.inputTokens))
                            keyValueRow("Output Tokens", formatInt(usage.outputTokens))
                            keyValueRow("Total Tokens", formatInt(usage.totalTokens))
                            keyValueRow("Estimated Cost", formatCurrency(usage.estimatedCost))
                        }
                    }
                    

                    if let memoryHitCount = snapshot.memoryHitCount {
                        Section("Memory (RAG)") {
                            keyValueRow("Recalled Items", "\(memoryHitCount)")
                            if let preview = snapshot.memoryPreview, !preview.isEmpty {
                                keyValueRow("Preview", preview)
                            }
                        }
                    }

                    if snapshot.status == .failed || snapshot.errorMessage != nil {
                        Section("Error") {
                            keyValueRow("Code", snapshot.errorCode?.rawValue ?? "Unknown")
                            keyValueRow("Message", snapshot.errorMessage ?? "None")
                        }
                    }
                } else {
                    Section("Debug Snapshot") {
                        Text("No generation snapshot yet.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("AI Debug")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                reloadMemoryItems()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func keyValueRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    private func formatInt(_ value: Int?) -> String {
        guard let value else { return "N/A" }
        return "\(value)"
    }

    private func formatMs(_ value: Int?) -> String {
        guard let value else { return "N/A" }
        return "\(value) ms"
    }

    private func formatCurrency(_ value: Double?) -> String {
        guard let value else { return "N/A" }
        return String(format: "$%.6f", value)
    }

    private var evaluationModel: String {
        manager.latestDebugSnapshot?.model ?? provider.defaultModel
    }

    private var passedEvaluationCount: Int {
        evaluationResults.filter(\.isPassed).count
    }

    private var isMemorySeedReady: Bool {
        !memoryItems.isEmpty
    }

    private func runBuiltInEvaluations() async {
        isRunningEvaluation = true
        defer { isRunningEvaluation = false }
        evaluationResults = await evaluationRunner.runBuiltInCases(provider: provider, model: evaluationModel)
    }

    private func reloadMemoryItems() {
        memoryItems = memory.items().sorted { $0.createdAt > $1.createdAt }
    }
}
