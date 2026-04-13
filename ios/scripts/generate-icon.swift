#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

func generateIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))

    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let scale = s / 1024.0

    // Background - dark with subtle gradient
    let bgColors = [
        CGColor(red: 0.06, green: 0.06, blue: 0.10, alpha: 1.0),
        CGColor(red: 0.04, green: 0.04, blue: 0.07, alpha: 1.0),
    ]
    let bgGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: bgColors as CFArray,
                                 locations: [0.0, 1.0])!
    let cornerRadius = 220 * scale
    let bgPath = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                        cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(bgPath)
    ctx.clip()
    ctx.drawLinearGradient(bgGradient,
                           start: CGPoint(x: 0, y: s),
                           end: CGPoint(x: s, y: 0),
                           options: [])
    ctx.resetClip()

    // Border glow
    let borderPath = CGPath(roundedRect: CGRect(x: 2 * scale, y: 2 * scale,
                                                 width: s - 4 * scale, height: s - 4 * scale),
                            cornerWidth: cornerRadius - 2 * scale,
                            cornerHeight: cornerRadius - 2 * scale, transform: nil)
    ctx.addPath(borderPath)
    ctx.setStrokeColor(CGColor(red: 0.83, green: 0.58, blue: 0.42, alpha: 0.35))
    ctx.setLineWidth(3 * scale)
    ctx.strokePath()

    // Title bar dots
    let dotY = s - 200 * scale
    let dotRadius = 22 * scale
    let dotSpacing = 56 * scale
    let dotStartX = s / 2 - dotSpacing  // centered

    // Red dot
    ctx.setFillColor(CGColor(red: 0.93, green: 0.36, blue: 0.36, alpha: 0.9))
    ctx.fillEllipse(in: CGRect(x: dotStartX - dotRadius, y: dotY - dotRadius,
                                width: dotRadius * 2, height: dotRadius * 2))
    // Yellow dot
    ctx.setFillColor(CGColor(red: 0.96, green: 0.72, blue: 0.26, alpha: 0.9))
    ctx.fillEllipse(in: CGRect(x: dotStartX + dotSpacing - dotRadius, y: dotY - dotRadius,
                                width: dotRadius * 2, height: dotRadius * 2))
    // Green dot
    ctx.setFillColor(CGColor(red: 0.30, green: 0.78, blue: 0.55, alpha: 0.9))
    ctx.fillEllipse(in: CGRect(x: dotStartX + dotSpacing * 2 - dotRadius, y: dotY - dotRadius,
                                width: dotRadius * 2, height: dotRadius * 2))

    // Face: >_< drawn as single centered text
    let faceColor = CGColor(red: 0.83, green: 0.58, blue: 0.42, alpha: 1.0)

    let faceFont = CTFontCreateWithName("Menlo-Bold" as CFString, 300 * scale, nil)
    let faceStr = NSAttributedString(string: ">_<", attributes: [
        .font: faceFont,
        .foregroundColor: NSColor(cgColor: faceColor)!,
    ])
    let faceLine = CTLineCreateWithAttributedString(faceStr)
    let faceBounds = CTLineGetBoundsWithOptions(faceLine, [])
    // Center horizontally and vertically (slightly below center for the dots above)
    let faceX = (s - faceBounds.width) / 2 - faceBounds.origin.x
    let faceY = (s - faceBounds.height) / 2 - faceBounds.origin.y - 30 * scale
    ctx.textPosition = CGPoint(x: faceX, y: faceY)
    CTLineDraw(faceLine, ctx)

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, to path: String) {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to create PNG for \(path)")
        return
    }
    do {
        try pngData.write(to: URL(fileURLWithPath: path))
        print("Generated: \(path)")
    } catch {
        print("Error writing \(path): \(error)")
    }
}

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] :
    "/Users/nikhilchowdary/ClaudePal/ios/ClaudePal/Assets.xcassets/AppIcon.appiconset"

// Generate all required sizes
let sizes = [1024, 180, 167, 152, 120, 87, 80, 76, 60, 58, 40, 29, 20]
for size in sizes {
    let image = generateIcon(size: size)
    savePNG(image, to: "\(outputDir)/icon-\(size).png")
}

print("Done!")
