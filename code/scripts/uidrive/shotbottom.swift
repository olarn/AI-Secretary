import CoreGraphics
import Foundation
let pid = Int(CommandLine.arguments[1])!
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
var best: [String: CGFloat]? = nil
for w in list {
    guard (w[kCGWindowOwnerPID as String] as? Int) == pid,
          let b = w[kCGWindowBounds as String] as? [String: CGFloat], b["Width"]! > 200 else { continue }
    best = b
}
guard let b = best else { print("no panel"); exit(1) }
let h: CGFloat = 150
let rect = "\(Int(b["X"]!)),\(Int(b["Y"]! + b["Height"]! - h - 30)),\(Int(b["Width"]!)),\(Int(h))"
print("rect \(rect)")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
p.arguments = ["-x", "-R\(rect)", CommandLine.arguments[2]]
try p.run(); p.waitUntilExit()
