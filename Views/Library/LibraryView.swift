import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var libraryManager: LocalLibraryManager
    @EnvironmentObject private var playerManager: PlayerManager
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var playlistsManager: PlaylistsManager
    @EnvironmentObject private var nav: NavigationCoordinator
    @EnvironmentObject private var downloadManager: DownloadManager

    /// One `.fileImporter` for all three import kinds. Stacking three of
    /// them on the same view is a SwiftUI trap: only the last one presents,
    /// so plain "Import Files…" silently did nothing from the day folder and
    /// M3U import were added (06ebed1). `importKind` picks the content types
    /// and handler at presentation time.
    @State private var isImporting = false
    @State private var importKind: LibraryImportKind = .files
    @State private var importError: String?
    @State private var importProgress: FolderImporter.Progress?
    @State private var importSummary: String?
    @State private var addToPlaylistTrack: LocalTrack?
    @State private var selectedTab: LibraryTab = .offlineTracks
    @Namespace private var tabIndicator

    enum LibraryTab: String, CaseIterable {
        case offlineTracks = "Offline Tracks"
        case downloads = "Downloads"

        var displayName: String {
            switch self {
            case .offlineTracks: return "Canciones locales"
            case .downloads: return "Descargas"
            }
        }
    }

    @AppStorage("librarySortOrder") private var sortOrderRaw: String = LibrarySortOrder.recentlyAdded.rawValue
    @AppStorage("libraryGroupBy") private var groupByRaw: String = LibraryGroupBy.none.rawValue
    @AppStorage("libraryScope") private var scopeRaw: String = LibraryScope.songs.rawValue
    @State private var selectedGenre: String?

    private var scope: Binding<LibraryScope> {
        Binding(get: { LibraryScope(rawValue: scopeRaw) ?? .songs }, set: { scopeRaw = $0.rawValue })
    }

    @StateObject private var vm: LibraryViewModel

    private var tokens: DesignTokens { themeManager.tokens }

    init(library: LocalLibraryManager) {
        let savedSort = UserDefaults.standard.string(forKey: "librarySortOrder")
            ?? LibrarySortOrder.recentlyAdded.rawValue
        let savedGroup = UserDefaults.standard.string(forKey: "libraryGroupBy")
            ?? LibraryGroupBy.none.rawValue
        let initialSort = LibrarySortOrder(rawValue: savedSort) ?? .recentlyAdded
        let initialGroup = LibraryGroupBy(rawValue: savedGroup) ?? .none
        _vm = StateObject(
            wrappedValue: LibraryViewModel(
                library: library,
                initialSortOrder: initialSort,
                initialGroupBy: initialGroup,
                searchDebounce: 0.15
            )
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                tokens.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    if !vm.tracks.isEmpty {
                        LibraryScopeBar(scope: scope, tokens: tokens)
                            .padding(.horizontal, DS.Spacing.lg)
                            .padding(.vertical, DS.Spacing.sm)
                            .frame(maxWidth: 600)
                    }
                    offlineTracksContent
                }
            }
            .navigationTitle("Biblioteca")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $vm.searchText, prompt: "Buscar en la biblioteca")
            .onChange(of: vm.sortOrder) { newValue in
                sortOrderRaw = newValue.rawValue
            }
            .onChange(of: vm.groupBy) { newValue in
                groupByRaw = newValue.rawValue
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        playActiveTab()
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .disabled(activeTabIsEmpty)
                    .accessibilityLabel("Reproducir todo")
                }
                if selectedTab == .offlineTracks && scope.wrappedValue == .songs {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker("Ordenar por", selection: $vm.sortOrder) {
                                ForEach(LibrarySortOrder.allCases) { order in
                                    Text(order.displayName).tag(order)
                                }
                            }
                            Picker("Agrupar por", selection: $vm.groupBy) {
                                ForEach(LibraryGroupBy.allCases) { group in
                                    Text(group.displayName).tag(group)
                                }
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease")
                        }
                        .accessibilityLabel("Opciones de orden y agrupación")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            beginImport(.files)
                        } label: {
                            Label("Importar archivos…", systemImage: "doc.badge.plus")
                        }
                        Button {
                            beginImport(.folder)
                        } label: {
                            Label("Importar carpeta…", systemImage: "folder.badge.plus")
                        }
                        Button {
                            beginImport(.m3u)
                        } label: {
                            Label("Importar lista M3U…", systemImage: "list.bullet.rectangle")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Importar audio")
                }
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: importKind.contentTypes,
            allowsMultipleSelection: importKind.allowsMultipleSelection
        ) { result in
            switch result {
            case .success(let urls):
                switch importKind {
                case .files:  Task { await importURLs(urls) }
                case .folder: if let folder = urls.first { Task { await importFolder(folder) } }
                case .m3u:    if let url = urls.first { importM3U(url) }
                }
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .overlay(alignment: .bottom) {
            if let progress = importProgress {
                importProgressBanner(progress)
                    .padding(.bottom, 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .alert(
            "Importación",
            isPresented: Binding(get: { importSummary != nil }, set: { if !$0 { importSummary = nil } })
        ) {
            Button("Aceptar", role: .cancel) { importSummary = nil }
        } message: {
            Text(importSummary ?? "")
        }
        .alert(
            "Error de importación",
            isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })
        ) {
            Button("Aceptar", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .sheet(item: $addToPlaylistTrack) { track in
            addToPlaylistSheet(for: track)
        }
        .sheet(item: $nav.missingRepairTrack) { track in
            MissingTrackRepairSheet(
                track: track,
                onReimport: { url in
                    do {
                        _ = try libraryManager.repairMissing(trackID: track.id, newFileURL: url)
                    } catch {
                        importError = "No se pudo reparar '\(track.fileName)': \(error.localizedDescription)"
                    }
                },
                onRemove: {
                    libraryManager.remove(track)
                },
                onDismiss: { nav.missingRepairTrack = nil }
            )
        }
        .onAppear {
            libraryManager.auditMissingFlags()
        }
    }

    @ViewBuilder
    private func addToPlaylistSheet(for track: LocalTrack) -> some View {
        NavigationStack {
            Group {
                if playlistsManager.playlists.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No hay listas")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(tokens.textPrimary)
                        Text("Primero crea una lista desde la pestaña Listas")
                            .font(.subheadline)
                            .foregroundColor(tokens.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                } else {
                    List {
                        ForEach(playlistsManager.playlists) { playlist in
                            Button {
                                let asTrack = track.asPlayerTrack(fileURL: libraryManager.fileURL(for: track))
                                playlistsManager.addTrack(asTrack, to: playlist)
                                addToPlaylistTrack = nil
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(playlist.name)
                                            .font(.body)
                                            .foregroundColor(tokens.textPrimary)
                                        Text("\(playlist.tracks.count) \(playlist.tracks.count == 1 ? "canción" : "canciones")")
                                            .font(.caption)
                                            .foregroundColor(tokens.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                        .foregroundColor(tokens.accent)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Añadir a una lista")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { addToPlaylistTrack = nil }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(tokens.textSecondary)
            Text("Aún no hay archivos")
                .font(.title3)
                .foregroundColor(tokens.textPrimary)
            Text("Importa tus archivos de audio desde la app Archivos para escucharlos sin conexión.")
                .font(.callout)
                .foregroundColor(tokens.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                beginImport(.files)
            } label: {
                Label("Importar", systemImage: "plus")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(tokens.accent)
            .padding(.top, 8)
        }
    }

    // MARK: - Tab picker (matches the Playlists Recently-Added/Played style)

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(LibraryTab.allCases, id: \.self) { tab in
                Button {
                    Haptics.selection()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 6) {
                        Text(tab.displayName)
                            .font(DS.Typography.bodyEm)
                            .foregroundColor(selectedTab == tab ? tokens.textPrimary : tokens.textSecondary)
                        ZStack {
                            Capsule().fill(Color.clear).frame(height: 3)
                            if selectedTab == tab {
                                Capsule()
                                    .fill(tokens.accent)
                                    .frame(height: 3)
                                    .matchedGeometryEffect(id: "libraryTabIndicator", in: tabIndicator)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Offline Tracks tab (imported local files)

    @ViewBuilder
    private var offlineTracksContent: some View {
        if vm.tracks.isEmpty {
            emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.filteredAndSortedTracks.isEmpty {
            noSearchResults.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch scope.wrappedValue {
            case .songs:
                let anchors = songAnchors
                ScrollViewReader { proxy in
                    ScrollView {
                        trackSections(vm.sections, showHeaders: vm.groupBy != .none,
                                      playIn: vm.filteredAndSortedTracks)
                            .padding(.vertical, DS.Spacing.sm)
                            .padding(.trailing, anchors == nil ? 0 : AlphabetIndexBar.width)
                    }
                    .overlay(alignment: .trailing) {
                        if let anchors, anchors.count > 1 {
                            AlphabetIndexBar(available: Set(anchors.keys), tokens: tokens) { letter in
                                if let id = anchors[letter] { proxy.scrollTo(id, anchor: .top) }
                            }
                            .padding(.vertical, DS.Spacing.lg)
                        }
                    }
                }
            case .albums:
                CollectionGrid(collections: vm.albums, tokens: tokens) { collectionDetail($0) }
            case .artists:
                CollectionGrid(collections: vm.artists, tokens: tokens) { collectionDetail($0) }
            case .genres:
                genresContent
            case .folders:
                folderLevel([])
            }
        }
    }

    /// First row per letter for the A–Z bar, or `nil` when the current order
    /// isn't alphabetical (recently added, duration, size).
    private var songAnchors: [String: AnyHashable]? {
        if vm.groupBy != .none {
            return AlphabetIndex.anchors(vm.sections.filter { !$0.tracks.isEmpty },
                                         letter: { AlphabetIndex.letter(for: $0.title) },
                                         id: { AnyHashable($0.tracks[0].id) })
        }
        switch vm.sortOrder {
        case .title:
            return AlphabetIndex.anchors(vm.filteredAndSortedTracks,
                                         letter: { AlphabetIndex.letter(for: $0.title) }, id: { AnyHashable($0.id) })
        case .artist:
            return AlphabetIndex.anchors(vm.filteredAndSortedTracks,
                                         letter: { AlphabetIndex.letter(for: $0.artist) }, id: { AnyHashable($0.id) })
        case .recentlyAdded, .duration, .fileSize:
            return nil
        }
    }

    /// Rows for `sections`; tapping one plays `playIn` from that track.
    private func trackSections(_ sections: [LibrarySection], showHeaders: Bool,
                               playIn list: [LocalTrack]) -> some View {
        LazyVStack(spacing: 2) {
            ForEach(sections) { section in
                LibrarySectionView(
                    section: section,
                    showHeader: showHeaders,
                    tokens: tokens,
                    isCurrentTrack: isCurrentTrack,
                    isPlaying: playerManager.isPlaying,
                    onPlay: { playOrRepair($0, in: list) },
                    onPlayNext: { enqueueLocal($0, playNext: true) },
                    onAddToQueue: { enqueueLocal($0, playNext: false) },
                    onAddToPlaylist: { addToPlaylistTrack = $0 },
                    onDelete: { libraryManager.remove($0) }
                )
            }
        }
    }

    // MARK: - Browse: genres and collection detail

    // MARK: - Browse: folders

    /// One level of the Folders browser: subfolders, then the songs that sit
    /// directly in this folder. AnyView because levels nest recursively.
    private func folderLevel(_ path: [String]) -> AnyView {
        let contents = LibraryViewModel.folderContents(vm.filteredAndSortedTracks, at: path)
        return AnyView(
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(contents.folders) { folder in
                        NavigationLink {
                            ZStack {
                                tokens.background.ignoresSafeArea()
                                folderLevel(path + [folder.key])
                            }
                            .navigationTitle(folder.title)
                            .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            folderRow(folder)
                        }
                        .buttonStyle(.plain)
                    }
                    if !contents.tracks.isEmpty {
                        trackSections([LibrarySection(id: path.joined(separator: "/"), title: "", tracks: contents.tracks)],
                                      showHeaders: false, playIn: contents.tracks)
                    }
                    if contents.folders.isEmpty && contents.tracks.isEmpty {
                        Text("No hay canciones en esta carpeta.")
                            .font(DS.Typography.body)
                            .foregroundColor(tokens.textSecondary)
                            .padding(DS.Spacing.lg)
                    }
                }
                .padding(.vertical, DS.Spacing.sm)
            }
        )
    }

    private func folderRow(_ folder: FolderEntry) -> some View {
        let unknown = folder.key == LibraryViewModel.noFolderKey
        return HStack(spacing: DS.Spacing.md) {
            Image(systemName: unknown ? "questionmark.folder.fill" : "folder.fill")
                .font(.title2)
                .foregroundStyle(tokens.accentGradient)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.title)
                    .font(.body.weight(.medium))
                    .foregroundColor(tokens.textPrimary)
                    .lineLimit(1)
                Text(unknown ? "Importadas antes de guardar carpetas · \(LibraryViewModel.songCount(folder.songCount))"
                             : LibraryViewModel.songCount(folder.songCount))
                    .font(.caption)
                    .foregroundColor(tokens.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(tokens.textSecondary)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var genresContent: some View {
        let current = vm.genres.first(where: { $0.id == selectedGenre }) ?? vm.genres.first
        return ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                GenreChips(genres: vm.genres,
                           selection: Binding(get: { current?.id }, set: { selectedGenre = $0 }),
                           tokens: tokens)
                    .padding(.horizontal, DS.Spacing.lg)
                if let genre = current {
                    Text(genre.title)
                        .font(DS.Typography.titleLarge)
                        .foregroundColor(tokens.textPrimary)
                        .padding(.horizontal, DS.Spacing.lg)
                        .accessibilityAddTraits(.isHeader)
                    trackSections([LibrarySection(id: genre.id, title: "", tracks: genre.tracks)],
                                  showHeaders: false, playIn: genre.tracks)
                }
            }
            .padding(.vertical, DS.Spacing.sm)
        }
    }

    private func collectionDetail(_ collection: LibraryCollection) -> some View {
        ZStack {
            tokens.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: DS.Spacing.lg) {
                    CollectionTile(collection: collection, tokens: tokens)
                        .frame(maxWidth: 220)
                    PlayShuffleButtons(
                        tokens: tokens,
                        onPlay: { playCollection(collection.tracks, shuffled: false) },
                        onShuffle: { playCollection(collection.tracks, shuffled: true) }
                    )
                    .padding(.horizontal, DS.Spacing.lg)
                    .frame(maxWidth: 500)
                    trackSections([LibrarySection(id: collection.id, title: "", tracks: collection.tracks)],
                                  showHeaders: false, playIn: collection.tracks)
                }
                .padding(.vertical, DS.Spacing.lg)
            }
        }
        .navigationTitle(collection.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func playCollection(_ tracks: [LocalTrack], shuffled: Bool) {
        let playable = tracks.filter { !$0.isMissing }
            .map { $0.asPlayerTrack(fileURL: libraryManager.fileURL(for: $0)) }
        guard !playable.isEmpty else { return }
        playerManager.playSlice(shuffled ? playable.shuffled() : playable, startIndex: 0)
    }

    // MARK: - YouTube Downloads tab

    /// Downloaded tracks, filtered by the shared search field (title/artist).
    private var filteredDownloads: [DownloadRecord] {
        let q = vm.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return downloadManager.records }
        return downloadManager.records.filter {
            $0.title.range(of: q, options: .caseInsensitive) != nil
                || $0.artist.range(of: q, options: .caseInsensitive) != nil
        }
    }

    @ViewBuilder
    private var downloadsContent: some View {
        if downloadManager.records.isEmpty {
            downloadsEmptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredDownloads.isEmpty {
            noSearchResults.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(filteredDownloads) { rec in
                        downloadRow(rec)
                    }
                }
                .padding(.vertical)
            }
        }
    }

    @ViewBuilder
    private var downloadsEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(tokens.textSecondary)
            Text("Aún no hay descargas")
                .font(.title3)
                .foregroundColor(tokens.textPrimary)
            Text("Toca el botón de descarga de una canción para guardarla aquí y escucharla sin conexión.")
                .font(.callout)
                .foregroundColor(tokens.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func downloadRow(_ rec: DownloadRecord) -> some View {
        Button {
            let tracks = filteredDownloads.map(\.asTrack)
            let idx = filteredDownloads.firstIndex { $0.videoID == rec.videoID } ?? 0
            playerManager.playSlice(tracks, startIndex: idx)
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                TrackThumbnail(url: rec.thumbnailURL, size: 48, cornerRadius: DS.Radius.sm, tokens: tokens)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rec.title)
                        .font(.body)
                        .lineLimit(1)
                        .foregroundColor(playerManager.currentTrack?.id == rec.videoID ? tokens.accent : tokens.textPrimary)
                    HStack(spacing: 6) {
                        Text(rec.artist).lineLimit(1)
                        Text("· \(Self.formatBytes(rec.sizeBytes))")
                        QualityBadge(
                            AudioQuality.forFile(
                                fileName: rec.fileName,
                                sizeBytes: rec.sizeBytes,
                                durationSeconds: rec.durationSeconds
                            ),
                            tokens: tokens
                        )
                    }
                    .font(.caption)
                    .foregroundColor(tokens.textSecondary)
                }
                Spacer()
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(tokens.textSecondary)
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                Haptics.medium()
                playerManager.playNext(rec.asTrack)
            } label: {
                Label("Reproducir a continuación", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            Button {
                Haptics.medium()
                playerManager.addToQueue(rec.asTrack)
            } label: {
                Label("Añadir a la cola", systemImage: "text.badge.plus")
            }
            Divider()
            Button(role: .destructive) {
                downloadManager.remove(rec.videoID)
            } label: {
                Label("Eliminar descarga", systemImage: "trash")
            }
        }
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    @ViewBuilder
    private var noSearchResults: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(tokens.textSecondary)
            Text("Sin resultados")
                .font(.title3)
                .foregroundColor(tokens.textPrimary)
            Text("Ninguna canción coincide con \"\(vm.searchText)\".")
                .font(.callout)
                .foregroundColor(tokens.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Actions

    /// Bulk-imports a picked folder (recursively). Per-file failures are
    /// counted as skipped rather than aborting — one unsupported file in a
    /// 500-track folder must not kill the run.
    private func beginImport(_ kind: LibraryImportKind) {
        importKind = kind
        isImporting = true
    }

    private func importFolder(_ folder: URL) async {
        let result = await FolderImporter.importAll(
            from: folder,
            importFile: { url, folder in _ = try await libraryManager.importFile(at: url, folderPath: folder) },
            onProgress: { progress in
                withAnimation(.easeOut(duration: 0.15)) { importProgress = progress }
            }
        )
        withAnimation { importProgress = nil }
        Haptics.success()
        importSummary = result.total == 0
            ? "No se encontraron archivos de audio en esa carpeta."
            : "Se importaron \(result.imported) de \(result.total) \(result.total == 1 ? "archivo" : "archivos")"
                + (result.skipped > 0 ? " · \(result.skipped) \(result.skipped == 1 ? "omitido" : "omitidos")" : "") + "."
    }

    /// Imports an M3U/M3U8 playlist by matching its entries against the local
    /// library (by file name, then title+artist) and creating a playlist from
    /// whatever resolves.
    private func importM3U(_ url: URL) {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let entries = try M3UPlaylist.parse(text)
            let (tracks, unmatched) = M3UPlaylist.resolve(
                entries: entries,
                libraryTracks: libraryManager.tracks,
                fileURL: { libraryManager.fileURL(for: $0) }
            )
            guard !tracks.isEmpty else {
                importError = "Ninguna de las \(entries.count) entradas coincide con canciones de tu biblioteca. Importa primero los archivos de audio y después la lista."
                return
            }
            let name = url.deletingPathExtension().lastPathComponent
            _ = playlistsManager.create(name: name, tracks: tracks)
            Haptics.success()
            importSummary = unmatched.isEmpty
                ? "Se creó “\(name)” con \(tracks.count) \(tracks.count == 1 ? "canción" : "canciones")."
                : "Se creó “\(name)” con \(tracks.count) de \(entries.count) canciones. \(unmatched.count) \(unmatched.count == 1 ? "no se encontró" : "no se encontraron") en tu biblioteca."
        } catch {
            importError = error.localizedDescription
        }
    }

    /// Live progress while a folder import runs.
    private func importProgressBanner(_ progress: FolderImporter.Progress) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            ProgressView()
            Text("Importando \(progress.imported + progress.skipped) de \(progress.total)…")
                .font(DS.Typography.caption)
                .foregroundColor(tokens.textPrimary)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
        .background(Capsule().fill(.ultraThinMaterial))
        .softShadow()
    }

    private func importURLs(_ urls: [URL]) async {
        // Collect every failure — overwriting one alert message per error
        // meant a multi-file import reported only the last problem.
        var failures: [String] = []
        for url in urls {
            do {
                _ = try await libraryManager.importFile(at: url)
            } catch let error as ImportError {
                failures.append(importErrorMessage(for: error, fileName: url.lastPathComponent))
            } catch {
                failures.append("No se pudo importar \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        guard !failures.isEmpty else { return }
        importError = failures.count == 1
            ? failures[0]
            : "No se pudieron importar \(failures.count) de \(urls.count) archivos:\n\n"
                + failures.joined(separator: "\n\n")
    }

    private func importErrorMessage(for error: ImportError, fileName: String) -> String {
        switch error {
        case .unsupportedFormat(let format):
            return "\(fileName) usa el formato \(format.displayName), que no es compatible. Conviértelo a MP3 o FLAC e inténtalo de nuevo."
        case .fileNotDownloaded:
            return "\(fileName) aún no ha terminado de descargarse de iCloud. Ábrelo en la app Archivos, espera a que termine la descarga e inténtalo de nuevo."
        case .zeroByteFile:
            return "\(fileName) está vacío (0 bytes). Elige otro archivo."
        }
    }

    /// Hold-to-queue for a local file. Skips tracks with no bytes on disk
    /// (`isMissing`) so a placeholder entry isn't enqueued. Converts to a
    /// playable `Track` via the injected library manager's file URL.
    private func enqueueLocal(_ track: LocalTrack, playNext: Bool) {
        guard !track.isMissing else { return }
        Haptics.medium()
        let asTrack = track.asPlayerTrack(fileURL: libraryManager.fileURL(for: track))
        if playNext {
            playerManager.playNext(asTrack)
        } else {
            playerManager.addToQueue(asTrack)
        }
    }

    private func playOrRepair(_ track: LocalTrack, in list: [LocalTrack]) {
        if track.isMissing {
            nav.missingRepairTrack = track
        } else {
            playTrack(track, in: list)
        }
    }

    /// `list` is what the user sees (sorted, filtered, or one album), so
    /// Next/Previous follow the on-screen order.
    private func playTrack(_ track: LocalTrack, in list: [LocalTrack]) {
        // Build the full library as Track objects, then start playback
        // at the tapped track. Subsequent Next/Previous cycles through
        // the library in the same order the user sees in the list.
        // Pre-filter missing tracks and re-locate the tapped track's
        // index in the filtered list — `playSlice` clamps its
        // `startIndex` to the playable array's bounds, so passing the
        // unfiltered index would silently skip to the wrong track when
        // missing entries precede the tapped one.
        let library = list
        guard let result = Self.playableStartIndex(
            in: library,
            tappedTrack: track,
            fileURL: { libraryManager.fileURL(for: $0) }
        ) else { return }
        playerManager.playSlice(result.playable, startIndex: result.startIndex)
    }

    /// Pre-filters missing tracks from `library` and locates `tappedTrack`'s
    /// index in the resulting playable array. Returns `nil` if the tapped
    /// track is missing from the library.
    ///
    /// Exposed as a static, parameterised helper so unit tests can drive
    /// the same pre-filter + re-locate path that `playTrack` uses without
    /// having to instantiate a full `LibraryView` (which carries a dozen
    /// `@StateObject` / `@EnvironmentObject` dependencies).
    ///
    /// The pre-filter is load-bearing: `PlayerManager.playSlice` clamps its
    /// `startIndex` to the playable array's bounds, so passing the
    /// *unfiltered* index alongside the *unfiltered* library causes
    /// `playSlice`'s internal filter + clamp to land on the wrong track
    /// whenever a missing entry precedes the tapped one. See
    /// `test_playSlice_skippedMissingTracks_preservesStartIndex`.
    static func playableStartIndex(
        in library: [LocalTrack],
        tappedTrack: LocalTrack,
        fileURL: (LocalTrack) -> URL
    ) -> (playable: [Track], startIndex: Int)? {
        let playable = library
            .filter { !$0.isMissing }
            .map { $0.asPlayerTrack(fileURL: fileURL($0)) }
        guard let idx = playable.firstIndex(where: { $0.id == "local:\(tappedTrack.id.uuidString)" }) else {
            return nil
        }
        return (playable, idx)
    }

    private func playAll() {
        guard !vm.filteredAndSortedTracks.isEmpty else { return }
        let asTracks = vm.filteredAndSortedTracks.filter { !$0.isMissing }.map {
            $0.asPlayerTrack(fileURL: libraryManager.fileURL(for: $0))
        }
        playerManager.playSlice(asTracks, startIndex: 0)
    }

    /// Play-all for whichever tab is showing.
    private func playActiveTab() {
        switch selectedTab {
        case .offlineTracks:
            playAll()
        case .downloads:
            let tracks = filteredDownloads.map(\.asTrack)
            guard !tracks.isEmpty else { return }
            playerManager.playSlice(tracks, startIndex: 0)
        }
    }

    private var activeTabIsEmpty: Bool {
        selectedTab == .offlineTracks ? vm.tracks.isEmpty : downloadManager.records.isEmpty
    }

    private func isCurrentTrack(_ track: LocalTrack) -> Bool {
        playerManager.currentTrack?.id == "local:\(track.id.uuidString)"
    }
}

/// What the Library's single `.fileImporter` is being asked for. Internal
/// (not private) so the content-type mapping can be unit-tested.
enum LibraryImportKind {
    case files, folder, m3u

    var contentTypes: [UTType] {
        switch self {
        case .files:  return [.audio]
        case .folder: return [.folder]
        case .m3u:    return [.m3uPlaylist, .plainText]
        }
    }

    var allowsMultipleSelection: Bool { self == .files }
}
