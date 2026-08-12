import CoreGraphics
import AppKit
let a = CommandLine.arguments.dropFirst().map { CGFloat(Double($0)!) }
let p = CGPoint(x: a[0], y: a[1])
guard NSWorkspace.shared.frontmostApplication?.localizedName == "AI Secretary" else {
    print("REFUSING — not frontmost"); exit(2)
}
CGWarpMouseCursorPosition(p)
usleep(250_000)
for t in [CGEventType.leftMouseDown, .leftMouseUp] {
    let e = CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)
    e?.flags = .maskCommand
    e?.post(tap: .cghidEventTap)
    usleep(60_000)
}
print("cmd-clicked \(p.x),\(p.y)")
