import SwiftUI

struct AIDebugPanelView: View {
    let provider: LLMProvider
    @ObservedObject var manager: OllamaManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Runtime") {
                    keyValueRow("Provider", provider.displayName)
                    keyValueRow("Generating", manager.isGenerating ? "Yes" : "No")
                    keyValueRow("Current Session", manager.currentSessionId ?? "None")
                    keyValueRow("Message Count", "\(manager.messages.count)")
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
}
