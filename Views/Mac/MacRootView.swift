#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Root of the native macOS window: the iPad landscape layout (icon rail ·
/// Now Playing panel · content), plus what only a Mac has — drag & drop,
/// the output-device follow-up — and the app-level duties `ContentView`
/// does on iOS (play history, flushing stores, error banner).
struct MacRootView: View {
    @EnvironmentObject private var appleMusic: AppleMusicService
    @EnvironmentObject private var settingsManager: SettingsManager
    @EnvironmentObject private var outputMonitor: AudioOutputMonitor
    @EnvironmentObject private var libraryManager: LocalLibraryManager
    @EnvironmentObject private var playerManager: PlayerManager
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var nav: NavigationCoordinator
    @EnvironmentObject private var favoritesManager: FavoritesManager
    @EnvironmentObject private var playlistsManager: PlaylistsManager
    @EnvironmentObject private var recentlyPlayedManager: RecentlyPlayedManager
    @EnvironmentObject private var videoLibraryManager: VideoLibraryManager
    @EnvironmentObject private var downloadManager: DownloadManager
    @EnvironmentObject private var eqController: EQController
    @EnvironmentObject private var smartPlaylistsManager: SmartPlaylistsManager
    @EnvironmentObject private var savedEQProfilesManager: SavedEQProfilesManager
    @EnvironmentObject private var librarySearchManager: LibrarySearchManager
    @Environment(\.scenePhase) private var scenePhase

    @State private var dropTargeted = false
    @State private var importProgress: FolderImporter.Progress?
    @State private var importSummary: String?
    @State private var errorBanner: String?
    @State private var showAddMusic = false
    @AppStorage(MacOutputSettings.deviceUIDKey) private var deviceUID = ""

    var body: some View {
        TabletRootView()
            .frame(minWidth: 1000, minHeight: 640)
            // Window toolbar on every section (not only where a screen adds
            // its own items): quick output switch and "Añadir música".
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    outputMenu
                    Button { showAddMusic = true } label: {
                        Label("Añadir música", systemImage: "folder.badge.plus")
                    }
                    .help("Añadir carpetas o archivos a la biblioteca (se quedan en su sitio)")
                }
            }
            .fileImporter(isPresented: $showAddMusic, allowedContentTypes: [.folder, .audio],
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { Task { await importDropped(urls) } }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard importProgress == nil else { return false }
                Task { await importDropped(urls) }
                return true
            } isTargeted: { dropTargeted = $0 }
            .overlay { if dropTargeted { dropHint } }
            .overlay(alignment: .top) { banners }
            .alert("Añadir a la biblioteca",
                   isPresented: Binding(get: { importSummary != nil }, set: { if !$0 { importSummary = nil } })) {
                Button("Aceptar", role: .cancel) {}
            } message: {
                Text(importSummary ?? "")
            }
            .sheet(item: $nav.presentedSheet) { sheet in
                PlayerSheetContent(sheet: sheet)
                    .frame(minWidth: 460, minHeight: 520)
            }
            .preferredColorScheme(themeManager.isDarkMode ? .dark : .light)
            .onAppear {
                MacSpaceBar.install(togglePlayPause: togglePlayPause)
                playerManager.configureFavorites(favoritesManager)
                appleMusic.configure(music: playerManager)
                playerManager.configureDownloads(downloadManager)
            }
            // Active device changed (picked in Ajustes, plugged/unplugged):
            // move playback there and ready it for the current file.
            .onChange(of: outputMonitor.snapshot.deviceUID) { _ in playerManager.applyOutputDevice() }
            // One source at a time: local music starting sends Apple Music away.
            .onChange(of: playerManager.isPlaying) { playing in
                if playing { appleMusic.resignActiveSource() }
            }
            .onChange(of: settingsManager.appleMusicEnabled) { enabled in
                if !enabled { appleMusic.shutDown() }
            }
            // Every track that becomes current counts as played (feeds Inicio).
            .onChange(of: playerManager.currentTrack?.id) { _ in
                if let track = playerManager.currentTrack { recentlyPlayedManager.trackPlayed(track) }
            }
            .onChange(of: playerManager.playerError) { error in
                switch error {
                case .streamFailed(let msg): showBanner(msg)
                case .trackMissing: showBanner("Falta el archivo. Vuelve a añadirlo desde Biblioteca.")
                case nil: break
                }
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active { libraryManager.auditMissingFlags() } else { flushAllStores() }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                flushAllStores()  // saves are debounced; ⌘Q must not lose the last change
            }
    }

    /// Output device at a glance (name · rate) and a one-click switch.
    private var outputMenu: some View {
        Menu {
            Picker("Salida", selection: $deviceUID) {
                Text("Predeterminado del sistema").tag("")
                ForEach(outputMonitor.devices) { device in
                    Text("\(device.name) · \(device.kind.label)").tag(device.uid)
                }
            }
            .pickerStyle(.inline)
            .onChange(of: deviceUID) { _ in outputMonitor.refresh() }
            Divider()
            SettingsLink { Text("Ajustes de salida…") }
        } label: {
            Label(outputSummary, systemImage: outputMonitor.snapshot.isUSBDAC ? "cable.connector" : "hifispeaker")
                .labelStyle(.titleAndIcon)
        }
        .help(outputMonitor.snapshot.displayText)
    }

    private var outputSummary: String {
        let s = outputMonitor.snapshot
        let rate = s.sampleRate.map { String(format: "%g kHz", $0 / 1_000) } ?? "—"
        return "\(s.deviceName ?? "Sin salida") · \(rate)"
    }

    /// Space bar / menu: whichever source Now Playing shows.
    private func togglePlayPause() {
        if appleMusic.isActiveSource { appleMusic.togglePlayPause() } else { playerManager.togglePlayPause() }
    }

    private func flushAllStores() {
        favoritesManager.flushPendingWrites()
        playlistsManager.flushPendingWrites()
        recentlyPlayedManager.flushPendingWrites()
        libraryManager.flushPendingWrites()
        videoLibraryManager.flushPendingWrites()
        downloadManager.flushPendingWrites()
        playerManager.flushPendingWrites()
        eqController.flushPendingWrites()
        smartPlaylistsManager.flushPendingWrites()
        savedEQProfilesManager.flushPendingWrites()
        librarySearchManager.flushPendingWrites()
    }

    private func showBanner(_ message: String) {
        withAnimation { errorBanner = message }
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            withAnimation { if errorBanner == message { errorBanner = nil } }
            playerManager.playerError = nil
        }
    }

    @ViewBuilder
    private var banners: some View {
        VStack(spacing: DS.Spacing.sm) {
            if let p = importProgress {
                HStack(spacing: DS.Spacing.sm) {
                    ProgressView().controlSize(.small)
                    Text("Añadiendo \(p.imported + p.skipped) de \(p.total)…").font(.callout)
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.sm)
                .background(Capsule().fill(.regularMaterial))
            }
            if let msg = errorBanner {
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(Capsule().fill(.regularMaterial))
            }
        }
        .padding(.top, DS.Spacing.sm)
    }

    private var dropHint: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(themeManager.theme.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
            .background(themeManager.theme.accentColor.opacity(0.08))
            .overlay {
                Label("Suelta para añadir a la biblioteca", systemImage: "square.and.arrow.down")
                    .font(.title3.weight(.semibold))
            }
            .padding(DS.Spacing.lg)
            .allowsHitTesting(false)
    }

    /// Dropped folders and files are added by reference (they stay where they
    /// are). Per-file failures (unsupported, empty) count as skipped.
    private func importDropped(_ urls: [URL]) async {
        var total = FolderImporter.Progress()
        importProgress = total
        for url in urls {
            let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            if isFolder {
                libraryManager.retainAccess(to: url)
                let base = total
                let result = await FolderImporter.importAll(
                    from: url,
                    importFile: { file, folder in _ = try await libraryManager.importFile(at: file, folderPath: folder) },
                    onProgress: { p in
                        importProgress = FolderImporter.Progress(imported: base.imported + p.imported,
                                                                 skipped: base.skipped + p.skipped,
                                                                 total: base.total + p.total)
                    })
                total.imported += result.imported
                total.skipped += result.skipped
                total.total += result.total
            } else if FolderImporter.audioExtensions.contains(url.pathExtension.lowercased()) {
                total.total += 1
                do {
                    _ = try await libraryManager.importFile(at: url)
                    total.imported += 1
                } catch {
                    total.skipped += 1
                }
                importProgress = total
            }
        }
        importProgress = nil
        UserDefaults.standard.set(TabletSection.library.rawValue, forKey: "tabletSection")
        importSummary = total.total == 0
            ? "No se encontraron archivos de audio."
            : "Se añadieron \(total.imported) de \(total.total) \(total.total == 1 ? "archivo" : "archivos")"
                + (total.skipped > 0 ? " · \(total.skipped) no compatibles u omitidos" : "")
                + ". Los archivos se quedan en su carpeta."
    }
}

/// Output device, rate matching and exclusive mode. Shown in Configuración
/// (rail) and in the Ajustes window (⌘,).
struct MacOutputControls: View {
    @EnvironmentObject private var outputMonitor: AudioOutputMonitor
    @AppStorage(OutputRateMatcher.defaultsKey) private var matchRate = true
    @AppStorage(MacOutputSettings.deviceUIDKey) private var deviceUID = ""
    @AppStorage(MacOutputSettings.exclusiveKey) private var exclusive = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Picker("Dispositivo", selection: $deviceUID) {
                Text("Predeterminado del sistema").tag("")
                ForEach(outputMonitor.devices) { device in
                    Text("\(device.name) · \(device.kind.label)").tag(device.uid)
                }
                if !deviceUID.isEmpty, !outputMonitor.devices.contains(where: { $0.uid == deviceUID }) {
                    Text("Elegido (desconectado)").tag(deviceUID)
                }
            }
            note("\(outputMonitor.snapshot.displayText). Ailen suena por este dispositivo sin cambiar la salida del resto del Mac; si se desconecta, vuelve al predeterminado hasta que lo conectes de nuevo.")
            Toggle("Igualar la frecuencia de salida a la del archivo", isOn: $matchRate)
            note("Antes de cada canción, el dispositivo pasa a la frecuencia del archivo (o a un múltiplo exacto si no la admite), para que macOS no la convierta. Sin modo exclusivo afecta también a otras apps que usen ese dispositivo. Al cerrar Ailen se restaura la frecuencia anterior.")
            Toggle("Modo exclusivo", isOn: $exclusive)
            note("Ailen toma el dispositivo para ella sola: ninguna otra app ni los sonidos del sistema suenan por él. Se libera al desactivarlo o al cerrar Ailen. Nada de esto garantiza salida bit-perfect: el volumen de Ailen por debajo del 100 % y el ecualizador modifican el audio.")
        }
        .onChange(of: deviceUID) { _ in outputMonitor.refresh() }  // monitor → player follow
        .onChange(of: exclusive) { _ in Task { await OutputRateMatcher.prepare(sourceRate: nil) } }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Ajustes window (⌘,).
struct MacSettingsView: View {
    var body: some View {
        Form { MacOutputControls() }
            .formStyle(.grouped)
            .frame(width: 500)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Menu-bar "Controles" with the usual Mac player shortcuts.
struct MacPlaybackCommands: Commands {
    let player: PlayerManager

    var body: some Commands {
        CommandMenu("Controles") {
            Button("Reproducir / Pausa") { player.togglePlayPause() }
            Button("Siguiente") { player.nextTrack() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button("Anterior") { player.previousTrack() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Divider()
            Button("Subir volumen") { player.setVolume(player.volume + 0.1) }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button("Bajar volumen") { player.setVolume(player.volume - 0.1) }
                .keyboardShortcut(.downArrow, modifiers: .command)
        }
    }
}

/// Space = play/pause, like Music.app — except while typing in a text field
/// (search), where the space must reach the field. A menu shortcut can't make
/// that distinction: key equivalents fire before the field sees the key.
@MainActor
enum MacSpaceBar {
    private static var monitor: Any?

    static func install(togglePlayPause: @escaping @MainActor () -> Void) {
        guard monitor == nil else { return }
        // Leave the output devices as we found them (rate, hog mode).
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: nil) { _ in
            CoreAudioHAL.queue.sync { CoreAudioHAL.restoreDevices() }
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard event.keyCode == 49, mods.isEmpty,
                  !(NSApp.keyWindow?.firstResponder is NSText) else { return event }
            togglePlayPause()
            return nil
        }
    }
}
#endif
