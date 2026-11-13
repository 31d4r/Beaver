import BeaverCore
import Foundation
import Testing
@testable import Beaver

/// What the card context menu's Share item sends: PDFs only, the whole selection when the
/// card is part of it, and that card alone otherwise.
@MainActor
struct WorkspaceCardActionsTests {
    private let secondPNG = URL(fileURLWithPath: "/tmp/second.png")

    /// PDF, image, PDF, image.
    private func makeMixedReactor() async -> BeaverReactor {
        let images = MockImageService()
        images.thumbnailsByURL[TestFixtures.samplePNG] = TestImages.solid(width: 10, height: 10)
        images.thumbnailsByURL[secondPNG] = TestImages.solid(width: 12, height: 12)
        let reactor = BeaverReactor(
            saveLocationProvider: MockSaveLocationProvider(),
            imageService: images,
            exportService: MockExportService()
        )
        await reactor.action(.addFiles([TestFixtures.samplePDF, TestFixtures.samplePNG, TestFixtures.sample2PDF, secondPNG]))
        return reactor
    }

    private func shareURLs(_ reactor: BeaverReactor, card index: Int) -> [URL] {
        let item = reactor.state.items[index]
        let isSelected = reactor.state.selection.contains(item.id)
        return WorkspaceCardActions(reactor: reactor, item: item, isSelected: isSelected).shareURLs
    }

    @Test func unselectedPDFCardSharesOnlyItself() async {
        let reactor = await makeMixedReactor()

        let urls = reactor.state.items.map(\.url)

        #expect(shareURLs(reactor, card: 0) == [urls[0]])
        #expect(shareURLs(reactor, card: 2) == [urls[2]])
    }

    @Test func imageCardOffersNoShare() async {
        let reactor = await makeMixedReactor()

        #expect(shareURLs(reactor, card: 1).isEmpty)
    }

    @Test func selectedPDFCardSharesSelectedPDFsInListOrder() async {
        let reactor = await makeMixedReactor()
        let ids = reactor.state.items.map(\.id)
        reactor.action(.select(ids[2], .none))
        reactor.action(.select(ids[1], .command))
        reactor.action(.select(ids[0], .command))

        #expect(shareURLs(reactor, card: 2) == [reactor.state.items[0].url, reactor.state.items[2].url])
    }

    @Test func pdfCardOutsideTheSelectionSharesOnlyItself() async {
        let reactor = await makeMixedReactor()
        reactor.action(.select(reactor.state.items[0].id, .none))

        #expect(shareURLs(reactor, card: 2) == [reactor.state.items[2].url])
    }
}
