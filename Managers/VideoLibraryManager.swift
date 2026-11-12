import AVFoundation
import Combine
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Linked videos (MP4, MOV, M4V). Videos are never copied: the index keeps
/// security-scoped bookmarks to the linked folder or file and plays the
/// original. Only the index and small JPEG thumbnails live in the app.
@MainActor
final class VideoLibraryManager: ObservableObject {
    static let schemaVersion = 1
    static let extensions: Set<String> = ["mp4", "mov", "m4v"]

    @Published private(set) var videos: [VideoItem] = []
    @Published private(set) var sources: [VideoSource] = []

    let thumbnailsDirectory: URL
    private let store: KeyValueStore
    private let fileManager: FileManager
    private let isCloudFileNotDownloaded: (URL) -> Bool
    private let inspect: (URL) async -> VideoProbe?
    private let makeThumbnail: (URL, Double?) async -> Data?
    private var saveDebouncer: Debouncer!

    init(
        store: KeyValueStore,
        thumbnailsDirectory: URL,
        fileManager: FileManager = .default,
        isCloudFileNotDownloaded: @escaping (URL) -> Bool = LocalLibraryManager.defaultIsCloudFileNotDownloaded(_:),
        inspect: @escaping (URL) async -> VideoProbe? = VideoLibraryManager.defaultInspect(_:),
        makeThumbnail: @escaping (URL, Double?) async -> Data? = VideoLibraryManager.defaultThumbnail(_:duration:)
    ) {
        self.store = store
        self.thumbnailsDirectory = thumbnailsDirectory
        self.fileManager = fileManager
        self.isCloudFileNotDownloaded = isCloudFileNotDownloaded
        self.inspect = inspect
        self.makeThumbnail = makeThumbnail
        self.saveDebouncer = Debouncer(delay: 0.5) { [weak self] in self?.performSave() }
        try? fileManager.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
        if let state = SchemaStore.loadItems(VideoLibraryState.self, from: store,
                                             currentVersion: Self.schemaVersion)?.first {
            sources = state.sources
            videos = state.videos
        }
    }

    // MARK: - Linking

    /// Links single files (from the document picker). Returns one Spanish
    /// message per file that could not be linked.
    func addFiles(_ urls: [URL]) async -> [String] {
        var failures: [String] = []
        for url in urls {
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            if isAlreadyLinked(file: url) { continue }
            do {
                let bookmark = try url.bookmarkData(options: .minimalBookmark,
                                                    includingResourceValuesForKeys: nil, relativeTo: nil)
                var item = try await makeItem(for: url)
                item.fileBookmark = bookmark
                item.folderPath = url.deletingLastPathComponent().lastPathComponent
                videos.insert(item, at: 0)
                save()
            } catch let error as VideoImportError {
                failures.append(error.message(fileName: url.lastPathComponent))
            } catch {
                failures.append("No se pudo añadir \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return failures
    }

    /// Links a folder: one bookmark for the folder, one entry per video
    /// below it. Re-adding a linked folder only picks up new videos.
    func addFolder(_ root: URL,
                   onProgress: @MainActor (FolderImporter.Progress) -> Void = { _ in }) async -> FolderImporter.Progress {
        let didStart = root.startAccessingSecurityScopedResource()
        defer { if didStart { root.stopAccessingSecurityScopedResource() } }
        guard let bookmark = try? root.bookmarkData(options: .minimalBookmark,
                                                     includingResourceValuesForKeys: nil, relativeTo: nil) else {
            return FolderImporter.Progress()
        }
        let source: VideoSource
        if let existing = sources.first(where: { resolve($0.bookmark)?.standardizedFileURL == root.standardizedFileURL }) {
            source = existing
        } else {
            source = VideoSource(id: UUID(), displayName: root.lastPathComponent, bookmark: bookmark)
            sources.append(source)
            save()
        }
        return await scan(source: source, root: root, onProgress: onProgress)
    }

    /// "Actualizar carpetas": links new videos in every linked folder and
    /// re-checks which ones can be reached.
    func refreshSources() async -> Int {
        var added = 0
        for source in sources {
            guard let root = resolve(source.bookmark) else { continue }
            let didStart = root.startAccessingSecurityScopedResource()
            added += await scan(source: source, root: root).imported
            if didStart { root.stopAccessingSecurityScopedResource() }
        }
        auditMissingFlags()
        return added
    }

    private func scan(source: VideoSource, root: URL,
                      onProgress: @MainActor (FolderImporter.Progress) -> Void = { _ in }) async -> FolderImporter.Progress {
        let known = Set(videos.filter { $0.sourceID == source.id }.compactMap(\.relativePath))
        let files = FolderImporter.audioFiles(in: root, extensions: Self.extensions)
        var progress = FolderImporter.Progress(total: files.count)
        onProgress(progress)
        for file in files {
            let folder = FolderImporter.relativeFolder(of: file, in: root)
            let relative = folder.isEmpty ? file.lastPathComponent : "\(folder)/\(file.lastPathComponent)"
            if known.contains(relative) {
                progress.total -= 1  // already linked, not part of this run
            } else if var item = try? await makeItem(for: file) {
                item.sourceID = source.id
                item.relativePath = relative
                item.folderPath = folder
                videos.insert(item, at: 0)
                progress.imported += 1
                save()
            } else {
                progress.skipped += 1
            }
            onProgress(progress)
        }
        return progress
    }

    /// Checks and describes one file the caller already has access to.
    private func makeItem(for url: URL) async throws -> VideoItem {
        let ext = url.pathExtension.lowercased()
        guard Self.extensions.contains(ext) else { throw VideoImportError.unsupportedFormat(ext: ext) }
        if isCloudFileNotDownloaded(url) { throw VideoImportError.fileNotDownloaded }
        let size = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        guard size > 0 else { throw VideoImportError.zeroByteFile }
        guard let probe = await inspect(url) else { throw VideoImportError.notPlayable }

        let id = UUID()
        var thumbnailName: String?
        if let jpeg = await makeThumbnail(url, probe.durationSeconds) {
            let name = "\(id.uuidString).jpg"
            if (try? jpeg.write(to: thumbnailsDirectory.appendingPathComponent(name), options: .atomic)) != nil {
                thumbnailName = name
            }
        }
        let fallback = url.deletingPathExtension().lastPathComponent
        let title = probe.title.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? fallback
        return VideoItem(id: id, title: title, importedAt: Date(), fileSizeBytes: size,
                         durationSeconds: probe.durationSeconds, thumbnailFileName: thumbnailName)
    }

    private func isAlreadyLinked(file url: URL) -> Bool {
        let target = url.standardizedFileURL
        return videos.contains { item in
            item.fileBookmark.flatMap { resolve($0) }?.standardizedFileURL == target
        }
    }

    // MARK: - Reaching the original

    /// The video's URL with security-scoped access started. Call `stop`
    /// when done (the player keeps it open while playing, also in PiP).
    func open(_ item: VideoItem) -> (url: URL, stop: () -> Void)? {
        let scoped: URL
        let url: URL
        if let sourceID = item.sourceID, let relative = item.relativePath,
           let source = sources.first(where: { $0.id == sourceID }),
           let root = resolve(source.bookmark, refreshing: sourceID) {
            scoped = root
            url = root.appendingPathComponent(relative)
        } else if let bookmark = item.fileBookmark, let file = resolve(bookmark, refreshingVideo: item.id) {
            scoped = file
            url = file
        } else {
            return nil
        }
        let didStart = scoped.startAccessingSecurityScopedResource()
        return (url, { if didStart { scoped.stopAccessingSecurityScopedResource() } })
    }

    /// Re-checks which originals can be reached right now.
    func auditMissingFlags() {
        var changed = false
        for i in videos.indices {
            var reachable = false
            if let access = open(videos[i]) {
                reachable = fileManager.fileExists(atPath: access.url.path)
                access.stop()
            }
            if videos[i].isMissing == reachable {
                videos[i].isMissing = !reachable
                changed = true
            }
        }
        if changed { save() }
    }

    private func resolve(_ bookmark: Data, refreshing sourceID: UUID? = nil,
                         refreshingVideo videoID: UUID? = nil) -> URL? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [],
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale {
            // The file or folder moved: store a fresh bookmark for next time.
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            if let fresh = try? url.bookmarkData(options: .minimalBookmark,
                                                 includingResourceValuesForKeys: nil, relativeTo: nil) {
                if let sourceID, let i = sources.firstIndex(where: { $0.id == sourceID }) {
                    sources[i].bookmark = fresh
                    save()
                } else if let videoID, let i = videos.firstIndex(where: { $0.id == videoID }) {
                    videos[i].fileBookmark = fresh
                    save()
                }
            }
        }
        return url
    }

    // MARK: - Editing

    func thumbnailURL(for item: VideoItem) -> URL? {
        item.thumbnailFileName.map { thumbnailsDirectory.appendingPathComponent($0) }
    }

    func setResume(_ id: UUID, seconds: Double?) {
        guard let i = videos.firstIndex(where: { $0.id == id }), videos[i].resumePosition != seconds else { return }
        videos[i].resumePosition = seconds
        save()
    }

    /// Removes the video from Ailen. The original file is never touched.
    func remove(_ item: VideoItem) {
        if let thumb = thumbnailURL(for: item) { try? fileManager.removeItem(at: thumb) }
        videos.removeAll { $0.id == item.id }
        // A linked folder with nothing left is unlinked too.
        sources.removeAll { source in !videos.contains { $0.sourceID == source.id } }
        save()
    }

    /// Removes every video and linked folder from Ailen; originals stay.
    func removeAll() {
        for item in videos {
            if let thumb = thumbnailURL(for: item) { try? fileManager.removeItem(at: thumb) }
        }
        videos.removeAll()
        sources.removeAll()
        save()
        flushPendingWrites()
    }

    // MARK: - Persistence

    func flushPendingWrites() { saveDebouncer.flush() }

    private func save() { saveDebouncer.call() }

    private func performSave() {
        let state = VideoLibraryState(sources: sources, videos: videos)
        guard let data = try? SchemaStore.encode([state], schemaVersion: Self.schemaVersion) else { return }
        try? store.save(data)
    }

    // MARK: - AVFoundation defaults

    /// `nil` unless the file has a video track and AVFoundation can play it.
    nonisolated static func defaultInspect(_ url: URL) async -> VideoProbe? {
        let asset = AVURLAsset(url: url)
        guard (try? await asset.load(.isPlayable)) == true,
              let tracks = try? await asset.loadTracks(withMediaType: .video), !tracks.isEmpty else { return nil }
        var duration: Double?
        if let time = try? await asset.load(.duration), time.seconds.isFinite, time.seconds > 0 {
            duration = time.seconds
        }
        var title: String?
        if let metadata = try? await asset.load(.commonMetadata),
           let item = metadata.first(where: { $0.commonKey == .commonKeyTitle }) {
            title = try? await item.load(.stringValue)
        }
        return VideoProbe(durationSeconds: duration, title: title)
    }

    /// A 480 px JPEG frame at 10 % of the duration (orientation applied).
    nonisolated static func defaultThumbnail(_ url: URL, duration: Double?) async -> Data? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        let time = CMTime(seconds: max(0, (duration ?? 10) * 0.1), preferredTimescale: 600)
        guard let image = try? await generator.image(at: time).image else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
