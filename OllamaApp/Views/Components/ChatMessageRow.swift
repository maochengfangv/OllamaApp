import SwiftUI
import UIKit
import Foundation

struct ChatMessageRow: View {
    let message: ChatMessage
    let isGenerating: Bool
    let isStreaming: Bool
    let onResend: (() -> Void)?
    @State private var didCopy: Bool = false

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
                HStack(spacing: 4) {
                    Circle().frame(width: 6, height: 6).opacity(0.4)
                    Circle().frame(width: 6, height: 6).opacity(0.7)
                    Circle().frame(width: 6, height: 6).opacity(1.0)
                }
                .padding(12)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                VStack(alignment: .leading, spacing: 8) {
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
    private func messageText(foreground: Color) -> some View {
        if message.role == .model, isStreaming {
            Text(message.content)
                .foregroundColor(foreground)
                .textSelection(.enabled)
        } else if let attributed = try? AttributedString(
            markdown: message.content,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        ) {
            Text(attributed)
                .foregroundColor(foreground)
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
