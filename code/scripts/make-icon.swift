#!/usr/bin/env swift
//
// Renders a source PNG into a set of square, transparent icon images and builds
// an .icns file. The source needn't be square, and needn't be cropped: its
// transparent margin is trimmed off, then what's left is aspect-fit and
// centered on a transparent canvas, so nothing is stretched and nothing is
// rendered smaller than the icon slot allows.
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

/// The part of `source` that isn't fully transparent, in the image's own
/// coordinates.
///
/// Icon art arrives padded: the drawing in `docs/Noti-Icon.png` covers 62% x
/// 57% of its 1024pt canvas, and drawing that margin too meant the artwork was
/// rendered at 62% of the size the icon slot allows — which is why it couldn't
/// be made out in Finder's list view (owner, 2026-08-19). Trimming here rather
/// than cropping the file keeps the source as it was delivered.
///
/// Returns the whole image when it is fully opaque, or when the pixels can't
/// be read — a slightly small icon beats no icon.
func contentBounds(of image: NSImage) -> NSRect {
    let whole = NSRect(origin: .zero, size: image.size)
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return whole }

    let wide = rep.pixelsWide, high = rep.pixelsHigh
    var minX = wide, minY = high, maxX = -1, maxY = -1
    for y in 0..<high {
        for x in 0..<wide {
            // Anything this faint reads as nothing on screen, and a stray
            // near-zero pixel in a corner would defeat the whole trim.
            guard let colour = rep.colorAt(x: x, y: y), colour.alphaComponent > 0.05 else { continue }
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }
    }
    guard maxX >= minX, maxY >= minY else { return whole }

    // colorAt(x:y:) counts y down from the top; draw(in:from:) counts it up
    // from the bottom. Drop this flip and the art sits off-centre vertically by
    // however much the margins differ — which looks nearly right, so it is not
    // caught by glancing at it.
    let perPixelX = image.size.width / CGFloat(wide)
    let perPixelY = image.size.height / CGFloat(high)
    return NSRect(
        x: CGFloat(minX) * perPixelX,
        y: CGFloat(high - 1 - maxY) * perPixelY,
        width: CGFloat(maxX - minX + 1) * perPixelX,
        height: CGFloat(maxY - minY + 1) * perPixelY
    )
}

// Scanned once, not once per variant: it is a read of every pixel in the
// source, and there are ten variants.
let content = contentBounds(of: source)

/// How much of the icon's square the trimmed artwork is scaled to fill.
///
/// Not 1.0, because macOS masks app icons to a rounded square: art that reaches
/// the edge loses its corners. Measured against that mask at a 22.4%-of-side
/// corner radius, this drawing loses nothing even at 1.0 — its corners are
/// empty, being an atom rather than a square — so the 8% here is not paying for
/// clipping. It is margin against the mask being slightly tighter than that
/// measurement assumes, and it keeps the outer planets off the very edge of the
/// tile, where they would sit closer to it than any neighbouring app's icon.
let contentFill: CGFloat = 0.92

/// Draws the opaque part of `source` aspect-fit and centered on a transparent
/// square of `pixels`.
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
