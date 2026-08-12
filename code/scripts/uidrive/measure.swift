import AppKit
import Foundation

// The two calls `partView` makes per message on every parent body evaluation.
func attributed(_ s: String) -> AttributedString {
    (try? AttributedString(markdown: s)) ?? AttributedString(s)
}
func styled(_ text: AttributedString, size: CGFloat) -> NSAttributedString {
    let r = NSMutableAttributedString(attributedString: NSAttributedString(text))
    r.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: size, weight: .regular),
                     .foregroundColor: NSColor.white],
                    range: NSRange(location: 0, length: r.length))
    return r
}
func naturalWidth(_ text: AttributedString, size: CGFloat) -> Double {
    ceil(styled(text, size: size).boundingRect(
        with: CGSize(width: 100_000, height: CGFloat.greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading]).width)
}

let short = "ได้ค่ะ ตัวอย่างโค้ด 3 บรรทัดง่ายๆ ค่ะ"
let long = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 40)

for (name, body) in [("short", short), ("long", long)] {
    let a = attributed(body)
    let t0 = Date()
    for _ in 0..<200 { _ = naturalWidth(attributed(body), size: 14) }
    let per = Date().timeIntervalSince(t0) / 200 * 1000
    _ = a
    print(String(format: "%@: %.3f ms per message per body evaluation", name, per))
}
