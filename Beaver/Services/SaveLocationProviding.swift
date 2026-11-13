import Foundation
import UniformTypeIdentifiers

/// Asks where to save a new PDF or page image, or which folder to save several files into.
///
/// Opening files and choosing the split folder use SwiftUI's `fileImporter`, which
/// works on every platform. Saving stays behind this protocol because the PDF is
/// only built after the destination is known, so the export can show progress
/// and report skipped files. The Mac asks with a save panel; iOS saves into the
/// app's Documents folder and then offers Share and Show in Files.
@MainActor
protocol SaveLocationProviding {
    /// Where to save one new file of `contentType`, or `nil` when the person cancels.
    func saveLocation(defaultName: String, prompt: String, contentType: UTType) -> URL?
    /// A folder to save several new files into, or `nil` when the person cancels. The Mac asks
    /// with an open panel, as Split does; iOS makes a new folder named `defaultName` in Beaver's
    /// Documents folder.
    func folderLocation(defaultName: String, prompt: String) -> URL?
    /// Called after an export that saved nothing (it failed or was cancelled) with the location
    /// it was given, so a folder made just for it doesn't stay behind empty.
    func discardIfUnused(_ location: URL)
}

extension SaveLocationProviding {
    /// The Mac's panels make no folders of their own, so there is nothing to remove.
    func discardIfUnused(_ location: URL) {}

    /// Where to save one new PDF.
    func saveLocation(defaultName: String, prompt: String) -> URL? {
        saveLocation(defaultName: defaultName, prompt: prompt, contentType: .pdf)
    }
}

#if os(macOS)
/// The save location each platform uses by default. On iOS each export gets its own folder.
typealias PlatformSaveLocationService = SavePanelService
#else
typealias PlatformSaveLocationService = DocumentsSaveLocationService
#endif

extension PlatformSaveLocationService {
    /// Where finished scans go: the save panel on the Mac, and straight into Beaver's
    /// Documents folder on iOS, without an export folder.
    static func forScans() -> PlatformSaveLocationService {
        #if os(macOS)
        SavePanelService()
        #else
        DocumentsSaveLocationService(groupsIntoExportFolders: false)
        #endif
    }
}
