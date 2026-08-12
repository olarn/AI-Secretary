import CoreGraphics
import Foundation
let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list {
    let owner = w[kCGWindowOwnerName as String] as? String ?? ""
    if owner.contains("Secretary") || owner.contains("AISecretary") {
        print(owner, w[kCGWindowBounds as String] ?? "-", "alpha:", w[kCGWindowAlpha as String] ?? "-", "onscreen:", w[kCGWindowIsOnscreen as String] ?? "-")
    }
}
