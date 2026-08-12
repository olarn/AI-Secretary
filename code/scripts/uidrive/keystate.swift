import AppKit
let front = NSWorkspace.shared.frontmostApplication
print("frontmost:", front?.localizedName ?? "?", front?.processIdentifier ?? -1)
