import SwiftUI

// Player building blocks shared by the full-screen player (iPhone, iPad
// portrait) and the always-visible Now Playing panel (iPad landscape).

/// "1:05" style time.
func formatPlaybackTime(_ time: TimeInterval) -> String {
    let t = Int(max(0, time))
    return String(format: "%d:%02d", t / 60, t % 60)
}

/// File, output route and audio mode, on one glass card. Source and output
/// stay on separate lines: they are different measurements.
struct PlayerQualityCard: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var outputMonitor: AudioOutputMonitor
    @EnvironmentObject private var eqController: EQController

    let track: Track
    let sourceInfo: SourceAudioInfo?

    var body: some View {
        VStack(spacing: 2) {
            if track.localFileURL != nil {
                Text(sourceInfo?.displayText ?? "Archivo: No disponible")
                    .font(.caption)
                    .foregroundColor(themeManager.textSecondary)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel(sourceInfo?.displayText ?? "Datos del archivo no disponibles")
            }

            // Route data, not file data: the session rate after activation.
            Text(outputMonitor.snapshot.displayText)
                .font(.caption)
                .foregroundColor(themeManager.textSecondary)
                .multilineTextAlignment(.center)

            Text(eqController.isEnabled ? "Modo: Ecualizador (modifica el audio)" : "Modo: Directo (sin EQ)")
                .font(.caption)
                .foregroundColor(themeManager.textSecondary)

            if outputMonitor.snapshot.isUSBDAC {
                Label("DAC USB conectado", systemImage: "cable.connector")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(themeManager.tokens.highlightColor)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
        .glassSurface(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Elapsed · bar · total on one line, plus the rebuffering indicator.
/// In-app volume slider (`PlayerManager.volume`). The hardware buttons still
/// move the system volume; this scales Ailen's output beneath it.
struct PlayerVolumeSlider: View {
    @EnvironmentObject private var playerManager: PlayerManager
    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            Button { playerManager.setVolume(0) } label: {
                Image(systemName: playerManager.volume == 0 ? "speaker.slash.fill" : "speaker.fill")
                    .font(.caption)
                    .foregroundColor(themeManager.textSecondary)
                    .frame(width: 24, height: 34)
            }
            .accessibilityLabel("Silenciar")
            Slider(value: Binding(get: { Double(playerManager.volume) },
                                  set: { playerManager.setVolume(Float($0)) }),
                   in: 0...1)
                .tint(themeManager.theme.accentColor)
                .accessibilityLabel("Volumen")
                .accessibilityValue("\(Int((playerManager.volume * 100).rounded())) %")
            Button { playerManager.setVolume(1) } label: {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.caption)
                    .foregroundColor(themeManager.textSecondary)
                    .frame(width: 24, height: 34)
            }
            .accessibilityLabel("Volumen máximo")
        }
    }
}

struct PlayerSeekBar: View {
    @EnvironmentObject private var playerManager: PlayerManager
    @EnvironmentObject private var clock: PlaybackClock
    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: DS.Spacing.md) {
                Text(formatPlaybackTime(clock.currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(themeManager.textSecondary)
                    .accessibilityHidden(true)
                Slider(
                    value: Binding(
                        get: { clock.currentTime },
                        set: { playerManager.seek(to: $0) }
                    ),
                    in: 0...max(clock.duration, 1)
                ) {
                    Text("Posición")
                }
                .tint(themeManager.theme.accentColor)
                // Native Slider announces a bare percentage; give VoiceOver a
                // meaningful position ("1:05 of 3:20") and an adjustable label.
                .accessibilityLabel("Posición de reproducción")
                .accessibilityValue("\(formatPlaybackTime(clock.currentTime)) de \(formatPlaybackTime(clock.duration))")
                Text(formatPlaybackTime(clock.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(themeManager.textSecondary)
                    .accessibilityHidden(true)
            }

            HStack {
                Spacer()
                if playerManager.isRebuffering {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Cargando…")
                            .font(.caption2)
                            .foregroundColor(themeManager.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Cargando")
                }
                Spacer()
            }
            .frame(minHeight: 14)
        }
    }
}

/// Repeat · previous · play · next · shuffle. `compact` shrinks the buttons
/// for the iPad side panel.
struct PlayerTransportControls: View {
    @EnvironmentObject private var playerManager: PlayerManager
    @EnvironmentObject private var themeManager: ThemeManager

    var compact = false

    private var skipSide: CGFloat { compact ? 44 : 52 }
    private var playSide: CGFloat { compact ? 62 : 76 }

    var body: some View {
        HStack(spacing: compact ? DS.Spacing.sm : DS.Spacing.lg) {
            Button { playerManager.cycleRepeatMode() } label: {
                Image(systemName: repeatIcon)
                    .font(.title3)
                    .foregroundColor(playerManager.repeatMode != .off ? themeManager.theme.accentColor : themeManager.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Modo de repetición: \(playerManager.repeatMode == .off ? "desactivado" : playerManager.repeatMode == .one ? "una canción" : "todas")")

            Button { playerManager.previousTrack() } label: {
                Image(systemName: "backward.end.fill")
                    .font(compact ? .title3 : .title2)
                    .foregroundColor(themeManager.textPrimary)
                    .frame(width: skipSide, height: skipSide)
                    .glassSurface(in: Circle(), interactive: true)
                    .contentShape(Circle())
            }
            .accessibilityLabel("Canción anterior")

            // Glass button with a gradient ring and gradient icon.
            Button { playerManager.togglePlayPause() } label: {
                Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: compact ? 24 : 30, weight: .bold))
                    .foregroundStyle(themeManager.tokens.accentGradient)
                    .frame(width: playSide, height: playSide)
                    .glassSurface(in: Circle(), interactive: true)
                    .overlay(Circle().strokeBorder(themeManager.tokens.accentGradient, lineWidth: 3))
                    .contentShape(Circle())
            }
            .accessibilityLabel(playerManager.isPlaying ? "Pausar" : "Reproducir")

            Button { playerManager.nextTrack() } label: {
                Image(systemName: "forward.end.fill")
                    .font(compact ? .title3 : .title2)
                    .foregroundColor(themeManager.textPrimary)
                    .frame(width: skipSide, height: skipSide)
                    .glassSurface(in: Circle(), interactive: true)
                    .contentShape(Circle())
            }
            .accessibilityLabel("Siguiente canción")

            Button { playerManager.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .font(.title3)
                    .foregroundColor(playerManager.isShuffled ? themeManager.theme.accentColor : themeManager.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(playerManager.isShuffled ? "Aleatorio activado" : "Aleatorio desactivado")
        }
    }

    private var repeatIcon: String {
        playerManager.repeatMode == .one ? "repeat.1" : "repeat"
    }
}

/// Favourite, add to playlist, EQ, speed, share and delete, in a glass
/// capsule. Deleting a file asks for confirmation; `onNothingLeft` runs when
/// the deletion left nothing playing (the full player uses it to close).
struct PlayerSecondaryControls: View {
    @EnvironmentObject private var playerManager: PlayerManager
    @EnvironmentObject private var favoritesManager: FavoritesManager
    @EnvironmentObject private var playlistsManager: PlaylistsManager
    @EnvironmentObject private var recentlyPlayedManager: RecentlyPlayedManager
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var nav: NavigationCoordinator
    @EnvironmentObject private var localLibraryManager: LocalLibraryManager

    let track: Track
    var spacing: CGFloat = 20
    var onNothingLeft: () -> Void = {}

    @State private var trackPendingDeletion: Track?
    /// true = "Eliminar del disco" (also deletes the original in Files).
    @State private var deletionFromDisk = false
    @State private var deletionError: String?

    var body: some View {
        HStack(spacing: spacing) {
            Button {
                favoritesManager.toggle(track)
                if favoritesManager.isFavorite(track) {
                    recentlyPlayedManager.trackAdded(track)
                }
            } label: {
                Image(systemName: favoritesManager.isFavorite(track) ? "heart.fill" : "heart")
                    .font(.title3)
                    .foregroundColor(favoritesManager.isFavorite(track) ? themeManager.tokens.highlightColor : themeManager.textPrimary)
            }
            .accessibilityLabel(favoritesManager.isFavorite(track) ? "Quitar de Favoritos" : "Añadir a Favoritos")

            DownloadButton(track: track)

            Button { nav.presentedSheet = .addToPlaylist } label: {
                Image(systemName: "text.badge.plus")
                    .font(.title3)
                    .foregroundColor(themeManager.textPrimary)
            }
            .accessibilityLabel("Añadir a una lista")

            Button { nav.presentedSheet = .equalizer } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3)
                    .foregroundColor(themeManager.textPrimary)
            }
            .accessibilityLabel("Ecualizador")

            Button { nav.presentedSheet = .speedAndPitch } label: {
                Text(speedLabel(playerManager.playbackRate))
                    .scaledFont(size: 15, weight: .semibold, relativeTo: .subheadline)
                    .monospacedDigit()
                    // Wide enough for "0.81×", so fine values don't shift the row.
                    .frame(minWidth: 46)
                    .foregroundColor(isTuningAtDefault
                                     ? themeManager.textPrimary
                                     : themeManager.theme.accentColor)
            }
            .accessibilityLabel("Velocidad y tono")
            .accessibilityValue(tuningAccessibilityValue)

            // Share the song's name, not the thumbnail image. See
            // `Track.shareText` for why this is never a URL.
            ShareLink(item: track.shareText, subject: Text(track.title)) {
                Image(systemName: "square.and.arrow.up")
                    .font(.title3)
                    .foregroundColor(themeManager.textPrimary)
            }

            deleteMenu
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        .glassSurface(in: Capsule())
        .confirmationDialog(
            deletionFromDisk ? "¿Eliminar del disco?" : "¿Eliminar de la biblioteca?",
            isPresented: Binding(get: { trackPendingDeletion != nil },
                                 set: { if !$0 { trackPendingDeletion = nil } }),
            titleVisibility: .visible,
            presenting: trackPendingDeletion
        ) { pending in
            Button(deletionFromDisk ? "Eliminar del disco" : "Eliminar de la biblioteca", role: .destructive) {
                deleteFile(pending)
            }
            Button("Cancelar", role: .cancel) {}
        } message: { pending in
            #if os(macOS)
            Text(deletionFromDisk
                 ? "Se moverá a la Papelera el archivo de «\(pending.title)» y se quitará de la biblioteca, Favoritos y listas."
                 : "Se quitará «\(pending.title)» de la biblioteca, Favoritos y listas. El archivo de tu Mac no se borra.")
            #else
            Text(deletionFromDisk
                 ? "Se borrará de la app Archivos el archivo original de «\(pending.title)» y se quitará de la biblioteca, Favoritos y listas. No se puede deshacer."
                 : "Se quitará «\(pending.title)» de la biblioteca, Favoritos y listas, y se borrará su copia en Ailen. El original en la app Archivos no se toca.")
            #endif
        }
        .alert(
            "No se pudo eliminar",
            isPresented: Binding(get: { deletionError != nil }, set: { if !$0 { deletionError = nil } })
        ) {
            Button("Aceptar", role: .cancel) { deletionError = nil }
        } message: {
            Text(deletionError ?? "")
        }
    }

    private func playlistsContaining(_ track: Track) -> [Playlist] {
        playlistsManager.playlists.filter { $0.tracks.contains { $0.id == track.id } }
    }

    private var deleteMenu: some View {
        let lists = playlistsContaining(track)
        return Menu {
            Section("Quitar de una lista") {
                if lists.isEmpty {
                    Text("No está en ninguna lista")
                }
                ForEach(lists) { list in
                    Button {
                        playlistsManager.removeTrack(track, from: list)
                    } label: {
                        Label("Quitar de «\(list.name)»", systemImage: "minus.circle")
                    }
                }
            }
            // Only imported files can be deleted from the device.
            if track.localFileURL != nil {
                Button(role: .destructive) {
                    deletionFromDisk = false
                    trackPendingDeletion = track
                } label: {
                    Label("Eliminar de la biblioteca…", systemImage: "trash")
                }
                Button(role: .destructive) {
                    deletionFromDisk = true
                    trackPendingDeletion = track
                } label: {
                    Label("Eliminar del disco…", systemImage: "xmark.bin")
                }
            }
        } label: {
            Image(systemName: "trash")
                .font(.title3)
                .foregroundColor(themeManager.textPrimary)
        }
        .accessibilityLabel("Eliminar")
    }

    /// Stops using the track first, so AVPlayer is no longer reading the file,
    /// then removes every reference and the file itself.
    private func deleteFile(_ track: Track) {
        guard let local = localLibraryManager.tracks.first(where: { "local:\($0.id.uuidString)" == track.id }) else {
            return
        }
        let failed = localLibraryManager.purge([local], fromDisk: deletionFromDisk, player: playerManager,
                                               favorites: favoritesManager, playlists: playlistsManager,
                                               recents: recentlyPlayedManager)
        if !failed.isEmpty {
            deletionError = "No se pudo borrar el archivo original; la canción sigue en la biblioteca. Si se importó antes de esta versión, bórrala desde la app Archivos."
            return
        }
        if playerManager.currentTrack == nil {
            onNothingLeft()
        }
    }

    /// "1×", "0.5×", "1.25×" — `%g` trims trailing zeros.
    private func speedLabel(_ rate: Float) -> String {
        "\(String(format: "%g", Double(rate)))×"
    }

    private var isTuningAtDefault: Bool {
        playerManager.playbackRate == PlaybackTuning.defaultSpeed
            && playerManager.playbackPitch == PlaybackTuning.defaultPitch
    }

    private var tuningAccessibilityValue: String {
        let speed = speedLabel(playerManager.playbackRate)
        guard playerManager.playbackPitch != PlaybackTuning.defaultPitch else { return speed }
        return speed + ", tono " + String(format: "%+.1f", playerManager.playbackPitch) + " semitonos"
    }
}

/// Adds `tracks` to one of the user's playlists, or to a new one created
/// right here. The one sheet behind every "Añadir a una lista" (player,
/// library — including multi-select — and favourites).
struct AddToPlaylistSheet: View {
    @EnvironmentObject private var playlistsManager: PlaylistsManager
    @EnvironmentObject private var recentlyPlayedManager: RecentlyPlayedManager
    @EnvironmentObject private var themeManager: ThemeManager

    let tracks: [Track]
    /// Runs after the tracks were added, and on "Listo".
    let onDone: () -> Void

    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""

    var body: some View {
        NavigationStack {
            List {
                Button {
                    showNewPlaylistAlert = true
                } label: {
                    Label("Nueva lista…", systemImage: "plus")
                        .foregroundColor(themeManager.theme.accentColor)
                }
                ForEach(playlistsManager.playlists) { playlist in
                    Button {
                        tracks.forEach { playlistsManager.addTrack($0, to: playlist) }
                        finish()
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(playlist.name)
                                    .font(.body)
                                    .foregroundColor(themeManager.textPrimary)
                                Text("\(playlist.tracks.count) \(playlist.tracks.count == 1 ? "canción" : "canciones")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "plus.circle")
                                .foregroundColor(themeManager.theme.accentColor)
                        }
                    }
                }
            }
            .navigationTitle("Añadir a una lista")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Listo", action: onDone)
                }
            }
            .alert("Nueva lista", isPresented: $showNewPlaylistAlert) {
                TextField("Nombre de la lista", text: $newPlaylistName)
                Button("Cancelar", role: .cancel) { newPlaylistName = "" }
                Button("Crear") {
                    let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
                    newPlaylistName = ""
                    guard !name.isEmpty else { return }
                    _ = playlistsManager.create(name: name, tracks: tracks)
                    finish()
                }
            } message: {
                Text(tracks.count == 1 ? "Se añadirá «\(tracks[0].title)»."
                                       : "Se añadirán \(tracks.count) canciones.")
            }
        }
    }

    private func finish() {
        Haptics.success()
        tracks.forEach(recentlyPlayedManager.trackAdded)
        onDone()
    }
}

/// `AddToPlaylistSheet` for whatever is playing (the player's button).
private struct CurrentTrackAddToPlaylistSheet: View {
    @EnvironmentObject private var playerManager: PlayerManager
    @EnvironmentObject private var nav: NavigationCoordinator

    var body: some View {
        AddToPlaylistSheet(tracks: playerManager.currentTrack.map { [$0] } ?? []) {
            nav.presentedSheet = nil
        }
    }
}

/// Root-level sheet host for `nav.presentedSheet`, so the player sheets work
/// from any screen (full player, iPad side panel, rail).
struct PlayerSheetContent: View {
    let sheet: AppSheet

    var body: some View {
        switch sheet {
        case .equalizer: EqualizerView()
        case .speedAndPitch: SpeedPitchSheet()
        case .addToPlaylist: CurrentTrackAddToPlaylistSheet()
        case .queue: QueueView()
        case .missingTrackRepair: EmptyView()
        }
    }
}

#if os(iOS)
/// "Editar" / "Listo" for reordering the queue. The system `EditButton`
/// shows "Edit" because the app ships no Spanish localization bundle.
struct QueueEditButton: View {
    @Binding var editMode: EditMode

    var body: some View {
        Button(editMode.isEditing ? "Listo" : "Editar") {
            withAnimation { editMode = editMode.isEditing ? .inactive : .active }
        }
    }
}

#endif

/// Now Playing backdrop shared by the iPad panel and the full-screen player:
/// the current artwork, heavily blurred and darkened so text stays legible,
/// under Liquid Glass. Without artwork, a soft accent gradient. Fills the
/// screen edges; place it as a background.
struct ArtworkBlurBackground: View {
    let url: URL?
    var image: PlatformImage? = nil
    let tokens: DesignTokens

    var body: some View {
        ZStack {
            tokens.background
            if let image {
                Color.clear
                    .overlay {
                        Image(platformImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .blur(radius: 60)
                            .opacity(0.7)
                    }
                    .clipped()
            } else if let url {
                // Fill inside a clear box and clip it: an aspect-filled square
                // image is wider than a tall container and would spill out.
                Color.clear
                    .overlay {
                        AsyncCachedImage(url: url, targetSize: 120) { tokens.accentGradient.opacity(0.3) }
                            .aspectRatio(contentMode: .fill)
                            .blur(radius: 60)
                            .opacity(0.7)
                    }
                    .clipped()
            } else {
                tokens.accentGradient.opacity(0.3)
            }
            // Dark enough for secondary text over bright covers.
            Color.black.opacity(0.45)
            Color.clear.glassSurface(in: Rectangle())
        }
        .clipped()
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
