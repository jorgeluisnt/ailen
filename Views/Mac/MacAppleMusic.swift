#if os(macOS)
import Combine
import MusicKit
import SwiftUI

/// Apple Music on the Mac. Same role and surface as the iOS service, built on
/// MusicKit (`MusicLibraryRequest`, `ApplicationMusicPlayer`) because
/// MediaPlayer's library and player don't exist on macOS. Audio is
/// DRM-protected and played by Apple: no EQ, rate matching or quality data.
/// Nothing touches Apple Music until the section is enabled and opened.
@MainActor
final class AppleMusicService: ObservableObject {
    enum Access: Equatable { case unknown, authorized, unavailable(String) }

    struct NowEntry: Equatable {
        let id: String
        let title: String
        let artist: String
        let duration: TimeInterval
        let artwork: Artwork?
    }

    @Published private(set) var access: Access = .unknown
    @Published private(set) var playlists: [MusicKit.Playlist] = []
    @Published private(set) var albums: [Album] = []
    @Published private(set) var songs: [Song] = []
    @Published private(set) var isLoading = false
    @Published private(set) var libraryError: String?
    @Published private(set) var nowPlaying: NowEntry?
    @Published private(set) var isPlaying = false
    /// Apple Music was the last thing started: Now Playing shows it.
    @Published private(set) var isActiveSource = false
    @Published private(set) var shuffleOn = false
    @Published private(set) var repeatState: ExternalNowPlaying.Repeat = .off

    enum CatalogState: Equatable { case idle, searching, results, unavailable(String) }
    @Published private(set) var catalogState: CatalogState = .idle
    @Published private(set) var catalogSongs: [Song] = []
    @Published private(set) var catalogAlbums: [Album] = []
    @Published var alertMessage: String?

    private weak var music: PlayerManager?
    private var observers: Set<AnyCancellable> = []
    private var player: ApplicationMusicPlayer { .shared }

    func configure(music: PlayerManager) { self.music = music }

    // MARK: - Permission and library

    /// Reflects a permission granted earlier without prompting.
    func refreshAccess() async {
        guard access == .unknown, MusicAuthorization.currentStatus == .authorized else { return }
        access = .authorized
        await loadLibrary()
    }

    func requestAccess() async {
        let status = await MusicAuthorization.request()
        if let message = AppleMusicAvailability.message(forAuthorization: status) {
            access = .unavailable(message)
            return
        }
        access = .authorized
        await loadLibrary()
    }

    /// Playlists, albums and songs from the user's library, A→Z.
    func loadLibrary() async {
        guard access == .authorized else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let lists = try await MusicLibraryRequest<MusicKit.Playlist>().response().items
            let albumItems = try await MusicLibraryRequest<Album>().response().items
            let songItems = try await MusicLibraryRequest<Song>().response().items
            playlists = lists.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            albums = albumItems.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            songs = songItems.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            libraryError = nil
        } catch {
            libraryError = AppleMusicAvailability.catalogMessage(for: error)
        }
    }

    static func songCount(_ n: Int) -> String { "\(n) \(n == 1 ? "canción" : "canciones")" }

    // MARK: - Playback

    /// Plays `items` from `index`. Local music pauses first.
    func play<Item: PlayableMusicItem>(_ items: [Item], startAt index: Int = 0, shuffled: Bool = false) async {
        guard !items.isEmpty else { return }
        takeOver()
        if shuffled {
            player.queue = ApplicationMusicPlayer.Queue(for: items.shuffled())
        } else {
            player.queue = ApplicationMusicPlayer.Queue(for: items, startingAt: items[min(max(index, 0), items.count - 1)])
        }
        player.state.shuffleMode = .off
        do {
            try await player.play()
        } catch {
            alertMessage = AppleMusicAvailability.catalogMessage(for: error)
        }
        refreshState()
    }

    /// An album's or playlist's tracks (fetched on demand).
    func tracks(of album: Album) async -> [MusicKit.Track] {
        (try? await album.with([.tracks]).tracks).map(Array.init) ?? []
    }

    func tracks(of playlist: MusicKit.Playlist) async -> [MusicKit.Track] {
        (try? await playlist.with([.tracks]).tracks).map(Array.init) ?? []
    }

    func togglePlayPause() {
        if isPlaying {
            player.pause()
        } else {
            takeOver()
            Task { try? await player.play() }
        }
    }

    func pause() {
        guard isPlaying else { return }
        player.pause()
    }

    /// Local music took over: Now Playing goes back to it.
    func resignActiveSource() {
        pause()
        isActiveSource = false
    }

    /// The section was disabled: stop and forget.
    func shutDown() {
        if isActiveSource || isPlaying { player.stop() }
        observers.removeAll()
        nowPlaying = nil
        isPlaying = false
        isActiveSource = false
    }

    func toggleShuffle() {
        player.state.shuffleMode = shuffleOn ? .off : .songs
        refreshState()
    }

    func cycleRepeat() {
        switch repeatState {
        case .off: player.state.repeatMode = .all
        case .all: player.state.repeatMode = MusicPlayer.RepeatMode.one
        case .one: player.state.repeatMode = MusicPlayer.RepeatMode.none
        }
        refreshState()
    }

    /// Now Playing model for the shared external views.
    var nowPlayingModel: ExternalNowPlaying? {
        guard let now = nowPlaying else { return nil }
        return ExternalNowPlaying(
            source: "Apple Music", title: now.title, artist: now.artist, artwork: nil,
            isPlaying: isPlaying, shuffleOn: shuffleOn, repeatState: repeatState, duration: now.duration,
            position: { ApplicationMusicPlayer.shared.playbackTime },
            note: "Reproducido por Apple Music · sin ecualizador ni datos de calidad",
            playPause: { [weak self] in self?.togglePlayPause() },
            next: { Task { try? await ApplicationMusicPlayer.shared.skipToNextEntry() } },
            previous: { Task { try? await ApplicationMusicPlayer.shared.skipToPreviousEntry() } },
            toggleShuffle: { [weak self] in self?.toggleShuffle() },
            cycleRepeat: { [weak self] in self?.cycleRepeat() },
            seek: { ApplicationMusicPlayer.shared.playbackTime = $0 },
            musicKitArtwork: now.artwork)
    }

    private func takeOver() {
        music?.yieldToOtherPlayer()
        isActiveSource = true
        guard observers.isEmpty else { return }
        // The player's state and queue are ObservableObjects: mirror them.
        player.state.objectWillChange
            .merge(with: player.queue.objectWillChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // objectWillChange fires before the change lands.
                Task { @MainActor in self?.refreshState() }
            }
            .store(in: &observers)
    }

    private func refreshState() {
        let state = player.state
        isPlaying = state.playbackStatus == .playing
        shuffleOn = state.shuffleMode == .songs
        switch state.repeatMode {
        case .some(.one): repeatState = .one
        case .some(.all): repeatState = .all
        default: repeatState = .off
        }
        guard let entry = player.queue.currentEntry else {
            nowPlaying = nil
            return
        }
        var duration: TimeInterval = 0
        if case .song(let song) = entry.item { duration = song.duration ?? 0 }
        let next = NowEntry(id: entry.id, title: entry.title, artist: entry.subtitle ?? "",
                            duration: duration, artwork: entry.artwork)
        if next != nowPlaying { nowPlaying = next }
    }

    // MARK: - Catalog

    func searchCatalog(_ rawTerm: String) async {
        let term = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            catalogState = .idle
            catalogSongs = []
            catalogAlbums = []
            return
        }
        catalogState = .searching
        do {
            var request = MusicCatalogSearchRequest(term: term, types: [Song.self, Album.self])
            request.limit = 25
            let response = try await request.response()
            guard !Task.isCancelled else { return }
            catalogSongs = Array(response.songs)
            catalogAlbums = Array(response.albums)
            catalogState = .results
        } catch {
            guard !Task.isCancelled else { return }
            catalogState = .unavailable(AppleMusicAvailability.catalogMessage(for: error))
        }
    }

    /// Catalog content needs an Apple Music subscription; say so up front.
    func playCatalog(_ songs: [Song], startAt index: Int = 0) async {
        guard await canPlayCatalog() else { return }
        await play(songs, startAt: index)
    }

    func playCatalogAlbum(_ album: Album, shuffled: Bool = false) async {
        guard await canPlayCatalog() else { return }
        await play(await tracks(of: album), shuffled: shuffled)
    }

    private func canPlayCatalog() async -> Bool {
        if let subscription = try? await MusicSubscription.current, !subscription.canPlayCatalogContent {
            alertMessage = AppleMusicAvailability.subscriptionMessage
            return false
        }
        return true
    }
    // "Añadir a tu biblioteca" (MusicLibrary.add) is unavailable on macOS.
}

// MARK: - Screen

/// Apple Music section on the Mac: library (Listas · Álbumes · Canciones)
/// and catalog search.
struct AppleMusicView: View {
    @EnvironmentObject private var appleMusic: AppleMusicService
    @EnvironmentObject private var themeManager: ThemeManager

    enum Scope: String, CaseIterable, Identifiable {
        case playlists = "Listas", albums = "Álbumes", songs = "Canciones"
        var id: String { rawValue }
    }

    @State private var scope: Scope = .playlists
    @State private var query = ""

    private var tokens: DesignTokens { themeManager.tokens }

    var body: some View {
        NavigationStack {
            ZStack {
                tokens.background.ignoresSafeArea()
                content
            }
            .navigationTitle("Apple Music")
            .searchable(text: $query, prompt: "Buscar en Apple Music")
            .task(id: query) {
                try? await Task.sleep(nanoseconds: 400_000_000)  // debounce typing
                guard !Task.isCancelled else { return }
                await appleMusic.searchCatalog(query)
            }
        }
        .task { await appleMusic.refreshAccess() }
        .alert("Apple Music", isPresented: Binding(get: { appleMusic.alertMessage != nil },
                                                   set: { if !$0 { appleMusic.alertMessage = nil } })) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(appleMusic.alertMessage ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch appleMusic.access {
        case .unknown:
            message(icon: "music.note.house", title: "Conecta tu biblioteca de Apple Music",
                    detail: "Ailen mostrará tus listas, álbumes y canciones y las reproducirá con el reproductor de Apple. Sin ecualizador ni datos de calidad.") {
                Button("Permitir acceso") { Task { await appleMusic.requestAccess() } }
                    .buttonStyle(.borderedProminent)
                    .tint(tokens.accent)
            }
        case .unavailable(let text):
            message(icon: "lock", title: "Apple Music no disponible", detail: text) { EmptyView() }
        case .authorized:
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                catalogResults
            } else {
                library
            }
        }
    }

    private var library: some View {
        VStack(spacing: DS.Spacing.md) {
            Picker("Ver", selection: $scope) {
                ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)
            .padding(.top, DS.Spacing.md)

            if let error = appleMusic.libraryError {
                message(icon: "exclamationmark.triangle", title: "No se pudo leer tu biblioteca", detail: error) {
                    Button("Reintentar") { Task { await appleMusic.loadLibrary() } }
                }
            } else if appleMusic.isLoading {
                ProgressView().frame(maxHeight: .infinity)
            } else {
                switch scope {
                case .playlists:
                    List(appleMusic.playlists) { list in
                        NavigationLink {
                            AMTracksDetail(title: list.name, artwork: list.artwork) { await appleMusic.tracks(of: list) }
                        } label: {
                            row(artwork: list.artwork, title: list.name, subtitle: list.curatorName ?? "Lista")
                        }
                    }
                case .albums:
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: DS.Spacing.lg)],
                                  spacing: DS.Spacing.lg) {
                            ForEach(appleMusic.albums) { album in
                                NavigationLink {
                                    AMTracksDetail(title: album.title, artwork: album.artwork) { await appleMusic.tracks(of: album) }
                                } label: {
                                    tile(artwork: album.artwork, title: album.title, subtitle: album.artistName)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(DS.Spacing.lg)
                    }
                case .songs:
                    List(Array(appleMusic.songs.enumerated()), id: \.element.id) { index, song in
                        Button {
                            Task { await appleMusic.play(appleMusic.songs, startAt: index) }
                        } label: {
                            row(artwork: song.artwork, title: song.title, subtitle: song.artistName)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    @ViewBuilder
    private var catalogResults: some View {
        switch appleMusic.catalogState {
        case .idle, .searching:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable(let text):
            message(icon: "magnifyingglass", title: "Búsqueda no disponible", detail: text) { EmptyView() }
        case .results:
            List {
                if !appleMusic.catalogSongs.isEmpty {
                    Section("Canciones") {
                        ForEach(Array(appleMusic.catalogSongs.enumerated()), id: \.element.id) { index, song in
                            HStack {
                                Button {
                                    Task { await appleMusic.playCatalog(appleMusic.catalogSongs, startAt: index) }
                                } label: {
                                    row(artwork: song.artwork, title: song.title, subtitle: song.artistName)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                if !appleMusic.catalogAlbums.isEmpty {
                    Section("Álbumes") {
                        ForEach(appleMusic.catalogAlbums) { album in
                            HStack {
                                Button {
                                    Task { await appleMusic.playCatalogAlbum(album) }
                                } label: {
                                    row(artwork: album.artwork, title: album.title, subtitle: album.artistName)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private func row(artwork: Artwork?, title: String, subtitle: String) -> some View {
        HStack(spacing: DS.Spacing.md) {
            AMArtwork(artwork: artwork, side: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body).foregroundColor(tokens.textPrimary).lineLimit(1)
                Text(subtitle).font(.caption).foregroundColor(tokens.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private func tile(artwork: Artwork?, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            AMArtwork(artwork: artwork, side: 150)
            Text(title).font(.callout.weight(.semibold)).foregroundColor(tokens.textPrimary).lineLimit(1)
            Text(subtitle).font(.caption).foregroundColor(tokens.textSecondary).lineLimit(1)
        }
        .frame(width: 150)
    }

    private func message<Action: View>(icon: String, title: String, detail: String,
                                       @ViewBuilder action: () -> Action) -> some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: icon).font(.system(size: 44, weight: .light)).foregroundColor(tokens.textSecondary)
            Text(title).font(.title3.weight(.semibold)).foregroundColor(tokens.textPrimary)
            Text(detail).font(.callout).foregroundColor(tokens.textSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 420)
            action()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// An album's or playlist's tracks, with Reproducir / Aleatorio.
private struct AMTracksDetail: View {
    @EnvironmentObject private var appleMusic: AppleMusicService
    @EnvironmentObject private var themeManager: ThemeManager

    let title: String
    let artwork: Artwork?
    let load: () async -> [MusicKit.Track]

    @State private var tracks: [MusicKit.Track]?

    var body: some View {
        let tokens = themeManager.tokens
        ScrollView {
            VStack(spacing: DS.Spacing.lg) {
                AMArtwork(artwork: artwork, side: 200)
                Text(title).font(.title2.weight(.bold)).foregroundColor(tokens.textPrimary)
                if let tracks {
                    PlayShuffleButtons(
                        tokens: tokens,
                        onPlay: { Task { await appleMusic.play(tracks) } },
                        onShuffle: { Task { await appleMusic.play(tracks, shuffled: true) } })
                        .frame(maxWidth: 420)
                    LazyVStack(spacing: 0) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            Button {
                                Task { await appleMusic.play(tracks, startAt: index) }
                            } label: {
                                HStack {
                                    Text("\(index + 1)").font(.caption.monospacedDigit())
                                        .foregroundColor(tokens.textSecondary).frame(width: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(track.title).foregroundColor(tokens.textPrimary).lineLimit(1)
                                        Text(track.artistName).font(.caption).foregroundColor(tokens.textSecondary).lineLimit(1)
                                    }
                                    Spacer()
                                    if let d = track.duration { Text(formatPlaybackTime(d)).font(.caption.monospacedDigit())
                                        .foregroundColor(tokens.textSecondary) }
                                }
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .padding(DS.Spacing.lg)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(tokens.background)
        .navigationTitle(title)
        .task { if tracks == nil { tracks = await load() } }
    }
}

/// MusicKit artwork (library artwork isn't a plain URL; `ArtworkImage` loads it).
struct AMArtwork: View {
    let artwork: Artwork?
    let side: CGFloat

    var body: some View {
        Group {
            if let artwork {
                ArtworkImage(artwork, width: side, height: side)
            } else {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                    .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side > 100 ? 12 : 6, style: .continuous))
    }
}
#endif
