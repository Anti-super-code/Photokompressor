import Foundation

enum FileSizeFormatting {
    static func string(_ bytes: Int64) -> String {
        switch bytes {
        case 1_073_741_824...: return String(format: "%.2f GB", Double(bytes) / 1_073_741_824.0)
        case 1_048_576...: return String(format: "%.1f MB", Double(bytes) / 1_048_576.0)
        case 1024...: return String(format: "%.0f KB", Double(bytes) / 1024.0)
        default: return "\(bytes) B"
        }
    }
}
