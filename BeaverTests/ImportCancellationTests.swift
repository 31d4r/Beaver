import BeaverCore
import Foundation
import Testing
@testable import Beaver

/// Adding files shows the importing activity, and Cancel adds nothing, says nothing and
/// deletes only the copies Beaver made for that import.
@MainActor
struct ImportCancellationTests {
    private let images = MockImageService()

    private func makeReactor() -> BeaverReactor {
        images.thumbnailsByURL[TestFixtures.samplePNG] = TestImages.solid(width: 10, height: 10)
        return BeaverReactor(
            saveLocationProvider: MockSaveLocationProvider(),
            imageService: images,
            exportService: MockExportService()
        )
    }

    /// A copy of the sample image where Beaver keeps copies, in its own folder.
    private func makeImportedCopy() throws -> URL {
        let folder = ImportedFileStorage.directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appendingPathComponent("photo.png")
        try FileManager.default.copyItem(at: TestFixtures.samplePNG, to: copy)
        images.thumbnailsByURL[copy] = TestImages.solid(width: 10, height: 10)
        return copy
    }

    /// Starts adding `urls`, waits until the import shows, then cancels it.
    private func addThenCancel(_ urls: [URL], on reactor: BeaverReactor) async {
        images.blocksUntilCancelled = true
        let running = Task { await reactor.action(.addFiles(urls)) }
        while reactor.state.activity != .importing {
            await Task.yield()
        }
        #expect(!reactor.state.canEdit)
        reactor.action(.cancelExport)
        await running.value
        images.blocksUntilCancelled = false
    }

    @Test func importShowsTheActivityAndEndsIt() async {
        let reactor = makeReactor()

        await reactor.action(.addFiles([TestFixtures.samplePDF, TestFixtures.samplePNG]))

        #expect(reactor.state.items.count == 2)
        #expect(reactor.state.activity == nil)
        #expect(BeaverReactor.Activity.importing.title == DesignSystem.Progress.addingFiles)
    }

    @Test func cancelAddsNothingAndShowsNoError() async {
        let reactor = makeReactor()

        await addThenCancel([TestFixtures.samplePDF, TestFixtures.samplePNG], on: reactor)

        #expect(reactor.state.items.isEmpty)
        #expect(reactor.state.activity == nil)
        #expect(reactor.state.exportAlert == nil)
        #expect(reactor.state.canEdit)
        #expect(!reactor.state.canUndo)
    }

    @Test func cancelDeletesCopiesButNeverOriginals() async throws {
        let reactor = makeReactor()
        let copy = try makeImportedCopy()

        await addThenCancel([copy, TestFixtures.samplePNG, TestFixtures.samplePDF], on: reactor)

        #expect(!FileManager.default.fileExists(atPath: copy.deletingLastPathComponent().path))
        #expect(FileManager.default.fileExists(atPath: TestFixtures.samplePNG.path))
        #expect(FileManager.default.fileExists(atPath: TestFixtures.samplePDF.path))
    }

    @Test func cancelKeepsACopyThatUndoCanStillBringBack() async throws {
        let reactor = makeReactor()
        let copy = try makeImportedCopy()
        defer { ImportedFileStorage.discard([copy]) }
        await reactor.action(.addFiles([copy]))
        reactor.action(.remove(Set(reactor.state.items.map(\.id))))

        await addThenCancel([copy], on: reactor)

        #expect(FileManager.default.fileExists(atPath: copy.path))
        reactor.action(.undo)
        #expect(reactor.state.items.map(\.url) == [copy])
    }

    @Test func aCancelledImportCanBeStartedAgain() async {
        let reactor = makeReactor()
        await addThenCancel([TestFixtures.samplePNG], on: reactor)

        await reactor.action(.addFiles([TestFixtures.samplePNG]))

        #expect(reactor.state.items.map(\.url) == [TestFixtures.samplePNG])
    }

    @Test func storageDiscardLeavesFilesOutsideItAlone() throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImportCancellationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        let file = outside.appendingPathComponent("keep.png")
        try FileManager.default.copyItem(at: TestFixtures.samplePNG, to: file)

        #expect(!ImportedFileStorage.isCopy(file))
        ImportedFileStorage.discard([file])

        #expect(FileManager.default.fileExists(atPath: file.path))
    }
}
