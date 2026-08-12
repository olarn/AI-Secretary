import AppKit
func gray(_ path: String) -> ([UInt8], Int, Int) {
    let img = NSImage(contentsOfFile: path)!
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    var out = [UInt8](); out.reserveCapacity(rep.pixelsWide * rep.pixelsHigh)
    for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide {
        let c = rep.colorAt(x: x, y: y)!
        out.append(UInt8(c.brightnessComponent * 255))
    }}
    return (out, rep.pixelsWide, rep.pixelsHigh)
}
let (base, w, h) = gray("f0.png")
for i in 1...7 {
    let (other, _, _) = gray("f\(i).png")
    var changed = 0, total = 0.0
    for j in 0..<base.count {
        let d = abs(Int(base[j]) - Int(other[j]))
        if d > 6 { changed += 1 }
        total += Double(d)
    }
    print("f0 vs f\(i): changed px \(changed) (\(String(format: "%.2f", Double(changed) * 100 / Double(base.count)))%), mean delta \(String(format: "%.3f", total / Double(base.count)))")
}
print("size \(w)x\(h)")
