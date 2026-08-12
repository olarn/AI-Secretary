import AppKit
import CoreGraphics
// Presses a key with modifiers, only while the given pid is frontmost.
let pid = Int(CommandLine.arguments[1])!
let code = CGKeyCode(UInt16(CommandLine.arguments[2])!)
// An unknown name is a hard error, not a skipped modifier. `cmd` was missing
// from this table while the README said it was supported, so `modkey <pid> 4
// cmd` posted a bare `h`, printed "pressed", and read as "⌘H is broken" — for
// half an hour, against an app whose ⌘H was fine. Silently dropping a modifier
// is worse than refusing: the bare key still goes somewhere, and into a focused
// chat box that means typing a letter into the person's message.
let names: [String: CGEventFlags] = [
    "cmd": .maskCommand,
    "command": .maskCommand,
    "shift": .maskShift,
    "option": .maskAlternate,
    "alt": .maskAlternate,
    "control": .maskControl,
    "ctrl": .maskControl,
]
var flags: CGEventFlags = []
for name in CommandLine.arguments.dropFirst(3) {
    guard let flag = names[name] else {
        print("unknown modifier '\(name)' — one of \(names.keys.sorted().joined(separator: ", "))")
        exit(2)
    }
    flags.insert(flag)
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
