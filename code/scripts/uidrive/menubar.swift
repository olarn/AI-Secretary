import CoreGraphics
import Foundation
// The status item lives in the menu bar; find its owner's bar window.
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
let pid = Int(CommandLine.arguments[1])!
for w in list where (w[kCGWindowOwnerPID as String] as? Int) == pid {
    let b = w[kCGWindowBounds as String] as! [String: CGFloat]
    let layer = w[kCGWindowLayer as String] as? Int ?? 0
    print("layer \(layer) x=\(b["X"]!) y=\(b["Y"]!) w=\(b["Width"]!) h=\(b["Height"]!)")
}
