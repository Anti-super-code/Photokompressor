// Regenerates source-icon-1024.png: a red dot squeezed by four white
// triangles from each edge, on a black rounded-square background.
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
ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
ctx.fillPath()

let center = CGPoint(x: size / 2, y: size / 2)
let dotRadius: CGFloat = 150

// Red dot, center — same red as the app's own Theme.danger (#FF3B30).
ctx.setFillColor(CGColor(red: 0xFF / 255.0, green: 0x3B / 255.0, blue: 0x30 / 255.0, alpha: 1))
ctx.addEllipse(in: CGRect(x: center.x - dotRadius, y: center.y - dotRadius,
                           width: dotRadius * 2, height: dotRadius * 2))
ctx.fillPath()

// Four white triangles, pointing inward from each edge, tips just touching the dot.
let baseHalfWidth: CGFloat = 105
let outerMargin: CGFloat = 165
let tipInset: CGFloat = dotRadius - 6 // slight overlap onto the dot for a "pressing" look

ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))

func triangle(base1: CGPoint, base2: CGPoint, tip: CGPoint) {
    ctx.beginPath()
    ctx.move(to: base1)
    ctx.addLine(to: base2)
    ctx.addLine(to: tip)
    ctx.closePath()
    ctx.fillPath()
}

// Top: base along the top edge, tip pointing down into the dot.
triangle(
    base1: CGPoint(x: center.x - baseHalfWidth, y: size - outerMargin),
    base2: CGPoint(x: center.x + baseHalfWidth, y: size - outerMargin),
    tip: CGPoint(x: center.x, y: center.y + tipInset)
)
// Bottom: base along the bottom edge, tip pointing up into the dot.
triangle(
    base1: CGPoint(x: center.x - baseHalfWidth, y: outerMargin),
    base2: CGPoint(x: center.x + baseHalfWidth, y: outerMargin),
    tip: CGPoint(x: center.x, y: center.y - tipInset)
)
// Left: base along the left edge, tip pointing right into the dot.
triangle(
    base1: CGPoint(x: outerMargin, y: center.y - baseHalfWidth),
    base2: CGPoint(x: outerMargin, y: center.y + baseHalfWidth),
    tip: CGPoint(x: center.x - tipInset, y: center.y)
)
// Right: base along the right edge, tip pointing left into the dot.
triangle(
    base1: CGPoint(x: size - outerMargin, y: center.y - baseHalfWidth),
    base2: CGPoint(x: size - outerMargin, y: center.y + baseHalfWidth),
    tip: CGPoint(x: center.x + tipInset, y: center.y)
)

let image = ctx.makeImage()!
let outURL = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(outURL.path)")
