import CoreGraphics
import Foundation

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
