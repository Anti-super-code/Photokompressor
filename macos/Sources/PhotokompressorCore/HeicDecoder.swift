import Foundation
import ImageIO
import CoreGraphics
import CVips

/// The Windows build decodes HEIC via Magick.NET because bundled libvips can't
/// (H.265 patent licensing). macOS's own ImageIO has decoded HEIC natively
/// since 2017, so this is simpler and better here: no third-party decoder at
/// all. Mirrors HeicDecoder.cs's contract — decode, bake in EXIF orientation,
/// render into sRGB, hand vips a raw pixel buffer — just via CGImageSource
/// instead of Magick.NET.
public enum HeicDecoder {
    public static func isHeic(path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ext == "heic" || ext == "heif"
    }

    public enum HeicError: Error { case decodeFailed, renderFailed, vipsFailed }

    public static func load(path: String) throws -> VipsImageRef {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw HeicError.decodeFailed
        }
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = props[kCGImagePropertyPixelWidth] as? Int,
              let pixelHeight = props[kCGImagePropertyPixelHeight] as? Int else {
            throw HeicError.decodeFailed
        }
        // CGImageSourceCreateImageAtIndex has no "apply orientation" option —
        // only the thumbnail family does. Asking for a thumbnail no larger
        // than the source's own largest side never actually downscales it
        // (thumbnailing only ever shrinks), so this gets a full-resolution,
        // orientation-baked image, matching MagickImage.AutoOrient().
        let maxDim = max(pixelWidth, pixelHeight)
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDim,
            kCGImageSourceShouldCache: false,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            throw HeicError.decodeFailed
        }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw HeicError.renderFailed
        }

        let width = cgImage.width
        let height = cgImage.height
        let sourceHasAlpha = [CGImageAlphaInfo.premultipliedFirst, .premultipliedLast, .first, .last]
            .contains(cgImage.alphaInfo)

        // CGBitmapContext can't render tightly-packed 3-byte RGB, so we always
        // draw into a 4-band buffer (CG's draw() does the real color-managed
        // sRGB conversion from the source's embedded profile, same effect as
        // magick.TransformColorSpace(ColorProfiles.SRGB)), then strip the
        // alpha band afterwards for genuinely-opaque sources — matching
        // Magick.NET's 3-band export for photos with no real alpha channel,
        // so the Flatten step downstream isn't triggered needlessly and PNG/
        // WebP output doesn't gain a spurious constant-255 alpha channel.
        let bytesPerRow = width * 4
        var rgba = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let ctx = rgba.withUnsafeMutableBytes({ ptr -> CGContext? in
            CGContext(data: ptr.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow, space: colorSpace,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }) else {
            throw HeicError.renderFailed
        }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let vipsImage: VipsImageRef?
        if sourceHasAlpha {
            vipsImage = rgba.withUnsafeBufferPointer { ptr in
                cvips_image_from_srgb_buffer(ptr.baseAddress, ptr.count, Int32(width), Int32(height), 4)
            }
        } else {
            var rgb = [UInt8](repeating: 0, count: width * height * 3)
            rgba.withUnsafeBufferPointer { src in
                for pixel in 0..<(width * height) {
                    rgb[pixel * 3 + 0] = src[pixel * 4 + 0]
                    rgb[pixel * 3 + 1] = src[pixel * 4 + 1]
                    rgb[pixel * 3 + 2] = src[pixel * 4 + 2]
                }
            }
            vipsImage = rgb.withUnsafeBufferPointer { ptr in
                cvips_image_from_srgb_buffer(ptr.baseAddress, ptr.count, Int32(width), Int32(height), 3)
            }
        }

        guard let image = vipsImage else { throw HeicError.vipsFailed }
        return image
    }
}
