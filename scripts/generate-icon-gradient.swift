#!/usr/bin/env swift
// Generates IntelliWhisper-gradient.icns with a vertical gradient waveform.
// Colors: #00be9a (top/bright) → #009880 → #007866 → #006255 (bottom/dark)
// Usage: swift scripts/generate-icon-gradient.swift [output-path]
//   default output: Resources/IntelliWhisper-gradient.icns

import AppKit
import Foundation

let outputPath: String = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Resources/IntelliWhisper-gradient.icns"

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------
let backgroundColor = NSColor.white
let symbolName = "waveform"

// Gradient colors: brightest (top) → darkest (bottom)
func color(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
    NSColor(calibratedRed: CGFloat(r) / 255.0, green: CGFloat(g) / 255.0,
            blue: CGFloat(b) / 255.0, alpha: 1.0)
}
let gradientColors: [NSColor] = [
    color(0x00, 0xbe, 0x9a),  // #00be9a (brightest)
    color(0x00, 0x98, 0x80),  // #009880
    color(0x00, 0x78, 0x66),  // #007866
    color(0x00, 0x62, 0x55),  // #006255 (darkest)
]

// macOS .icns required sizes (pixels)
let sizes: [Int] = [16, 32, 64, 128, 256, 512, 1024]

// ---------------------------------------------------------------------------
// Render one size
// ---------------------------------------------------------------------------
func renderIcon(size: Int) -> NSBitmapImageRep {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: s, height: s)

    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx

    // Rounded-rect background (macOS icon shape: ~22.37% corner radius)
    let cornerRadius = s * 0.2237
    let bgRect = NSRect(x: 0, y: 0, width: s, height: s)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)
    backgroundColor.setFill()
    bgPath.fill()

    // SF Symbol — horizontally stretched for wider bars
    let fontSize = s * 0.5
    let horizontalStretch: CGFloat = 1.35
    if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
        let config = NSImage.SymbolConfiguration(pointSize: fontSize, weight: .medium)
        let configured = symbol.withSymbolConfiguration(config)!

        let symbolSize = configured.size
        let stretchedWidth = symbolSize.width * horizontalStretch
        let x = (s - stretchedWidth) / 2
        let y = (s - symbolSize.height) / 2
        let drawRect = NSRect(x: x, y: y, width: stretchedWidth, height: symbolSize.height)

        // Create gradient-filled version:
        // 1. Draw symbol as black mask
        // 2. Fill with vertical gradient using source-atop
        let tinted = NSImage(size: symbolSize)
        tinted.lockFocus()

        // Draw the symbol (black)
        configured.draw(in: NSRect(origin: .zero, size: symbolSize))

        // Apply vertical gradient over the symbol using source-atop
        let gradient = NSGradient(colors: gradientColors)!
        let symbolRect = NSRect(origin: .zero, size: symbolSize)

        // Save state, set compositing, draw gradient
        NSGraphicsContext.current?.cgContext.setBlendMode(.sourceAtop)
        gradient.draw(in: symbolRect, angle: 270)  // 270 = top to bottom

        tinted.unlockFocus()

        tinted.draw(in: drawRect)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// ---------------------------------------------------------------------------
// Build iconset directory, then convert to .icns
// ---------------------------------------------------------------------------
let fm = FileManager.default
let tempDir = NSTemporaryDirectory() + "IntelliWhisper-gradient.iconset"
try? fm.removeItem(atPath: tempDir)
try fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)

for size in sizes {
    // 1x
    let rep1x = renderIcon(size: size)
    let name1x = "icon_\(size)x\(size).png"
    let data1x = rep1x.representation(using: .png, properties: [:])!
    try data1x.write(to: URL(fileURLWithPath: "\(tempDir)/\(name1x)"))

    // 2x (except for 1024 which has no 2x)
    if size <= 512 {
        let rep2x = renderIcon(size: size * 2)
        let name2x = "icon_\(size)x\(size)@2x.png"
        let data2x = rep2x.representation(using: .png, properties: [:])!
        try data2x.write(to: URL(fileURLWithPath: "\(tempDir)/\(name2x)"))
    }
}

// Convert iconset to icns using iconutil
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", "-o", outputPath, tempDir]
try process.run()
process.waitUntilExit()

if process.terminationStatus == 0 {
    print("Created \(outputPath)")
} else {
    fputs("iconutil failed with status \(process.terminationStatus)\n", stderr)
    exit(1)
}

// Cleanup
try? fm.removeItem(atPath: tempDir)
