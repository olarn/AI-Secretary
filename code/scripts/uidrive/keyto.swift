import AppKit
import CoreGraphics
import Foundation

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
