import AppKit
import CoreGraphics
import Foundation

let pid = Int(CommandLine.arguments[1])!
let steps = Int(CommandLine.arguments[2]) ?? 10
let dx = CGFloat(Double(CommandLine.arguments[3]) ?? 30)
let dy = CGFloat(Double(CommandLine.arguments[4]) ?? -20)

func windows() -> [[String: CGFloat]] {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
    return list.compactMap { w in
        guard (w[kCGWindowOwnerPID as String] as? Int) == pid else { return nil }
        return w[kCGWindowBounds as String] as? [String: CGFloat]
    }
}
func panel() -> [String: CGFloat]? { windows().first { $0["Width"]! > 200 } }
func character() -> [String: CGFloat]? { windows().first { $0["Width"]! <= 200 } }

func describe(_ label: String) {
    let c = character().map { "char x=\($0["X"]!) y=\($0["Y"]!)" } ?? "char ?"
    let p = panel().map { "chat x=\($0["X"]!) y=\($0["Y"]!) w=\($0["Width"]!) h=\($0["Height"]!)" } ?? "chat ?"
    print("\(label): \(c) | \(p)")
}

guard let b = panel() else { print("no chat panel open"); exit(1) }
guard Int(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1) == pid else {
    print("NOT FRONTMOST — refusing to drag"); exit(2)
}

let gripOnRight = CommandLine.arguments.count > 5 && CommandLine.arguments[5] == "right"
var p = CGPoint(
    x: gripOnRight ? b["X"]! + b["Width"]! - 24 : b["X"]! + 24,
    y: b["Y"]! + 24
)
describe("before")

CGWarpMouseCursorPosition(p)
usleep(200_000)
CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)?
    .post(tap: .cghidEventTap)
usleep(150_000)

for step in 1...steps {
    p.x += dx
    p.y += dy
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: p, mouseButton: .left)?
        .post(tap: .cghidEventTap)
    usleep(180_000)
    describe("step \(step) pointer=\(Int(p.x)),\(Int(p.y))")
}

CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)?
    .post(tap: .cghidEventTap)
usleep(300_000)
describe("after")
