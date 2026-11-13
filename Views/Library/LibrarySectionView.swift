import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Renders one section of the library — a header (when grouping is on)
/// followed by the rows. Used inside `LibraryView`'s
/// `ScrollView { LazyVStack { ForEach(vm.sections) { ... } } }`.
struct LibrarySectionView: View {
    #if os(macOS)
    @EnvironmentObject private var libraryManager: LocalLibraryManager
    #endif
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
    let onDeleteFromDisk: (LocalTrack) -> Void
    /// Non-nil while the library is in multi-select mode: taps toggle
    /// membership instead of playing, and the per-row menus are hidden.
    var selection: Binding<Set<UUID>>? = nil

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
                        onTap: { selection == nil ? onPlay(track) : toggle(track) }
                    )
                    if let selection {
                        let selected = selection.wrappedValue.contains(track.id)
                        Button { toggle(track) } label: {
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundColor(selected ? tokens.accent : tokens.textSecondary)
                                .frame(width: 40, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel(selected ? "Deseleccionar \(track.title)" : "Seleccionar \(track.title)")
                    } else {
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
                }
                .padding(.leading, DS.Spacing.lg)
                .padding(.trailing, DS.Spacing.xs)
                .padding(.vertical, 4)
                .background(isCurrentTrack(track) || selection?.wrappedValue.contains(track.id) == true
                            ? tokens.accentSubtle : Color.clear)
                .contextMenu { if selection == nil { actions(for: track) } }
                .id(track.id)  // A–Z index jump target
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

    private func toggle(_ track: LocalTrack) {
        Haptics.selection()
        if selection?.wrappedValue.remove(track.id) == nil {
            selection?.wrappedValue.insert(track.id)
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
        Button(role: .destructive) {
            onDeleteFromDisk(track)
        } label: {
            Label("Eliminar del disco", systemImage: "xmark.bin")
        }
        #if os(macOS)
        Divider()
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([libraryManager.fileURL(for: track)])
        } label: {
            Label("Mostrar en Finder", systemImage: "folder")
        }
        .disabled(track.isMissing)
        #endif
    }
}
