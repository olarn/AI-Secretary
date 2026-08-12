import CoreGraphics
import Foundation
let x = CGFloat(Double(CommandLine.arguments[1])!)
let y = CGFloat(Double(CommandLine.arguments[2])!)
let hold = UInt32(Double(CommandLine.arguments[3])! * 1_000_000)
let p = CGPoint(x: x, y: y)
CGWarpMouseCursorPosition(p)
usleep(300_000)
CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
usleep(hold)
CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
