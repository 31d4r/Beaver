import BeaverCore
import Foundation
import Testing
@testable import Beaver

/// Cancel in the progress bar, and the saved location the success banner reveals.
@MainActor
struct ExportCancellationTests {
    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeaverCancelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func cancelStopsTheExportAndShowsNothing() async {
        let panels = MockSaveLocationProvider()
        panels.saveURL = URL(fileURLWithPath: "/tmp/beaver-tests/merged.pdf")
        // The service honours Cancel before writing, as the real one does.
        let export = MockExportService(result: .cancelled, isGated: true)
        let reactor = BeaverReactor(saveLocationProvider: panels, imageService: MockImageService(), exportService: export)
        await reactor.action(.addFiles([TestFixtures.samplePDF, TestFixtures.sample2PDF]))

        let running = Task { await reactor.exportOneFile() }
        while reactor.state.activity == nil {
            await Task.yield()
        }
        reactor.action(.cancelExport)
        await running.value

        #expect(reactor.state.activity == nil)
        #expect(reactor.state.exportAlert == nil)
        #expect(reactor.state.canEdit)
        // Nothing was saved, so the save location may remove the folder it made for it.
        #expect(panels.discardedLocations == [panels.saveURL])
    }

    @Test func cancelAfterTheFileIsWrittenKeepsItAndShowsTheSavedBanner() async {
        let panels = MockSaveLocationProvider()
        let destination = URL(fileURLWithPath: "/tmp/beaver-tests/merged.pdf")
        panels.saveURL = destination
        // Cancel lands while the service is already writing, so it still reports the saved file.
        let saved = ExportAlert(message: "merged", isSuccess: true, output: destination)
        let export = MockExportService(result: saved, isGated: true)
        let reactor = BeaverReactor(saveLocationProvider: panels, imageService: MockImageService(), exportService: export)
        await reactor.action(.addFiles([TestFixtures.samplePDF, TestFixtures.sample2PDF]))

        let running = Task { await reactor.exportOneFile() }
        while reactor.state.activity == nil {
            await Task.yield()
        }
        reactor.action(.cancelExport)
        export.release()
        await running.value

        #expect(reactor.state.activity == nil)
        #expect(reactor.state.exportAlert == saved)
        #expect(reactor.state.exportAlert?.output == destination)
        #expect(reactor.state.canEdit)
        #expect(panels.discardedLocations.isEmpty)
    }

    @Test func cancelThenFailureShowsNoError() async {
        let panels = MockSaveLocationProvider()
        panels.saveURL = URL(fileURLWithPath: "/tmp/beaver-tests/merged.pdf")
        let export = MockExportService(result: ExportAlert(message: "failed", isSuccess: false), isGated: true)
        let reactor = BeaverReactor(saveLocationProvider: panels, imageService: MockImageService(), exportService: export)
        await reactor.action(.addFiles([TestFixtures.samplePDF, TestFixtures.sample2PDF]))

        let running = Task { await reactor.exportOneFile() }
        while reactor.state.activity == nil {
            await Task.yield()
        }
        reactor.action(.cancelExport)
        export.release()
        await running.value

        #expect(reactor.state.exportAlert == nil)
        #expect(reactor.state.canEdit)
    }

    @Test func cancelWithoutAnExportDoesNothing() async {
        let reactor = BeaverReactor(
            saveLocationProvider: MockSaveLocationProvider(),
            imageService: MockImageService(),
            exportService: MockExportService()
        )
        await reactor.action(.addFiles([TestFixtures.samplePDF]))

        reactor.action(.cancelExport)

        #expect(reactor.state.activity == nil)
        #expect(reactor.state.items.count == 1)
    }

    @Test func cancelledMergeWritesNoFile() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("merged.pdf")

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await ExportService().mergePDFs(urls: [TestFixtures.samplePDF], rotations: [], to: destination)
        }
        let alert = await task.value

        #expect(alert == .cancelled)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func cancelledSplitWritesNoPages() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await ExportService().splitPDFs(urls: [TestFixtures.sample2PDF], rotations: [], into: directory)
        }
        let alert = await task.value

        #expect(alert == .cancelled)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.isEmpty)
    }

    @Test func cancelDuringSplitRemovesThePagesAlreadyWritten() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileIO = CancellingFileIOService()
        let service = ExportService(writer: PDFFileWriterService(fileIOService: fileIO))

        let alert = await Task {
            await service.splitPDFs(urls: [TestFixtures.samplePDF, TestFixtures.sample2PDF], rotations: [], into: directory)
        }.value

        #expect(alert == .cancelled)
        #expect(fileIO.writeCount == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test func cancelDuringPageImagesRemovesTheImagesAlreadyWritten() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileIO = CancellingFileIOService()
        let service = ExportService(fileIOService: fileIO)
        let sources = [TestFixtures.samplePDF, TestFixtures.sample2PDF].map { PageExportSource(url: $0) }

        let alert = await Task {
            await service.exportPageImages(sources, as: .png, into: directory)
        }.value

        #expect(alert == .cancelled)
        #expect(fileIO.writeCount == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test func cancelledWriterStopsBetweenPagesAndListsWhatItWrote() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pages = PDFService().splitPDF(urls: [TestFixtures.samplePDF, TestFixtures.sample2PDF], rotations: []).pages
        try #require(pages.count > 1)

        let (successCount, savedURLs) = await Task {
            let result = PDFFileWriterService(fileIOService: CancellingFileIOService()).savePDFDocuments(pages, to: directory)
            return (result.successCount, result.savedURLs)
        }.value

        #expect(successCount == 1)
        #expect(savedURLs.count == 1)
        #expect(savedURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test func mergeReportsTheSavedFile() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("merged.pdf")

        let alert = await ExportService().mergePDFs(urls: [TestFixtures.samplePDF], rotations: [], to: destination)

        #expect(alert.isSuccess)
        #expect(alert.output == destination)
    }

    @Test func convertReportsTheSavedFile() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("images.pdf")

        let alert = await ExportService().convertImages(urls: [TestFixtures.samplePNG], rotations: [], to: destination, recognizeText: false)

        #expect(alert.isSuccess)
        #expect(alert.output == destination)
    }

    @Test func splitReportsTheFolder() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let alert = await ExportService().splitPDFs(urls: [TestFixtures.samplePDF], rotations: [], into: directory)

        #expect(alert.isSuccess)
        #expect(alert.output == directory)
    }

    @Test func failedMergeHasNoOutput() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missing = directory.appendingPathComponent("missing.pdf")

        let alert = await ExportService().mergePDFs(
            urls: [missing],
            rotations: [],
            to: directory.appendingPathComponent("merged.pdf")
        )

        #expect(!alert.isSuccess)
        #expect(alert.output == nil)
    }
}

/// Writes for real, then cancels the task that asked, as if Cancel arrived after the first file.
private final class CancellingFileIOService: FileIOServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var writes = 0
    private let fileIO = FileIOService()

    var writeCount: Int { lock.withLock { writes } }

    func write(data: Data, to url: URL) throws {
        try fileIO.write(data: data, to: url)
        lock.withLock { writes += 1 }
        withUnsafeCurrentTask { $0?.cancel() }
    }

    func fileExists(at url: URL) -> Bool {
        fileIO.fileExists(at: url)
    }
}
