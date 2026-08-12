import CoreGraphics
import Foundation
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
var out: [String] = []
for w in list where (w[kCGWindowOwnerName as String] as? String ?? "").contains("Secretary") {
    let b = w[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
    out.append("\(Int(b["Width"] ?? 0))x\(Int(b["Height"] ?? 0))@\(Int(b["X"] ?? 0)),\(Int(b["Y"] ?? 0))")
}
print(out.joined(separator: " | "))
