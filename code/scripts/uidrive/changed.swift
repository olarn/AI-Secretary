import AppKit

// Where do two captures differ, and by how much?
//
// Usage: swift changed.swift a.png b.png
//
// Written for the thinking animation in 0.14.259-260, where neither question a
// still can answer was the question that mattered. "Is it animating?" is two
// frames apart in time differing *only* in the region that should move — this
// prints that region's bounding box, so the claim names the pixels instead of
// asserting from a screenshot. "Has it stopped?" is the same two frames coming
// back `identical`, which is how the 259 bug was caught: three captures a
// second apart with the app idle, and the badge differed in every pair.
//
// `diff.swift` is the neighbour that greyscale-diffs a numbered f0/f1/f2 series
// at once. This one takes two named files and tells you *where*.
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
        // Sum of channel differences. 0.06 is above capture noise and well
        // below anything a person would call a visible change.
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
