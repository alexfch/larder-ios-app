import SwiftUI
import UniformTypeIdentifiers

/// Wraps a backup's JSON `Data` for SwiftUI's `.fileExporter`, so exporting reuses the system's
/// own save/share picker (Files, AirDrop, iCloud Drive, etc.) instead of a custom share-sheet
/// bridge — the user picks the destination, which is the actual security-relevant decision for
/// this feature (see `BackupPayload`'s doc comment).
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
