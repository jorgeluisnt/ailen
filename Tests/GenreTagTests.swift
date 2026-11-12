import XCTest
@testable import Ailen

final class GenreTagTests: XCTestCase {
    func test_genreIdentifiersPerFormat() {
        // Identifiers observed with AVFoundation on FLAC, MP4, MP3 and WAV files.
        for id in ["vorb/GENRE", "itsk/%A9gen", "id3/TCON", "caaf/info-genre",
                   "mdta/com.apple.quicktime.genre"] {
            XCTAssertTrue(GenreTag.isGenreIdentifier(id), id)
        }
        XCTAssertFalse(GenreTag.isGenreIdentifier("id3/TIT2"))
        XCTAssertFalse(GenreTag.isGenreIdentifier("itsk/%A9alb"))
    }

    func test_normalizedGenre() {
        XCTAssertEqual(GenreTag.normalizedGenre(" Rock "), "Rock")
        XCTAssertEqual(GenreTag.normalizedGenre("FusiÃ³n"), "Fusión", "UTF-8 read as Latin-1 is repaired")
        XCTAssertEqual(GenreTag.normalizedGenre("Música"), "Música")
        XCTAssertEqual(GenreTag.normalizedGenre("ロック"), "ロック")
        XCTAssertNil(GenreTag.normalizedGenre("(17)"), "ID3v1 numeric codes are not guessed")
        XCTAssertNil(GenreTag.normalizedGenre("17"))
        XCTAssertNil(GenreTag.normalizedGenre("   "))
    }

    func test_localTrackGenreSurvivesRoundTripAndOldDataDecodesAsUnread() throws {
        let track = LocalTrack(id: UUID(), title: "T", artist: nil, artworkFileName: nil,
                               fileName: "x.flac", importedAt: Date(), fileSizeBytes: 1,
                               durationSeconds: nil, genre: "Jazz")
        let decoded = try JSONDecoder().decode(LocalTrack.self, from: JSONEncoder().encode(track))
        XCTAssertEqual(decoded.genre, "Jazz")

        let old = #"{"id":"\#(UUID().uuidString)","title":"T","fileName":"x.flac","importedAt":0,"fileSizeBytes":1}"#
        let legacy = try JSONDecoder().decode(LocalTrack.self, from: Data(old.utf8))
        XCTAssertNil(legacy.genre, "pre-genre data means 'not read yet', so it gets backfilled")
        XCTAssertNil(legacy.displayGenre)
    }
}
