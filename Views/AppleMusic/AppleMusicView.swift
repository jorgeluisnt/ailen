import MediaPlayer
import MusicKit
import SwiftUI

/// Optional Apple Music section: the user's library (playlists, albums,
/// songs) played by Apple's player. Only shown when enabled in Settings.
struct AppleMusicView: View {
    @EnvironmentObject private var service: AppleMusicService
    @EnvironmentObject private var themeManager: ThemeManager

    private enum Shelf: String, CaseIterable {
        case playlists, albums, songs
        var title: String {
            switch self {
            case .playlists: return "Listas"
            case .albums: return "Álbumes"
            case .songs: return "Canciones"
            }
        }
    }

    @AppStorage("appleMusicShelf") private var shelfRaw = Shelf.playlists.rawValue
    @AppStorage("appleMusicMode") private var modeRaw = "library"
    @State private var searchText = ""

    private var tokens: DesignTokens { themeManager.tokens }
    private var shelf: Shelf { Shelf(rawValue: shelfRaw) ?? .playlists }

    var body: some View {
        NavigationStack {
            ZStack {
                tokens.background.ignoresSafeArea()
                switch service.libraryAuth {
                case .authorized: authorizedContent
                case .notDetermined: permissionPrompt
                default: permissionDenied
                }
            }
            .navigationTitle("Apple Music")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            if service.libraryAuth == .authorized && service.songs.isEmpty { service.loadLibrary() }
        }
        .alert("Apple Music", isPresented: Binding(get: { service.alertMessage != nil },
                                                   set: { if !$0 { service.alertMessage = nil } })) {
            Button("Aceptar", role: .cancel) { service.alertMessage = nil }
        } message: { Text(service.alertMessage ?? "") }
    }

    private var isSearchMode: Bool { modeRaw == "search" }

    /// Biblioteca (works with any account) · Buscar (catalog, needs MusicKit).
    private var authorizedContent: some View {
        VStack(spacing: 0) {
            Picker("Modo", selection: $modeRaw) {
                Text("Mi biblioteca").tag("library")
                Text("Buscar en Apple Music").tag("search")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.sm)
            .frame(maxWidth: 480)
            if isSearchMode { catalogContent } else { library }
        }
        .searchable(text: $searchText, prompt: isSearchMode ? "Canciones, álbumes, artistas" : "Buscar en tu biblioteca")
        // Catalog: search 0.4 s after typing stops.
        .task(id: isSearchMode ? searchText : "") {
            guard isSearchMode else { return }
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await service.searchCatalog(searchText)
        }
    }

    // MARK: - Catalog

    @ViewBuilder
    private var catalogContent: some View {
        switch service.catalogState {
        case .idle:
            emptyText("Busca canciones y álbumes en el catálogo de Apple Music. Necesita conexión a internet.")
        case .searching:
            VStack { Spacer(); ProgressView(); Spacer() }
        case .unavailable(let message):
            VStack(spacing: DS.Spacing.md) {
                Spacer()
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 36, weight: .light))
                    .foregroundColor(tokens.textSecondary)
                Text(message)
                    .font(DS.Typography.body)
                    .foregroundColor(tokens.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                Spacer()
            }
            .padding(DS.Spacing.xl)
        case .results:
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    if !service.catalogAlbums.isEmpty {
                        sectionTitle("Álbumes")
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: DS.Spacing.md) {
                                ForEach(service.catalogAlbums) { album in catalogAlbumTile(album) }
                            }
                            .padding(.horizontal, DS.Spacing.lg)
                        }
                    }
                    if !service.catalogSongs.isEmpty {
                        sectionTitle("Canciones")
                        LazyVStack(spacing: 2) {
                            ForEach(Array(service.catalogSongs.enumerated()), id: \.element.id) { index, song in
                                catalogSongRow(song, index: index)
                            }
                        }
                    }
                    if service.catalogAlbums.isEmpty && service.catalogSongs.isEmpty {
                        emptyText("Sin resultados.")
                    }
                }
                .padding(.vertical, DS.Spacing.md)
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.footnote.weight(.semibold))
            .tracking(1.5)
            .foregroundColor(tokens.textSecondary)
            .padding(.horizontal, DS.Spacing.lg)
            .accessibilityAddTraits(.isHeader)
    }

    private func catalogAlbumTile(_ album: Album) -> some View {
        Button { Task { await service.playCatalogAlbum(album) } } label: {
            VStack(alignment: .leading, spacing: 4) {
                catalogArtwork(album.artwork, size: 150, corner: 12)
                Text(album.title).font(DS.Typography.bodyEm).foregroundColor(tokens.textPrimary).lineLimit(1)
                Text(album.artistName).font(DS.Typography.caption).foregroundColor(tokens.textSecondary).lineLimit(1)
            }
            .frame(width: 150, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { Task { await service.playCatalogAlbum(album) } } label: { Label("Reproducir", systemImage: "play.fill") }
            Button { Task { await service.playCatalogAlbum(album, shuffled: true) } } label: { Label("Aleatorio", systemImage: "shuffle") }
            addButton(added: service.addedToLibrary.contains(album.id)) { await service.addToLibrary(album) }
        }
        .accessibilityLabel("\(album.title), \(album.artistName)")
    }

    private func catalogSongRow(_ song: Song, index: Int) -> some View {
        HStack(spacing: DS.Spacing.md) {
            Button { Task { await service.playCatalog(service.catalogSongs, startAt: index) } } label: {
                HStack(spacing: DS.Spacing.md) {
                    catalogArtwork(song.artwork, size: 48, corner: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title).font(.body.weight(.medium)).foregroundColor(tokens.textPrimary).lineLimit(1)
                        Text(song.artistName).font(.caption).foregroundColor(tokens.textSecondary).lineLimit(1)
                    }
                    Spacer()
                    if let duration = song.duration {
                        Text(formatPlaybackTime(duration)).font(.caption.monospacedDigit()).foregroundColor(tokens.textSecondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Menu {
                addButton(added: service.addedToLibrary.contains(song.id)) { await service.addToLibrary(song) }
            } label: {
                Image(systemName: service.addedToLibrary.contains(song.id) ? "checkmark" : "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundColor(tokens.textSecondary)
                    .frame(width: 40, height: 44)
            }
            .accessibilityLabel("Más opciones para \(song.title)")
        }
        .padding(.leading, DS.Spacing.lg)
        .padding(.trailing, DS.Spacing.xs)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func addButton(added: Bool, action: @escaping () async -> Void) -> some View {
        if added {
            Label("En tu biblioteca", systemImage: "checkmark")
        } else {
            Button { Task { await action() } } label: { Label("Añadir a mi biblioteca", systemImage: "plus") }
        }
    }

    private func catalogArtwork(_ artwork: Artwork?, size: CGFloat, corner: CGFloat) -> some View {
        Group {
            if let artwork {
                ArtworkImage(artwork, width: size, height: size)
            } else {
                ArtworkPlaceholder(tokens: tokens, cornerRadius: corner)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .accessibilityHidden(true)
    }

    // MARK: - Library

    private var library: some View {
        VStack(spacing: 0) {
            Picker("Biblioteca", selection: $shelfRaw) {
                ForEach(Shelf.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.sm)
            .frame(maxWidth: 480)

            Label("El audio lo reproduce Apple Music: sin ecualizador ni datos de calidad.", systemImage: "info.circle")
                .font(DS.Typography.caption)
                .foregroundColor(tokens.textSecondary)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.sm)

            if service.isLoading {
                Spacer(); ProgressView(); Spacer()
            } else {
                switch shelf {
                case .playlists: collectionGrid(filtered(service.playlists))
                case .albums: collectionGrid(filtered(service.albums))
                case .songs: songList(filteredSongs, playIn: filteredSongs)
                }
            }
        }
        .refreshable { service.loadLibrary() }
    }

    private func filtered(_ collections: [AMCollection]) -> [AMCollection] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return collections }
        return collections.filter {
            $0.title.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || $0.subtitle.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private var filteredSongs: [AMSong] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return service.songs }
        return service.songs.filter {
            $0.title.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || $0.artist.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private func collectionGrid(_ collections: [AMCollection]) -> some View {
        Group {
            if collections.isEmpty {
                emptyText(searchText.isEmpty ? "No hay nada aquí en tu biblioteca de Apple Music." : "Sin resultados.")
            } else {
                let anchors = AlphabetIndex.anchors(collections, letter: { AlphabetIndex.letter(for: $0.title) },
                                                    id: { AnyHashable($0.id) })
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 190), spacing: DS.Spacing.md)],
                                  spacing: DS.Spacing.lg) {
                            ForEach(collections) { collection in
                                NavigationLink { collectionDetail(collection) } label: { tile(collection) }
                                    .buttonStyle(.plain)
                                    .id(collection.id)
                            }
                        }
                        .padding(DS.Spacing.lg)
                        .padding(.trailing, anchors.count > 1 ? AlphabetIndexBar.width : 0)
                    }
                    .overlay(alignment: .trailing) {
                        if anchors.count > 1 {
                            AlphabetIndexBar(available: Set(anchors.keys), tokens: tokens) { letter in
                                if let id = anchors[letter] { proxy.scrollTo(id, anchor: .top) }
                            }
                            .padding(.vertical, DS.Spacing.lg)
                        }
                    }
                }
            }
        }
    }

    private func tile(_ collection: AMCollection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            AMArtwork(item: collection.artworkItem, size: 190, corner: 12, tokens: tokens)
            Text(collection.title)
                .font(DS.Typography.bodyEm)
                .foregroundColor(tokens.textPrimary)
                .lineLimit(1)
            Text(collection.subtitle)
                .font(DS.Typography.caption)
                .foregroundColor(tokens.textSecondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private func collectionDetail(_ collection: AMCollection) -> some View {
        let songs = collection.items.map(AMSong.init)
        return ZStack {
            tokens.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: DS.Spacing.lg) {
                    AMArtwork(item: collection.artworkItem, size: 220, corner: 16, tokens: tokens)
                        .frame(width: 220)
                    VStack(spacing: 2) {
                        Text(collection.title).font(DS.Typography.titleLarge).foregroundColor(tokens.textPrimary)
                        Text(collection.subtitle).font(DS.Typography.caption).foregroundColor(tokens.textSecondary)
                    }
                    .multilineTextAlignment(.center)
                    PlayShuffleButtons(tokens: tokens,
                                       onPlay: { service.play(collection.items) },
                                       onShuffle: { service.play(collection.items, shuffled: true) })
                        .padding(.horizontal, DS.Spacing.lg)
                        .frame(maxWidth: 500)
                    songRows(songs, playIn: songs)
                }
                .padding(.vertical, DS.Spacing.lg)
            }
        }
        .navigationTitle(collection.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func songList(_ songs: [AMSong], playIn: [AMSong]) -> some View {
        Group {
            if songs.isEmpty {
                emptyText(searchText.isEmpty ? "No hay canciones en tu biblioteca de Apple Music." : "Sin resultados.")
            } else {
                ScrollView { songRows(songs, playIn: playIn).padding(.vertical, DS.Spacing.sm) }
            }
        }
    }

    private func songRows(_ songs: [AMSong], playIn list: [AMSong]) -> some View {
        LazyVStack(spacing: 2) {
            ForEach(songs) { song in
                Button {
                    service.play(list.map(\.item), startAt: list.firstIndex(of: song) ?? 0)
                } label: {
                    HStack(spacing: DS.Spacing.md) {
                        AMArtwork(item: song.item, size: 48, corner: 10, tokens: tokens)
                            .frame(width: 48, height: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title)
                                .font(.body.weight(.medium))
                                .foregroundColor(service.nowPlaying?.id == song.id ? tokens.highlightColor : tokens.textPrimary)
                                .lineLimit(1)
                            Text(song.artist)
                                .font(.caption)
                                .foregroundColor(tokens.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if song.isCloud {
                            Image(systemName: "icloud")
                                .font(.caption)
                                .foregroundColor(tokens.textSecondary)
                                .accessibilityLabel("En la nube, necesita conexión")
                        }
                        Text(formatPlaybackTime(song.duration))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(tokens.textSecondary)
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Permission

    private var permissionPrompt: some View {
        VStack(spacing: DS.Spacing.lg) {
            Image(systemName: "music.note.house")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(tokens.accentGradient)
            Text("Conecta tu biblioteca de Apple Music")
                .font(DS.Typography.titleLarge)
                .foregroundColor(tokens.textPrimary)
                .multilineTextAlignment(.center)
            Text("Ailen mostrará tus listas, álbumes y canciones de la app Música y las reproducirá con el reproductor de Apple. El ecualizador y los datos de calidad no se aplican a Apple Music.")
                .font(DS.Typography.body)
                .foregroundColor(tokens.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Button {
                Task { await service.requestAccess() }
            } label: {
                Text("Permitir acceso")
                    .font(DS.Typography.bodyEm)
                    .foregroundColor(.white)
                    .padding(.horizontal, DS.Spacing.xl)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(tokens.accentGradient))
            }
            .buttonStyle(.plain)
        }
        .padding(DS.Spacing.xl)
    }

    private var permissionDenied: some View {
        VStack(spacing: DS.Spacing.lg) {
            Image(systemName: "lock")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(tokens.textSecondary)
            Text("Sin acceso a Apple Music")
                .font(DS.Typography.titleLarge)
                .foregroundColor(tokens.textPrimary)
            Text("Actívalo en Ajustes de iOS → Ailen → Medios y Apple Music.")
                .font(DS.Typography.body)
                .foregroundColor(tokens.textSecondary)
                .multilineTextAlignment(.center)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Abrir Ajustes", destination: url)
                    .font(DS.Typography.bodyEm)
                    .foregroundColor(tokens.highlightColor)
            }
        }
        .padding(DS.Spacing.xl)
    }

    private func emptyText(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(DS.Typography.body)
                .foregroundColor(tokens.textSecondary)
                .multilineTextAlignment(.center)
                .padding(DS.Spacing.xl)
            Spacer()
        }
    }
}

/// Artwork of a library item, or the placeholder.
struct AMArtwork: View {
    let item: MPMediaItem?
    let size: CGFloat
    let corner: CGFloat
    let tokens: DesignTokens

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image = AppleMusicService.artwork(item, size: size) {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    ArtworkPlaceholder(tokens: tokens, cornerRadius: corner)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Mini player for Apple Music (replaces the local one while Apple Music is
/// the active source). Tapping it opens the full-screen player.
struct AppleMusicNowPlayingBar: View {
    @EnvironmentObject private var service: AppleMusicService
    @EnvironmentObject private var themeManager: ThemeManager
    var onTap: () -> Void = {}

    var body: some View {
        let tokens = themeManager.tokens
        HStack(spacing: DS.Spacing.md) {
            Button(action: onTap) {
                HStack(spacing: DS.Spacing.md) {
                    AMArtwork(item: service.nowPlaying?.item, size: 44, corner: 8, tokens: tokens)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(service.nowPlaying?.title ?? "")
                            .font(DS.Typography.bodyEm)
                            .foregroundColor(tokens.highlightColor)
                            .lineLimit(1)
                        Text("Apple Music · \(service.nowPlaying?.artist ?? "")")
                            .font(DS.Typography.caption)
                            .foregroundColor(tokens.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Abre el reproductor a pantalla completa")
            Button { service.togglePlayPause() } label: {
                Image(systemName: service.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .foregroundColor(tokens.textPrimary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(service.isPlaying ? "Pausar" : "Reproducir")
            Button { service.skipToNext() } label: {
                Image(systemName: "forward.fill")
                    .font(.body)
                    .foregroundColor(tokens.textPrimary)
                    .frame(width: 40, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Siguiente canción")
        }
        .padding(.leading, DS.Spacing.sm)
        .padding(.trailing, DS.Spacing.xs)
        .padding(.vertical, 6)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .glassSurface(in: RoundedRectangle(cornerRadius: 26, style: .continuous), interactive: true)
    }
}
