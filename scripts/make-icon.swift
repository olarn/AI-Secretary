#!/usr/bin/env swift
//
// Renders a source PNG into a set of square, transparent icon images and builds
// an .icns file. The source needn't be square: it's aspect-fit and centered on
// a transparent canvas so nothing is stretched.
//
// Usage: swift scripts/make-icon.swift <source.png> <output.icns>

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

/// Draws `source` aspect-fit and centered on a transparent square of `pixels`.
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
    let size = source.size
    let scale = min(canvas / size.width, canvas / size.height)
    let w = size.width * scale
    let h = size.height * scale
    let rect = NSRect(x: (canvas - w) / 2, y: (canvas - h) / 2, width: w, height: h)
    source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let iconsetDir = NSTemporaryDirectory() + "AppIcon-\(UUID().uuidString).iconset"
try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

// (filename, pixel size) pairs required by iconutil.
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

// Hand off to iconutil to produce the .icns.
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconsetDir, "-o", outputPath]
try proc.run()
proc.waitUntilExit()
try? FileManager.default.removeItem(atPath: iconsetDir)
exit(proc.terminationStatus)
