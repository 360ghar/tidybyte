#!/usr/bin/env swift

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let sizes: [(name: String, size: Int)] = [
    ("icon_20", 20),
    ("icon_20@2x", 40),
    ("icon_20@3x", 60),
    ("icon_29", 29),
    ("icon_29@2x", 58),
    ("icon_29@3x", 87),
    ("icon_40", 40),
    ("icon_40@2x", 80),
    ("icon_40@3x", 120),
    ("icon_60@2x", 120),
    ("icon_60@3x", 180),
    ("icon_76", 76),
    ("icon_76@2x", 152),
    ("icon_167", 167),
    ("icon_1024", 1024)
]

let colorSpace = CGColorSpaceCreateDeviceRGB()

func drawAppIcon(size: Int) -> CGImage {
    let width = CGFloat(size)
    let height = CGFloat(size)
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: colorSpace, bitmapInfo: bitmapInfo)!
    context.interpolationQuality = .high

    // Dark gradient background
    let bgColors: [CGColor] = [
        CGColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0),
        CGColor(red: 0.17, green: 0.17, blue: 0.18, alpha: 1.0)
    ]
    let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors as CFArray, locations: [0.0, 1.0])!
    context.drawLinearGradient(bgGradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: width, y: height), options: [])

    // Photo thumbnail
    let photoWidth = width * 0.55
    let photoHeight = height * 0.70
    let photoX = (width - photoWidth) / 2
    let photoY = (height - photoHeight) / 2
    let photoRect = CGRect(x: photoX, y: photoY, width: photoWidth, height: photoHeight)
    let cornerRadius = width * 0.08
    
    // Photo background with gradient
    let photoColors: [CGColor] = [
        CGColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 0.35),
        CGColor(red: 0.58, green: 0.0, blue: 0.83, alpha: 0.35)
    ]
    let photoGradient = CGGradient(colorsSpace: colorSpace, colors: photoColors as CFArray, locations: [0.0, 1.0])!
    
    let photoPath = CGPath(
        roundedRect: photoRect,
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil
    )
    context.addPath(photoPath)
    context.clip()
    context.drawLinearGradient(photoGradient, start: CGPoint(x: photoX, y: photoY), end: CGPoint(x: photoX + photoWidth, y: photoY + photoHeight), options: [])
    context.resetClip()

    // Photo border
    context.addPath(photoPath)
    context.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.15))
    context.setLineWidth(width * 0.01)
    context.strokePath()

    // Draw sparkles around the wand
    let sparklePositions: [(x: CGFloat, y: CGFloat, size: CGFloat)] = [
        (0.75, 0.25, 0.06),
        (0.80, 0.35, 0.04),
        (0.68, 0.18, 0.03),
        (0.85, 0.28, 0.05),
        (0.72, 0.32, 0.035),
    ]

    for sparkle in sparklePositions {
        drawSparkle(context: context, center: CGPoint(x: width * sparkle.x, y: height * sparkle.y), size: width * sparkle.size, color: CGColor(red: 1.0, green: 0.95, blue: 0.5, alpha: 0.9))
    }

    // Draw magic wand
    drawWand(context: context, center: CGPoint(x: width * 0.5, y: height * 0.5), size: width * 0.45)

    return context.makeImage()!
}

func drawSparkle(context: CGContext, center: CGPoint, size: CGFloat, color: CGColor) {
    let points = 4
    var pathPoints: [CGPoint] = []

    for i in 0..<(points * 2) {
        let angle = CGFloat.pi / CGFloat(points) * CGFloat(i) - CGFloat.pi / 2
        let radius = i % 2 == 0 ? size : size * 0.4
        let x = center.x + cos(angle) * radius
        let y = center.y + sin(angle) * radius
        pathPoints.append(CGPoint(x: x, y: y))
    }

    let path = CGMutablePath()
    path.move(to: pathPoints[0])
    for point in pathPoints[1...] {
        path.addLine(to: point)
    }
    path.closeSubpath()

    context.addPath(path)
    context.setFillColor(color)
    context.fillPath()
}

func drawWand(context: CGContext, center: CGPoint, size: CGFloat) {
    let wandLength = size
    let angle = -CGFloat.pi / 5

    let halfLength = wandLength / 2
    let dx = cos(angle) * halfLength
    let dy = sin(angle) * halfLength

    let start = CGPoint(x: center.x - dx, y: center.y - dy)
    let end = CGPoint(x: center.x + dx, y: center.y + dy)

    // Draw star/sparkle at wand tip first
    let starSize = size * 0.25
    drawStar(context: context, center: end, size: starSize)

    // Draw small glow around the star
    let glowPath = CGPath(ellipseIn: CGRect(x: end.x - starSize * 1.5, y: end.y - starSize * 1.5, width: starSize * 3, height: starSize * 3), transform: nil)
    context.addPath(glowPath)
    let glowColors: [CGColor] = [
        CGColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 0.3),
        CGColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 0.0)
    ]
    let glowGradient = CGGradient(colorsSpace: colorSpace, colors: glowColors as CFArray, locations: [0.0, 1.0])!
    context.clip()
    context.drawRadialGradient(glowGradient, startCenter: end, startRadius: 0, endCenter: end, endRadius: starSize * 1.5, options: [])
    context.resetClip()

    // Wand body
    let wandWidth = size * 0.12
    let perpX = -sin(angle) * wandWidth / 2
    let perpY = cos(angle) * wandWidth / 2

    let wandPath = CGMutablePath()
    wandPath.move(to: CGPoint(x: start.x - perpX, y: start.y - perpY))
    wandPath.addLine(to: CGPoint(x: start.x + perpX, y: start.y + perpY))
    wandPath.addLine(to: CGPoint(x: end.x + perpX, y: end.y + perpY))
    wandPath.addLine(to: CGPoint(x: end.x - perpX, y: end.y - perpY))
    wandPath.closeSubpath()

    // Wand gradient (gold to orange)
    let wandColors: [CGColor] = [
        CGColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1.0),
        CGColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 1.0)
    ]
    let wandGradient = CGGradient(colorsSpace: colorSpace, colors: wandColors as CFArray, locations: [0.0, 1.0])!
    
    context.addPath(wandPath)
    context.clip()
    context.drawLinearGradient(wandGradient, start: end, end: start, options: [])
    context.resetClip()
}

func drawStar(context: CGContext, center: CGPoint, size: CGFloat) {
    let points = 4
    var pathPoints: [CGPoint] = []

    for i in 0..<(points * 2) {
        let angle = CGFloat.pi / CGFloat(points) * CGFloat(i) - CGFloat.pi / 2
        let radius = i % 2 == 0 ? size : size * 0.35
        let x = center.x + cos(angle) * radius
        let y = center.y + sin(angle) * radius
        pathPoints.append(CGPoint(x: x, y: y))
    }

    let path = CGMutablePath()
    path.move(to: pathPoints[0])
    for point in pathPoints[1...] {
        path.addLine(to: point)
    }
    path.closeSubpath()

    // Star gradient (bright yellow to white)
    let starColors: [CGColor] = [
        CGColor(red: 1.0, green: 0.98, blue: 0.8, alpha: 1.0),
        CGColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1.0)
    ]
    let starGradient = CGGradient(colorsSpace: colorSpace, colors: starColors as CFArray, locations: [0.3, 1.0])!

    context.addPath(path)
    context.clip()
    context.drawLinearGradient(starGradient, start: CGPoint(x: center.x, y: center.y - size), end: CGPoint(x: center.x, y: center.y + size), options: [])
    context.resetClip()
}

// Main execution
let outputDir = "Tidybyte/Resources/Assets.xcassets/AppIcon.appiconset"

for (name, size) in sizes {
    let image = drawAppIcon(size: size)
    let url = URL(fileURLWithPath: "\(outputDir)/\(name).png")
    
    if let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        print("Generated: \(name).png (\(size)x\(size))")
    }
}

print("\nAll icons generated successfully!")
print("Output directory: \(outputDir)")