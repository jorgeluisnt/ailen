import Combine
import MediaPlayer
import MusicKit
import SwiftUI

/// A song from the user's Apple Music / Music app library.
struct AMSong: Identifiable, Hashable {
    let item: MPMediaItem
    var id: MPMediaEntityPersistentID { item.persistentID }
    var title: String { item.title ?? "Sin título" }
    var artist: String { item.artist ?? "Artista desconocido" }
    var duration: TimeInterval { item.playbackDuration }
    /// In the cloud only (not downloaded): needs a connection to play.
    var isCloud: Bool { item.isCloudItem }
}

/// A playlist or album from the user's library.
struct AMCollection: Identifiable, Hashable {
    let id: MPMediaEntityPersistentID
    let title: String
    let subtitle: String
    let items: [MPMediaItem]
    var artworkItem: MPMediaItem? { items.first { $0.artwork != nil } }
}

/// Optional Apple Music integration. Library and playback use MediaPlayer,
/// which only needs the user's permission (works with a free developer
/// account). Audio is DRM-protected and played by Apple, so Ailen's EQ,
/// Direct mode and quality data don't apply. Nothing runs until the section
/// is enabled in Settings and opened.
@MainActor
final class AppleMusicService: ObservableObject {
    @Published private(set) var libraryAuth: MPMediaLibraryAuthorizationStatus = MPMediaLibrary.authorizationStatus()
    @Published private(set) var playlists: [AMCollection] = []
    @Published private(set) var albums: [AMCollection] = []
    @Published private(set) var songs: [AMSong] = []
    @Published private(set) var isLoading = false
    @Published private(set) var nowPlaying: AMSong?
    @Published private(set) var isPlaying = false
    /// Apple Music was the last thing started: Now Playing shows and controls
    /// it. Cleared when local music starts or the section is disabled.
    @Published private(set) var isActiveSource = false
    @Published private(set) var shuffleOn = false
    @Published private(set) var repeatMode: MPMusicRepeatMode = .none

    // Catalog (MusicKit service; needs a paid developer account).
    enum CatalogState: Equatable { case idle, searching, results, unavailable(String) }
    @Published private(set) var catalogState: CatalogState = .idle
    @Published private(set) var catalogSongs: [Song] = []
    @Published private(set) var catalogAlbums: [Album] = []
    @Published private(set) var addedToLibrary: Set<MusicItemID> = []
    /// One-off messages (subscription missing, add failed…).
    @Published var alertMessage: String?

    private weak var music: PlayerManager?
    private weak var video: VideoPlaybackController?
    /// Created on first use, so nothing touches Apple Music while disabled.
    private var player: MPMusicPlayerApplicationController?
    private var observers: [NSObjectProtocol] = []

    func configure(music: PlayerManager, video: VideoPlaybackController) {
        self.music = music
        self.video = video
    }

    // MARK: - Permission and library

    func requestAccess() async {
        libraryAuth = await withCheckedContinuation { continuation in
            MPMediaLibrary.requestAuthorization { continuation.resume(returning: $0) }
        }
        if libraryAuth == .authorized { loadLibrary() }
    }

    /// Reads playlists, albums and songs (A→Z).
    func loadLibrary() {
        libraryAuth = MPMediaLibrary.authorizationStatus()
        guard libraryAuth == .authorized else { return }
        isLoading = true
        defer { isLoading = false }
        let byTitle: (AMCollection, AMCollection) -> Bool = {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        playlists = (MPMediaQuery.playlists().collections as? [MPMediaPlaylist] ?? [])
            .filter { $0.count > 0 }
            .map { list in
                AMCollection(id: list.persistentID, title: list.name ?? "Lista",
                             subtitle: Self.songCount(list.count), items: list.items)
            }
            .sorted(by: byTitle)
        albums = (MPMediaQuery.albums().collections ?? [])
            .compactMap { album in
                guard let first = album.representativeItem else { return nil }
                return AMCollection(id: first.albumPersistentID, title: first.albumTitle ?? "Álbum",
                                    subtitle: first.albumArtist ?? first.artist ?? "Artista desconocido",
                                    items: album.items)
            }
            .sorted(by: byTitle)
        songs = (MPMediaQuery.songs().items ?? []).map(AMSong.init)
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    static func songCount(_ n: Int) -> String { "\(n) \(n == 1 ? "canción" : "canciones")" }

    // MARK: - Playback

    /// Plays `items` from `index`. Local music and any video stop first.
    func play(_ items: [MPMediaItem], startAt index: Int = 0, shuffled: Bool = false) {
        guard !items.isEmpty else { return }
        let player = ensurePlayer()
        music?.yieldToOtherPlayer()
        video?.stop()
        isActiveSource = true
        player.setQueue(with: MPMediaItemCollection(items: items))
        player.shuffleMode = shuffled ? .songs : .off
        if !shuffled { player.nowPlayingItem = items[min(max(index, 0), items.count - 1)] }
        player.prepareToPlay()
        player.play()
    }

    func togglePlayPause() {
        guard let player else { return }
        if player.playbackState == .playing {
            player.pause()
        } else {
            music?.yieldToOtherPlayer()
            video?.stop()
            isActiveSource = true
            player.play()
        }
    }

    // MARK: - Now Playing controls

    /// Read by the seek bar on a timer (the player doesn't publish it).
    var currentTime: TimeInterval { player?.currentPlaybackTime ?? 0 }
    var duration: TimeInterval { nowPlaying?.duration ?? 0 }

    func seek(to time: TimeInterval) { player?.currentPlaybackTime = time }

    func toggleShuffle() {
        guard let player else { return }
        player.shuffleMode = player.shuffleMode == .off ? .songs : .off
        refreshState()
    }

    func cycleRepeat() {
        guard let player else { return }
        switch player.repeatMode {
        case .none, .default: player.repeatMode = .all
        case .all: player.repeatMode = .one
        default: player.repeatMode = .none
        }
        refreshState()
    }

    /// Local music took over: Now Playing goes back to it.
    func resignActiveSource() {
        pause()
        isActiveSource = false
    }

    var nowPlayingArtwork: UIImage? { Self.artwork(nowPlaying?.item, size: 600) }

    /// Now Playing model for the shared external views.
    var nowPlayingModel: ExternalNowPlaying? {
        guard let song = nowPlaying else { return nil }
        let repeatState: ExternalNowPlaying.Repeat = repeatMode == .one ? .one : (repeatMode == .all ? .all : .off)
        return ExternalNowPlaying(
            source: "Apple Music", title: song.title, artist: song.artist, artwork: nowPlayingArtwork,
            isPlaying: isPlaying, shuffleOn: shuffleOn, repeatState: repeatState, duration: song.duration,
            position: { [weak self] in self?.currentTime ?? 0 },
            note: "Reproducido por Apple Music · sin ecualizador ni datos de calidad",
            playPause: { [weak self] in self?.togglePlayPause() },
            next: { [weak self] in self?.skipToNext() },
            previous: { [weak self] in self?.skipToPrevious() },
            toggleShuffle: { [weak self] in self?.toggleShuffle() },
            cycleRepeat: { [weak self] in self?.cycleRepeat() },
            seek: { [weak self] in self?.seek(to: $0) })
    }

    func skipToNext() { player?.skipToNextItem() }
    func skipToPrevious() { player?.skipToPreviousItem() }

    /// Local music or a video took over.
    func pause() {
        guard let player, player.playbackState == .playing else { return }
        player.pause()
    }

    /// The section was disabled: stop and forget the player.
    func shutDown() {
        player?.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        player?.endGeneratingPlaybackNotifications()
        player = nil
        nowPlaying = nil
        isPlaying = false
        isActiveSource = false
    }

    private func ensurePlayer() -> MPMusicPlayerApplicationController {
        if let player { return player }
        let player = MPMusicPlayerController.applicationQueuePlayer
        player.beginGeneratingPlaybackNotifications()
        let center = NotificationCenter.default
        for name in [Notification.Name.MPMusicPlayerControllerNowPlayingItemDidChange,
                     .MPMusicPlayerControllerPlaybackStateDidChange] {
            observers.append(center.addObserver(forName: name, object: player, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshState() }
            })
        }
        self.player = player
        return player
    }

    private func refreshState() {
        guard let player else { return }
        nowPlaying = player.nowPlayingItem.map(AMSong.init)
        isPlaying = player.playbackState == .playing
        shuffleOn = player.shuffleMode != .off
        repeatMode = player.repeatMode
    }

    // MARK: - Catalog (MusicKit)

    func searchCatalog(_ rawTerm: String) async {
        let term = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            catalogState = .idle
            catalogSongs = []
            catalogAlbums = []
            return
        }
        catalogState = .searching
        let status = await MusicAuthorization.request()
        if let message = AppleMusicAvailability.message(forAuthorization: status) {
            catalogState = .unavailable(message)
            return
        }
        do {
            var request = MusicCatalogSearchRequest(term: term, types: [Song.self, Album.self])
            request.limit = 25
            let response = try await request.response()
            guard !Task.isCancelled else { return }
            catalogSongs = Array(response.songs)
            catalogAlbums = Array(response.albums)
            catalogState = .results
        } catch {
            guard !Task.isCancelled else { return }
            catalogState = .unavailable(AppleMusicAvailability.catalogMessage(for: error))
        }
    }

    /// Catalog songs play in the same player, queued by store ID.
    func playCatalog(_ songs: [Song], startAt index: Int = 0) async {
        await playStoreIDs(songs.map(\.id.rawValue), start: songs.indices.contains(index) ? songs[index].id.rawValue : nil)
    }

    func playCatalogAlbum(_ album: Album, shuffled: Bool = false) async {
        do {
            let detailed = try await album.with([.tracks])
            let ids = (detailed.tracks ?? []).map(\.id.rawValue)
            await playStoreIDs(shuffled ? ids.shuffled() : ids, start: nil)
        } catch {
            alertMessage = AppleMusicAvailability.catalogMessage(for: error)
        }
    }

    private func playStoreIDs(_ ids: [String], start: String?) async {
        guard !ids.isEmpty else { return }
        if let subscription = try? await MusicSubscription.current, !subscription.canPlayCatalogContent {
            alertMessage = AppleMusicAvailability.subscriptionMessage
            return
        }
        let player = ensurePlayer()
        music?.yieldToOtherPlayer()
        video?.stop()
        isActiveSource = true
        let descriptor = MPMusicPlayerStoreQueueDescriptor(storeIDs: ids)
        descriptor.startItemID = start
        player.shuffleMode = .off
        player.setQueue(with: descriptor)
        do {
            try await player.prepareToPlay()
            player.play()
        } catch {
            alertMessage = AppleMusicAvailability.catalogMessage(for: error)
        }
    }

    func addToLibrary(_ song: Song) async {
        do {
            try await MusicLibrary.shared.add(song)
            addedToLibrary.insert(song.id)
        } catch {
            alertMessage = AppleMusicAvailability.catalogMessage(for: error)
        }
    }

    func addToLibrary(_ album: Album) async {
        do {
            try await MusicLibrary.shared.add(album)
            addedToLibrary.insert(album.id)
        } catch {
            alertMessage = AppleMusicAvailability.catalogMessage(for: error)
        }
    }

    // MARK: - Artwork

    static func artwork(_ item: MPMediaItem?, size: CGFloat) -> UIImage? {
        item?.artwork?.image(at: CGSize(width: size, height: size))
    }
}
