import SwiftUI
import UniformTypeIdentifiers

/// Linked videos: all of them in a grid, or browsed by folder. Nothing is
/// copied; videos play from where they are in Files.
struct VideosView: View {
    @EnvironmentObject private var library: VideoLibraryManager
    @EnvironmentObject private var playback: VideoPlaybackController
    @EnvironmentObject private var themeManager: ThemeManager

    private enum Scope: String, CaseIterable {
        case all, folders
        var title: String { self == .all ? "Todos" : "Carpetas" }
    }

    private enum ImportKind { case files, folder }

    @AppStorage("videoScope") private var scopeRaw = Scope.all.rawValue
    @State private var searchText = ""
    @State private var isImporting = false
    @State private var importKind: ImportKind = .files
    @State private var progress: FolderImporter.Progress?
    @State private var summary: String?
    @State private var pendingRemoval: VideoItem?

    private var tokens: DesignTokens { themeManager.tokens }
    private var scope: Scope { Scope(rawValue: scopeRaw) ?? .all }

    /// Search (title, accents ignored) and A→Z order.
    private var visible: [VideoItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return library.videos
            .filter { query.isEmpty || $0.title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                tokens.background.ignoresSafeArea()
                if library.videos.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        Picker("Vista", selection: $scopeRaw) {
                            ForEach(Scope.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.vertical, DS.Spacing.sm)
                        .frame(maxWidth: 420)
                        if scope == .all {
                            grid(visible)
                        } else {
                            folderLevel([])
                        }
                    }
                }
            }
            .navigationTitle("Videos")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Buscar videos")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { addMenu }
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: importKind == .folder
                ? [.folder]
                : [.mpeg4Movie, .quickTimeMovie, UTType(filenameExtension: "m4v") ?? .movie],
            allowsMultipleSelection: importKind == .files
        ) { result in
            guard case .success(let urls) = result else { return }
            Task { await add(urls) }
        }
        .overlay(alignment: .bottom) {
            if let progress {
                HStack(spacing: DS.Spacing.sm) {
                    ProgressView()
                    Text("Añadiendo \(progress.imported + progress.skipped) de \(progress.total)…")
                        .font(DS.Typography.caption)
                        .foregroundColor(tokens.textPrimary)
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.sm)
                .glassSurface(in: Capsule())
                .padding(.bottom, 110)
            }
        }
        .alert("Videos", isPresented: Binding(get: { summary != nil }, set: { if !$0 { summary = nil } })) {
            Button("Aceptar", role: .cancel) { summary = nil }
        } message: { Text(summary ?? "") }
        .alert("No se puede reproducir",
               isPresented: Binding(get: { playback.errorMessage != nil }, set: { if !$0 { playback.errorMessage = nil } })) {
            Button("Aceptar", role: .cancel) { playback.errorMessage = nil }
        } message: { Text(playback.errorMessage ?? "") }
        .confirmationDialog("¿Quitar el video de Ailen?",
                            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
                            titleVisibility: .visible, presenting: pendingRemoval) { item in
            Button("Quitar de Ailen", role: .destructive) { library.remove(item) }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("El archivo original no se borra; sigue en la app Archivos.")
        }
        .task { library.auditMissingFlags() }
    }

    // MARK: - Adding

    private var addMenu: some View {
        Menu {
            Button { importKind = .files; isImporting = true } label: {
                Label("Añadir videos…", systemImage: "film")
            }
            Button { importKind = .folder; isImporting = true } label: {
                Label("Añadir carpeta…", systemImage: "folder.badge.plus")
            }
            if !library.sources.isEmpty {
                Button {
                    Task {
                        let added = await library.refreshSources()
                        summary = added == 0 ? "No hay videos nuevos en tus carpetas."
                            : "Se añadieron \(added) \(added == 1 ? "video nuevo" : "videos nuevos")."
                    }
                } label: {
                    Label("Actualizar carpetas", systemImage: "arrow.clockwise")
                }
            }
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("Añadir videos")
    }

    private func add(_ urls: [URL]) async {
        switch importKind {
        case .files:
            let failures = await library.addFiles(urls)
            if !failures.isEmpty { summary = failures.joined(separator: "\n\n") }
        case .folder:
            guard let folder = urls.first else { return }
            let result = await library.addFolder(folder) { progress = $0 }
            progress = nil
            summary = result.total == 0
                ? "No hay videos nuevos MP4, MOV o M4V en esa carpeta."
                : "Se añadieron \(result.imported) de \(result.total) videos"
                    + (result.skipped > 0 ? " · \(result.skipped) no compatibles o no disponibles" : "") + "."
        }
    }

    // MARK: - Grid

    private func grid(_ items: [VideoItem]) -> some View {
        let anchors = AlphabetIndex.anchors(items, letter: { AlphabetIndex.letter(for: $0.title) },
                                            id: { AnyHashable($0.id) })
        let showIndex = scope == .all && anchors.count > 1
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 360), spacing: DS.Spacing.lg)],
                          spacing: DS.Spacing.lg) {
                    ForEach(items) { item in
                        Button { playback.play(item) } label: { VideoCard(item: item, tokens: tokens) }
                            .buttonStyle(.plain)
                            .id(item.id)
                            .contextMenu { actions(for: item) }
                    }
                }
                .padding(DS.Spacing.lg)
                .padding(.trailing, showIndex ? AlphabetIndexBar.width : 0)
            }
            .overlay(alignment: .trailing) {
                if showIndex {
                    AlphabetIndexBar(available: Set(anchors.keys), tokens: tokens) { letter in
                        if let id = anchors[letter] { proxy.scrollTo(id, anchor: .top) }
                    }
                    .padding(.vertical, DS.Spacing.lg)
                }
            }
        }
    }

    @ViewBuilder
    private func actions(for item: VideoItem) -> some View {
        Button { playback.play(item) } label: {
            Label(item.resumePosition == nil ? "Reproducir" : "Continuar", systemImage: "play.fill")
        }
        if item.resumePosition != nil {
            Button { playback.play(item, fromStart: true) } label: {
                Label("Desde el inicio", systemImage: "backward.end.fill")
            }
        }
        Divider()
        Button(role: .destructive) { pendingRemoval = item } label: {
            Label("Quitar de Ailen", systemImage: "minus.circle")
        }
    }

    // MARK: - Folders

    /// One folder level: subfolders, then the videos directly in it.
    private func folderLevel(_ path: [String]) -> AnyView {
        let contents = LibraryViewModel.folderContents(visible, at: path, folderPath: \.folderPath)
        return AnyView(
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
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
                    if !contents.items.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 360), spacing: DS.Spacing.lg)],
                                  spacing: DS.Spacing.lg) {
                            ForEach(contents.items) { item in
                                Button { playback.play(item) } label: { VideoCard(item: item, tokens: tokens) }
                                    .buttonStyle(.plain)
                                    .contextMenu { actions(for: item) }
                            }
                        }
                        .padding(DS.Spacing.lg)
                    }
                }
                .padding(.vertical, DS.Spacing.sm)
            }
        )
    }

    private func folderRow(_ folder: FolderEntry) -> some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: "folder.fill")
                .font(.title2)
                .foregroundStyle(tokens.accentGradient)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.title)
                    .font(.body.weight(.medium))
                    .foregroundColor(tokens.textPrimary)
                Text("\(folder.songCount) \(folder.songCount == 1 ? "video" : "videos")")
                    .font(.caption)
                    .foregroundColor(tokens.textSecondary)
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

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.lg) {
            Image(systemName: "film.stack")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(tokens.accentGradient)
            Text("Aún no hay videos")
                .font(DS.Typography.titleLarge)
                .foregroundColor(tokens.textPrimary)
            Text("Añade videos MP4, MOV o M4V desde la app Archivos. No se copian: se reproducen desde donde están.")
                .font(DS.Typography.body)
                .foregroundColor(tokens.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            HStack(spacing: DS.Spacing.md) {
                Button { importKind = .files; isImporting = true } label: {
                    Label("Añadir videos", systemImage: "film")
                        .font(DS.Typography.bodyEm)
                        .foregroundColor(.white)
                        .padding(.horizontal, DS.Spacing.lg)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(tokens.accentGradient))
                }
                Button { importKind = .folder; isImporting = true } label: {
                    Label("Añadir carpeta", systemImage: "folder.badge.plus")
                        .font(DS.Typography.bodyEm)
                        .foregroundColor(tokens.textPrimary)
                        .padding(.horizontal, DS.Spacing.lg)
                        .frame(minHeight: 44)
                        .glassSurface(in: Capsule(), interactive: true)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(DS.Spacing.xl)
    }
}

/// 16:9 thumbnail with duration, resume progress and availability.
struct VideoCard: View {
    @EnvironmentObject private var library: VideoLibraryManager
    let item: VideoItem
    let tokens: DesignTokens

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.black
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay {
                    if let url = library.thumbnailURL(for: item) {
                        AsyncCachedImage(url: url, targetSize: 360) { placeholder }
                            .aspectRatio(contentMode: .fill)
                    } else {
                        placeholder
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if let duration = item.durationSeconds {
                        Text(Self.format(duration))
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.black.opacity(0.6)))
                            .padding(6)
                    }
                }
                .overlay(alignment: .bottom) {
                    if let resume = item.resumePosition, let duration = item.durationSeconds, duration > 0 {
                        GeometryReader { geo in
                            Capsule().fill(tokens.accentGradient)
                                .frame(width: geo.size.width * min(resume / duration, 1), height: 4)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                    }
                }
                .overlay {
                    if item.isMissing {
                        ZStack {
                            Color.black.opacity(0.6)
                            Label("No disponible", systemImage: "exclamationmark.icloud")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.white)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(item.title)
                .font(DS.Typography.bodyEm)
                .foregroundColor(tokens.textPrimary)
                .lineLimit(2)
            Text([item.fileExtension, ByteCountFormatter.string(fromByteCount: item.fileSizeBytes, countStyle: .file)]
                .filter { !$0.isEmpty }.joined(separator: " · "))
                .font(DS.Typography.caption)
                .foregroundColor(tokens.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(item.resumePosition == nil ? "Reproduce el video" : "Continúa donde lo dejaste")
    }

    private var placeholder: some View {
        Image(systemName: "film")
            .font(.title)
            .foregroundColor(tokens.textSecondary)
    }

    static func format(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }
}
