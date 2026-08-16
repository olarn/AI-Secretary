import CoreGraphics
import Foundation

// Drag a real file from Finder onto the app, and photograph the app *while the
// pointer is still holding it*.
//
// usage: swift dragcap.swift x0 y0 x1 y1 holdSeconds out.png x,y,w,h
//
// Written for the drop area in 0.14.263, which exists only mid-drag: `drag.swift`
// presses, moves and releases in one shot, so there is no moment left to
// capture and the one thing worth checking cannot be seen. The hold here is
// what makes it photographable.
//
// Two things this encodes, both learned by getting them wrong first:
//
// 1. **Ask the picture where the icon is, not AppleScript.** Finder's
//    `position of item` is relative to the icon view, and adding it to the
//    window's `bounds` lands in the sidebar — the first run dragged the
//    "Recents" row onto the app and the app, correctly, ignored it. Capture the
//    Finder window, look at it, and read the icon's coordinates off the image.
// 2. **Keep moving while holding.** A drag with no events in flight can be
//    treated as finished by the view under it, and the drop area disappears a
//    moment before the capture.
let a = Array(CommandLine.arguments.dropFirst())
guard a.count == 7, let x0 = Double(a[0]), let y0 = Double(a[1]),
      let x1 = Double(a[2]), let y1 = Double(a[3]), let hold = Double(a[4])
else {
    print("usage: dragcap.swift x0 y0 x1 y1 holdSeconds out.png x,y,w,h")
    exit(64)
}
let out = a[5]
let rect = a[6]

func post(_ type: CGEventType, _ point: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
}

CGWarpMouseCursorPosition(CGPoint(x: x0, y: y0))
usleep(400_000)
post(.leftMouseDown, CGPoint(x: x0, y: y0))
usleep(200_000)

// Stepped and slow: Finder starts its drag session off the first few moves, and
// a teleport produces no session at all.
let steps = 40
for i in 1...steps {
    let t = Double(i) / Double(steps)
    post(.leftMouseDragged, CGPoint(x: x0 + (x1 - x0) * t, y: y0 + (y1 - y0) * t))
    usleep(25_000)
}

let shot = Process()
shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
shot.arguments = ["-x", "-R\(rect)", out]

let deadline = Date().addingTimeInterval(hold)
var captured = false
while Date() < deadline {
    post(.leftMouseDragged, CGPoint(x: x1, y: y1))
    usleep(60_000)
    post(.leftMouseDragged, CGPoint(x: x1 + 1, y: y1))
    usleep(60_000)
    if !captured {
        try? shot.run()
        shot.waitUntilExit()
        captured = true
    }
}

post(.leftMouseUp, CGPoint(x: x1, y: y1))
print("dropped at \(x1),\(y1); capture \(captured ? "taken" : "skipped") → \(out)")
