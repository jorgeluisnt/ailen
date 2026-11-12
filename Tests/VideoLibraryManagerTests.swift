import XCTest
@testable import Ailen

@MainActor
final class VideoLibraryManagerTests: XCTestCase {
    private var tmp: URL!
    private var root: URL!

    override func setUp() async throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("videos_\(UUID().uuidString)")
        root = tmp.appendingPathComponent("Peliculas")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Viajes/2024"), withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func makeManager(store: KeyValueStore = InMemoryKeyValueStore(),
                             playable: Bool = true) -> VideoLibraryManager {
        VideoLibraryManager(
            store: store,
            thumbnailsDirectory: tmp.appendingPathComponent("thumbs"),
            isCloudFileNotDownloaded: { _ in false },
            inspect: { _ in playable ? VideoProbe(durationSeconds: 120, title: nil) : nil },
            makeThumbnail: { _, _ in Data([0xFF, 0xD8, 0xFF]) }
        )
    }

    @discardableResult
    private func file(_ relative: String, bytes: Int = 16) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try Data(repeating: 1, count: bytes).write(to: url)
        return url
    }

    func test_folderLinksSupportedVideosWithRelativePathsAndNoCopies() async throws {
        try file("intro.mp4")
        try file("Viajes/playa.mov")
        try file("Viajes/2024/montana.m4v")
        try file("Viajes/peli.mkv")       // unsupported
        try file("notas.txt")
        let manager = makeManager()

        let progress = await manager.addFolder(root)

        XCTAssertEqual(progress.imported, 3)
        XCTAssertEqual(manager.sources.map(\.displayName), ["Peliculas"])
        XCTAssertEqual(Set(manager.videos.compactMap(\.relativePath)),
                       ["intro.mp4", "Viajes/playa.mov", "Viajes/2024/montana.m4v"])
        XCTAssertEqual(manager.videos.first { $0.relativePath == "Viajes/2024/montana.m4v" }?.folderPath, "Viajes/2024")
        XCTAssertEqual(manager.videos.first { $0.relativePath == "intro.mp4" }?.folderPath, "")
        XCTAssertNotNil(manager.videos.first?.thumbnailFileName)
        // Only thumbnails were written to the app; the folder holds 5 originals.
        let thumbs = try FileManager.default.contentsOfDirectory(atPath: manager.thumbnailsDirectory.path)
        XCTAssertEqual(thumbs.count, 3)
    }

    func test_reAddingAFolderOnlyLinksNewVideos() async throws {
        try file("a.mp4")
        let manager = makeManager()
        _ = await manager.addFolder(root)
        try file("b.mp4")

        let second = await manager.addFolder(root)

        XCTAssertEqual(second.imported, 1)
        XCTAssertEqual(manager.videos.count, 2)
        XCTAssertEqual(manager.sources.count, 1, "same folder → same source")
    }

    func test_singleFilesAreValidated() async throws {
        let good = try file("bueno.mp4")
        let mkv = try file("otro.mkv")
        let empty = try file("vacio.mov", bytes: 0)
        let manager = makeManager()

        let failures = await manager.addFiles([good, mkv, empty])

        XCTAssertEqual(manager.videos.map(\.title), ["bueno"])
        XCTAssertNotNil(manager.videos.first?.fileBookmark)
        XCTAssertEqual(failures.count, 2)
        XCTAssertTrue(failures[0].contains("MKV no es compatible"))
        XCTAssertTrue(failures[1].contains("vacío"))
    }

    func test_unplayableFileIsRejected() async throws {
        let audioOnly = try file("solo-audio.mp4")
        let manager = makeManager(playable: false)
        let failures = await manager.addFiles([audioOnly])
        XCTAssertTrue(manager.videos.isEmpty)
        XCTAssertTrue(failures.first?.contains("no se puede reproducir") == true)
    }

    func test_indexPersistsAndRemoveNeverTouchesOriginals() async throws {
        let original = try file("a.mp4")
        let store = InMemoryKeyValueStore()
        let manager = makeManager(store: store)
        _ = await manager.addFolder(root)
        manager.setResume(manager.videos[0].id, seconds: 42)
        manager.flushPendingWrites()

        let relaunched = makeManager(store: store)
        XCTAssertEqual(relaunched.videos.first?.resumePosition, 42)
        XCTAssertEqual(relaunched.sources.count, 1)

        relaunched.removeAll()
        XCTAssertTrue(relaunched.videos.isEmpty)
        XCTAssertTrue(relaunched.sources.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path), "the original video stays")
    }

    func test_openResolvesTheLinkedFileAndAuditFlagsMissing() async throws {
        let video = try file("Viajes/playa.mov")
        let manager = makeManager()
        _ = await manager.addFolder(root)
        let item = try XCTUnwrap(manager.videos.first)

        let access = try XCTUnwrap(manager.open(item))
        XCTAssertEqual(access.url.resolvingSymlinksInPath().path, video.resolvingSymlinksInPath().path)
        access.stop()

        try FileManager.default.removeItem(at: video)
        manager.auditMissingFlags()
        XCTAssertTrue(manager.videos.first?.isMissing == true)
    }

    func test_resumeRule() {
        XCTAssertNil(VideoResume.position(current: 3, duration: 100), "first seconds aren't worth saving")
        XCTAssertEqual(VideoResume.position(current: 40, duration: 100), 40)
        XCTAssertNil(VideoResume.position(current: 96, duration: 100), "finished")
        XCTAssertEqual(VideoResume.position(current: 40, duration: nil), 40)
    }

    func test_genericFolderContentsWorksForVideos() {
        let paths: [String?] = ["Viajes/2024", "Viajes", "", nil]
        let top = LibraryViewModel.folderContents(paths, at: [], folderPath: { $0 })
        XCTAssertEqual(top.folders.map(\.title), ["Viajes", "Sin carpeta"])
        XCTAssertEqual(top.items.count, 1, "the item directly in the linked folder")
    }
}
