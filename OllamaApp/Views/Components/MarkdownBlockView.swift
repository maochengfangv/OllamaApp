//
//  MarkdownBlockView.swift
//  OllamaApp
//
//  Created by maochengfang on 2026/10/28.
//

import SwiftUI

struct MarkdownBlockView: View {
    let text: String
    let foreground: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    private enum Block {
        case blank
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullet(level: Int, marker: String, text: String)
        case quote(String)
    }

    private var blocks: [Block] {
        text.components(separatedBy: .newlines).map(parse)
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .blank:
            Color.clear.frame(height: 4)
        case .heading(let level, let content):
            inline(content)
                .font(level <= 2 ? .headline : .subheadline)
                .foregroundColor(foreground)
        case .paragraph(let content):
            inline(content)
                .font(.body)
                .foregroundColor(foreground)
        case .bullet(let level, let marker, let content):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(marker)
                    .font(.body)
                    .foregroundColor(foreground)
                inline(content)
                    .font(.body)
                    .foregroundColor(foreground)
            }
            .padding(.leading, CGFloat(min(level, 3)) * 14)
        case .quote(let content):
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(foreground.opacity(0.3))
                    .frame(width: 3)
                inline(content)
                    .font(.body)
                    .foregroundColor(foreground.opacity(0.85))
            }
        }
    }

    private func inline(_ raw: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: raw,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(raw)
    }

    private func parse(_ line: String) -> Block {
        let indent = line.prefix(while: { $0 == " " }).count
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty { return .blank }

        if trimmed.hasPrefix("#") {
            let level = trimmed.prefix(while: { $0 == "#" }).count
            let content = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            return .heading(level: level, text: content)
        }

        if trimmed.hasPrefix("> ") || trimmed == ">" {
            let dropCount = trimmed.hasPrefix("> ") ? 2 : 1
            let content = String(trimmed.dropFirst(dropCount)).trimmingCharacters(in: .whitespaces)
            return .quote(content)
        }

        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            return .bullet(level: indent / 2, marker: "•", text: String(trimmed.dropFirst(2)))
        }

        if let ordered = orderedMarker(trimmed) {
            return .bullet(level: indent / 2, marker: ordered.marker, text: ordered.content)
        }

        return .paragraph(trimmed)
    }

    private func orderedMarker(_ trimmed: String) -> (marker: String, content: String)? {
        var digits = ""
        var index = trimmed.startIndex
        while index < trimmed.endIndex, trimmed[index].isNumber {
            digits.append(trimmed[index])
            index = trimmed.index(after: index)
        }
        guard !digits.isEmpty, index < trimmed.endIndex else { return nil }
        let separator = trimmed[index]
        guard separator == "." || separator == ")" else { return nil }
        let afterSeparator = trimmed.index(after: index)
        guard afterSeparator < trimmed.endIndex, trimmed[afterSeparator] == " " else { return nil }
        let content = String(trimmed[trimmed.index(after: afterSeparator)...])
        return ("\(digits).", content)
    }
}

