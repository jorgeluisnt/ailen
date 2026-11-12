import AVFoundation
import AVKit
import Combine
import UIKit

/// Plays one linked video with the system player (AVPlayerViewController),
/// presented full screen from UIKit so it gets the native close button,
/// gestures, AirPlay and Picture in Picture. It owns the player and the
/// security-scoped access, so PiP keeps playing after the screen closes.
@MainActor
final class VideoPlaybackController: NSObject, ObservableObject {
    @Published private(set) var isPlaying = false
    @Published var errorMessage: String?

    private(set) var current: VideoItem?
    private weak var library: VideoLibraryManager?
    private weak var music: PlayerManager?

    private var playerController: AVPlayerViewController?
    private var player: AVPlayer?
    private var stopAccess: (() -> Void)?
    private var timeObserver: Any?
    private var rateObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var isInPictureInPicture = false

    func configure(library: VideoLibraryManager, music: PlayerManager) {
        self.library = library
        self.music = music
    }

    // MARK: - Playback

    func play(_ item: VideoItem, fromStart: Bool = false) {
        stop()
        guard let library, let access = library.open(item) else {
            errorMessage = VideoImportError.unavailable.message(fileName: item.title)
            return
        }
        guard FileManager.default.fileExists(atPath: access.url.path),
              !LocalLibraryManager.defaultIsCloudFileNotDownloaded(access.url) else {
            // iCloud: ask for the download so a later attempt can work.
            try? FileManager.default.startDownloadingUbiquitousItem(at: access.url)
            access.stop()
            library.auditMissingFlags()
            errorMessage = VideoImportError.unavailable.message(fileName: item.title)
            return
        }

        music?.yieldToOtherPlayer()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, policy: .default, options: [])
        try? session.setActive(true)

        let player = AVPlayer(url: access.url)
        player.preventsDisplaySleepDuringVideoPlayback = true  // never sleep mid-video
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.updatesNowPlayingInfoCenter = true
        controller.delegate = self
        controller.modalPresentationStyle = .fullScreen

        self.player = player
        self.playerController = controller
        self.stopAccess = access.stop
        self.current = item

        if !fromStart, let resume = item.resumePosition {
            player.seek(to: CMTime(seconds: resume, preferredTimescale: 600))
        }
        // Save the position every 5 s, so a crash or kill loses little.
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 5, preferredTimescale: 1),
                                                      queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveResume() }
        }
        rateObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            let playing = player.timeControlStatus != .paused
            Task { @MainActor in self?.isPlaying = playing }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let id = self.current?.id else { return }
                self.library?.setResume(id, seconds: nil)  // watched to the end
            }
        }

        present(controller)
        player.play()
    }

    /// Pauses the video (e.g. music started from the lock screen or PiP).
    func pause() {
        player?.pause()
    }

    /// Ends playback: saves the position, releases the file and gives the
    /// lock-screen controls back to music.
    func stop() {
        guard player != nil else { return }
        saveResume()
        player?.pause()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        rateObservation = nil
        playerController?.player = nil
        playerController = nil
        player = nil
        stopAccess?()
        stopAccess = nil
        current = nil
        isPlaying = false
        isInPictureInPicture = false
        music?.otherPlayerDidFinish()
    }

    private func saveResume() {
        guard let player, let item = current else { return }
        let seconds = player.currentTime().seconds
        let duration = player.currentItem?.duration.seconds
        library?.setResume(item.id, seconds: VideoResume.position(
            current: seconds, duration: (duration?.isFinite == true) ? duration : item.durationSeconds))
    }

    // MARK: - Presentation

    private func present(_ controller: UIViewController) {
        guard let root = Self.topViewController() else { return }
        root.present(controller, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

extension VideoPlaybackController: AVPlayerViewControllerDelegate {
    nonisolated func playerViewController(
        _ playerViewController: AVPlayerViewController,
        willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator
    ) {
        coordinator.animate(alongsideTransition: nil) { context in
            guard !context.isCancelled else { return }
            Task { @MainActor in
                // Closed with ✕ or a swipe: stop, unless PiP keeps playing.
                if !self.isInPictureInPicture { self.stop() }
            }
        }
    }

    nonisolated func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
        Task { @MainActor in self.isInPictureInPicture = true }
    }

    nonisolated func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
        Task { @MainActor in
            self.isInPictureInPicture = false
            // PiP closed without returning to full screen: playback is over.
            if playerViewController.presentingViewController == nil { self.stop() }
        }
    }

    /// "Back to full screen" from the PiP window.
    nonisolated func playerViewController(
        _ playerViewController: AVPlayerViewController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        Task { @MainActor in
            if playerViewController.presentingViewController == nil, let root = Self.topViewController() {
                root.present(playerViewController, animated: true) { completionHandler(true) }
            } else {
                completionHandler(true)
            }
        }
    }
}
