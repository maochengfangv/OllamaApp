import SwiftUI
import UIKit
import Foundation

struct ChatMessageRow: View {
    let message: ChatMessage
    let isGenerating: Bool
    let isStreaming: Bool
    let onResend: (() -> Void)?
    @State private var didCopy: Bool = false
    @State private var isReasoningExpanded: Bool = false

    private var hasReasoning: Bool {
        guard let reasoning = message.reasoningContent else { return false }
        return !reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 50)
                bubble(background: Color.blue, foreground: .white)
                    .contextMenu {
                        if let onResend {
                            Button("重新发送", action: onResend)
                                .disabled(isGenerating)
                        }
                    }
            } else {
                bubble(background: Color.gray.opacity(0.15), foreground: .primary)
                Spacer(minLength: 50)
            }
        }
    }

    private func bubble(background: Color, foreground: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if message.role == .model, message.content.isEmpty, isGenerating {
                VStack(alignment: .leading, spacing: 8) {
                    if hasReasoning {
                        reasoningSection(foreground: foreground)
                    }
                    HStack(spacing: 4) {
                        Circle().frame(width: 6, height: 6).opacity(0.4)
                        Circle().frame(width: 6, height: 6).opacity(0.7)
                        Circle().frame(width: 6, height: 6).opacity(1.0)
                    }
                }
                .padding(12)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    reasoningSection(foreground: foreground)
                    messageText(foreground: foreground)

                    HStack {
                        Spacer()
                        Button(action: copyToClipboard) {
                            HStack(spacing: 6) {
                                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                                Text(didCopy ? "已复制" : "复制")
                            }
                            .font(.caption)
                            .foregroundColor(foreground.opacity(0.85))
                        }
                        .disabled(message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(12)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    @ViewBuilder
    private func reasoningSection(foreground: Color) -> some View {
        if message.role == .model,
           let reasoning = message.reasoningContent,
           !reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isReasoningExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isReasoningExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                        Text(isStreaming ? "思考中…" : "思考过程")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(foreground.opacity(0.7))
                }
                .buttonStyle(.plain)

                if isReasoningExpanded {
                    MarkdownBlockView(text: reasoning, foreground: foreground.opacity(0.7))
                        .font(.footnote)
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(foreground.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.bottom, 2)
        }
    }

    @ViewBuilder
    private func messageText(foreground: Color) -> some View {
        if message.role == .model, isStreaming {
            Text(message.content)
                .foregroundColor(foreground)
                .textSelection(.enabled)
        } else if message.role == .model {
            MarkdownBlockView(text: message.content, foreground: foreground)
                .textSelection(.enabled)
        } else {
            Text(message.content)
                .foregroundColor(foreground)
                .textSelection(.enabled)
        }
    }

    private func copyToClipboard() {
        UIPasteboard.general.string = message.content
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            didCopy = false
        }
    }
}
