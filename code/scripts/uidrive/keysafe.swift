import AppKit
import CoreGraphics
import Foundation

// Never post keys unless the intended app is frontmost — synthetic keys have
// leaked into a terminal before.
let pid = Int(CommandLine.arguments[1])!
let code = CGKeyCode(UInt16(CommandLine.arguments[2])!)
let times = Int(CommandLine.arguments[3])!

let front = NSWorkspace.shared.frontmostApplication
guard Int(front?.processIdentifier ?? -1) == pid else {
    print("NOT FRONTMOST (\(front?.processIdentifier ?? -1) \(front?.localizedName ?? "?")) — no keys sent")
    exit(2)
}
for _ in 0..<times {
    CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)?.post(tap: .cghidEventTap)
    usleep(40_000)
    CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)?.post(tap: .cghidEventTap)
    usleep(120_000)
}
print("sent \(times)x key \(code) to \(pid)")
