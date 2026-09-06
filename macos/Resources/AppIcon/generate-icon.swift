// Regenerates source-icon-1024.png: a mild red dot squeezed by two charcoal
// triangles pointing in from left and right, on a light grey
// rounded-square background.
//
//   swift generate-icon.swift source-icon-1024.png
//
// After regenerating, rebuild Photokompressor.icns from it (see
// build/package-mac.sh's icon step, or run the same sips/iconutil
// pipeline by hand at 16/32/128/256/512 + @2x).
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

let size: CGFloat = 1024
let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                     bitsPerComponent: 8, bytesPerRow: 0,
                     space: CGColorSpaceCreateDeviceRGB(),
                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// Rounded-square canvas, matching the existing app icon's convention.
let corner: CGFloat = 190
let bgPath = CGPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size),
                     cornerWidth: corner, cornerHeight: corner, transform: nil)
ctx.addPath(bgPath)
ctx.setFillColor(CGColor(red: 0xE4 / 255.0, green: 0xE7 / 255.0, blue: 0xEC / 255.0, alpha: 1))
ctx.fillPath()

let center = CGPoint(x: size / 2, y: size / 2)
let dotRadius: CGFloat = 150

// Red dot, center — a milder, less saturated red than the earlier design
// (which leaned near-maroon); closer to the app's own UI red.
ctx.setFillColor(CGColor(red: 0xE0 / 255.0, green: 0x4B / 255.0, blue: 0x40 / 255.0, alpha: 1))
ctx.addEllipse(in: CGRect(x: center.x - dotRadius, y: center.y - dotRadius,
                           width: dotRadius * 2, height: dotRadius * 2))
ctx.fillPath()

// Two charcoal triangles, pointing inward from left and right only, tips
// just touching/overlapping the dot.
let baseHalfWidth: CGFloat = 110
let outerDistance: CGFloat = 430 // distance from center to each triangle's base midpoint
let tipInset: CGFloat = dotRadius - 6 // slight overlap onto the dot for a "pressing" look

ctx.setFillColor(CGColor(red: 0x3A / 255.0, green: 0x3F / 255.0, blue: 0x47 / 255.0, alpha: 1))

func triangle(angleDegrees: Double) {
    let angle = angleDegrees * .pi / 180
    let dir = CGPoint(x: cos(angle), y: sin(angle))
    let perp = CGPoint(x: -dir.y, y: dir.x)
    let baseCenter = CGPoint(x: center.x + dir.x * outerDistance, y: center.y + dir.y * outerDistance)
    let base1 = CGPoint(x: baseCenter.x + perp.x * baseHalfWidth, y: baseCenter.y + perp.y * baseHalfWidth)
    let base2 = CGPoint(x: baseCenter.x - perp.x * baseHalfWidth, y: baseCenter.y - perp.y * baseHalfWidth)
    let tip = CGPoint(x: center.x + dir.x * tipInset, y: center.y + dir.y * tipInset)

    ctx.beginPath()
    ctx.move(to: base1)
    ctx.addLine(to: base2)
    ctx.addLine(to: tip)
    ctx.closePath()
    ctx.fillPath()
}

// Right, then left.
triangle(angleDegrees: 0)
triangle(angleDegrees: 180)

let image = ctx.makeImage()!
let outURL = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(outURL.path)")
