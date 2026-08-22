import AppKit
import CoreGraphics
import Foundation

let pid = Int(CommandLine.arguments[1])!
func panelRect() -> [String: CGFloat]? {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
    for w in list {
        guard (w[kCGWindowOwnerPID as String] as? Int) == pid,
              let b = w[kCGWindowBounds as String] as? [String: CGFloat], b["Width"]! > 200 else { continue }
        return b
    }
    return nil
}
func click(_ p: CGPoint) {
    CGWarpMouseCursorPosition(p)
    usleep(250_000)
    for t in [CGEventType.leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(60_000)
    }
}
guard let b = panelRect() else { print("chat panel not open"); exit(1) }
let field = CGPoint(x: b["X"]! + b["Width"]! / 2 - 20, y: b["Y"]! + b["Height"]! - 88)
print("panel \(b["X"]!),\(b["Y"]!) \(b["Width"]!)x\(b["Height"]!) → field \(field.x),\(field.y)")
click(field)
usleep(400_000)
let front = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
guard Int(front) == pid else { print("NOT FRONTMOST (\(front)) — no keys sent"); exit(2) }
let keys: [(CGKeyCode, CGEventFlags)] = [(9, .maskCommand), (36, CGEventFlags())]
for (code, flags) in keys {
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
        e?.flags = flags
        e?.post(tap: .cghidEventTap)
        usleep(60_000)
    }
    usleep(300_000)
}
print("sent")
