import AppKit
import CoreGraphics
import Foundation

// Sends one keystroke, but only if the app that is about to receive it is the
// one named on the command line. Testing a system-wide hot key means firing
// keys while some *other* app is frontmost, so the usual "is our app in front?"
// guard is inverted here — the risk is the same either way, which is a key
// landing somewhere nobody expected.
let expected = CommandLine.arguments[1]
let code = CGKeyCode(UInt16(CommandLine.arguments[2])!)
let cmd = CommandLine.arguments.count > 3 && CommandLine.arguments[3] == "cmd"

let front = NSWorkspace.shared.frontmostApplication
guard front?.localizedName == expected else {
    print("REFUSING — frontmost is \(front?.localizedName ?? "?"), expected \(expected)")
    exit(2)
}

let flags: CGEventFlags = cmd ? .maskCommand : []
for down in [true, false] {
    let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
    e?.flags = flags
    e?.post(tap: .cghidEventTap)
    usleep(40_000)
}
print("sent \(cmd ? "cmd+" : "")keycode \(code) while \(expected) was frontmost")
