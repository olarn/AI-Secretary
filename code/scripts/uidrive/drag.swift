import CoreGraphics
import Foundation
let a = CommandLine.arguments.dropFirst().map { CGFloat(Double($0)!) }
let (x0,y0,x1,y1) = (a[0],a[1],a[2],a[3])
CGWarpMouseCursorPosition(CGPoint(x: x0, y: y0))
usleep(300_000)
CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: CGPoint(x: x0, y: y0), mouseButton: .left)?.post(tap: .cghidEventTap)
usleep(120_000)
let steps = 25
for i in 1...steps {
    let t = CGFloat(i) / CGFloat(steps)
    let p = CGPoint(x: x0 + (x1-x0)*t, y: y0 + (y1-y0)*t)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(25_000)
}
usleep(120_000)
CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: CGPoint(x: x1, y: y1), mouseButton: .left)?.post(tap: .cghidEventTap)
