import Foundation

/// Beaver's temporary folder for copies of files handed over by Photos, a drop or another app.
/// Each copy sits in its own folder there. Files the person picked in place are never in it,
/// so `discard` can't delete an original.
enum ImportedFileStorage {
    /// iOS empties it between launches.
    static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Imported", isDirectory: true)
    }

    /// Whether `url` is a copy Beaver made, in its own folder inside `directory`.
    static func isCopy(_ url: URL) -> Bool {
        url.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL.path
            == directory.standardizedFileURL.path
    }

    /// Deletes the copies among `urls`, each with the folder made for it; leaves every other file alone.
    static func discard(_ urls: [URL]) {
        for url in urls where isCopy(url) {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
    }
}
