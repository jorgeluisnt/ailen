import SwiftUI

/// iPad home: artists, recently played and favourites, from the user's own
/// library only. Each section can be played as a whole.
struct HomeView: View {
    @EnvironmentObject private var playerManager: PlayerManager
    @EnvironmentObject private var recentlyPlayedManager: RecentlyPlayedManager
    @EnvironmentObject private var favoritesManager: FavoritesManager
    @EnvironmentObject private var themeManager: ThemeManager

    @ObservedObject private var library: LocalLibraryManager
    @StateObject private var vm: LibraryViewModel
    @State private var randomPicks: [Track] = []

    private var tokens: DesignTokens { themeManager.tokens }

    init(library: LocalLibraryManager) {
        self.library = library
        _vm = StateObject(wrappedValue: LibraryViewModel(library: library, initialSortOrder: .title))
    }

    /// Stored tracks resolved against the current library: unique, still
    /// imported, file present. Stored `Track`s carry absolute paths that go
    /// stale across reinstalls, so URLs are rebuilt from the library entry.
    static func resolveLocal(_ tracks: [Track], in library: [LocalTrack],
                             fileURL: (LocalTrack) -> URL) -> [Track] {
        let byID = Dictionary(library.map { ("local:\($0.id.uuidString)", $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        return tracks.compactMap { track in
            guard seen.insert(track.id).inserted, let local = byID[track.id], !local.isMissing else { return nil }
            return local.asPlayerTrack(fileURL: fileURL(local))
        }
    }

    private var recent: [Track] {
        Self.resolveLocal(recentlyPlayedManager.recentlyPlayed, in: library.tracks, fileURL: library.fileURL(for:))
    }

    private var favorites: [Track] {
        Self.resolveLocal(favoritesManager.tracks, in: library.tracks, fileURL: library.fileURL(for:))
    }

    var body: some View {
        ZStack {
            tokens.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                    Text("Inicio")
                        .font(DS.Typography.display)
                        .foregroundColor(tokens.textPrimary)
                        .accessibilityAddTraits(.isHeader)

                    genresSection
                    artistsSection
                    trackSection("Reproducidas recientemente", tracks: Array(recent.prefix(12)),
                                 empty: "Aún no has reproducido nada.")
                    if favorites.isEmpty {
                        // No favourites yet: a stable random pick from the library.
                        trackSection("Canciones aleatorias", tracks: randomPicks,
                                     empty: "Importa música para ver canciones aquí.",
                                     note: "Marca canciones con ♥ para ver aquí tus favoritos.")
                    } else {
                        trackSection("Favoritos", tracks: favorites, empty: "")
                    }
                }
                .padding(DS.Spacing.xl)
            }
        }
        // Re-pick only when the library changes, not on every redraw.
        .task(id: library.tracks.count) { pickRandom() }
    }

    private func pickRandom() {
        randomPicks = library.tracks.filter { !$0.isMissing }.shuffled().prefix(12)
            .map { $0.asPlayerTrack(fileURL: library.fileURL(for: $0)) }
    }

    // MARK: - Sections

    private func header(_ title: String, play: [Track]?) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.footnote.weight(.semibold))
                .tracking(1.5)
                .foregroundColor(tokens.textSecondary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let play, !play.isEmpty {
                Button { playerManager.playSlice(play, startIndex: 0) } label: {
                    Image(systemName: "play.fill")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(tokens.accentGradient))
                }
                .accessibilityLabel("Reproducir \(title)")
            }
        }
    }

    /// Artists as large square cards (artwork, name, song count).
    private var artistsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            header("Artistas", play: nil)
            if vm.artists.isEmpty {
                emptyText("Importa música para ver tus artistas.")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: DS.Spacing.lg) {
                        ForEach(vm.artists.prefix(30)) { artist in
                            Button { play(artist) } label: { artistCard(artist) }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Reproducir \(artist.title), \(artist.subtitle)")
                        }
                    }
                }
            }
        }
    }

    private func artistCard(_ artist: LibraryCollection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            artwork(artist.artworkTrack?.artworkURL, size: 160, corner: 16)
            Text(artist.title)
                .font(DS.Typography.bodyEm)
                .foregroundColor(tokens.textPrimary)
                .lineLimit(1)
            Text(artist.subtitle)
                .font(DS.Typography.caption)
                .foregroundColor(tokens.textSecondary)
                .lineLimit(1)
        }
        .frame(width: 160, alignment: .leading)
    }

    /// Genres as glass capsules with a round cover.
    private var genresSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            header("Géneros", play: nil)
            if vm.genres.isEmpty {
                emptyText("Tus géneros aparecerán aquí cuando importes música.")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Spacing.md) {
                        ForEach(vm.genres) { genre in
                            genreChip(genre)
                        }
                    }
                }
            }
        }
    }

    private func genreChip(_ genre: LibraryCollection) -> some View {
        Button { play(genre) } label: {
            HStack(spacing: DS.Spacing.sm) {
                artwork(genre.artworkTrack?.artworkURL, size: 40, corner: 20)
                    .clipShape(Circle())
                Text(genre.title)
                    .font(DS.Typography.bodyEm)
                    .foregroundColor(tokens.textPrimary)
                    .lineLimit(1)
            }
            .padding(.leading, 6)
            .padding(.trailing, DS.Spacing.lg)
            .padding(.vertical, 6)
            .glassSurface(in: Capsule(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reproducir \(genre.title), \(genre.subtitle)")
    }

    private func artwork(_ url: URL?, size: CGFloat, corner: CGFloat) -> some View {
        Group {
            if let url {
                AsyncCachedImage(url: url, targetSize: size) {
                    ArtworkPlaceholder(tokens: tokens, cornerRadius: corner)
                }
                .aspectRatio(contentMode: .fill)
            } else {
                ArtworkPlaceholder(tokens: tokens, cornerRadius: corner)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }

    private func play(_ collection: LibraryCollection) {
        let tracks = collection.tracks.filter { !$0.isMissing }
            .map { $0.asPlayerTrack(fileURL: library.fileURL(for: $0)) }
        if !tracks.isEmpty { playerManager.playSlice(tracks, startIndex: 0) }
    }

    private func trackSection(_ title: String, tracks: [Track], empty: String,
                              note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            header(title, play: tracks)
            if let note {
                Text(note)
                    .font(DS.Typography.caption)
                    .foregroundColor(tokens.textSecondary)
            }
            if tracks.isEmpty {
                emptyText(empty)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: DS.Spacing.lg)],
                          alignment: .leading, spacing: DS.Spacing.lg) {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                        Button { playerManager.playSlice(tracks, startIndex: index) } label: {
                            trackTile(track)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func trackTile(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let url = track.thumbnailURL {
                        AsyncCachedImage(url: url, targetSize: 200) {
                            ArtworkPlaceholder(tokens: tokens, cornerRadius: 14)
                        }
                        .aspectRatio(contentMode: .fill)
                    } else {
                        ArtworkPlaceholder(tokens: tokens, cornerRadius: 14)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(track.title)
                .font(DS.Typography.bodyEm)
                .foregroundColor(tokens.textPrimary)
                .lineLimit(1)
            Text(track.artist)
                .font(DS.Typography.caption)
                .foregroundColor(tokens.textSecondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private func emptyText(_ text: String) -> some View {
        Text(text)
            .font(DS.Typography.body)
            .foregroundColor(tokens.textSecondary)
    }
}
