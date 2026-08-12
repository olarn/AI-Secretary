import AppKit
import CoreGraphics
// Presses a key with modifiers, only while the given pid is frontmost.
let pid = Int(CommandLine.arguments[1])!
let code = CGKeyCode(UInt16(CommandLine.arguments[2])!)
var flags: CGEventFlags = []
for name in CommandLine.arguments.dropFirst(3) {
    if name == "shift" { flags.insert(.maskShift) }
    if name == "option" { flags.insert(.maskAlternate) }
}
let front = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
guard Int(front) == pid else { print("NOT FRONTMOST (\(front))"); exit(2) }
for down in [true, false] {
    let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
    e?.flags = flags
    e?.post(tap: .cghidEventTap)
    usleep(60_000)
}
print("pressed")
