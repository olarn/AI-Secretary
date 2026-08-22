import SwiftUI
import AppKit

_ = NSApplication.shared

enum RingLayout: String, CaseIterable {
    case centredStack
    case centredStackWithRingBaselinePinnedToItsBottom
    case firstTextBaselineStack
}

struct ModelRow: View {
    let inherited: Bool
    let layout: RingLayout
    let footnoteFontSize: CGFloat
    let ringFontSize: CGFloat

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                Text("Model")
                    .font(.system(size: footnoteFontSize))
                    .foregroundStyle(.black)
                stack
                    .font(.system(size: footnoteFontSize))
            }
        }
        .frame(width: 260, height: 90, alignment: .topLeading)
        .background(.white)
    }

    @ViewBuilder private var stack: some View {
        if layout == .firstTextBaselineStack {
            HStack(alignment: .firstTextBaseline, spacing: 6) { contents }
        } else {
            HStack(alignment: .center, spacing: 6) { contents }
        }
    }

    @ViewBuilder private var contents: some View {
        Menu { Button("x") {} } label: { Text("Opus") }
            .menuStyle(.borderlessButton)
            .fixedSize()
        if inherited {
            ring
        }
        Spacer(minLength: 0)
    }

    @ViewBuilder private var ring: some View {
        if layout == .centredStackWithRingBaselinePinnedToItsBottom {
            Image(systemName: "circle.dashed")
                .font(.system(size: ringFontSize))
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
        } else {
            Image(systemName: "circle.dashed")
                .font(.system(size: ringFontSize))
        }
    }
}

let renderScale: CGFloat = 4
let labelColumnWidth = 40

@MainActor func topmostDarkRowOfLabelColumn(_ view: some View) -> Int {
    let renderer = ImageRenderer(content: view)
    renderer.scale = renderScale
    guard let rendered = renderer.cgImage else { return -1 }
    let width = rendered.width
    let height = rendered.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.draw(rendered, in: CGRect(x: 0, y: 0, width: width, height: height))
    for row in 0..<height {
        for column in 0..<min(width, labelColumnWidth * Int(renderScale)) {
            if pixels[(row * width + column) * 4] < 128 { return row }
        }
    }
    return -1
}

MainActor.assumeIsolated {
    print("appFontSize menuFontSize ringFontSize " + RingLayout.allCases.map(\.rawValue).joined(separator: " "))
    for appFontSize in stride(from: 10.0, through: 32.0, by: 2.0) {
        let footnoteFontSize = max(8, appFontSize - 3)
        let ringFontSize = max(8, appFontSize - 5) * 0.8
        var line = String(format: "%11.0f %12.0f %12.1f", appFontSize, footnoteFontSize, ringFontSize)
        for layout in RingLayout.allCases {
            let withRing = topmostDarkRowOfLabelColumn(
                ModelRow(inherited: true, layout: layout, footnoteFontSize: footnoteFontSize, ringFontSize: ringFontSize)
            )
            let withoutRing = topmostDarkRowOfLabelColumn(
                ModelRow(inherited: false, layout: layout, footnoteFontSize: footnoteFontSize, ringFontSize: ringFontSize)
            )
            line += String(format: " %+.2f", Double(withRing - withoutRing) / Double(renderScale))
        }
        print(line)
    }
}
