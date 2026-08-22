import AppKit

func bitmap(_ path: String) -> NSBitmapImageRep? {
    guard let image = NSImage(contentsOfFile: path),
          let tiff = image.tiffRepresentation else { return nil }
    return NSBitmapImageRep(data: tiff)
}

let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 2 else {
    print("usage: changed.swift a.png b.png"); exit(64)
}
guard let a = bitmap(args[0]), let b = bitmap(args[1]) else {
    print("could not read both images"); exit(1)
}

var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1, n = 0
var worst = 0.0
for y in 0..<min(a.pixelsHigh, b.pixelsHigh) {
    for x in 0..<min(a.pixelsWide, b.pixelsWide) {
        guard let p = a.colorAt(x: x, y: y), let q = b.colorAt(x: x, y: y) else { continue }
        let d = abs(p.redComponent - q.redComponent)
            + abs(p.greenComponent - q.greenComponent)
            + abs(p.blueComponent - q.blueComponent)
        if d > 0.06 {
            n += 1
            worst = max(worst, d)
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
}

if n == 0 {
    print("\(args[0]) vs \(args[1]): identical")
} else {
    print("""
    \(args[0]) vs \(args[1]): \(n) px changed, \
    box x=\(minX)…\(maxX) y=\(minY)…\(maxY), worst Δ=\(String(format: "%.3f", worst))
    """)
}
