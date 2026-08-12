import CoreGraphics
import Foundation
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list {
    guard let pid = w[kCGWindowOwnerPID as String] as? Int, let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
    let name = w[kCGWindowOwnerName as String] as? String ?? "?"
    if CommandLine.arguments.count > 1, String(pid) != CommandLine.arguments[1] { continue }
    print("pid \(pid) \(name) x=\(b["X"]!) y=\(b["Y"]!) w=\(b["Width"]!) h=\(b["Height"]!) alpha=\(w[kCGWindowAlpha as String] as? Double ?? -1)")
}
