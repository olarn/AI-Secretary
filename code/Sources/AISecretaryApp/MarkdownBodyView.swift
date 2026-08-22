import SwiftUI
import SecretaryCore

struct MarkdownBodyView: View {
    @Environment(\.palette) private var theme

    let text: String
    let fontSize: Double
    let font: FontChoice
    let secondaryFontSize: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(
                Array(MarkdownTableParser.segments(of: text).enumerated()),
                id: \.offset
            ) { _, segment in
                switch segment {
                case .text(let body):
                    MessageTextView(
                        text: MessageMarkdown.attributed(body),
                        fontSize: fontSize,
                        font: font,
                        palette: theme
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
                            .font(.system(size: fontSize, weight: .bold, design: font.swiftUIDesign))
                    }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(MessageMarkdown.attributed(cell))
                                .font(.system(size: fontSize, design: font.swiftUIDesign))
                        }
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(8)
            .textSelection(.enabled)
        }
        .background(theme.nestedFill.color, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(theme.hairline.color, lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func codeView(_ block: CodeBlock) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language = block.language {
                Text(language)
                    .font(.system(size: secondaryFontSize))
                    .foregroundStyle(theme.mutedText.color)
                    .padding(.horizontal, 8)
                    .padding(.top, 5)
            }
            ScrollView(.horizontal, showsIndicators: true) {
                Text(block.code)
                    .font(.system(size: fontSize, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.nestedFill.color, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(theme.hairline.color, lineWidth: 1)
        )
    }
}
