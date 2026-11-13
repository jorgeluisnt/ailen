import Foundation
import Combine

enum DefaultStartTab: String, CaseIterable {
    case library = "Library"
    case favorites = "Favorites"
    case playlists = "Playlists"
    case search = "Search"
    case more = "More"

    /// Presentation text is separate from the raw value stored by older builds.
    var displayName: String {
        switch self {
        case .library: return "Biblioteca"
        case .favorites: return "Favoritos"
        case .playlists: return "Listas"
        case .search: return "Buscar"
        case .more: return "Ajustes"
        }
    }
}

enum SleepTimerDuration: String, CaseIterable {
    case off = "Off"
    case min15 = "15 min"
    case min30 = "30 min"
    case min45 = "45 min"
    case hour1 = "1 hour"
    case hour2 = "2 hours"

    /// Presentation text; the raw value is persisted and must not change.
    var displayName: String {
        switch self {
        case .off:   return "Desactivado"
        case .min15: return "15 min"
        case .min30: return "30 min"
        case .min45: return "45 min"
        case .hour1: return "1 hora"
        case .hour2: return "2 horas"
        }
    }

    /// The duration in seconds, or `nil` for `.off` (no timer).
    var timeInterval: TimeInterval? {
        switch self {
        case .off:   return nil
        case .min15: return 15 * 60
        case .min30: return 30 * 60
        case .min45: return 45 * 60
        case .hour1: return 60 * 60
        case .hour2: return 2 * 60 * 60
        }
    }
}

final class SettingsManager: ObservableObject {
    /// Library, not Favorites: a first-run user has no favorites and needs
    /// the Import button in front of them. A saved choice still wins (`load()`).
    @Published var defaultStartTab: DefaultStartTab = .library
    /// Screen behaviour while the player is open and playing.
    @Published var screenWhilePlaying: ScreenWhilePlaying = .normal
    /// Optional Apple Music section; off = Ailen never touches Apple Music.
    @Published var appleMusicEnabled = false
    /// Optional Spotify section (controls the Spotify app on this device).
    @Published var spotifyEnabled = false
    /// Client ID from the user's own app in the Spotify developer dashboard
    /// (not a secret: the login uses PKCE).
    @Published var spotifyClientID = ""
    @Published var isDarkMode: Bool = true
    @Published var selectedThemeID: String = "soundwave"
    /// Editable theme, as hex. Empty = Sound Wave default.
    @Published var customAccentHex: String = ""
    @Published var customAccentEndHex: String = ""
    @Published var customBackgroundHex: String = ""
    @Published var sleepTimer: SleepTimerDuration = .off
    @Published private(set) var searchHistory: [String] = []
    /// Backend server URL / API key overrides (More → Backend). Persisted
    /// under the `BackendConfig` keys so URL resolution sees them; empty
    /// string = no override.
    @Published var backendURLOverride: String = ""
    @Published var backendAPIKeyOverride: String = ""
    /// Which protocol the configured server speaks (Aria backend vs Subsonic).
    @Published var serverKind: BackendConfig.ServerKind = .aria
    @Published var subsonicUsername: String = ""
    /// Mirrored into the Keychain on save — never persisted to UserDefaults.
    @Published var subsonicPassword: String = ""
    /// Set when a Keychain write fails, so Settings can say so rather than let
    /// the password silently vanish on the next launch. See `KeychainStore`.
    @Published private(set) var credentialStorageFailed = false

    /// The backend URL as currently *typed*, not as last saved.
    var resolvedBaseURL: String {
        BackendConfig.baseURL(override: backendURLOverride)
    }

    /// The live server configuration, for building backend clients. Reading
    /// this instead of `BackendConfig.current` keeps the Keychain out of the
    /// per-search path and reflects credentials the moment they're typed.
    var backendSnapshot: BackendConfig.Snapshot {
        BackendConfig.Snapshot(kind: serverKind, baseURL: resolvedBaseURL,
                               subsonicUsername: subsonicUsername,
                               subsonicPassword: subsonicPassword)
    }

    /// Live equivalent of `BackendConfig.isConfigured`, computed from the
    /// published fields.
    ///
    /// Views must use this one. `BackendConfig` reads `UserDefaults`, which
    /// `save()` only writes from an `onChange` — i.e. *after* SwiftUI has
    /// already recomputed the body. A view reading `BackendConfig` directly
    /// therefore renders one edit behind, which is invisible while typing a
    /// URL (the next keystroke catches it up) but sticks on a one-shot change
    /// like the Server Type picker.
    var isServerConfigured: Bool {
        BackendConfig.isConfigured(kind: serverKind, baseURL: resolvedBaseURL,
                                   subsonicUsername: subsonicUsername,
                                   subsonicPassword: subsonicPassword)
    }

    private let maxHistoryItems = 20
    private let defaults = UserDefaults.standard
    /// What the Keychain currently holds, so `save()` only writes on a change.
    private var lastStoredPassword: String?

    init() { load() }

    func addSearchToHistory(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        searchHistory.removeAll { $0 == trimmed }
        searchHistory.insert(trimmed, at: 0)
        if searchHistory.count > maxHistoryItems {
            searchHistory = Array(searchHistory.prefix(maxHistoryItems))
        }
        save()
    }

    func removeSearchHistoryItem(_ item: String) {
        searchHistory.removeAll { $0 == item }
        save()
    }

    func clearSearchHistory() {
        searchHistory.removeAll()
        save()
    }

    private func load() {
        appleMusicEnabled = defaults.bool(forKey: "apple_music_enabled")
        spotifyEnabled = defaults.bool(forKey: "spotify_enabled")
        spotifyClientID = defaults.string(forKey: "spotify_client_id") ?? ""
        if let raw = defaults.string(forKey: "screen_while_playing"),
           let val = ScreenWhilePlaying(rawValue: raw) { screenWhilePlaying = val }
        if let raw = defaults.string(forKey: "default_start_tab"),
           let val = DefaultStartTab(rawValue: raw) { defaultStartTab = val }
        isDarkMode = defaults.object(forKey: "dark_mode") as? Bool ?? true
        selectedThemeID = defaults.string(forKey: "theme_id") ?? "soundwave"
        // One-time move to the Sound Wave redesign: "blue" was the old
        // default, written by every settings save, so it is not a reliable
        // sign of an explicit choice.
        if !defaults.bool(forKey: "theme_soundwave_migrated") {
            if selectedThemeID == "blue" { selectedThemeID = "soundwave" }
            defaults.set(true, forKey: "theme_soundwave_migrated")
        }
        customAccentHex = defaults.string(forKey: "theme_custom_accent") ?? ""
        customAccentEndHex = defaults.string(forKey: "theme_custom_accent_end") ?? ""
        customBackgroundHex = defaults.string(forKey: "theme_custom_background") ?? ""
        // The sleep timer is intentionally NOT restored. It's ephemeral —
        // nothing re-arms it at launch, so restoring a stale "30 min"
        // selection would show a duration with no running timer. It always
        // starts at `.off` each launch.
        if let history = defaults.stringArray(forKey: "search_history") {
            searchHistory = history
        }
        backendURLOverride = defaults.string(forKey: BackendConfig.urlOverrideKey) ?? ""
        backendAPIKeyOverride = defaults.string(forKey: BackendConfig.apiKeyOverrideKey) ?? ""
        serverKind = BackendConfig.ServerKind(rawValue: defaults.string(forKey: BackendConfig.serverKindKey) ?? "") ?? .aria
        subsonicUsername = defaults.string(forKey: BackendConfig.subsonicUsernameKey) ?? ""
        subsonicPassword = KeychainStore.get(account: KeychainStore.subsonicPasswordAccount) ?? ""
        lastStoredPassword = subsonicPassword
    }

    func save() {
        defaults.set(defaultStartTab.rawValue, forKey: "default_start_tab")
        defaults.set(screenWhilePlaying.rawValue, forKey: "screen_while_playing")
        defaults.set(appleMusicEnabled, forKey: "apple_music_enabled")
        defaults.set(spotifyEnabled, forKey: "spotify_enabled")
        defaults.set(spotifyClientID, forKey: "spotify_client_id")
        defaults.set(isDarkMode, forKey: "dark_mode")
        defaults.set(selectedThemeID, forKey: "theme_id")
        defaults.set(customAccentHex, forKey: "theme_custom_accent")
        defaults.set(customAccentEndHex, forKey: "theme_custom_accent_end")
        defaults.set(customBackgroundHex, forKey: "theme_custom_background")
        // Sleep timer is ephemeral and deliberately not persisted (see load()).
        defaults.set(searchHistory, forKey: "search_history")
        defaults.set(backendURLOverride, forKey: BackendConfig.urlOverrideKey)
        defaults.set(backendAPIKeyOverride, forKey: BackendConfig.apiKeyOverrideKey)
        defaults.set(serverKind.rawValue, forKey: BackendConfig.serverKindKey)
        defaults.set(subsonicUsername, forKey: BackendConfig.subsonicUsernameKey)
        // The password is a real credential: Keychain only. Guarded on an
        // actual change — `save()` runs for every settings edit (theme, start
        // page…), and the Keychain is far too expensive to hit each time.
        if subsonicPassword != lastStoredPassword {
            let stored = KeychainStore.set(subsonicPassword,
                                           account: KeychainStore.subsonicPasswordAccount)
            credentialStorageFailed = !stored
            if stored { lastStoredPassword = subsonicPassword }
        }
    }

    func setTheme(_ id: String) {
        selectedThemeID = id
        save()
    }
}

/// What the screen does while music plays (iOS only; see ScreenAwakeController).
enum ScreenWhilePlaying: String, CaseIterable {
    case normal, keepOn, keepOnDim

    var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .keepOn: return "Mantener encendida"
        case .keepOnDim: return "Encendida y atenuar"
        }
    }
}
