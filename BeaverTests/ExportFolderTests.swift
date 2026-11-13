#if os(iOS)
import BeaverCore
import Foundation
import Testing
@testable import Beaver

/// On iOS each export goes into its own `export-<time>` folder in Beaver's Documents folder.
@MainActor
struct ExportFolderTests {
    private let documents: URL
    private let utc = TimeZone(identifier: "UTC")!
    /// 2026-11-13 22:50:12 UTC.
    private let exportTime = Date(timeIntervalSince1970: 1_794_610_212)

    init() throws {
        documents = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeaverExportFolderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
    }

    private func makeService(at date: Date? = nil) -> DocumentsSaveLocationService {
        let time = date ?? exportTime
        return DocumentsSaveLocationService(directory: documents, timeZone: utc, now: { time })
    }

    private func contents(of folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    // MARK: - The folder

    @Test func folderNameIsSortableLocalTimeWithoutColons() {
        let name = DocumentsSaveLocationService.exportFolderName(for: exportTime, timeZone: utc)
        #expect(name == "export-2026-11-13_22-50-12")
        #expect(!name.contains(":"))

        let vienna = TimeZone(identifier: "Europe/Vienna")!
        #expect(DocumentsSaveLocationService.exportFolderName(for: exportTime, timeZone: vienna) == "export-2026-11-13_23-50-12")
    }

    @Test func aPDFIsSavedInsideANewExportFolderUnderItsUsualName() throws {
        let url = try #require(makeService().saveLocation(defaultName: "Merged.pdf", prompt: "", contentType: .pdf))

        #expect(url.lastPathComponent == "Merged.pdf")
        #expect(url.deletingLastPathComponent().lastPathComponent == "export-2026-11-13_22-50-12")
        #expect(url.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL == documents.standardizedFileURL)
        #expect(try contents(of: documents) == ["export-2026-11-13_22-50-12"])
    }

    @Test func pageImagesGoStraightIntoTheExportFolder() throws {
        let folder = try #require(makeService().folderLocation(defaultName: "sample_images", prompt: ""))

        #expect(folder.lastPathComponent == "export-2026-11-13_22-50-12")
        #expect(folder.deletingLastPathComponent().standardizedFileURL == documents.standardizedFileURL)
        #expect(try contents(of: folder).isEmpty)
    }

    @Test func twoExportsInTheSameSecondGetTheirOwnFolders() throws {
        let service = makeService()
        let first = try #require(service.saveLocation(defaultName: "Merged.pdf", prompt: "", contentType: .pdf))
        let second = try #require(service.saveLocation(defaultName: "Merged.pdf", prompt: "", contentType: .pdf))

        #expect(first.deletingLastPathComponent().lastPathComponent == "export-2026-11-13_22-50-12")
        #expect(second.deletingLastPathComponent().lastPathComponent == "export-2026-11-13_22-50-12 (2)")
        #expect(second.lastPathComponent == "Merged.pdf")
    }

    @Test func eachExportGetsAFolderForItsOwnTime() throws {
        let earlier = try #require(makeService().folderLocation(defaultName: "a", prompt: ""))
        let later = try #require(makeService(at: exportTime.addingTimeInterval(61)).folderLocation(defaultName: "a", prompt: ""))

        #expect(earlier.lastPathComponent == "export-2026-11-13_22-50-12")
        #expect(later.lastPathComponent == "export-2026-11-13_22-51-13")
    }

    @Test func scansStillSaveStraightIntoDocuments() throws {
        let scans = DocumentsSaveLocationService(directory: documents, groupsIntoExportFolders: false)
        let url = try #require(scans.saveLocation(defaultName: "Scan.pdf", prompt: "", contentType: .pdf))

        #expect(url.deletingLastPathComponent().standardizedFileURL == documents.standardizedFileURL)
        #expect(try contents(of: documents).isEmpty)
    }

    // MARK: - Cleaning up

    @Test func discardRemovesAnEmptyExportFolderButKeepsOneWithFiles() throws {
        let service = makeService()
        let unused = try #require(service.saveLocation(defaultName: "Merged.pdf", prompt: "", contentType: .pdf))
        let used = try #require(service.saveLocation(defaultName: "Merged.pdf", prompt: "", contentType: .pdf))
        try Data("pdf".utf8).write(to: used)

        service.discardIfUnused(unused)
        service.discardIfUnused(used)

        #expect(!FileManager.default.fileExists(atPath: unused.deletingLastPathComponent().path))
        #expect(FileManager.default.fileExists(atPath: used.path))
    }

    @Test func discardNeverRemovesDocumentsOrFoldersOutsideIt() throws {
        let scans = DocumentsSaveLocationService(directory: documents, groupsIntoExportFolders: false)
        let scan = try #require(scans.saveLocation(defaultName: "Scan.pdf", prompt: "", contentType: .pdf))
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeaverOutside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)

        scans.discardIfUnused(scan)
        scans.discardIfUnused(outside)

        #expect(FileManager.default.fileExists(atPath: documents.path))
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }

    // MARK: - Through the reactor

    @Test func mergeSavesIntoTheExportFolderAndTheBannerOpensIt() async throws {
        let reactor = BeaverReactor(saveLocationProvider: makeService(), imageService: MockImageService())
        await reactor.action(.addFiles([TestFixtures.samplePDF, TestFixtures.sample2PDF]))

        await reactor.exportOneFile()

        let alert = try #require(reactor.state.exportAlert)
        #expect(alert.isSuccess)
        let output = try #require(alert.output)
        let folder = documents.appendingPathComponent("export-2026-11-13_22-50-12", isDirectory: true)
        #expect(output.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: output.path))

        let link = try #require(ExportBannerPolicy.filesAppURL(showing: output, isFolder: false))
        #expect(URL(filePath: link.path(percentEncoded: false)).lastPathComponent == "export-2026-11-13_22-50-12")
    }

    @Test func pageImagesLandInTheExportFolderAndTheBannerOpensIt() async throws {
        let reactor = BeaverReactor(saveLocationProvider: makeService(), imageService: MockImageService())
        await reactor.action(.addFiles([TestFixtures.samplePDF]))

        await reactor.action(.perform(.exportPNG))

        let alert = try #require(reactor.state.exportAlert)
        #expect(alert.isSuccess)
        let folder = documents.appendingPathComponent("export-2026-11-13_22-50-12", isDirectory: true)
        let output = try #require(alert.output)
        #expect(output.standardizedFileURL.path == folder.standardizedFileURL.path)
        #expect(try contents(of: folder).allSatisfy { $0.hasSuffix(".png") })
        #expect(try !contents(of: folder).isEmpty)
        #expect(alert.sharedFiles.allSatisfy { $0.deletingLastPathComponent().standardizedFileURL.path == folder.standardizedFileURL.path })

        let link = try #require(ExportBannerPolicy.filesAppURL(showing: output, isFolder: true))
        #expect(URL(filePath: link.path(percentEncoded: false)).lastPathComponent == "export-2026-11-13_22-50-12")
    }

    @Test func cancelledExportLeavesNoFolderBehind() async {
        let export = MockExportService(result: .cancelled)
        let reactor = BeaverReactor(saveLocationProvider: makeService(), imageService: MockImageService(), exportService: export)
        await reactor.action(.addFiles([TestFixtures.samplePDF, TestFixtures.sample2PDF]))

        await reactor.exportOneFile()

        #expect(reactor.state.exportAlert?.isSuccess != true)
        #expect((try? contents(of: documents)) == [])
    }

    @Test func cancelledPageImagesLeaveNoFolderBehind() async {
        let export = MockExportService(result: .cancelled)
        let reactor = BeaverReactor(saveLocationProvider: makeService(), imageService: MockImageService(), exportService: export)
        await reactor.action(.addFiles([TestFixtures.samplePDF]))

        await reactor.action(.perform(.exportJPEG))

        #expect(reactor.state.exportAlert?.isSuccess != true)
        #expect((try? contents(of: documents)) == [])
    }

    @Test func failedExportLeavesNoFolderBehind() async {
        let export = MockExportService(result: ExportAlert(message: "failed", isSuccess: false))
        let reactor = BeaverReactor(saveLocationProvider: makeService(), imageService: MockImageService(), exportService: export)
        await reactor.action(.addFiles([TestFixtures.samplePDF, TestFixtures.sample2PDF]))

        await reactor.exportOneFile()

        #expect(reactor.state.exportAlert?.isSuccess == false)
        #expect((try? contents(of: documents)) == [])
    }
}
#endif
