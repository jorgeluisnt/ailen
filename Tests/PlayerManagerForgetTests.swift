import XCTest
@testable import Ailen

/// "Eliminar archivo" in Now Playing: the player must drop the track before
/// its file is deleted.
@MainActor
final class PlayerManagerForgetTests: XCTestCase {
    private var player: PlayerManager!
    private var files: [URL] = []

    override func setUp() {
        super.setUp()
        player = PlayerManager(urlSession: MockURLSession())
    }

    override func tearDown() {
        files.forEach { try? FileManager.default.removeItem(at: $0) }
        player = nil
        super.tearDown()
    }

    private func localTrack(_ name: String) throws -> Track {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)_\(UUID().uuidString).mp3")
        try Data(repeating: 0, count: 64).write(to: url)
        files.append(url)
        return Track(id: "local:\(UUID().uuidString)", title: name, artist: "A", localFileURL: url)
    }

    func test_forgetQueuedTrackOnlyRemovesItFromQueue() throws {
        let current = try localTrack("current"), doomed = try localTrack("doomed"), other = try localTrack("other")
        player.play(current)
        player.queue = [doomed, other, doomed]

        player.forget(doomed)

        XCTAssertEqual(player.currentTrack?.id, current.id)
        XCTAssertEqual(player.queue.map(\.id), [other.id])
    }

    func test_forgetCurrentTrackAdvancesToNextQueued() throws {
        let doomed = try localTrack("doomed"), next = try localTrack("next"), last = try localTrack("last")
        player.play(doomed)
        player.queue = [next, last]

        player.forget(doomed)

        XCTAssertEqual(player.currentTrack?.id, next.id)
        XCTAssertEqual(player.queue.map(\.id), [last.id])
    }

    func test_forgetCurrentTrackWithEmptyQueueStops() throws {
        let doomed = try localTrack("doomed")
        player.play(doomed)

        player.forget(doomed)

        XCTAssertNil(player.currentTrack)
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.playbackState, .idle)
    }
}
