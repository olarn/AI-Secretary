import CoreGraphics
import Foundation
let x = CGFloat(Double(CommandLine.arguments[1])!)
let y = CGFloat(Double(CommandLine.arguments[2])!)
let p = CGPoint(x: x, y: y)
CGWarpMouseCursorPosition(p)
usleep(200_000)
for type in [CGEventType.leftMouseDown, .leftMouseUp] {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(60_000)
}
