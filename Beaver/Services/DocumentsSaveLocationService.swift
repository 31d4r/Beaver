#if os(iOS)
import BeaverCore
import Foundation
import UniformTypeIdentifiers

/// Saves new files into the app's Documents folder, which the Files app shows under
/// On My iPhone › Beaver. iOS has no modal save panel, so the export writes here first
/// and the banner then offers Share, and Show in Files to open the folder it went into.
///
/// Exports each get their own new folder, `export-2026-11-13_23-50-12`, named for the local
/// time they started, so they sort by date in Files and never mix with earlier ones.
@MainActor
struct DocumentsSaveLocationService: SaveLocationProviding {
    static let exportFolderPrefix = "export-"

    private let directory: URL?
    private let writer: PDFFileWriterService
    private let groupsIntoExportFolders: Bool
    private let timeZone: TimeZone
    private let now: () -> Date

    /// - Parameters:
    ///   - groupsIntoExportFolders: `false` saves straight into Documents, as finished scans do.
    ///   - now: The time that names a new export folder; tests pass a fixed one.
    init(
        directory: URL? = nil,
        writer: PDFFileWriterService = PDFFileWriterService(),
        groupsIntoExportFolders: Bool = true,
        timeZone: TimeZone = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.directory = directory
        self.writer = writer
        self.groupsIntoExportFolders = groupsIntoExportFolders
        self.timeZone = timeZone
        self.now = now
    }

    func saveLocation(defaultName: String, prompt: String, contentType: UTType) -> URL? {
        let folder: URL?
        if groupsIntoExportFolders {
            folder = makeExportFolder()
        } else if let documents = documentsFolder {
            try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
            folder = documents
        } else {
            folder = nil
        }
        return folder.map { writer.uniqueURL(for: defaultName, in: $0) }
    }

    /// The export folder itself, so page images sit right inside it; without export folders,
    /// a new folder `defaultName` (or `defaultName (2)`) in Documents.
    func folderLocation(defaultName: String, prompt: String) -> URL? {
        if groupsIntoExportFolders {
            return makeExportFolder()
        }
        guard let documents = documentsFolder else { return nil }
        return makeFolder(named: defaultName, in: documents)
    }

    /// Removes the folder made for `location` (a folder, or a file in one) when nothing was
    /// saved in it. Documents itself and anything outside it are never removed.
    func discardIfUnused(_ location: URL) {
        guard let documents = documentsFolder else { return }
        let isDirectory = (try? location.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        let folder = isDirectory ? location : location.deletingLastPathComponent()
        guard folder.deletingLastPathComponent().standardizedFileURL.path == documents.standardizedFileURL.path,
              let contents = try? FileManager.default.contentsOfDirectory(atPath: folder.path),
              contents.isEmpty
        else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    /// `export-2026-11-13_23-50-12`: local time, sortable, and without the colons Files
    /// doesn't allow in names.
    static func exportFolderName(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return exportFolderPrefix + formatter.string(from: date)
    }

    static var documentsDirectory: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    private var documentsFolder: URL? { directory ?? Self.documentsDirectory }

    /// A new export folder, with ` (2)` added when two exports start in the same second.
    private func makeExportFolder() -> URL? {
        guard let documents = documentsFolder else { return nil }
        return makeFolder(named: Self.exportFolderName(for: now(), timeZone: timeZone), in: documents)
    }

    private func makeFolder(named name: String, in parent: URL) -> URL? {
        let path = writer.uniqueURL(for: name, in: parent).path(percentEncoded: false)
        let folder = URL(filePath: path, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        return folder
    }
}
#endif
