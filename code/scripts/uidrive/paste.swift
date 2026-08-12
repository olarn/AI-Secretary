import AppKit
import CoreGraphics
import Foundation
let pid = Int(CommandLine.arguments[1])!
func windows() -> [[String: CGFloat]] {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
    return list.compactMap { w in
        guard (w[kCGWindowOwnerPID as String] as? Int) == pid else { return nil }
        return w[kCGWindowBounds as String] as? [String: CGFloat]
    }
}
func panel() -> [String: CGFloat]? { windows().first { $0["Width"]! > 200 } }
func character() -> [String: CGFloat]? { windows().first { $0["Width"]! <= 200 } }
func click(_ p: CGPoint) {
    CGWarpMouseCursorPosition(p); usleep(250_000)
    for t in [CGEventType.leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(60_000)
    }
}
guard let c = character() else { print("no character"); exit(1) }
let body = CGPoint(x: c["X"]! + c["Width"]! / 2, y: c["Y"]! + 40)
if panel() != nil { click(body); usleep(900_000) }
click(body); usleep(1_200_000)
guard let b = panel() else { print("panel did not open"); exit(1) }
click(CGPoint(x: b["X"]! + b["Width"]! / 2 - 20, y: b["Y"]! + b["Height"]! - 88))
usleep(400_000)
let front = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
guard Int(front) == pid else { print("NOT FRONTMOST (\(front))"); exit(2) }
// Paste only — deliberately no Return, so nothing is sent.
for down in [true, false] {
    let e = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: down)
    e?.flags = .maskCommand
    e?.post(tap: .cghidEventTap)
    usleep(60_000)
}
print("pasted")
