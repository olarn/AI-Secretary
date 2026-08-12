import CoreGraphics
import Foundation
// Horizontal scroll at an explicit screen point.
let x = Double(CommandLine.arguments[1])!, y = Double(CommandLine.arguments[2])!
let dir = Int32(CommandLine.arguments[3])!
let p = CGPoint(x: x, y: y)
CGWarpMouseCursorPosition(p); usleep(300_000)
for _ in 0..<10 {
    let e = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 0, wheel2: dir, wheel3: 0)
    e?.location = p
    e?.post(tap: .cghidEventTap)
    usleep(40_000)
}
print("scrolled")
