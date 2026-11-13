#if os(macOS)
import Combine
import CoreAudio
import Foundation

/// How the default output device is attached, from Core Audio's transport
/// type. Only `.usb` is reported as a USB DAC.
enum AudioOutputKind: Equatable {
    case usb, builtIn, bluetooth, hdmi, displayPort, airPlay, thunderbolt, aggregate, virtual, other

    init(transportType: UInt32) {
        switch transportType {
        case kAudioDeviceTransportTypeUSB: self = .usb
        case kAudioDeviceTransportTypeBuiltIn: self = .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: self = .bluetooth
        case kAudioDeviceTransportTypeHDMI: self = .hdmi
        case kAudioDeviceTransportTypeDisplayPort: self = .displayPort
        case kAudioDeviceTransportTypeAirPlay: self = .airPlay
        case kAudioDeviceTransportTypeThunderbolt: self = .thunderbolt
        case kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate: self = .aggregate
        case kAudioDeviceTransportTypeVirtual: self = .virtual
        default: self = .other
        }
    }

    var label: String {
        switch self {
        case .usb: return "USB"
        case .builtIn: return "Integrada"
        case .bluetooth: return "Bluetooth"
        case .hdmi: return "HDMI"
        case .displayPort: return "DisplayPort"
        case .airPlay: return "AirPlay"
        case .thunderbolt: return "Thunderbolt"
        case .aggregate: return "Dispositivo agregado"
        case .virtual: return "Dispositivo virtual"
        case .other: return "Otra salida"
        }
    }
}

/// The default output device as Core Audio reports it. Same role (and the
/// same `displayText` / `isUSBDAC` API) as the iOS route snapshot.
struct AudioOutputSnapshot: Equatable {
    /// Core Audio UID of the device Ailen plays to (stable across launches).
    var deviceUID: String? = nil
    let deviceName: String?
    let kind: AudioOutputKind?
    /// The device's nominal sample rate — the rate its clock is actually set
    /// to on macOS, not a session request. `nil` when unreadable.
    let sampleRate: Double?

    static let none = AudioOutputSnapshot(deviceName: nil, kind: nil, sampleRate: nil)

    var isUSBDAC: Bool { kind == .usb }

    var displayText: String {
        guard let kind else { return "Salida: No disponible" }
        let rate = sampleRate.map { String(format: "%g kHz", $0 / 1_000) } ?? "No disponible"
        let name = deviceName.map { $0.isEmpty ? "" : " · \($0)" } ?? ""
        return "Salida: \(kind.label)\(name) · \(rate)"
    }
}

/// An output-capable device, for the Ajustes picker.
struct MacOutputDevice: Identifiable, Hashable {
    let uid: String
    let name: String
    let kind: AudioOutputKind
    var id: String { uid }
}

/// The user's Mac output choices (persisted).
nonisolated enum MacOutputSettings {
    /// Chosen device UID; absent = follow the system default output.
    static let deviceUIDKey = "macOutputDeviceUID"
    static let exclusiveKey = "macExclusiveMode"

    static var selectedUID: String? { UserDefaults.standard.string(forKey: deviceUIDKey) }
    static var exclusive: Bool { UserDefaults.standard.bool(forKey: exclusiveKey) }
}

/// Core Audio HAL access. Reads are safe from any thread; anything that
/// changes a device (rate, hog mode) runs on `queue`.
nonisolated enum CoreAudioHAL {
    static let queue = DispatchQueue(label: "ailen.coreaudio")

    static func address(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func value<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: T) -> T? {
        var address = address(selector)
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    static var defaultOutputDevice: AudioObjectID? {
        value(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice,
              AudioObjectID(kAudioObjectUnknown)).flatMap { $0 == kAudioObjectUnknown ? nil : $0 }
    }

    static func nominalRate(_ device: AudioObjectID) -> Double? {
        value(device, kAudioDevicePropertyNominalSampleRate, Float64(0)).flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    }

    /// Every device with at least one output stream.
    static func outputDevices() -> [(id: AudioObjectID, device: MacOutputDevice)] {
        var address = address(kAudioHardwarePropertyDevices)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            var streams = Self.address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr, streamSize > 0,
                  let uid = string(id, kAudioDevicePropertyDeviceUID) else { return nil }
            let transport = value(id, kAudioDevicePropertyTransportType, UInt32(0)) ?? 0
            return (id, MacOutputDevice(uid: uid, name: string(id, kAudioObjectPropertyName) ?? uid,
                                        kind: AudioOutputKind(transportType: transport)))
        }
    }

    static func device(forUID uid: String) -> AudioObjectID? {
        outputDevices().first { $0.device.uid == uid }?.id
    }

    /// The device Ailen plays to: the chosen one while connected, otherwise
    /// the system default (so unplugging the DAC never leaves it silent).
    static var activeDevice: AudioObjectID? {
        MacOutputSettings.selectedUID.flatMap(device(forUID:)) ?? defaultOutputDevice
    }

    /// For `AVPlayer.audioOutputDeviceUniqueID`: the chosen device if
    /// connected, else `nil` (= follow the system default).
    static var playerDeviceUID: String? {
        MacOutputSettings.selectedUID.flatMap { device(forUID: $0) != nil ? $0 : nil }
    }

    static func snapshot() -> AudioOutputSnapshot {
        guard let device = activeDevice else { return .none }
        let transport = value(device, kAudioDevicePropertyTransportType, UInt32(0))
        return AudioOutputSnapshot(
            deviceUID: string(device, kAudioDevicePropertyDeviceUID),
            deviceName: string(device, kAudioObjectPropertyName),
            kind: transport.map(AudioOutputKind.init(transportType:)) ?? .other,
            sampleRate: nominalRate(device)
        )
    }

    // MARK: Mutations — `queue` only

    /// Sets the active device to the best rate for `sourceRate` (see
    /// `OutputRateMatch`) and waits up to ~1 s for the HAL to apply it.
    static func matchRate(to sourceRate: Double) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard let device = activeDevice else { return }
        var address = address(kAudioDevicePropertyAvailableNominalSampleRates)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return }
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: Int(size) / MemoryLayout<AudioValueRange>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &ranges) == noErr,
              let target = OutputRateMatch.bestRate(for: sourceRate,
                                                    supported: ranges.map { $0.mMinimum...$0.mMaximum }),
              abs((nominalRate(device) ?? 0) - target) > 1 else { return }
        if originalRates[device] == nil { originalRates[device] = nominalRate(device) }
        var rateAddress = Self.address(kAudioDevicePropertyNominalSampleRate)
        var newRate = Float64(target)
        guard AudioObjectSetPropertyData(device, &rateAddress, 0, nil,
                                         UInt32(MemoryLayout<Float64>.size), &newRate) == noErr else { return }
        // Asynchronous in the HAL: wait so playback starts at the new rate.
        for _ in 0..<20 where abs((nominalRate(device) ?? 0) - target) > 1 {
            usleep(50_000)
        }
    }

    /// Each device's rate before Ailen first changed it. `queue` only.
    nonisolated(unsafe) private static var originalRates: [AudioObjectID: Double] = [:]

    /// At quit: puts every device back at the rate it had and releases
    /// exclusive mode — Ailen changed a system-wide setting, so undo it.
    static func restoreDevices() {
        dispatchPrecondition(condition: .onQueue(queue))
        for (device, rate) in originalRates {
            var address = address(kAudioDevicePropertyNominalSampleRate)
            var value = Float64(rate)
            AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float64>.size), &value)
        }
        originalRates = [:]
        if let held = hogged {
            setHogOwner(held, -1)
            hogged = nil
        }
    }

    /// Device currently hogged by Ailen. `queue` only.
    nonisolated(unsafe) private static var hogged: AudioObjectID?

    /// Exclusive (hog) mode: takes the active device for Ailen alone when the
    /// setting is on, and gives back any device it no longer should hold. A
    /// device another app already hogs is left alone. The HAL also releases
    /// it if Ailen quits or crashes.
    static func updateExclusive() {
        dispatchPrecondition(condition: .onQueue(queue))
        let wanted = MacOutputSettings.exclusive ? activeDevice : nil
        if let held = hogged, held != wanted {
            setHogOwner(held, -1)
            hogged = nil
        }
        guard let device = wanted, hogged != device,
              value(device, kAudioDevicePropertyHogMode, pid_t(-1)) == -1 else { return }
        setHogOwner(device, getpid())
        if value(device, kAudioDevicePropertyHogMode, pid_t(-1)) == getpid() { hogged = device }
    }

    private static func setHogOwner(_ device: AudioObjectID, _ owner: pid_t) {
        var address = address(kAudioDevicePropertyHogMode)
        var pid = owner
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<pid_t>.size), &pid)
    }
}

/// What the monitor reads, injectable for tests.
protocol AudioDeviceReading: AnyObject {
    func snapshot() -> AudioOutputSnapshot
    func devices() -> [MacOutputDevice]
    /// Calls `onChange` (any thread) when devices come or go, the default
    /// output changes, or the active device's sample rate changes.
    func observeChanges(_ onChange: @escaping @Sendable () -> Void)
}

final class CoreAudioDeviceReader: AudioDeviceReading {
    private let queue = DispatchQueue(label: "ailen.audio-output-monitor")
    private var watchedDevice: AudioObjectID = kAudioObjectUnknown
    private var onChange: (@Sendable () -> Void)?

    func snapshot() -> AudioOutputSnapshot { CoreAudioHAL.snapshot() }
    func devices() -> [MacOutputDevice] { CoreAudioHAL.outputDevices().map(\.device) }

    func observeChanges(_ onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        let system = AudioObjectID(kAudioObjectSystemObject)
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDevices] {
            var address = CoreAudioHAL.address(selector)
            AudioObjectAddPropertyListenerBlock(system, &address, queue) { [weak self] _, _ in
                self?.watchActiveDevice()
                onChange()
            }
        }
        queue.async { self.watchActiveDevice() }
    }

    /// Points the sample-rate listener at the active device. `queue` only.
    private func watchActiveDevice() {
        guard let device = CoreAudioHAL.activeDevice, device != watchedDevice else { return }
        var address = CoreAudioHAL.address(kAudioDevicePropertyNominalSampleRate)
        // ponytail: the previous device's listener stays registered (blocks are
        // removed by identity); harmless, it only triggers an extra re-read.
        watchedDevice = device
        let onChange = self.onChange
        AudioObjectAddPropertyListenerBlock(device, &address, queue) { _, _ in onChange?() }
    }

    /// The monitor calls this after the user picks another device.
    func activeDeviceChanged() { queue.async { self.watchActiveDevice() } }
}

/// Readies the active output for a file before it starts: exclusive mode
/// and, when on, "Igualar frecuencia" (device rate = file rate, so macOS
/// doesn't resample). The rate is a device setting, shared with other apps
/// unless exclusive mode holds the device.
enum OutputRateMatcher {
    static let defaultsKey = "macMatchOutputRate"

    nonisolated static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }

    /// Whether `prepare` has anything to do (else playback starts at once).
    static var isNeeded: Bool { isEnabled || MacOutputSettings.exclusive }

    /// `sourceRate` nil = only refresh exclusive mode.
    static func prepare(sourceRate: Double?) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            CoreAudioHAL.queue.async {
                CoreAudioHAL.updateExclusive()
                if let sourceRate, isEnabled { CoreAudioHAL.matchRate(to: sourceRate) }
                done.resume()
            }
        }
    }
}

/// Publishes the active output device, its sample rate and the device list.
@MainActor
final class AudioOutputMonitor: ObservableObject {
    @Published private(set) var snapshot: AudioOutputSnapshot
    @Published private(set) var devices: [MacOutputDevice]

    private let reader: AudioDeviceReading

    init(reader: AudioDeviceReading = CoreAudioDeviceReader()) {
        self.reader = reader
        self.snapshot = reader.snapshot()
        self.devices = reader.devices()
        reader.observeChanges { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }

    func sessionDidActivate() { refresh() }

    /// Re-reads everything; call after changing the chosen device.
    func refresh() {
        (reader as? CoreAudioDeviceReader)?.activeDeviceChanged()
        let next = reader.snapshot()
        if next != snapshot { snapshot = next }
        let list = reader.devices()
        if list != devices { devices = list }
    }
}
#endif
