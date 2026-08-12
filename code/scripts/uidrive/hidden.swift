import AppKit
let pid = Int32(CommandLine.arguments[1])!
if let a = NSRunningApplication(processIdentifier: pid) {
    print("isHidden=\(a.isHidden) isActive=\(a.isActive) name=\(a.localizedName ?? "?")")
} else { print("not running") }
