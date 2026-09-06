import Foundation

/// Numeric tuning per preset — kept identical to the Windows build's Presets.cs
/// so output size/quality tradeoffs match across platforms.
public enum Presets {
    public struct JpegParams { public let q: Int32; public let forceSubsampleOn: Bool }
    public struct PngParams { public let palette: Bool; public let q: Int32; public let dither: Double; public let effort: Int32 }
    public struct WebpParams { public let q: Int32; public let effort: Int32; public let alphaQ: Int32 }

    public static func jpeg(_ preset: QualityPreset) -> JpegParams {
        switch preset {
        case .high: return JpegParams(q: 82, forceSubsampleOn: false)
        case .balanced: return JpegParams(q: 72, forceSubsampleOn: true)
        case .smallest: return JpegParams(q: 58, forceSubsampleOn: true)
        }
    }

    public static func png(_ preset: QualityPreset) -> PngParams {
        switch preset {
        case .high: return PngParams(palette: false, q: 100, dither: 1.0, effort: 7)
        case .balanced: return PngParams(palette: true, q: 90, dither: 1.0, effort: 7)
        case .smallest: return PngParams(palette: true, q: 65, dither: 0.8, effort: 10)
        }
    }

    public static func webp(_ preset: QualityPreset) -> WebpParams {
        switch preset {
        case .high: return WebpParams(q: 80, effort: 4, alphaQ: 90)
        case .balanced: return WebpParams(q: 68, effort: 5, alphaQ: 85)
        case .smallest: return WebpParams(q: 52, effort: 6, alphaQ: 80)
        }
    }
}
