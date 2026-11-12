import XCTest
@testable import Ailen

@MainActor
final class FoldersAndClearLibraryTests: XCTestCase {
    private func track(_ title: String, folder: String?) -> LocalTrack {
        LocalTrack(id: UUID(), title: title, artist: nil, artworkFileName: nil,
                   fileName: "\(UUID().uuidString).mp3", importedAt: Date(),
                   fileSizeBytes: 1, durationSeconds: nil, folderPath: folder)
    }

    // MARK: - Folders

    func test_relativeFolderBelowThePickedRoot() {
        let root = URL(fileURLWithPath: "/tmp/Musica")
        XCTAssertEqual(FolderImporter.relativeFolder(of: root.appendingPathComponent("Rock/Queen/a.flac"), in: root), "Rock/Queen")
        XCTAssertEqual(FolderImporter.relativeFolder(of: root.appendingPathComponent("suelta.mp3"), in: root), "")
    }

    func test_folderLevelsListSubfoldersAndSongsHere() {
        let tracks = [
            track("Bohemian", folder: "Rock/Queen"),
            track("Radio Gaga", folder: "Rock/Queen"),
            track("Rock suelto", folder: "Rock"),
            track("Jazz 1", folder: "Jazz"),
            track("En la raíz", folder: ""),
            track("Antigua", folder: nil),
        ]
        let top = LibraryViewModel.folderContents(tracks, at: [])
        XCTAssertEqual(top.folders.map(\.title), ["Jazz", "Rock", "Sin carpeta"], "A→Z, unknown last")
        XCTAssertEqual(top.folders.map(\.songCount), [1, 3, 1], "counts include subfolders")
        XCTAssertEqual(top.tracks.map(\.title), ["En la raíz"])

        let rock = LibraryViewModel.folderContents(tracks, at: ["Rock"])
        XCTAssertEqual(rock.folders.map(\.title), ["Queen"])
        XCTAssertEqual(rock.tracks.map(\.title), ["Rock suelto"])

        let queen = LibraryViewModel.folderContents(tracks, at: ["Rock", "Queen"])
        XCTAssertTrue(queen.folders.isEmpty)
        XCTAssertEqual(queen.tracks.map(\.title), ["Bohemian", "Radio Gaga"], "input order kept")

        let unknown = LibraryViewModel.folderContents(tracks, at: [LibraryViewModel.noFolderKey])
        XCTAssertEqual(unknown.tracks.map(\.title), ["Antigua"])
    }

    func test_folderPathSurvivesEncoding() throws {
        let original = track("A", folder: "Rock/Queen")
        let decoded = try JSONDecoder().decode(LocalTrack.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.folderPath, "Rock/Queen")
        XCTAssertEqual(decoded.withGenre("Rock").folderPath, "Rock/Queen", "copies keep the folder")
    }

    // MARK: - Limpiar biblioteca

    func test_removeAllDeletesImportedFilesOnly() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lib_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let entry = track("A", folder: "Rock")
        try Data([1, 2, 3]).write(to: dir.appendingPathComponent(entry.fileName))
        let other = dir.appendingPathComponent("no-indexado.txt")
        try Data([9]).write(to: other)

        let store = InMemoryKeyValueStore(seed: try JSONEncoder().encode([entry]))
        let library = LocalLibraryManager(store: store, libraryDirectory: dir)
        XCTAssertEqual(library.tracks.count, 1)

        library.removeAll()

        XCTAssertTrue(library.tracks.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent(entry.fileName).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path), "only indexed files are deleted")
    }

    func test_playerForgetsEveryLocalTrack() throws {
        let player = PlayerManager(urlSession: MockURLSession())
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("p_\(UUID().uuidString).mp3")
        try Data(repeating: 0, count: 16).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let local = Track(id: "local:\(UUID().uuidString)", title: "L", artist: "A", localFileURL: file)
        player.play(local)
        player.queue = [Track(id: "local:\(UUID().uuidString)", title: "Q", artist: "A", localFileURL: file)]

        player.forget(where: { $0.localFileURL != nil })

        XCTAssertNil(player.currentTrack)
        XCTAssertTrue(player.queue.isEmpty)
    }
}
