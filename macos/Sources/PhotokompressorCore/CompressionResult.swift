import Foundation

public enum ResultStatus: String, Codable {
    case compressed, keptOriginal, failed, cancelled
}

public struct CompressionResult: Codable {
    public let inputPath: String
    public let outputPath: String?
    public let beforeBytes: Int64
    public let afterBytes: Int64
    public let status: ResultStatus
    public let note: String?

    public init(inputPath: String, outputPath: String?, beforeBytes: Int64, afterBytes: Int64,
                status: ResultStatus, note: String?) {
        self.inputPath = inputPath
        self.outputPath = outputPath
        self.beforeBytes = beforeBytes
        self.afterBytes = afterBytes
        self.status = status
        self.note = note
    }
}
