import Combine
import SpotifyiOS
import SwiftUI
import UIKit

/// What the Spotify app on this device is playing (from App Remote).
struct SpotifyTrackState: Equatable {
    var uri: String
    var title: String
    var artist: String
    var album: String
    var durationMs: Int
    /// Position reported by Spotify at `reportedAt`; interpolate while playing.
    var positionMs: Int
    var reportedAt: Date
    var isPaused: Bool
    var isShuffling: Bool
    /// 0 off, 1 track, 2 context (SPTAppRemotePlaybackOptionsRepeatMode).
    var repeatMode: UInt

    /// Current position in seconds, advanced from the last report while playing.
    func position(at date: Date = Date()) -> TimeInterval {
        let base = TimeInterval(positionMs) / 1000
        let elapsed = isPaused ? 0 : max(0, date.timeIntervalSince(reportedAt))
        return min(base + elapsed, TimeInterval(durationMs) / 1000)
    }
}

/// Optional Spotify integration: controls the Spotify app on this same
/// device through the official iOS SDK (App Remote) and logs in with PKCE.
/// The Spotify app plays the audio, so Ailen's EQ and quality data don't
/// apply. Nothing runs until enabled in Settings with a Client ID.
@MainActor
final class SpotifyService: NSObject, ObservableObject {
    enum ConnectionState: Equatable {
        case notConfigured, notInstalled, signedOut, connecting, connected, disconnected
        case failed(String)
    }

    @Published private(set) var state: ConnectionState = .notConfigured
    @Published private(set) var nowPlaying: SpotifyTrackState?
    @Published private(set) var artwork: UIImage?
    @Published private(set) var isPlaying = false
    /// Spotify was the last thing started: Now Playing shows and controls it.
    @Published private(set) var isActiveSource = false

    static let redirectURL = URL(string: "ailen-spotify://callback")!
    static let scopes: SPTScope = [.appRemoteControl, .userReadPlaybackState, .userModifyPlaybackState,
                                   .userReadCurrentlyPlaying, .playlistReadPrivate, .playlistReadCollaborative,
                                   .userLibraryRead, .userLibraryModify]
    private static let keychainAccount = "spotify.session"

    private var clientID = ""
    private var sessionManager: SPTSessionManager?
    private var appRemote: SPTAppRemote?
    /// Played once the connection is up (or used to wake Spotify).
    private var pendingPlayURI: String?
    /// The user asked for something: if Spotify is asleep, wake it.
    private var wakeOnFailure = false

    private weak var music: PlayerManager?
    private weak var video: VideoPlaybackController?
    private weak var appleMusic: AppleMusicService?

    func configure(clientID rawID: String, music: PlayerManager, video: VideoPlaybackController,
                   appleMusic: AppleMusicService) {
        self.music = music
        self.video = video
        self.appleMusic = appleMusic
        let clientID = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clientID != self.clientID || sessionManager == nil else { return }
        shutDown()
        self.clientID = clientID
        guard !clientID.isEmpty else {
            state = .notConfigured
            return
        }
        let configuration = SPTConfiguration(clientID: clientID, redirectURL: Self.redirectURL)
        let sessionManager = SPTSessionManager(configuration: configuration, delegate: self)
        sessionManager.session = Self.loadSession()
        let appRemote = SPTAppRemote(configuration: configuration, logLevel: .none)
        appRemote.delegate = self
        self.sessionManager = sessionManager
        self.appRemote = appRemote
        refreshState()
    }

    var accessToken: String? {
        guard let session = sessionManager?.session, !session.isExpired else { return nil }
        return session.accessToken
    }

    /// Callers waiting for a renewal in flight.
    private var tokenWaiters: [CheckedContinuation<String?, Never>] = []

    /// A valid token, renewing it first if it expired.
    func freshAccessToken() async -> String? {
        if let token = accessToken { return token }
        return await renewedAccessToken()
    }

    /// Forces a renewal (after a 401) and waits for it.
    func renewedAccessToken() async -> String? {
        guard let sessionManager, sessionManager.session != nil else { return nil }
        return await withCheckedContinuation { continuation in
            tokenWaiters.append(continuation)
            if tokenWaiters.count == 1 { sessionManager.renewSession() }
        }
    }

    private func finishRenewal(_ token: String?) {
        let waiters = tokenWaiters
        tokenWaiters.removeAll()
        waiters.forEach { $0.resume(returning: token) }
    }

    /// Web API client using this service's session.
    var webAPI: SpotifyWebAPI {
        SpotifyWebAPI(token: { [weak self] in await self?.freshAccessToken() },
                      renewedToken: { [weak self] in await self?.renewedAccessToken() })
    }

    private func refreshState() {
        guard let sessionManager else { state = .notConfigured; return }
        if !sessionManager.isSpotifyAppInstalled {
            state = .notInstalled
        } else if sessionManager.session == nil {
            state = .signedOut
        } else if appRemote?.isConnected == true {
            state = .connected
        } else if state != .connecting {
            state = .disconnected
        }
    }

    // MARK: - Login

    /// Opens the Spotify app (or a web sheet) to authorize Ailen.
    func signIn() {
        guard let sessionManager else { return }
        sessionManager.initiateSession(with: Self.scopes, options: .default, campaign: nil)
    }

    func signOut() {
        appRemote?.disconnect()
        sessionManager?.session = nil
        _ = KeychainStore.delete(account: Self.keychainAccount)
        clearPlayback()
        refreshState()
    }

    /// `ailen-spotify://callback…` from the login or from waking Spotify.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard url.scheme == Self.redirectURL.scheme else { return false }
        if let params = appRemote?.authorizationParameters(from: url),
           let token = params[SPTAppRemoteAccessTokenKey] {
            appRemote?.connectionParameters.accessToken = token
            appRemote?.connect()
            return true
        }
        return sessionManager?.application(UIApplication.shared, open: url, options: [:]) ?? false
    }

    // MARK: - Connection

    /// Connects to the Spotify app. `userInitiated` allows waking Spotify
    /// (iOS switches to it for a moment and comes back).
    func connect(userInitiated: Bool = false) {
        guard let appRemote, let sessionManager, sessionManager.isSpotifyAppInstalled else { refreshState(); return }
        guard let session = sessionManager.session else { state = .signedOut; return }
        if session.isExpired {
            sessionManager.renewSession()  // delegate reconnects when renewed
            return
        }
        guard !appRemote.isConnected else { state = .connected; return }
        wakeOnFailure = userInitiated
        appRemote.connectionParameters.accessToken = session.accessToken
        state = .connecting
        appRemote.connect()
    }

    /// App became active: reconnect quietly (no app switch).
    func appDidBecomeActive() {
        guard sessionManager?.session != nil else { return }
        connect(userInitiated: false)
    }

    /// App going to the background: the SDK must disconnect.
    func appWillResignActive() {
        if appRemote?.isConnected == true { appRemote?.disconnect() }
    }

    /// Section disabled or Client ID changed.
    func shutDown() {
        appRemote?.disconnect()
        appRemote = nil
        sessionManager = nil
        clientID = ""
        clearPlayback()
        state = .notConfigured
    }

    private func clearPlayback() {
        nowPlaying = nil
        artwork = nil
        isPlaying = false
        isActiveSource = false
    }

    // MARK: - Playback

    /// Plays a track, album or playlist URI in the Spotify app.
    func play(uri: String) {
        takeOver()
        guard let appRemote, appRemote.isConnected, let player = appRemote.playerAPI else {
            pendingPlayURI = uri
            connect(userInitiated: true)
            return
        }
        player.play(uri, callback: nil)
    }

    func togglePlayPause() {
        guard let player = appRemote?.playerAPI, appRemote?.isConnected == true else {
            connect(userInitiated: true)
            return
        }
        if isPlaying {
            player.pause(nil)
        } else {
            takeOver()
            player.resume(nil)
        }
    }

    func skipToNext() { appRemote?.playerAPI?.skip(toNext: nil) }
    func skipToPrevious() { appRemote?.playerAPI?.skip(toPrevious: nil) }

    func seek(to seconds: TimeInterval) {
        appRemote?.playerAPI?.seek(toPosition: Int(seconds * 1000), callback: nil)
    }

    func setShuffle(_ on: Bool) {
        appRemote?.playerAPI?.setShuffle(on, callback: nil)
    }

    func toggleShuffle() {
        guard let current = nowPlaying else { return }
        appRemote?.playerAPI?.setShuffle(!current.isShuffling, callback: nil)
    }

    /// off → context → track → off.
    func cycleRepeat() {
        guard let current = nowPlaying else { return }
        let next: SPTAppRemotePlaybackOptionsRepeatMode
        switch current.repeatMode {
        case 0: next = .context
        case 2: next = .track
        default: next = .off
        }
        appRemote?.playerAPI?.setRepeatMode(next, callback: nil)
    }

    /// Local music or Apple Music took over: pause Spotify, hand Now Playing back.
    func resignActiveSource() {
        if isPlaying { appRemote?.playerAPI?.pause(nil) }
        isActiveSource = false
    }

    /// This source starts: everything else steps aside.
    private func takeOver() {
        isActiveSource = true
        music?.yieldToOtherPlayer()
        video?.stop()
        appleMusic?.resignActiveSource()
    }

    // MARK: - Session storage (Keychain)

    private static func loadSession() -> SPTSession? {
        guard let encoded = KeychainStore.get(account: keychainAccount),
              let data = Data(base64Encoded: encoded) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: SPTSession.self, from: data)
    }

    private static func save(_ session: SPTSession) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: session, requiringSecureCoding: true) else { return }
        _ = KeychainStore.set(data.base64EncodedString(), account: keychainAccount)
    }

    private func apply(_ playerState: SPTAppRemotePlayerState) {
        let track = playerState.track
        let previousURI = nowPlaying?.uri
        let wasPaused = nowPlaying?.isPaused ?? true
        nowPlaying = SpotifyTrackState(
            uri: track.uri, title: track.name, artist: track.artist.name, album: track.album.name,
            durationMs: Int(track.duration), positionMs: playerState.playbackPosition, reportedAt: Date(),
            isPaused: playerState.isPaused, isShuffling: playerState.playbackOptions.isShuffling,
            repeatMode: playerState.playbackOptions.repeatMode.rawValue)
        isPlaying = !playerState.isPaused
        // Started from the Spotify app or the lock screen: Spotify becomes the source.
        if wasPaused && !playerState.isPaused && !isActiveSource { takeOver() }
        if previousURI != track.uri {
            appRemote?.imageAPI?.fetchImage(forItem: track, with: CGSize(width: 600, height: 600)) { [weak self] image, _ in
                let image = image as? UIImage
                Task { @MainActor in self?.artwork = image }
            }
        }
    }
}

// MARK: - SDK delegates (called on the main thread)

extension SpotifyService: SPTSessionManagerDelegate {
    nonisolated func sessionManager(manager: SPTSessionManager, didInitiate session: SPTSession) {
        let token = session.accessToken
        Task { @MainActor in
            Self.save(session)
            self.finishRenewal(token)
            self.connect(userInitiated: true)
        }
    }

    nonisolated func sessionManager(manager: SPTSessionManager, didRenew session: SPTSession) {
        let token = session.accessToken
        Task { @MainActor in
            Self.save(session)
            self.finishRenewal(token)
            self.connect(userInitiated: false)
        }
    }

    nonisolated func sessionManager(manager: SPTSessionManager, didFailWith error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.finishRenewal(nil)
            self.state = .failed("No se pudo iniciar sesión en Spotify: \(message)")
        }
    }
}

extension SpotifyService: SPTAppRemoteDelegate {
    nonisolated func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        Task { @MainActor in
            self.state = .connected
            self.wakeOnFailure = false
            appRemote.playerAPI?.delegate = self
            appRemote.playerAPI?.subscribe(toPlayerState: nil)
            appRemote.playerAPI?.getPlayerState { result, _ in
                guard let playerState = result as? SPTAppRemotePlayerState else { return }
                Task { @MainActor in self.apply(playerState) }
            }
            if let uri = self.pendingPlayURI {
                self.pendingPlayURI = nil
                appRemote.playerAPI?.play(uri, callback: nil)
            }
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        Task { @MainActor in
            if self.wakeOnFailure {
                // Spotify is asleep: open it briefly to start (and play); it
                // calls back with a token through `handle(_:)`.
                self.wakeOnFailure = false
                let uri = self.pendingPlayURI ?? ""
                self.pendingPlayURI = nil
                appRemote.authorizeAndPlayURI(uri) { opened in
                    guard !opened else { return }
                    Task { @MainActor in self.state = .failed("No se pudo abrir la app de Spotify.") }
                }
            } else {
                self.state = .disconnected
            }
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        Task { @MainActor in
            self.isPlaying = false
            self.refreshState()
        }
    }
}

extension SpotifyService: SPTAppRemotePlayerStateDelegate {
    nonisolated func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        Task { @MainActor in self.apply(playerState) }
    }
}
