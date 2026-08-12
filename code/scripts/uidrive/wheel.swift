import CoreGraphics
import Foundation
let pid = Int(CommandLine.arguments[1])!
let dir = Int32(CommandLine.arguments[2])!
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
var best: [String: CGFloat]? = nil
for w in list {
    guard (w[kCGWindowOwnerPID as String] as? Int) == pid,
          let b = w[kCGWindowBounds as String] as? [String: CGFloat], b["Width"]! > 200 else { continue }
    best = b
}
guard let b = best else { print("no panel"); exit(1) }
let p = CGPoint(x: b["X"]! + b["Width"]! / 2 - 20, y: b["Y"]! + b["Height"]! - 88)
CGWarpMouseCursorPosition(p)
usleep(300_000)
for _ in 0..<8 {
    let e = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: dir, wheel2: 0, wheel3: 0)
    e?.location = p
    e?.post(tap: .cghidEventTap)
    usleep(40_000)
}
print("scrolled at \(p.x),\(p.y)")
