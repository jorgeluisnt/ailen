import XCTest
@testable import Ailen

final class TabletLayoutTests: XCTestCase {
    func test_tabletOnlyForRegularWidthInLandscape() {
        XCTAssertTrue(TabletLayout.isTablet(sizeClass: .regular, size: CGSize(width: 1210, height: 834)))
        XCTAssertFalse(TabletLayout.isTablet(sizeClass: .regular, size: CGSize(width: 834, height: 1210)),
                       "portrait iPad keeps the tab bar")
        XCTAssertFalse(TabletLayout.isTablet(sizeClass: .compact, size: CGSize(width: 932, height: 430)),
                       "landscape iPhone is compact")
        XCTAssertFalse(TabletLayout.isTablet(sizeClass: nil, size: CGSize(width: 1000, height: 500)))
    }

    func test_homeResolvesStoredTracksAgainstTheLibrary() {
        let present = LocalTrack(id: UUID(), title: "A", artist: "X", artworkFileName: nil,
                                 fileName: "a.flac", importedAt: Date(), fileSizeBytes: 1, durationSeconds: 60)
        let missing = LocalTrack(id: UUID(), title: "B", artist: "Y", artworkFileName: nil,
                                 fileName: "b.flac", importedAt: Date(), fileSizeBytes: 1, durationSeconds: 60,
                                 isMissing: true)
        let stale = URL(fileURLWithPath: "/old/container/a.flac")
        let stored = [
            Track(id: "local:\(present.id.uuidString)", title: "A", artist: "X", localFileURL: stale),
            Track(id: "local:\(present.id.uuidString)", title: "A", artist: "X", localFileURL: stale),  // duplicate
            Track(id: "local:\(missing.id.uuidString)", title: "B", artist: "Y"),                      // file missing
            Track(id: "yt123", title: "Streamed", artist: "Z"),                                          // not local
        ]
        let fresh = URL(fileURLWithPath: "/current/a.flac")
        let resolved = HomeView.resolveLocal(stored, in: [present, missing]) { _ in fresh }

        XCTAssertEqual(resolved.map(\.title), ["A"])
        XCTAssertEqual(resolved.first?.localFileURL, fresh, "URL rebuilt from the current library")
    }
}
