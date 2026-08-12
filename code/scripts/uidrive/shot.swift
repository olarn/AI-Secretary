import CoreGraphics
import Foundation
let pid = Int(CommandLine.arguments[1])!
let out = CommandLine.arguments[2]
let h = Int(CommandLine.arguments[3]) ?? 90
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
var best: [String: CGFloat]? = nil
for w in list {
    guard (w[kCGWindowOwnerPID as String] as? Int) == pid,
          let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
    if b["Width"]! > 200 { best = b }   // the chat panel, not the character
}
guard let b = best else { print("no panel"); exit(1) }
let rect = "\(Int(b["X"]!)),\(Int(b["Y"]!)),\(Int(b["Width"]!)),\(h)"
print("rect \(rect)")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
p.arguments = ["-x", "-R\(rect)", out]
try p.run(); p.waitUntilExit()
