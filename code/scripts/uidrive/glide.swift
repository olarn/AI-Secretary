import CoreGraphics
import Foundation
let x2 = CGFloat(Double(CommandLine.arguments[1])!)
let y2 = CGFloat(Double(CommandLine.arguments[2])!)
let click = CommandLine.arguments.count > 3 && CommandLine.arguments[3] == "click"
let from = CGEvent(source: nil)?.location ?? .zero
let steps = 40
for i in 1...steps {
    let t = CGFloat(i) / CGFloat(steps)
    let p = CGPoint(x: from.x + (x2 - from.x) * t, y: from.y + (y2 - from.y) * t)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?
        .post(tap: .cghidEventTap)
    usleep(12_000)
}
usleep(300_000)
if click {
    let p = CGPoint(x: x2, y: y2)
    for t in [CGEventType.leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        usleep(60_000)
    }
}
print("glided to \(x2),\(y2)\(click ? " and clicked" : "")")
