import AppKit
import CoreGraphics

let pid = Int(CommandLine.arguments[1])!
let code = CGKeyCode(UInt16(CommandLine.arguments[2])!)
let times = Int(CommandLine.arguments[3]) ?? 1

for i in 1...times {
    let front = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
    guard Int(front) == pid else {
        print("STOPPED at \(i): frontmost is \(front), not \(pid)")
        exit(2)
    }
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
        e?.flags = .maskCommand
        e?.post(tap: .cghidEventTap)
        usleep(60_000)
    }
    usleep(200_000)
}
print("pressed \(times)x")
