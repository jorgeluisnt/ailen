import SwiftUI

/// Renders one section of the library — a header (when grouping is on)
/// followed by the rows. Used inside `LibraryView`'s
/// `ScrollView { LazyVStack { ForEach(vm.sections) { ... } } }`.
struct LibrarySectionView: View {
    let section: LibrarySection
    let showHeader: Bool
    let tokens: DesignTokens
    let isCurrentTrack: (LocalTrack) -> Bool
    let isPlaying: Bool
    let onPlay: (LocalTrack) -> Void
    let onPlayNext: (LocalTrack) -> Void
    let onAddToQueue: (LocalTrack) -> Void
    let onAddToPlaylist: (LocalTrack) -> Void
    let onDelete: (LocalTrack) -> Void

    // A Section (not a VStack) so the parent LazyVStack builds rows lazily;
    // a VStack would instantiate every row of the section at once.
    var body: some View {
        Section {
            ForEach(section.tracks) { track in
                HStack(spacing: 0) {
                    LibraryTrackRow(
                        track: track,
                        isCurrentTrack: isCurrentTrack(track),
                        isPlaying: isPlaying,
                        tokens: tokens,
                        onTap: { onPlay(track) }
                    )
                    // Sound Wave "⋯": the same actions as the long press.
                    Menu { actions(for: track) } label: {
                        Image(systemName: "ellipsis")
                            .font(.body.weight(.semibold))
                            .foregroundColor(tokens.textSecondary)
                            .frame(width: 40, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Más opciones para \(track.title)")
                }
                .padding(.leading, DS.Spacing.lg)
                .padding(.trailing, DS.Spacing.xs)
                .padding(.vertical, 4)
                .background(isCurrentTrack(track) ? tokens.accentSubtle : Color.clear)
                .contextMenu { actions(for: track) }
            }
        } header: {
            if showHeader && !section.title.isEmpty {
                Text(section.title)
                    .font(.headline)
                    .foregroundColor(tokens.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 16)
                    .accessibilityAddTraits(.isHeader)
            }
        }
    }

    @ViewBuilder
    private func actions(for track: LocalTrack) -> some View {
        Button {
            onPlay(track)
        } label: {
            Label("Reproducir", systemImage: "play.fill")
        }
        if !track.isMissing {
            Button {
                onPlayNext(track)
            } label: {
                Label("Reproducir a continuación", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            Button {
                onAddToQueue(track)
            } label: {
                Label("Añadir a la cola", systemImage: "text.badge.plus")
            }
        }
        Button {
            onAddToPlaylist(track)
        } label: {
            Label("Añadir a una lista", systemImage: "text.badge.plus")
        }
        Divider()
        Button(role: .destructive) {
            onDelete(track)
        } label: {
            Label("Eliminar de la biblioteca", systemImage: "trash")
        }
    }
}
