import Foundation

extension Notification.Name {
    /// Posted by `NowPlayingService` once audio output is active (iOS: after
    /// `setActive(true)` succeeds; macOS: on every start).
    static let ariaAudioSessionActivated = Notification.Name("AriaAudioSessionActivated")
}

#if os(iOS)
import AVFoundation
import Combine
import UIKit

/// One output port of the current audio route, as `AVAudioSession` reports it.
struct AudioOutputPort: Equatable {
    let name: String
    let type: AVAudioSession.Port

    /// Spanish label for the port type. Only `.usbAudio` is "USB"; Bluetooth,
    /// AirPlay, CarPlay and wired ports are never reported as a USB DAC.
    var kindLabel: String {
        switch type {
        case .usbAudio: return "USB"
        case .headphones: return "Auriculares con cable"
        case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP: return "Bluetooth"
        case .builtInSpeaker: return "Altavoz"
        case .builtInReceiver: return "Auricular del teléfono"
        case .airPlay: return "AirPlay"
        case .HDMI: return "HDMI"
        case .lineOut: return "Salida de línea"
        case .carAudio: return "CarPlay"
        default: return "Otra salida"
        }
    }
}

/// Output-route properties. Kept apart from `SourceAudioInfo`: these describe
/// where audio goes, not what the file contains.
struct AudioOutputSnapshot: Equatable {
    let ports: [AudioOutputPort]
    /// Session sample rate read after activation; `nil` when the session is
    /// inactive or has no output. Not a measurement of the DAC's clock.
    let sampleRate: Double?

    var primary: AudioOutputPort? { ports.first }
    var isUSBDAC: Bool { primary?.type == .usbAudio }

    var displayText: String {
        guard let port = primary else { return "Salida: No disponible" }
        let rate = sampleRate.map { String(format: "%g kHz", $0 / 1_000) } ?? "No disponible"
        let name = port.name.isEmpty || port.name == port.kindLabel ? "" : " · \(port.name)"
        return "Salida: \(port.kindLabel)\(name) · \(rate)"
    }
}

/// The parts of `AVAudioSession` the monitor reads, so tests can inject routes.
protocol AudioSessionReading: AnyObject {
    var outputPorts: [AudioOutputPort] { get }
    var sampleRate: Double { get }
}

extension AVAudioSession: AudioSessionReading {
    var outputPorts: [AudioOutputPort] {
        currentRoute.outputs.map { AudioOutputPort(name: $0.portName, type: $0.portType) }
    }
}

/// Publishes the active output route and the session's effective sample rate.
/// `preferredSampleRate` is never read: it is a request, not a result.
@MainActor
final class AudioOutputMonitor: ObservableObject {
    @Published private(set) var snapshot: AudioOutputSnapshot

    private let session: AudioSessionReading
    private let center: NotificationCenter
    private var sessionActive = false
    private var observers: [NSObjectProtocol] = []

    init(session: AudioSessionReading = AVAudioSession.sharedInstance(),
         center: NotificationCenter = .default) {
        self.session = session
        self.center = center
        self.snapshot = AudioOutputSnapshot(ports: session.outputPorts, sampleRate: nil)

        // Session notifications arrive on arbitrary threads; queue: .main
        // delivers them on the main thread before touching published state.
        func observe(_ name: Notification.Name, _ handle: @escaping @MainActor (Notification) -> Void) {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { note in
                MainActor.assumeIsolated { handle(note) }
            })
        }
        observe(.ariaAudioSessionActivated) { [weak self] _ in self?.sessionDidActivate() }
        observe(AVAudioSession.routeChangeNotification) { [weak self] _ in self?.refresh() }
        observe(AVAudioSession.interruptionNotification) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if raw == AVAudioSession.InterruptionType.began.rawValue { self?.sessionActive = false }
            self?.refresh()
        }
        // After a media-services reset every session object is rebuilt and
        // inactive until playback activates it again.
        observe(AVAudioSession.mediaServicesWereResetNotification) { [weak self] _ in
            self?.sessionActive = false
            self?.refresh()
        }
        observe(UIApplication.didBecomeActiveNotification) { [weak self] _ in self?.refresh() }
    }

    deinit {
        observers.forEach(center.removeObserver)
    }

    func sessionDidActivate() {
        sessionActive = true
        refresh()
    }

    /// Re-reads the route. The rate is only trusted once the session is active
    /// and has an output; otherwise it stays unknown.
    func refresh() {
        let ports = session.outputPorts
        let rate = session.sampleRate
        let known = sessionActive && !ports.isEmpty && rate.isFinite && rate > 0
        let next = AudioOutputSnapshot(ports: ports, sampleRate: known ? rate : nil)
        if next != snapshot { snapshot = next }
    }
}
#endif
