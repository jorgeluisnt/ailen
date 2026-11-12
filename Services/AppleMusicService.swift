import Combine
import MediaPlayer
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
            player.play()
        }
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
    }

    // MARK: - Artwork

    static func artwork(_ item: MPMediaItem?, size: CGFloat) -> UIImage? {
        item?.artwork?.image(at: CGSize(width: size, height: size))
    }
}
