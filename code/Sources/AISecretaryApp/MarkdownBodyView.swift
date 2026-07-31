import SwiftUI
import SecretaryCore

/// Renders a markdown body the way the chat does: prose, real tables, and code
/// blocks that scroll sideways instead of wrapping.
///
/// Extracted so an info window shows exactly what the chat showed. A second
/// renderer would drift — the first thing to go would be the rule that a table
/// scrolls inside its own box rather than widening the window.
struct MarkdownBodyView: View {
    let text: String
    let fontSize: Double
    /// For the language label above a code block, which is a caption rather than
    /// part of the content.
    let secondaryFontSize: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(
                Array(MarkdownTableParser.segments(of: text).enumerated()),
                id: \.offset
            ) { _, segment in
                switch segment {
                case .text(let body):
                    // AppKit-backed: SwiftUI's Text draws links but doesn't open
                    // them from a non-activating panel, and can't show a pointer
                    // or a hover underline over them.
                    MessageTextView(
                        text: MessageMarkdown.attributed(body),
                        fontSize: fontSize
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                case .table(let table):
                    tableView(table)
                case .code(let block):
                    codeView(block)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tableView(_ table: MarkdownTable) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    ForEach(Array(table.header.enumerated()), id: \.offset) { _, cell in
                        Text(MessageMarkdown.attributed(cell))
                            .font(.system(size: fontSize, weight: .bold))
                    }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(MessageMarkdown.attributed(cell))
                                .font(.system(size: fontSize))
                        }
                    }
                }
            }
            // Cells size to their content; the scroll view provides the room.
            .fixedSize(horizontal: true, vertical: false)
            .padding(8)
            .textSelection(.enabled)
        }
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func codeView(_ block: CodeBlock) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language = block.language {
                Text(language)
                    .font(.system(size: secondaryFontSize))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 5)
            }
            ScrollView(.horizontal, showsIndicators: true) {
                // Plain text, not markdown: inside a code block an asterisk is
                // an asterisk, and a backtick is a backtick.
                Text(block.code)
                    .font(.system(size: fontSize, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }
}
