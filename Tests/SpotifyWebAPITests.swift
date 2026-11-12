import XCTest
@testable import Ailen

final class SpotifyWebAPITests: XCTestCase {
    func test_searchURLUsesTheDevelopmentModeLimit() {
        let url = SpotifyWebAPI.searchURL(query: "café tacvba", offset: 20)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(url.path, "/v1/search")
        XCTAssertEqual(query["limit"], "10")
        XCTAssertEqual(query["offset"], "20")
        XCTAssertEqual(query["type"], "track,album,playlist")
        XCTAssertEqual(query["q"], "café tacvba")
    }

    func test_decodesPlaylistsWithOldAndNewCountFields() throws {
        let json = #"""
        {"items":[
          {"id":"a","name":"Mía","uri":"spotify:playlist:a","owner":{"id":"me","display_name":"Yo"},"collaborative":false,"items":{"total":12},"images":[{"url":"https://i.scdn.co/a"}]},
          {"id":"b","name":"Seguida","uri":"spotify:playlist:b","owner":{"id":"spotify"},"tracks":{"total":50},"images":null}
        ],"next":null,"total":2}
        """#
        let page = try JSONDecoder().decode(SpotifyPage<SpotifyPlaylist>.self, from: Data(json.utf8))
        XCTAssertEqual(page.items.map(\.count), [12, 50])
        XCTAssertEqual(page.items.first?.imageURL?.absoluteString, "https://i.scdn.co/a")
        XCTAssertNil(page.items.last?.imageURL)
    }

    func test_searchSkipsNullPlaylistsAndEntriesReadTrackOrItem() throws {
        let json = #"""
        {"tracks":{"items":[{"id":"t","name":"Canción","uri":"spotify:track:t","duration_ms":200000,"artists":[{"name":"A"},{"name":"B"}]}],"next":"x"},
         "playlists":{"items":[null,{"id":"p","name":"Lista","uri":"spotify:playlist:p"}],"next":null}}
        """#
        let result = try JSONDecoder().decode(SpotifySearchResponse.self, from: Data(json.utf8))
        XCTAssertEqual(result.tracks?.items.first?.artistNames, "A, B")
        XCTAssertEqual(result.playlists?.items.compactMap { $0 }.map(\.name), ["Lista"])

        let entries = #"{"items":[{"track":{"name":"Vieja","uri":"u1"}},{"item":{"name":"Nueva","uri":"u2"}},{"track":null}]}"#
        let page = try JSONDecoder().decode(SpotifyPage<SpotifyTrackEntry>.self, from: Data(entries.utf8))
        XCTAssertEqual(page.items.compactMap(\.value).map(\.name), ["Vieja", "Nueva"])
    }

    func test_statusCodesMapToSpanishMessages() {
        XCTAssertNil(SpotifyAPIError.from(status: 200, retryAfter: nil))
        XCTAssertEqual(SpotifyAPIError.from(status: 401, retryAfter: nil), .unauthorized)
        XCTAssertEqual(SpotifyAPIError.from(status: 403, retryAfter: nil), .forbidden)
        XCTAssertEqual(SpotifyAPIError.from(status: 429, retryAfter: "7"), .rateLimited(retryAfter: 7))
        XCTAssertTrue(SpotifyAPIError.forbidden.message.contains("modo desarrollo"))
        XCTAssertTrue(SpotifyAPIError.rateLimited(retryAfter: 7).message.contains("7 s"))
    }

    func test_positionAdvancesOnlyWhilePlayingAndStopsAtTheEnd() {
        let start = Date()
        var state = SpotifyTrackState(uri: "u", title: "t", artist: "a", album: "b", durationMs: 10_000,
                                      positionMs: 4_000, reportedAt: start, isPaused: false,
                                      isShuffling: false, repeatMode: 0)
        XCTAssertEqual(state.position(at: start.addingTimeInterval(2)), 6, accuracy: 0.01)
        XCTAssertEqual(state.position(at: start.addingTimeInterval(60)), 10, accuracy: 0.01, "capped at duration")
        state.isPaused = true
        XCTAssertEqual(state.position(at: start.addingTimeInterval(5)), 4, accuracy: 0.01)
    }
}
