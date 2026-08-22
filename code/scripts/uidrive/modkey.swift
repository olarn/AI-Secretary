import AppKit
import CoreGraphics
let pid = Int(CommandLine.arguments[1])!
let code = CGKeyCode(UInt16(CommandLine.arguments[2])!)
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
