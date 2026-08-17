import CVips
import Foundation

/// An opaque libvips image handle (a `VipsImage *` on the C side, never
/// exposed with its real struct type — see cvips_shim.h for why).
public typealias VipsImageRef = UnsafeMutableRawPointer

public enum VipsRuntime {
    private static let initialized: Bool = {
        cvips_init(CommandLine.arguments[0]) == 0
    }()

    public static func ensureInitialized() {
        _ = initialized
    }

    public static var lastError: String {
        String(cString: cvips_error_buffer())
    }

    public static func unref(_ image: VipsImageRef) {
        cvips_unref(image)
    }
}
