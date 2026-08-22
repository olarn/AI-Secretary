import CoreGraphics
import Foundation
let x = Double(CommandLine.arguments[1])!, y = Double(CommandLine.arguments[2])!
let dir = Int32(CommandLine.arguments[3])!
let ticks = CommandLine.arguments.count > 4 ? Int(CommandLine.arguments[4])! : 10
let p = CGPoint(x: x, y: y)
CGWarpMouseCursorPosition(p); usleep(300_000)
for _ in 0..<ticks {
    let e = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: dir, wheel2: 0, wheel3: 0)
    e?.location = p
    e?.post(tap: .cghidEventTap)
    usleep(40_000)
}
print("scrolled \(ticks) x \(dir) at \(x),\(y)")
