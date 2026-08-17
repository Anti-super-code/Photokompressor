import Foundation

/// Direct port of FileResultItem.cs — one row in the progress list.
final class ResultRowItem: ObservableObject, Identifiable {
    let id: String // inputPath, unique per batch
    let fileName: String
    @Published var detail: String = ""
    @Published var badge: String = ""
    @Published var kind: Kind = .pending

    enum Kind: String {
        case pending, done, kept, failed, cancelled
    }

    init(inputPath: String) {
        self.id = inputPath
        self.fileName = (inputPath as NSString).lastPathComponent
    }
}
