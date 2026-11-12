import Combine
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// What the screen does while music plays with the app in the foreground.
/// Raw values are persisted.
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

/// Keeps the screen awake (and optionally dims it after a pause without
/// touches) while music plays and the app is in the foreground, on any
/// screen. Everything is undone when playback stops or the app is
/// minimized: the idle timer is re-enabled and the user's brightness restored.
@MainActor
final class ScreenAwakeController: ObservableObject {
    static let dimDelay: UInt64 = 30_000_000_000  // 30 s
    static let dimLevel: CGFloat = 0.05

    private var isActive = false
    private var dims = false
    private var savedBrightness: CGFloat?
    private var dimTask: Task<Void, Never>?
    private var touchObserver: TouchObserver?

    /// `playing && foreground` decide; `mode` says how. A playing video
    /// always keeps the screen on at full brightness, whatever the mode.
    func update(playing: Bool, videoPlaying: Bool = false, foreground: Bool, mode: ScreenWhilePlaying) {
        let video = videoPlaying && foreground
        let active = video || (playing && foreground && mode != .normal)
        let dims = active && !video && mode == .keepOnDim
        guard active != isActive || dims != self.dims else { return }
        isActive = active
        self.dims = dims

        UIApplication.shared.isIdleTimerDisabled = active
        if dims {
            installTouchObserver()
            scheduleDim()
        } else {
            dimTask?.cancel()
            restoreBrightness()
            removeTouchObserver()
        }
    }

    /// Any touch: back to the user's brightness and restart the countdown.
    private func userInteracted() {
        restoreBrightness()
        if dims { scheduleDim() }
    }

    private func scheduleDim() {
        dimTask?.cancel()
        dimTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.dimDelay)
            guard !Task.isCancelled else { return }
            self?.dim()
        }
    }

    private var screen: UIScreen? {
        (UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene)?.screen
    }

    private func dim() {
        guard savedBrightness == nil, let screen else { return }
        savedBrightness = screen.brightness
        screen.brightness = min(Self.dimLevel, screen.brightness)
    }

    private func restoreBrightness() {
        guard let saved = savedBrightness else { return }
        savedBrightness = nil
        screen?.brightness = saved
    }

    // MARK: - Touches anywhere in the app

    private func installTouchObserver() {
        guard touchObserver == nil,
              let window = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows
                .first(where: \.isKeyWindow) else { return }
        let observer = TouchObserver { [weak self] in self?.userInteracted() }
        window.addGestureRecognizer(observer)
        touchObserver = observer
    }

    private func removeTouchObserver() {
        guard let observer = touchObserver else { return }
        observer.view?.removeGestureRecognizer(observer)
        touchObserver = nil
    }
}

/// Reports the start of any touch and immediately fails, so it never
/// blocks or delays the app's own gestures.
private final class TouchObserver: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private let onTouch: () -> Void

    init(onTouch: @escaping () -> Void) {
        self.onTouch = onTouch
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        onTouch()
        state = .failed
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
