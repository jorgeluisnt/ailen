import Foundation
import Combine

enum LibrarySortOrder: String, CaseIterable, Identifiable {
    case recentlyAdded
    case title
    case artist
    case duration
    case fileSize

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .recentlyAdded: return "Añadidas recientemente"
        case .title: return "Título"
        case .artist: return "Artista"
        case .duration: return "Duración"
        case .fileSize: return "Tamaño de archivo"
        }
    }
}

enum LibraryGroupBy: String, CaseIterable, Identifiable {
    case none
    case album
    case artist
    case genre

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "Ninguno"
        case .album: return "Álbum"
        case .artist: return "Artista"
        case .genre: return "Género"
        }
    }
}

/// An album, artist or genre in the browse grids: its tracks in the current
/// sort order, plus one track whose artwork represents it.
struct LibraryCollection: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let tracks: [LocalTrack]
    let artworkTrack: LocalTrack?
}

/// A folder at one level of the Folders browser.
struct FolderEntry: Identifiable, Hashable {
    /// Path component used to go one level down.
    let key: String
    let title: String
    /// Songs in this folder and all its subfolders.
    let songCount: Int
    var id: String { key }
}

struct LibrarySection: Identifiable, Hashable {
    let id: String
    let title: String
    let tracks: [LocalTrack]
}

@MainActor
final class LibraryViewModel: ObservableObject {

    @Published var searchText: String = ""
    @Published var sortOrder: LibrarySortOrder
    @Published var groupBy: LibraryGroupBy

    @Published private(set) var tracks: [LocalTrack] = []

    /// Cached, recomputed only when tracks/search/sort/group actually change
    /// (via the Combine pipeline below) rather than re-filtered/-sorted/-grouped
    /// on every SwiftUI body pass.
    @Published private(set) var filteredAndSortedTracks: [LocalTrack] = []
    @Published private(set) var sections: [LibrarySection] = []
    /// Browse grids, built from the same filtered and sorted list.
    @Published private(set) var albums: [LibraryCollection] = []
    @Published private(set) var artists: [LibraryCollection] = []
    @Published private(set) var genres: [LibraryCollection] = []

    private let library: LocalLibraryManager
    private var cancellables = Set<AnyCancellable>()

    init(
        library: LocalLibraryManager,
        initialSortOrder: LibrarySortOrder = .recentlyAdded,
        initialGroupBy: LibraryGroupBy = .none,
        searchDebounce: TimeInterval = 0
    ) {
        self.library = library
        self.sortOrder = initialSortOrder
        self.groupBy = initialGroupBy
        library.$tracks.assign(to: &$tracks)

        // Sorting (localized compares, ~75 ms for 20k titles) only reruns when
        // the tracks or the order change; typing only filters the sorted list,
        // after a short pause. The initial values pass through synchronously
        // (no debounce on the first value), so the lists start populated.
        let sorted = Publishers.CombineLatest($tracks, $sortOrder)
            .map { Self.sort($0, by: $1) }
        // 0 (tests) filters synchronously on every change.
        let query: AnyPublisher<String, Never> = searchDebounce > 0
            ? $searchText.dropFirst()
                .debounce(for: .seconds(searchDebounce), scheduler: RunLoop.main)
                .prepend(searchText)
                .removeDuplicates()
                .eraseToAnyPublisher()
            : $searchText.eraseToAnyPublisher()
        Publishers.CombineLatest3(sorted, query, $groupBy)
            .map { sorted, query, group in
                let filtered = Self.filter(sorted, query: query)
                return (filtered, Self.makeSections(filtered, groupBy: group))
            }
            .sink { [weak self] sorted, sections in
                self?.filteredAndSortedTracks = sorted
                self?.sections = sections
                self?.albums = Self.collections(sorted, key: { $0.album }) { tracks in
                    tracks.first(where: { $0.artist != nil })?.artist ?? "Artista desconocido"
                }
                self?.artists = Self.collections(sorted, key: { $0.artist }) { Self.songCount($0.count) }
                self?.genres = Self.collections(sorted, key: { $0.displayGenre }) { Self.songCount($0.count) }
            }
            .store(in: &cancellables)
    }

    /// Keeps the input order. Matches title, artist, album or genre, ignoring case
    /// and accents ("cafe" finds "Café").
    private static func filter(_ tracks: [LocalTrack], query rawQuery: String) -> [LocalTrack] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return tracks }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return tracks.filter { track in
            track.title.range(of: query, options: options) != nil
                || track.artist?.range(of: query, options: options) != nil
                || track.album?.range(of: query, options: options) != nil
                || track.displayGenre?.range(of: query, options: options) != nil
        }
    }

    private static func makeSections(
        _ tracks: [LocalTrack], groupBy: LibraryGroupBy
    ) -> [LibrarySection] {
        switch groupBy {
        case .none:
            return [LibrarySection(id: "all", title: "", tracks: tracks)]
        case .album:
            return sectionsBy(tracks, key: { $0.album })
        case .artist:
            return sectionsBy(tracks, key: { $0.artist })
        case .genre:
            return sectionsBy(tracks, key: { $0.displayGenre })
        }
    }

    private static func sectionsBy(
        _ tracks: [LocalTrack],
        key: (LocalTrack) -> String?
    ) -> [LibrarySection] {
        let buckets = Dictionary(grouping: tracks) { key($0) ?? Self.unknownKey }
        let orderedKeys = buckets.keys.sorted { lhs, rhs in
            if lhs == rhs { return false }
            if lhs == Self.unknownKey { return false }
            if rhs == Self.unknownKey { return true }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
        return orderedKeys.map { key in
            let bucket = buckets[key] ?? []
            let title = key == Self.unknownKey ? "Desconocido" : key
            return LibrarySection(id: title, title: title, tracks: bucket)
        }
    }

    private static let unknownKey = "\u{1F}unknown"

    /// Path key of the virtual folder holding tracks imported before folders
    /// were recorded. The control character keeps it from clashing with a
    /// real folder called "Sin carpeta".
    static let noFolderKey = "\u{1F}nofolder"

    /// Subfolders and songs at `path` (components below the folder the user
    /// picked). `tracks` order is kept, so the current sort applies.
    static func folderContents(_ tracks: [LocalTrack], at path: [String])
        -> (folders: [FolderEntry], tracks: [LocalTrack]) {
        let result = folderContents(tracks, at: path, folderPath: \.folderPath)
        return (result.folders, result.items)
    }

    /// Generic form, shared with Videos: `folderPath` reads each item's folder.
    static func folderContents<Item>(_ items: [Item], at path: [String],
                                     folderPath: (Item) -> String?)
        -> (folders: [FolderEntry], items: [Item]) {
        if path == [noFolderKey] {
            return ([], items.filter { folderPath($0) == nil })
        }
        var counts: [String: Int] = [:]
        var here: [Item] = []
        for track in items {
            guard let folderPath = folderPath(track) else {
                if path.isEmpty { counts[noFolderKey, default: 0] += 1 }
                continue
            }
            let parts = folderPath.split(separator: "/").map(String.init)
            guard parts.starts(with: path) else { continue }
            if parts.count == path.count {
                here.append(track)
            } else {
                counts[parts[path.count], default: 0] += 1
            }
        }
        let folders = counts.keys.sorted { lhs, rhs in
            if lhs == noFolderKey { return false }
            if rhs == noFolderKey { return true }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }.map { key in
            FolderEntry(key: key, title: key == noFolderKey ? "Sin carpeta" : key, songCount: counts[key] ?? 0)
        }
        return (folders, here)
    }

    static func songCount(_ n: Int) -> String { "\(n) \(n == 1 ? "canción" : "canciones")" }

    /// Groups by `key`, A→Z with untagged tracks last as "Desconocido"; track
    /// order inside each group is the input (sorted) order.
    static func collections(
        _ tracks: [LocalTrack],
        key: (LocalTrack) -> String?,
        subtitle: ([LocalTrack]) -> String
    ) -> [LibraryCollection] {
        sectionsBy(tracks, key: key).map { section in
            LibraryCollection(
                id: section.id,
                title: section.title,
                subtitle: subtitle(section.tracks),
                tracks: section.tracks,
                artworkTrack: section.tracks.first(where: { $0.artworkFileName != nil })
            )
        }
    }

    private static func sort(_ tracks: [LocalTrack], by order: LibrarySortOrder) -> [LocalTrack] {
        switch order {
        case .recentlyAdded:
            return tracks.sorted { $0.importedAt > $1.importedAt }
        case .title:
            return tracks.sorted { lhs, rhs in
                let c = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                return c == .orderedAscending
            }
        case .artist:
            return tracks.sorted { lhs, rhs in
                switch (lhs.artist, rhs.artist) {
                case (nil, nil):
                    return false
                case (nil, _):
                    return false
                case (_, nil):
                    return true
                case (let l?, let r?):
                    return l.localizedCaseInsensitiveCompare(r) == .orderedAscending
                }
            }
        case .duration:
            return tracks.sorted { lhs, rhs in
                switch (lhs.durationSeconds, rhs.durationSeconds) {
                case (nil, nil):
                    return false
                case (nil, _):
                    return false
                case (_, nil):
                    return true
                case (let l?, let r?):
                    return l < r
                }
            }
        case .fileSize:
            return tracks.sorted { $0.fileSizeBytes > $1.fileSizeBytes }
        }
    }
}
