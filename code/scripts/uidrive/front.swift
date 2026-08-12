import AppKit
let a = NSWorkspace.shared.frontmostApplication
print(a?.processIdentifier ?? -1, a?.localizedName ?? "?")
