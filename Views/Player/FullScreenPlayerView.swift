import SwiftUI

struct FullScreenPlayerView: View {
    @EnvironmentObject private var playerManager: PlayerManager
    @EnvironmentObject private var clock: PlaybackClock
    @EnvironmentObject private var favoritesManager: FavoritesManager
    @EnvironmentObject private var playlistsManager: PlaylistsManager
    @EnvironmentObject private var recentlyPlayedManager: RecentlyPlayedManager
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var nav: NavigationCoordinator
    @EnvironmentObject private var outputMonitor: AudioOutputMonitor
    @EnvironmentObject private var eqController: EQController
    @EnvironmentObject private var localLibraryManager: LocalLibraryManager

    var onDismiss: () -> Void

    @State private var dragOffset: CGFloat = 0
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var sourceInfo: SourceAudioInfo?
    @State private var trackPendingDeletion: Track?

    private let dragThreshold: CGFloat = 120

    var body: some View {
        ZStack {
            themeManager.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.headline)
                            .foregroundColor(themeManager.textPrimary)
                            .frame(width: 44, height: 44)
                            .glassSurface(in: Circle(), interactive: true)
                            .contentShape(Circle())
                    }
                    .accessibilityLabel("Cerrar reproductor")

                    Spacer()

                    Text("Ahora suena")
                        .font(.headline)
                        .foregroundColor(themeManager.textPrimary)
                        .accessibilityAddTraits(.isHeader)

                    Spacer()

                    Button {
                        nav.presentedSheet = .queue
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.headline)
                            .foregroundColor(playerManager.queue.isEmpty
                                             ? themeManager.textSecondary
                                             : themeManager.textPrimary)
                            .frame(width: 44, height: 44)
                            .glassSurface(in: Circle(), interactive: true)
                            // A real count badge: anchored to the frame's top-
                            // trailing corner and inset, so multi-digit counts
                            // grow leftward and stay inside the 44pt tap target
                            // instead of spilling into the neighbouring control.
                            .overlay(alignment: .topTrailing) {
                                if !playerManager.queue.isEmpty {
                                    Text(playerManager.queue.count > 99 ? "99+" : "\(playerManager.queue.count)")
                                        .scaledFont(size: 9, weight: .bold, relativeTo: .caption2)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 4)
                                        .frame(minWidth: 16, minHeight: 16)
                                        .background(Capsule().fill(themeManager.theme.accentColor))
                                        .padding([.top, .trailing], 2)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(playerManager.queue.isEmpty ? "Mostrar cola" : "Mostrar cola, \(playerManager.queue.count) a continuación")
                }
                .padding(.top, DS.Spacing.sm)
                .padding(.bottom, 20)

                if let track = playerManager.currentTrack {
                    artworkSection(track: track)
                    trackInfoSection(track: track)
                    seekBarSection
                    transportControls
                    secondaryControls(track: track)
                    queueHint
                    if playerManager.playbackState == .loading {
                        ProgressView()
                            .scaleEffect(1.2)
                            .tint(themeManager.theme.accentColor)
                            .padding(.top, 8)
                    }
                } else {
                    Spacer()
                    Text("Nada en reproducción")
                        .foregroundColor(themeManager.textSecondary)
                }

                Spacer()
            }
            // iPad: keep controls at a readable width instead of edge to edge.
            .frame(maxWidth: 560)
            .padding(.horizontal, DS.Spacing.xl)
        }
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height > dragThreshold {
                        onDismiss()
                    } else if value.translation.height < -dragThreshold * 0.6 {
                        nav.presentedSheet = .queue  // Sound Wave: swipe up for the queue
                    }
                    withAnimation(.spring(response: 0.3)) {
                        dragOffset = 0
                    }
                }
        )
        .sheet(item: $nav.presentedSheet) { sheet in
            switch sheet {
            case .equalizer:
                EqualizerView()
            case .speedAndPitch:
                SpeedPitchSheet()
            case .addToPlaylist:
                addToPlaylistSheet
            case .queue:
                QueueView()
            case .missingTrackRepair:
                EmptyView()
            }
        }
        .task(id: playerManager.currentTrack?.id) {
            sourceInfo = nil
            guard let url = playerManager.currentTrack?.localFileURL else { return }
            sourceInfo = await SourceAudioInfo.inspect(url)
        }
    }

    // MARK: - Artwork

    private func artworkSection(track: Track) -> some View {
        // Larger on iPad; smaller with accessibility text sizes so the
        // controls still fit on an iPhone screen.
        // On iPhone also capped to ~1/3 of the screen height, so the whole
        // player fits on small phones (SE: 227 pt) without scrolling.
        let side: CGFloat = horizontalSizeClass == .regular ? 420
            : dynamicTypeSize.isAccessibilitySize ? 160
            : min(290, UIScreen.main.bounds.height * 0.34)

        return Group {
            if let url = playerManager.currentArtworkURL {
                AsyncCachedImage(url: url, targetSize: side) {
                    ArtworkPlaceholder(tokens: themeManager.tokens, cornerRadius: DS.Radius.md)
                }
                .aspectRatio(contentMode: .fill)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: themeManager.theme.accentColor.opacity(0.25), radius: 24, y: 10)
            } else {
                ArtworkPlaceholder(tokens: themeManager.tokens, cornerRadius: 20)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .padding(.bottom, DS.Spacing.lg)
        .accessibilityHidden(true)  // decorative; title and artist follow
    }

    // MARK: - Track Info

    private func trackInfoSection(track: Track) -> some View {
        VStack(spacing: 4) {
            // Sound Wave order: artist above, large title below.
            Text(track.artist)
                .font(.title3)
                .foregroundColor(themeManager.textSecondary)
                .lineLimit(1)

            Text(track.title)
                .font(.title.weight(.bold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundColor(themeManager.textPrimary)

            if let album = track.album, !album.isEmpty {
                Text(album)
                    .font(.subheadline)
                    .foregroundColor(themeManager.textSecondary)
                    .lineLimit(1)
            }

            qualityCard(track: track)
                .padding(.top, DS.Spacing.sm)
        }
        .padding(.bottom, DS.Spacing.lg)
    }

    /// File, output route and audio mode, on one glass card. Source and
    /// output stay on separate lines: they are different measurements.
    private func qualityCard(track: Track) -> some View {
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

    /// Sound Wave's "swipe up for playlist", here opening the queue. Also a
    /// button, so it works without the gesture (VoiceOver, Switch Control).
    private var queueHint: some View {
        Button { nav.presentedSheet = .queue } label: {
            VStack(spacing: 2) {
                Image(systemName: "chevron.up")
                    .font(.caption.weight(.semibold))
                Text("Desliza hacia arriba para ver la cola")
                    .font(.caption2)
            }
            .foregroundColor(themeManager.textSecondary)
            .padding(.top, DS.Spacing.sm)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mostrar cola")
    }

    // MARK: - Seek Bar

    private var seekBarSection: some View {
        VStack(spacing: 4) {
            // Sound Wave: elapsed · bar · total on one line.
            HStack(spacing: DS.Spacing.md) {
                Text(formatTime(clock.currentTime))
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
                .accessibilityValue("\(formatTime(clock.currentTime)) de \(formatTime(clock.duration))")
                Text(formatTime(clock.duration))
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
        .padding(.bottom, DS.Spacing.sm)
    }

    // MARK: - Transport Controls

    private var transportControls: some View {
        // Sound Wave order: repeat · previous · play · next · shuffle.
        HStack(spacing: DS.Spacing.lg) {
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
                    .font(.title2)
                    .foregroundColor(themeManager.textPrimary)
                    .frame(width: 52, height: 52)
                    .glassSurface(in: Circle(), interactive: true)
                    .contentShape(Circle())
            }
            .accessibilityLabel("Canción anterior")

            // Glass button with a gradient ring and gradient icon.
            Button { playerManager.togglePlayPause() } label: {
                Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(themeManager.tokens.accentGradient)
                    .frame(width: 76, height: 76)
                    .glassSurface(in: Circle(), interactive: true)
                    .overlay(Circle().strokeBorder(themeManager.tokens.accentGradient, lineWidth: 3))
                    .contentShape(Circle())
            }
            .accessibilityLabel(playerManager.isPlaying ? "Pausar" : "Reproducir")

            Button { playerManager.nextTrack() } label: {
                Image(systemName: "forward.end.fill")
                    .font(.title2)
                    .foregroundColor(themeManager.textPrimary)
                    .frame(width: 52, height: 52)
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
        .padding(.bottom, DS.Spacing.lg)
    }

    private var repeatIcon: String {
        switch playerManager.repeatMode {
        case .off: return "repeat"
        case .one: return "repeat.1"
        case .all: return "repeat"
        }
    }

    // MARK: - Secondary Controls

    private func secondaryControls(track: Track) -> some View {
        HStack(spacing: 20) {
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

            deleteMenu(track: track)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        .glassSurface(in: Capsule())
        .confirmationDialog(
            "¿Eliminar el archivo?",
            isPresented: Binding(get: { trackPendingDeletion != nil },
                                 set: { if !$0 { trackPendingDeletion = nil } }),
            titleVisibility: .visible,
            presenting: trackPendingDeletion
        ) { pending in
            Button("Eliminar archivo", role: .destructive) { deleteFile(pending) }
            Button("Cancelar", role: .cancel) {}
        } message: { pending in
            Text("Se borrará «\(pending.title)» del dispositivo, de Favoritos y de todas las listas. No se puede deshacer.")
        }
    }

    // MARK: - Delete

    private func playlistsContaining(_ track: Track) -> [Playlist] {
        playlistsManager.playlists.filter { $0.tracks.contains { $0.id == track.id } }
    }

    private func deleteMenu(track: Track) -> some View {
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
                    trackPendingDeletion = track
                } label: {
                    Label("Eliminar archivo…", systemImage: "trash")
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
        playerManager.forget(track)
        for list in playlistsContaining(track) {
            playlistsManager.removeTrack(track, from: list)
        }
        if favoritesManager.isFavorite(track) {
            favoritesManager.remove(track)
        }
        localLibraryManager.remove(local)
        if playerManager.currentTrack == nil {
            onDismiss()
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

    // MARK: - Add to Playlist Sheet

    private var addToPlaylistSheet: some View {
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
                        Text("Primero crea una lista")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    List(playlistsManager.playlists) { playlist in
                        Button {
                            if let track = playerManager.currentTrack {
                                playlistsManager.addTrack(track, to: playlist)
                                recentlyPlayedManager.trackAdded(track)
                                nav.presentedSheet = nil
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(playlist.name)
                                        .font(.body)
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
            }
            .navigationTitle("Añadir a una lista")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Listo") { nav.presentedSheet = nil }
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatTime(_ time: TimeInterval) -> String {
        let t = Int(max(0, time))
        let m = t / 60
        let s = t % 60
        return String(format: "%d:%02d", m, s)
    }
}
