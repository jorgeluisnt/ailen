import Combine
import SwiftUI

/// Library and search state for the Spotify section (Web API).
@MainActor
final class SpotifyLibraryModel: ObservableObject {
    @Published var me: SpotifyUser?
    @Published var playlists: [SpotifyPlaylist] = []
    @Published var liked: [SpotifyTrack] = []
    /// `false` when Spotify refuses saved tracks to Development Mode apps.
    @Published var likedAvailable = true
    @Published var isLoading = false
    @Published var message: String?

    @Published var query = ""
    @Published var tracks: [SpotifyTrack] = []
    @Published var albums: [SpotifyAlbum] = []
    @Published var foundPlaylists: [SpotifyPlaylist] = []
    @Published var searching = false
    @Published var canLoadMore = false
    private var offset = 0

    func loadLibrary(_ api: SpotifyWebAPI) async {
        isLoading = true
        defer { isLoading = false }
        do {
            me = try? await api.me()
            playlists = try await api.myPlaylists()
            message = nil
        } catch let error as SpotifyAPIError {
            message = error.message
        } catch {
            message = "No se pudo conectar con Spotify. Comprueba la conexión a internet."
        }
        do {
            liked = try await api.savedTracks()
            likedAvailable = true
        } catch {
            likedAvailable = false
        }
    }

    /// Own or collaborative: Spotify only lists tracks of those.
    func canListTracks(_ playlist: SpotifyPlaylist) -> Bool {
        playlist.collaborative == true || (me != nil && playlist.owner?.id == me?.id)
    }

    func search(_ api: SpotifyWebAPI, more: Bool = false) async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            tracks = []; albums = []; foundPlaylists = []; canLoadMore = false
            return
        }
        if !more { offset = 0 }
        searching = true
        defer { searching = false }
        do {
            let result = try await api.search(q, offset: offset)
            guard !Task.isCancelled else { return }
            let newTracks = result.tracks?.items ?? []
            if more {
                tracks += newTracks
            } else {
                tracks = newTracks
                albums = result.albums?.items ?? []
                foundPlaylists = (result.playlists?.items ?? []).compactMap { $0 }
            }
            offset += SpotifyWebAPI.searchLimit
            canLoadMore = result.tracks?.next != nil
            message = nil
        } catch let error as SpotifyAPIError {
            message = error.message
        } catch {
            guard !Task.isCancelled else { return }
            message = "Buscar en Spotify necesita conexión a internet."
        }
    }
}

/// Optional Spotify section: your playlists and liked songs, and search,
/// played by the Spotify app on this device.
struct SpotifyView: View {
    @EnvironmentObject private var spotify: SpotifyService
    @EnvironmentObject private var themeManager: ThemeManager
    @StateObject private var model = SpotifyLibraryModel()
    @AppStorage("spotifyMode") private var modeRaw = "library"
    @State private var added: Set<String> = []

    private var tokens: DesignTokens { themeManager.tokens }
    private var isSearchMode: Bool { modeRaw == "search" }

    var body: some View {
        NavigationStack {
            ZStack {
                tokens.background.ignoresSafeArea()
                switch spotify.state {
                case .notConfigured:
                    notice("dot.radiowaves.left.and.right", "Falta el Client ID",
                           "Ve a Ajustes → Spotify y pega el Client ID de tu app del panel de desarrolladores de Spotify.")
                case .notInstalled:
                    VStack(spacing: DS.Spacing.lg) {
                        notice("arrow.down.app", "Instala Spotify",
                               "Ailen controla la app de Spotify de este dispositivo. Instálala e inicia sesión con tu cuenta Premium.")
                        if let url = URL(string: "https://apps.apple.com/app/id324684580") {
                            Link("Abrir en la App Store", destination: url)
                                .font(DS.Typography.bodyEm)
                                .foregroundColor(tokens.highlightColor)
                        }
                    }
                case .signedOut:
                    connectPrompt(nil)
                case .failed(let message):
                    connectPrompt(message)
                case .connecting, .connected, .disconnected:
                    content
                }
            }
            .navigationTitle("Spotify")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { connectionBadge }
            }
        }
    }

    // MARK: - Connection

    private var connectionBadge: some View {
        Group {
            switch spotify.state {
            case .connected:
                Label("Conectado", systemImage: "checkmark.circle.fill").foregroundColor(.green)
            case .connecting:
                ProgressView()
            case .disconnected:
                Button { spotify.connect(userInitiated: true) } label: {
                    Label("Conectar", systemImage: "arrow.triangle.2.circlepath")
                }
            default:
                EmptyView()
            }
        }
        .font(DS.Typography.caption)
        .labelStyle(.titleAndIcon)
    }

    private func connectPrompt(_ error: String?) -> some View {
        VStack(spacing: DS.Spacing.lg) {
            notice("dot.radiowaves.left.and.right", "Conecta tu cuenta de Spotify",
                   error ?? "Se abrirá la app de Spotify para autorizar a Ailen y volverás aquí. El audio lo reproduce Spotify: sin ecualizador ni datos de calidad.")
            Button { spotify.signIn() } label: {
                Text("Conectar con Spotify")
                    .font(DS.Typography.bodyEm)
                    .foregroundColor(.white)
                    .padding(.horizontal, DS.Spacing.xl)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(tokens.accentGradient))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            Picker("Modo", selection: $modeRaw) {
                Text("Mi biblioteca").tag("library")
                Text("Buscar en Spotify").tag("search")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.sm)
            .frame(maxWidth: 480)
            if let message = model.message {
                Text(message)
                    .font(DS.Typography.caption)
                    .foregroundColor(tokens.textSecondary)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.sm)
            }
            if isSearchMode { searchResults } else { library }
        }
        .searchable(text: $model.query, prompt: isSearchMode ? "Canciones, álbumes, listas" : "Buscar en tus listas")
        .task(id: isSearchMode ? model.query : "") {
            guard isSearchMode else { return }
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await model.search(spotify.webAPI)
        }
        .task { if model.playlists.isEmpty { await model.loadLibrary(spotify.webAPI) } }
    }

    // MARK: - Library

    private var library: some View {
        let q = model.query.trimmingCharacters(in: .whitespaces)
        let lists = q.isEmpty ? model.playlists : model.playlists.filter {
            $0.name.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                if model.isLoading && model.playlists.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(DS.Spacing.xl)
                }
                if model.likedAvailable && !model.liked.isEmpty && q.isEmpty {
                    NavigationLink { likedDetail } label: { likedRow }
                        .buttonStyle(.plain)
                }
                if !lists.isEmpty {
                    sectionTitle("Tus listas")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 190), spacing: DS.Spacing.md)],
                              spacing: DS.Spacing.lg) {
                        ForEach(lists) { playlist in
                            NavigationLink { playlistDetail(playlist) } label: { playlistTile(playlist) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                } else if !model.isLoading {
                    Text(q.isEmpty ? "No hay listas en tu cuenta de Spotify." : "Sin resultados.")
                        .font(DS.Typography.body)
                        .foregroundColor(tokens.textSecondary)
                        .padding(DS.Spacing.xl)
                }
                Label("El audio lo reproduce la app de Spotify: sin ecualizador ni datos de calidad.", systemImage: "info.circle")
                    .font(DS.Typography.caption)
                    .foregroundColor(tokens.textSecondary)
                    .padding(.horizontal, DS.Spacing.lg)
            }
            .padding(.vertical, DS.Spacing.md)
        }
        .refreshable { await model.loadLibrary(spotify.webAPI) }
    }

    private var likedRow: some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: "heart.fill")
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(RoundedRectangle(cornerRadius: 12).fill(tokens.accentGradient))
            VStack(alignment: .leading, spacing: 2) {
                Text("Tus me gusta").font(.body.weight(.semibold)).foregroundColor(tokens.textPrimary)
                Text("\(model.liked.count) canciones").font(.caption).foregroundColor(tokens.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundColor(tokens.textSecondary)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .contentShape(Rectangle())
    }

    private var likedDetail: some View {
        detailScreen(title: "Tus me gusta") {
            SpotifyTrackList(tracks: model.liked) { model.message = $0 }
        }
    }

    private func playlistTile(_ playlist: SpotifyPlaylist) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SpotifyArtwork(url: playlist.imageURL, corner: 12)
            Text(playlist.name)
                .font(DS.Typography.bodyEm)
                .foregroundColor(tokens.textPrimary)
                .lineLimit(1)
            Text(playlist.count.map { "\($0) canciones" } ?? (playlist.owner?.display_name ?? ""))
                .font(DS.Typography.caption)
                .foregroundColor(tokens.textSecondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private func playlistDetail(_ playlist: SpotifyPlaylist) -> some View {
        SpotifyPlaylistDetail(playlist: playlist, canList: model.canListTracks(playlist))
    }

    // MARK: - Search

    @ViewBuilder
    private var searchResults: some View {
        if model.query.trimmingCharacters(in: .whitespaces).isEmpty {
            VStack { Spacer()
                Text("Busca canciones, álbumes y listas en Spotify. Necesita conexión a internet.")
                    .font(DS.Typography.body).foregroundColor(tokens.textSecondary)
                    .multilineTextAlignment(.center).padding(DS.Spacing.xl)
                Spacer() }
        } else if model.searching && model.tracks.isEmpty {
            VStack { Spacer(); ProgressView(); Spacer() }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    if !model.tracks.isEmpty {
                        sectionTitle("Canciones")
                        SpotifyTrackList(tracks: model.tracks) { model.message = $0 }
                        if model.canLoadMore {
                            Button("Más canciones") { Task { await model.search(spotify.webAPI, more: true) } }
                                .font(DS.Typography.bodyEm)
                                .foregroundColor(tokens.highlightColor)
                                .padding(.horizontal, DS.Spacing.lg)
                        }
                    }
                    if !model.albums.isEmpty {
                        sectionTitle("Álbumes")
                        horizontalTiles(model.albums.map { ($0.id, $0.uri, $0.name, $0.artistNames, $0.imageURL) }, savable: true)
                    }
                    if !model.foundPlaylists.isEmpty {
                        sectionTitle("Listas")
                        horizontalTiles(model.foundPlaylists.map { ($0.id, $0.uri, $0.name, $0.owner?.display_name ?? "", $0.imageURL) }, savable: false)
                    }
                    if model.tracks.isEmpty && model.albums.isEmpty && model.foundPlaylists.isEmpty && !model.searching {
                        Text("Sin resultados.").font(DS.Typography.body).foregroundColor(tokens.textSecondary)
                            .padding(DS.Spacing.xl)
                    }
                }
                .padding(.vertical, DS.Spacing.md)
            }
        }
    }

    private func horizontalTiles(_ items: [(id: String, uri: String, title: String, subtitle: String, image: URL?)],
                                 savable: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: DS.Spacing.md) {
                ForEach(items, id: \.id) { item in
                    Button { spotify.play(uri: item.uri) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            SpotifyArtwork(url: item.image, corner: 12).frame(width: 150)
                            Text(item.title).font(DS.Typography.bodyEm).foregroundColor(tokens.textPrimary).lineLimit(1)
                            Text(item.subtitle).font(DS.Typography.caption).foregroundColor(tokens.textSecondary).lineLimit(1)
                        }
                        .frame(width: 150, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button { spotify.play(uri: item.uri) } label: { Label("Reproducir", systemImage: "play.fill") }
                        if savable { saveButton(item.uri) }
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
        }
    }

    // MARK: - Shared pieces

    @ViewBuilder
    private func saveButton(_ uri: String) -> some View {
        if added.contains(uri) {
            Label("En tu biblioteca", systemImage: "checkmark")
        } else {
            Button {
                Task {
                    do {
                        try await spotify.webAPI.saveToLibrary(uris: [uri])
                        added.insert(uri)
                    } catch let error as SpotifyAPIError {
                        model.message = error.message
                    } catch {
                        model.message = "No se pudo guardar en tu biblioteca de Spotify."
                    }
                }
            } label: {
                Label("Añadir a mi biblioteca", systemImage: "plus")
            }
        }
    }

    private func detailScreen<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        ZStack {
            tokens.background.ignoresSafeArea()
            ScrollView { content().padding(.vertical, DS.Spacing.md) }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.footnote.weight(.semibold))
            .tracking(1.5)
            .foregroundColor(tokens.textSecondary)
            .padding(.horizontal, DS.Spacing.lg)
            .accessibilityAddTraits(.isHeader)
    }

    private func notice(_ icon: String, _ title: String, _ text: String) -> some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(tokens.accentGradient)
            Text(title).font(DS.Typography.titleLarge).foregroundColor(tokens.textPrimary)
            Text(text)
                .font(DS.Typography.body)
                .foregroundColor(tokens.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
        .padding(DS.Spacing.xl)
    }
}

/// A playlist: play it whole; its songs are listed only when Spotify allows
/// it (own or collaborative playlists in Development Mode).
struct SpotifyPlaylistDetail: View {
    @EnvironmentObject private var spotify: SpotifyService
    @EnvironmentObject private var themeManager: ThemeManager
    let playlist: SpotifyPlaylist
    let canList: Bool
    @State private var tracks: [SpotifyTrack] = []
    @State private var message: String?

    var body: some View {
        let tokens = themeManager.tokens
        ZStack {
            tokens.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: DS.Spacing.lg) {
                    SpotifyArtwork(url: playlist.imageURL, corner: 16).frame(width: 220)
                    Text(playlist.name).font(DS.Typography.titleLarge).foregroundColor(tokens.textPrimary)
                        .multilineTextAlignment(.center)
                    PlayShuffleButtons(tokens: tokens,
                                       onPlay: { spotify.play(uri: playlist.uri) },
                                       onShuffle: { spotify.play(uri: playlist.uri); spotify.setShuffle(true) })
                        .padding(.horizontal, DS.Spacing.lg)
                        .frame(maxWidth: 500)
                    if let message {
                        Text(message).font(DS.Typography.caption).foregroundColor(tokens.textSecondary)
                            .multilineTextAlignment(.center).padding(.horizontal, DS.Spacing.lg)
                    }
                    SpotifyTrackList(tracks: tracks) { message = $0 }
                }
                .padding(.vertical, DS.Spacing.lg)
            }
        }
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard canList else {
                message = "Spotify solo deja ver las canciones de tus listas propias o colaborativas. Puedes reproducir esta lista entera."
                return
            }
            do {
                tracks = try await spotify.webAPI.playlistTracks(playlist.id)
            } catch let error as SpotifyAPIError {
                message = error.message
            } catch {
                message = "No se pudieron cargar las canciones."
            }
        }
    }
}

/// Square artwork from a Spotify image URL, or the placeholder.
struct SpotifyArtwork: View {
    @EnvironmentObject private var themeManager: ThemeManager
    let url: URL?
    let corner: CGFloat

    var body: some View {
        let tokens = themeManager.tokens
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let url {
                    AsyncCachedImage(url: url, targetSize: 200) { ArtworkPlaceholder(tokens: tokens, cornerRadius: corner) }
                        .aspectRatio(contentMode: .fill)
                } else {
                    ArtworkPlaceholder(tokens: tokens, cornerRadius: corner)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Song rows: tap plays in the Spotify app; ⋯ saves to your library.
struct SpotifyTrackList: View {
    @EnvironmentObject private var spotify: SpotifyService
    @EnvironmentObject private var themeManager: ThemeManager
    let tracks: [SpotifyTrack]
    /// Error text for the screen that shows the list.
    var onMessage: (String) -> Void = { _ in }
    @State private var added: Set<String> = []

    var body: some View {
        let tokens = themeManager.tokens
        LazyVStack(spacing: 2) {
            ForEach(tracks, id: \.stableID) { track in
                HStack(spacing: DS.Spacing.md) {
                    Button { spotify.play(uri: track.uri) } label: {
                        HStack(spacing: DS.Spacing.md) {
                            SpotifyArtwork(url: track.imageURL, corner: 10).frame(width: 48, height: 48)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.name)
                                    .font(.body.weight(.medium))
                                    .foregroundColor(spotify.nowPlaying?.uri == track.uri ? tokens.highlightColor : tokens.textPrimary)
                                    .lineLimit(1)
                                Text(track.artistNames).font(.caption).foregroundColor(tokens.textSecondary).lineLimit(1)
                            }
                            Spacer()
                            if let ms = track.duration_ms {
                                Text(formatPlaybackTime(TimeInterval(ms) / 1000))
                                    .font(.caption.monospacedDigit()).foregroundColor(tokens.textSecondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Menu {
                        if added.contains(track.uri) {
                            Label("En tu biblioteca", systemImage: "checkmark")
                        } else {
                            Button { save(track.uri) } label: { Label("Añadir a mi biblioteca", systemImage: "plus") }
                        }
                    } label: {
                        Image(systemName: added.contains(track.uri) ? "checkmark" : "ellipsis")
                            .font(.body.weight(.semibold))
                            .foregroundColor(tokens.textSecondary)
                            .frame(width: 40, height: 44)
                    }
                    .accessibilityLabel("Más opciones para \(track.name)")
                }
                .padding(.leading, DS.Spacing.lg)
                .padding(.trailing, DS.Spacing.xs)
                .padding(.vertical, 4)
            }
        }
    }

    private func save(_ uri: String) {
        Task {
            do {
                try await spotify.webAPI.saveToLibrary(uris: [uri])
                added.insert(uri)
            } catch let error as SpotifyAPIError {
                onMessage(error.message)
            } catch {
                onMessage("No se pudo guardar en tu biblioteca de Spotify.")
            }
        }
    }
}
