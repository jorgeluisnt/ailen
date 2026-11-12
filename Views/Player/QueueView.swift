import SwiftUI

struct QueueView: View {
    @EnvironmentObject private var playerManager: PlayerManager
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var playlistsManager: PlaylistsManager
    @Environment(\.dismiss) private var dismiss

    @State private var showSaveDialog = false
    @State private var newPlaylistName = ""
    @State private var editMode: EditMode = .inactive

    private var tokens: DesignTokens { themeManager.tokens }

    var body: some View {
        NavigationStack {
            ZStack {
                tokens.background.ignoresSafeArea()

                if playerManager.queue.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        trackCount
                            .padding(.horizontal, DS.Spacing.lg)
                            .padding(.vertical, DS.Spacing.sm)

                        queueList
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle("A continuación")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Listo") { dismiss() }
                        .foregroundColor(tokens.accent)
                }
                if !playerManager.queue.isEmpty {
                    ToolbarItemGroup(placement: .primaryAction) {
                        QueueEditButton(editMode: $editMode)
                            .foregroundColor(tokens.accent)
                        Menu {
                            Button {
                                newPlaylistName = ""
                                showSaveDialog = true
                            } label: {
                                Label("Guardar como lista", systemImage: "square.and.arrow.down")
                            }
                            Button(role: .destructive) {
                                Haptics.warning()
                                playerManager.clearQueue()
                            } label: {
                                Label("Vaciar cola", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundColor(tokens.accent)
                        }
                    }
                }
            }
            .alert("Guardar como lista", isPresented: $showSaveDialog) {
                TextField("Nombre de la lista", text: $newPlaylistName)
                Button("Cancelar", role: .cancel) {}
                Button("Guardar") { saveQueueAsPlaylist() }
            } message: {
                Text("Guarda la canción actual y todo lo que sigue a continuación.")
            }
        }
    }

    /// Snapshot the current track + up-next queue into a new playlist.
    private func saveQueueAsPlaylist() {
        let tracks = ([playerManager.currentTrack].compactMap { $0 }) + playerManager.queue
        guard !tracks.isEmpty else { return }
        let trimmed = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "Nueva lista" : trimmed
        playlistsManager.create(name: name, tracks: tracks)
        Haptics.success()
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.lg) {
            Spacer()
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [tokens.accent.opacity(0.30), tokens.accent.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 50, weight: .light))
                    .foregroundColor(tokens.accent)
            }
            .softShadow()
            VStack(spacing: DS.Spacing.sm) {
                Text("La cola está vacía")
                    .font(DS.Typography.titleLarge)
                    .foregroundColor(tokens.textPrimary)
                Text("Mantén pulsada una canción para añadirla a la cola")
                    .font(DS.Typography.body)
                    .foregroundColor(tokens.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, DS.Spacing.xl)
            Spacer()
        }
    }

    private var trackCount: some View {
        HStack {
            Text("\(playerManager.queue.count) \(playerManager.queue.count == 1 ? "canción" : "canciones")")
                .font(DS.Typography.captionStrong)
                .foregroundColor(tokens.textSecondary)
            Spacer()
        }
    }

    private var queueList: some View {
        QueueListContent(rowBackground: tokens.background, bottomInset: 60) { dismiss() }
    }
}

/// The up-next list: tap to play, swipe to remove, drag to reorder (in edit
/// mode). Shared by the queue sheet and the iPad Now Playing panel.
struct QueueListContent: View {
    @EnvironmentObject private var playerManager: PlayerManager
    @EnvironmentObject private var themeManager: ThemeManager

    var rowBackground: Color = .clear
    var bottomInset: CGFloat = 0
    /// Called when playing a row empties the queue.
    var onQueueEmptied: () -> Void = {}

    private var tokens: DesignTokens { themeManager.tokens }

    var body: some View {
        List {
            ForEach(Array(playerManager.queue.enumerated()), id: \.element.id) { index, track in
                Button {
                    Haptics.light()
                    playerManager.playFromQueue(at: index)
                    if playerManager.queue.isEmpty {
                        onQueueEmptied()
                    }
                } label: {
                    HStack(spacing: DS.Spacing.sm) {
                        Text("\(index + 1)")
                            .font(DS.Typography.captionStrong)
                            .foregroundColor(tokens.textSecondary)
                            .frame(width: 24)

                        TrackThumbnail(url: track.thumbnailURL, size: 44, cornerRadius: DS.Radius.sm, tokens: tokens)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .font(DS.Typography.bodyEm)
                                .lineLimit(1)
                                .foregroundColor(tokens.textPrimary)
                            Text(track.artist)
                                .font(DS.Typography.caption)
                                .lineLimit(1)
                                .foregroundColor(tokens.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(rowBackground)
                .listRowSeparatorTint(tokens.hairline)
                .listRowInsets(EdgeInsets(top: 4, leading: DS.Spacing.lg, bottom: 4, trailing: DS.Spacing.lg))
            }
            .onDelete { offsets in
                for idx in offsets.sorted(by: >) {
                    playerManager.removeFromQueue(at: idx)
                }
            }
            .onMove { offsets, destination in
                playerManager.moveInQueue(from: offsets, to: destination)
            }

            if bottomInset > 0 {
                Section {
                    Color.clear.frame(height: bottomInset)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}
