#!/usr/bin/env swift

import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <source.png> <output.icns>\n".utf8))
    exit(2)
}
let sourcePath = args[1]
let outputPath = args[2]

guard let source = NSImage(contentsOfFile: sourcePath) else {
    FileHandle.standardError.write(Data("could not load image: \(sourcePath)\n".utf8))
    exit(1)
}

func contentBounds(of image: NSImage) -> NSRect {
    let whole = NSRect(origin: .zero, size: image.size)
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return whole }

    let wide = rep.pixelsWide, high = rep.pixelsHigh
    var minX = wide, minY = high, maxX = -1, maxY = -1
    for y in 0..<high {
        for x in 0..<wide {
            guard let colour = rep.colorAt(x: x, y: y), colour.alphaComponent > 0.05 else { continue }
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }
    }
    guard maxX >= minX, maxY >= minY else { return whole }

    let perPixelX = image.size.width / CGFloat(wide)
    let perPixelY = image.size.height / CGFloat(high)
    return NSRect(
        x: CGFloat(minX) * perPixelX,
        y: CGFloat(high - 1 - maxY) * perPixelY,
        width: CGFloat(maxX - minX + 1) * perPixelX,
        height: CGFloat(maxY - minY + 1) * perPixelY
    )
}

let content = contentBounds(of: source)

let contentFill: CGFloat = 0.92

func square(_ pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    let canvas = CGFloat(pixels)
    let usable = canvas * contentFill
    let size = content.size
    let scale = min(usable / size.width, usable / size.height)
    let w = size.width * scale
    let h = size.height * scale
    let rect = NSRect(x: (canvas - w) / 2, y: (canvas - h) / 2, width: w, height: h)
    source.draw(in: rect, from: content, operation: .sourceOver, fraction: 1)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let iconsetDir = NSTemporaryDirectory() + "AppIcon-\(UUID().uuidString).iconset"
try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for (name, pixels) in variants {
    guard let data = square(pixels) else {
        FileHandle.standardError.write(Data("failed to render \(name)\n".utf8))
        exit(1)
    }
    try data.write(to: URL(fileURLWithPath: iconsetDir + "/" + name))
}

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconsetDir, "-o", outputPath]
try proc.run()
proc.waitUntilExit()
try? FileManager.default.removeItem(atPath: iconsetDir)
exit(proc.terminationStatus)
