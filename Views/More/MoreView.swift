import SwiftUI

struct MoreView: View {
    @EnvironmentObject private var playerManager: PlayerManager
    @EnvironmentObject private var settingsManager: SettingsManager
    @EnvironmentObject private var favoritesManager: FavoritesManager
    @EnvironmentObject private var playlistsManager: PlaylistsManager
    @EnvironmentObject private var recentlyPlayedManager: RecentlyPlayedManager
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var localLibraryManager: LocalLibraryManager
    @EnvironmentObject private var videoLibraryManager: VideoLibraryManager
    #if os(iOS)
    @EnvironmentObject private var videoPlayback: VideoPlaybackController
    @EnvironmentObject private var spotify: SpotifyService
    #endif

    @State private var showClearLibraryAlert = false
    @State private var showClearVideosAlert = false
    @State private var showClearFavoritesAlert = false
    @State private var showDeletePlaylistsAlert = false
    @State private var showClearCacheAlert = false
    @State private var showClearHistoryAlert = false
    @State private var showClearListeningHistoryAlert = false
    @State private var connectionTest: Loadable<String> = .idle

    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private var tokens: DesignTokens { themeManager.tokens }

    var body: some View {
        NavigationStack {
            ZStack {
                tokens.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: DS.Spacing.xl) {
                        heroHeader
                        settingsSection
                        #if os(macOS)
                        MoreCard(title: "Salida de audio", tokens: tokens) {
                            MacOutputControls()
                                .padding(DS.Spacing.md)
                        }
                        #endif
                        advancedSection
                        extrasSection
                        versionFooter
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.lg)
                    .padding(.bottom, 120)
                }
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert("Borrar historial de búsqueda", isPresented: $showClearHistoryAlert) {
            Button("Cancelar", role: .cancel) {}
            Button("Borrar", role: .destructive) {
                Haptics.warning()
                settingsManager.clearSearchHistory()
            }
        } message: {
            Text("Se eliminarán todas tus búsquedas recientes.")
        }
        .alert("Borrar caché", isPresented: $showClearCacheAlert) {
            Button("Cancelar", role: .cancel) {}
            Button("Borrar", role: .destructive) {
                Haptics.warning()
                URLCache.shared.removeAllCachedResponses()
            }
        } message: {
            Text("Se borrarán todas las imágenes y datos en caché.")
        }
        .alert("Limpiar biblioteca", isPresented: $showClearLibraryAlert) {
            Button("Cancelar", role: .cancel) {}
            Button("Borrar todo", role: .destructive) {
                Haptics.warning()
                clearLibrary()
            }
        } message: {
            #if os(macOS)
            Text("Se quitarán de Ailen \(LibraryViewModel.songCount(localLibraryManager.tracks.count)), con sus portadas, y de Favoritos, listas, cola e historial. Las listas se conservan. Los archivos de música de tu Mac no se borran.")
            #else
            Text("Se borrarán de este dispositivo \(LibraryViewModel.songCount(localLibraryManager.tracks.count)) importadas, con sus portadas, y se quitarán de Favoritos, listas, cola e historial. Las listas se conservan. Tus archivos originales en la app Archivos no se tocan. Esta acción no se puede deshacer.")
            #endif
        }
        #if os(iOS)
        .alert("Quitar todos los videos", isPresented: $showClearVideosAlert) {
            Button("Cancelar", role: .cancel) {}
            Button("Quitar todo", role: .destructive) {
                Haptics.warning()
                videoPlayback.stop()
                videoLibraryManager.removeAll()
            }
        } message: {
            Text("Se quitarán de Ailen \(videoLibraryManager.videos.count) videos y las carpetas enlazadas. Los archivos originales no se borran; siguen en la app Archivos.")
        }
        #endif
        .alert("Borrar todos los favoritos", isPresented: $showClearFavoritesAlert) {
            Button("Cancelar", role: .cancel) {}
            Button("Borrar todo", role: .destructive) {
                Haptics.warning()
                favoritesManager.removeAll()
            }
        } message: {
            Text("Se eliminarán todos tus favoritos de forma permanente. Esta acción no se puede deshacer.")
        }
        .alert("Eliminar todas las listas", isPresented: $showDeletePlaylistsAlert) {
            Button("Cancelar", role: .cancel) {}
            Button("Eliminar todas", role: .destructive) {
                Haptics.warning()
                playlistsManager.deleteAll()
            }
        } message: {
            Text("Se eliminarán todas las listas de forma permanente. Esta acción no se puede deshacer.")
        }
        .alert("Borrar historial de escucha", isPresented: $showClearListeningHistoryAlert) {
            Button("Cancelar", role: .cancel) {}
            Button("Borrar", role: .destructive) {
                Haptics.warning()
                recentlyPlayedManager.clearAll()
            }
        } message: {
            Text("Se borrarán los registros de Reproducidas recientemente y Añadidas recientemente.")
        }
    }

    // MARK: - Hero

    private var heroHeader: some View {
        VStack(spacing: DS.Spacing.md) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [tokens.accent, tokens.accent.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)
                    .softShadow()
                Image(systemName: "music.note")
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(.white)
            }

            VStack(spacing: 4) {
                Text("Ailen")
                    .font(DS.Typography.display)
                    .foregroundColor(tokens.textPrimary)
                Text("Tu música, a tu manera")
                    .font(DS.Typography.caption)
                    .foregroundColor(tokens.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.lg)
    }

    // MARK: - Settings

    private var settingsSection: some View {
        MoreCard(title: "Ajustes", tokens: tokens) {
            VStack(spacing: 0) {
                HStack(spacing: DS.Spacing.md) {
                    iconBadge(systemName: "house", color: tokens.accent)
                    Text("Pantalla inicial")
                        .font(DS.Typography.body)
                        .foregroundColor(tokens.textPrimary)
                    Spacer()
                    Picker("", selection: $settingsManager.defaultStartTab) {
                        ForEach(DefaultStartTab.allCases.filter { $0 != .search }, id: \.self) { tab in
                            Text(tab.displayName).tag(tab)
                        }
                    }
                    .tint(tokens.highlightColor)
                    .onChange(of: settingsManager.defaultStartTab) { _ in
                        Haptics.selection()
                        settingsManager.save()
                    }
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.md)

                // Screen-awake, Apple Music and Spotify are iOS-only.
                #if os(iOS)
                Divider().background(tokens.hairline).padding(.leading, 56)

                HStack(spacing: DS.Spacing.md) {
                    iconBadge(systemName: "sun.max", color: tokens.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pantalla mientras suena")
                            .font(DS.Typography.body)
                            .foregroundColor(tokens.textPrimary)
                        Text(screenModeExplanation)
                            .font(DS.Typography.caption)
                            .foregroundColor(tokens.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Picker("", selection: $settingsManager.screenWhilePlaying) {
                        ForEach(ScreenWhilePlaying.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .tint(tokens.highlightColor)
                    .onChange(of: settingsManager.screenWhilePlaying) { _ in
                        Haptics.selection()
                        settingsManager.save()
                    }
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.md)

                #endif

                Divider().background(tokens.hairline).padding(.leading, 56)

                HStack(spacing: DS.Spacing.md) {
                    iconBadge(systemName: "music.note.house", color: tokens.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Music")
                            .font(DS.Typography.body)
                            .foregroundColor(tokens.textPrimary)
                        Text("Muestra tu biblioteca de Apple Music y la reproduce con el reproductor de Apple. Sin ecualizador ni datos de calidad. Desactivado, Ailen no accede a Apple Music.")
                            .font(DS.Typography.caption)
                            .foregroundColor(tokens.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("", isOn: $settingsManager.appleMusicEnabled)
                        .labelsHidden()
                        .tint(tokens.highlightColor)
                        .onChange(of: settingsManager.appleMusicEnabled) { _ in
                            Haptics.selection()
                            settingsManager.save()
                        }
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.md)

                #if os(iOS)
                Divider().background(tokens.hairline).padding(.leading, 56)

                spotifySettings
                #endif

            }
        }
    }

    #if os(iOS)  // server config (streaming backend) is hidden; iOS only
    // MARK: - Backend

    /// Server URL + API key overrides. The app is a client for a self-hosted
    /// backend; with no server configured it runs as a local-files-only
    /// player (the Search tab hides — see ContentView).
    private var backendSection: some View {
        MoreCard(title: "Servidor", tokens: tokens) {
            VStack(spacing: 0) {
                // Type comes first: it decides what the fields below even mean
                // (API key for Aria's backend, username/password for Subsonic).
                HStack(spacing: DS.Spacing.md) {
                    iconBadge(systemName: "point.3.connected.trianglepath.dotted", color: tokens.accent)
                    Text("Tipo de servidor")
                        .font(DS.Typography.body)
                        .foregroundColor(tokens.textPrimary)
                    Spacer()
                    Picker("", selection: $settingsManager.serverKind) {
                        ForEach(BackendConfig.ServerKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .tint(tokens.highlightColor)
                    // Without this the menu label wraps to two lines in the row.
                    .fixedSize()
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.md)

                Divider().background(tokens.hairline).padding(.leading, 56)

                HStack(spacing: DS.Spacing.md) {
                    iconBadge(systemName: "server.rack", color: tokens.accent)
                    TextField(settingsManager.serverKind.urlPlaceholder,
                              text: $settingsManager.backendURLOverride)
                        .font(DS.Typography.body)
                        .foregroundColor(tokens.textPrimary)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.md)

                Divider().background(tokens.hairline).padding(.leading, 56)

                if settingsManager.serverKind == .subsonic {
                    HStack(spacing: DS.Spacing.md) {
                        iconBadge(systemName: "person", color: tokens.accent)
                        TextField("Usuario", text: $settingsManager.subsonicUsername)
                            .font(DS.Typography.body)
                            .foregroundColor(tokens.textPrimary)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.md)

                    Divider().background(tokens.hairline).padding(.leading, 56)

                    HStack(spacing: DS.Spacing.md) {
                        iconBadge(systemName: "lock", color: tokens.accent)
                        SecureField("Contraseña", text: $settingsManager.subsonicPassword)
                            .font(DS.Typography.body)
                            .foregroundColor(tokens.textPrimary)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.md)

                    Text(settingsManager.credentialStorageFailed
                         ? "No se pudo guardar la contraseña en el llavero; se olvidará cuando cierres Ailen."
                         : "Guardada en el llavero de iOS. Ailen envía un token con sal, nunca tu contraseña.")
                        .font(DS.Typography.micro)
                        .foregroundColor(settingsManager.credentialStorageFailed ? .orange : tokens.textSecondary)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.bottom, DS.Spacing.sm)

                    Divider().background(tokens.hairline).padding(.leading, 56)
                } else {
                    HStack(spacing: DS.Spacing.md) {
                        iconBadge(systemName: "key", color: tokens.accent)
                        SecureField("Clave de API (opcional)", text: $settingsManager.backendAPIKeyOverride)
                            .font(DS.Typography.body)
                            .foregroundColor(tokens.textPrimary)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.md)

                    Divider().background(tokens.hairline).padding(.leading, 56)
                }

                Button {
                    Haptics.light()
                    testConnection()
                } label: {
                    row(icon: "antenna.radiowaves.left.and.right", iconColor: tokens.accent,
                        title: "Probar conexión", isButton: true)
                }
                .buttonStyle(.plain)
                .disabled(connectionTest.isLoading)

                connectionStatusRow
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.bottom, DS.Spacing.md)
            }
        }
        .onChange(of: settingsManager.backendURLOverride) { _ in
            settingsManager.save()
            playerManager.reconfigureBackend(settingsManager.backendSnapshot)
            connectionTest = .idle
        }
        .onChange(of: settingsManager.backendAPIKeyOverride) { _ in
            settingsManager.save()
            playerManager.reconfigureBackend(settingsManager.backendSnapshot)
            connectionTest = .idle
        }
        .onChange(of: settingsManager.serverKind) { _ in
            settingsManager.save()
            playerManager.reconfigureBackend(settingsManager.backendSnapshot)
            connectionTest = .idle
        }
        .onChange(of: settingsManager.subsonicUsername) { _ in
            settingsManager.save()
            playerManager.reconfigureBackend(settingsManager.backendSnapshot)
            connectionTest = .idle
        }
        .onChange(of: settingsManager.subsonicPassword) { _ in
            settingsManager.save()
            playerManager.reconfigureBackend(settingsManager.backendSnapshot)
            connectionTest = .idle
        }
    }

    @ViewBuilder
    private var connectionStatusRow: some View {
        switch connectionTest {
        case .idle:
            Text(settingsManager.isServerConfigured
                 ? "Servidor: \(settingsManager.resolvedBaseURL)"
                 : "Sin servidor configurado: solo biblioteca local")
                .font(DS.Typography.caption)
                .foregroundColor(tokens.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Comprobando \(BackendConfig.baseURL)…")
                    .font(DS.Typography.caption)
                    .foregroundColor(tokens.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .loaded(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .font(DS.Typography.caption)
                .foregroundColor(.green)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .failed(let error):
            Label(error.localizedDescription, systemImage: "xmark.octagon.fill")
                .font(DS.Typography.caption)
                .foregroundColor(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Probes the currently resolved backend and reports the outcome inline —
    /// `/api/health` for Aria's backend, `ping.view` for Subsonic.
    private func testConnection() {
        connectionTest = .loading

        // Subsonic verifies credentials too, via ping.view — a URL that loads
        // is not enough when a username/password is involved.
        if settingsManager.serverKind == .subsonic {
            let base = settingsManager.resolvedBaseURL
            let user = settingsManager.subsonicUsername
            let password = settingsManager.subsonicPassword
            Task {
                guard !user.isEmpty, !password.isEmpty else {
                    connectionTest = .failed(SubsonicClient.ClientError.notConfigured)
                    return
                }
                let client = SubsonicClient(baseURL: base, username: user,
                                            password: password,
                                            session: PlayerManager.sharedURLSession)
                do {
                    connectionTest = .loaded("Conectado · \(try await client.ping())")
                } catch {
                    connectionTest = .failed(error)
                }
            }
            return
        }

        let base = BackendConfig.baseURL
        let apiKey = BackendConfig.apiKey
        Task {
            do {
                guard let url = URL(string: "\(base)/api/health") else {
                    throw URLError(.badURL)
                }
                var request = URLRequest(url: url, timeoutInterval: 5)
                if let apiKey {
                    request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
                }
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                var message = "Conectado"
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let version = json["yt_dlp_version"] as? String {
                    message = "Conectado · yt-dlp \(version)"
                }
                connectionTest = .loaded(message)
            } catch {
                connectionTest = .failed(error)
            }
        }
    }

    #endif

    // MARK: - Advanced

    private var advancedSection: some View {
        MoreCard(title: "Avanzado", tokens: tokens) {
            VStack(spacing: 0) {
                Button {
                    Haptics.warning()
                    showClearCacheAlert = true
                } label: {
                    row(icon: "trash.slash", iconColor: .orange, title: "Borrar caché de imágenes y datos", isButton: true)
                }
                .buttonStyle(.plain)

                Divider().background(tokens.hairline).padding(.leading, 56)

                Button {
                    Haptics.warning()
                    showClearLibraryAlert = true
                } label: {
                    row(icon: "trash", iconColor: .red, title: "Limpiar biblioteca", isButton: true)
                }
                .buttonStyle(.plain)
                .disabled(localLibraryManager.tracks.isEmpty)

                Divider().background(tokens.hairline).padding(.leading, 56)

                #if os(iOS)
                Button {
                    Haptics.warning()
                    showClearVideosAlert = true
                } label: {
                    row(icon: "film", iconColor: .red, title: "Quitar todos los videos", isButton: true)
                }
                .buttonStyle(.plain)
                .disabled(videoLibraryManager.videos.isEmpty)

                Divider().background(tokens.hairline).padding(.leading, 56)
                #endif

                Button {
                    Haptics.warning()
                    showClearFavoritesAlert = true
                } label: {
                    row(icon: "heart.slash", iconColor: .red, title: "Borrar todos los favoritos", isButton: true)
                }
                .buttonStyle(.plain)

                Divider().background(tokens.hairline).padding(.leading, 56)

                Button {
                    Haptics.warning()
                    showDeletePlaylistsAlert = true
                } label: {
                    row(icon: "trash", iconColor: .red, title: "Eliminar todas las listas", isButton: true)
                }
                .buttonStyle(.plain)

                Divider().background(tokens.hairline).padding(.leading, 56)

                Button {
                    Haptics.warning()
                    showClearListeningHistoryAlert = true
                } label: {
                    row(icon: "clock.arrow.circlepath", iconColor: .orange, title: "Borrar historial de escucha", isButton: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Extras

    private var extrasSection: some View {
        MoreCard(title: "Extras", tokens: tokens) {
            VStack(spacing: 0) {
                HStack(spacing: DS.Spacing.md) {
                    iconBadge(systemName: "moon.zzz", color: tokens.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Temporizador de apagado")
                            .font(DS.Typography.body)
                            .foregroundColor(tokens.textPrimary)
                        if let end = playerManager.sleepTimerEndDate {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Text("Pausa en \(countdownString(until: end, now: context.date))")
                                    .font(DS.Typography.caption)
                                    .foregroundColor(tokens.accent)
                            }
                        }
                    }
                    Spacer()
                    Picker("", selection: $settingsManager.sleepTimer) {
                        ForEach(SleepTimerDuration.allCases, id: \.self) { duration in
                            Text(duration.displayName).tag(duration)
                        }
                    }
                    .tint(tokens.highlightColor)
                    .onChange(of: settingsManager.sleepTimer) { newValue in
                        Haptics.selection()
                        settingsManager.save()
                        playerManager.startSleepTimer(newValue)
                    }
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.md)

                Divider().background(tokens.hairline).padding(.leading, 56)

                HStack(spacing: DS.Spacing.md) {
                    iconBadge(systemName: "moon.circle", color: tokens.accent)
                    Text("Modo oscuro")
                        .font(DS.Typography.body)
                        .foregroundColor(tokens.textPrimary)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { themeManager.isDarkMode },
                        set: { _ in
                            Haptics.light()
                            themeManager.toggleDarkMode()
                        }
                    ))
                    .tint(tokens.highlightColor)
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.md)

                Divider().background(tokens.hairline).padding(.leading, 56)

                NavigationLink {
                    themePicker
                } label: {
                    HStack(spacing: DS.Spacing.md) {
                        iconBadge(systemName: "paintpalette", color: tokens.accent)
                        Text("Elegir tema")
                            .font(DS.Typography.body)
                            .foregroundColor(tokens.textPrimary)
                        Spacer()
                        Circle()
                            .fill(tokens.accent)
                            .frame(width: 18, height: 18)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(tokens.textSecondary)
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.md)
                }
            }
        }
    }

    #if os(iOS)
    /// Spotify: on/off, the user's Client ID and how to get one.
    private var spotifySettings: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.md) {
                iconBadge(systemName: "dot.radiowaves.left.and.right", color: tokens.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spotify")
                        .font(DS.Typography.body)
                        .foregroundColor(tokens.textPrimary)
                    Text("Controla la app de Spotify de este dispositivo desde Ailen. Necesita Spotify Premium y la app de Spotify. Sin ecualizador ni datos de calidad.")
                        .font(DS.Typography.caption)
                        .foregroundColor(tokens.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: $settingsManager.spotifyEnabled)
                    .labelsHidden()
                    .tint(tokens.highlightColor)
                    .onChange(of: settingsManager.spotifyEnabled) { _ in
                        Haptics.selection()
                        settingsManager.save()
                    }
            }
            if settingsManager.spotifyEnabled {
                TextField("Client ID de tu app de Spotify", text: $settingsManager.spotifyClientID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.footnote, design: .monospaced))
                    .padding(DS.Spacing.sm)
                    .background(RoundedRectangle(cornerRadius: 8).fill(tokens.surface))
                    .onSubmit { settingsManager.save() }
                    .onChange(of: settingsManager.spotifyClientID) { _ in settingsManager.save() }
                    .padding(.leading, 40)
                DisclosureGroup("Cómo obtener el Client ID") {
                    Text("""
                    1. Entra en developer.spotify.com/dashboard con tu cuenta Premium y crea una app.
                    2. Marca las APIs "Web API" e "iOS".
                    3. Redirect URI: ailen-spotify://callback
                    4. Bundle ID de iOS: \(Bundle.main.bundleIdentifier ?? "el de esta app")
                    5. En "User Management" añade el correo de tu cuenta de Spotify.
                    6. Copia el Client ID y pégalo arriba.
                    """)
                    .font(DS.Typography.caption)
                    .foregroundColor(tokens.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .font(DS.Typography.caption)
                .tint(tokens.highlightColor)
                .padding(.leading, 40)
                if spotify.state != .signedOut && spotify.state != .notConfigured && spotify.state != .notInstalled {
                    Button("Cerrar sesión de Spotify", role: .destructive) { spotify.signOut() }
                        .font(DS.Typography.caption)
                        .padding(.leading, 40)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.md)
    }
    #endif

    private var screenModeExplanation: String {
        switch settingsManager.screenWhilePlaying {
        case .normal: return "Se apaga como siempre."
        case .keepOn: return "Mientras suena con la app abierta, no se bloquea. Con la app minimizada se apaga como siempre."
        case .keepOnDim: return "Mientras suena con la app abierta, no se bloquea y baja el brillo tras 30 s sin tocar. Minimizada, se apaga como siempre."
        }
    }

    /// Drops every reference to imported tracks, then deletes the files.
    /// The player lets go first so AVPlayer is no longer reading a file.
    private func clearLibrary() {
        let isLocal: (Track) -> Bool = { $0.localFileURL != nil || $0.id.hasPrefix("local:") }
        playerManager.forget(where: isLocal)
        favoritesManager.removeAll(where: isLocal)
        playlistsManager.removeTracks(where: isLocal)
        recentlyPlayedManager.removeAll(where: isLocal)
        localLibraryManager.removeAll()
    }

    // MARK: - Theme Picker

    private var themePicker: some View {
        ZStack {
            tokens.background.ignoresSafeArea()

            ScrollView {
                customThemeSection
                    .padding([.horizontal, .top], DS.Spacing.lg)
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.md), count: 2),
                    spacing: DS.Spacing.md
                ) {
                    ForEach(AppTheme.allThemes) { theme in
                        themeCard(theme)
                    }
                }
                .padding(DS.Spacing.lg)
            }
        }
        .navigationTitle("Temas")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Editable theme: accent, gradient end and dark background colours.
    private var customThemeSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Personalizar")
                .font(DS.Typography.titleMedium)
                .foregroundColor(tokens.highlightColor)
            ColorPicker("Color de acento", selection: Binding(
                get: { themeManager.theme.accentColor },
                set: { themeManager.setCustomAccent($0) }
            ), supportsOpacity: false)
            ColorPicker("Final del degradado", selection: Binding(
                get: { themeManager.theme.gradientEnd },
                set: { themeManager.setCustomAccent($0, end: true) }
            ), supportsOpacity: false)
            ColorPicker("Fondo (modo oscuro)", selection: Binding(
                get: { themeManager.darkBackground.color },
                set: { themeManager.setDarkBackground($0) }
            ), supportsOpacity: false)
            Capsule()
                .fill(tokens.accentGradient)
                .frame(height: 8)
                .accessibilityHidden(true)
            Text("El fondo se oscurece si hace falta para que el texto se lea bien. En modo claro se usa el fondo claro.")
                .font(DS.Typography.caption)
                .foregroundColor(tokens.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Restablecer Sound Wave") {
                Haptics.light()
                themeManager.resetCustomTheme()
            }
            .font(DS.Typography.bodyEm)
            .foregroundColor(tokens.highlightColor)
        }
        .font(DS.Typography.body)
        .foregroundColor(tokens.textPrimary)
        .padding(DS.Spacing.lg)
        .background(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous).fill(tokens.cardSurface))
    }

    private func themeCard(_ theme: AppTheme) -> some View {
        let isActive = themeManager.theme.id == theme.id
        return Button {
            Haptics.medium()
            themeManager.selectTheme(theme)
        } label: {
            VStack(spacing: DS.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [theme.accentColor, theme.gradientEnd == theme.accentColor
                                         ? theme.accentColor.opacity(0.5) : theme.gradientEnd],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .aspectRatio(1, contentMode: .fit)
                    if isActive {
                        Image(systemName: "checkmark")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .softShadow()
                Text(theme.name)
                    .font(DS.Typography.bodyEm)
                    .foregroundColor(tokens.textPrimary)
            }
            .padding(DS.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .fill(tokens.cardSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                            .stroke(isActive ? theme.accentColor : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Version

    private var versionFooter: some View {
        VStack(spacing: 4) {
            Text("Ailen v\(appVersion)")
                .font(DS.Typography.caption)
                .foregroundColor(tokens.textSecondary)
            Text("Hecho con ♥")
                .font(DS.Typography.micro)
                .foregroundColor(tokens.textSecondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.lg)
    }

    // MARK: - Row helpers

    @ViewBuilder
    private func row(icon: String, iconColor: Color, title: String, isButton: Bool = false, trailing: () -> some View = { EmptyView() }) -> some View {
        HStack(spacing: DS.Spacing.md) {
            iconBadge(systemName: icon, color: iconColor)
            Text(title)
                .font(DS.Typography.body)
                .foregroundColor(tokens.textPrimary)
            Spacer()
            trailing()
            if isButton {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(tokens.textSecondary)
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.md)
        .contentShape(Rectangle())
    }

    /// Formats the remaining time until `end` as `M:SS` (or `H:MM:SS`).
    private func countdownString(until end: Date, now: Date) -> String {
        let remaining = Int(max(0, end.timeIntervalSince(now)))
        let h = remaining / 3600
        let m = (remaining % 3600) / 60
        let s = remaining % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    private func iconBadge(systemName: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(color.opacity(0.18))
                .frame(width: 28, height: 28)
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
        }
    }
}

/// Card wrapper used to group More-view sections with a consistent surface.
private struct MoreCard<Content: View>: View {
    let title: String
    let tokens: DesignTokens
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            SectionLabel(title: title, tokens: tokens)
                .padding(.horizontal, DS.Spacing.sm)
            content()
                .glassSurface(in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        }
    }
}
